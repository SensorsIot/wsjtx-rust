package WstxCatControl {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import WstxKeying::*;
    private import WstxRadioProperties::ModeValue;
    private import WstxRadioProperties::Meter;
    private import WstxCat::CivFrame;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

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
        doc /* The connection to the radio on a scripted serial port. */
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
        doc /* The station's own IC-7300, read and set by hand. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 4; location = TestLocation::station; }
        @Automation { run = AutomationState::partial; method = "automated"; }
        objective { verify 'CL-008-04'; }
        @TestedBy { test = "server/tests/receive/radio_hardware.rs"; }
    }

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
             RigModel::dialRange, a filter number outside 1 to 3, or a data filter number
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
             and a frequency outside RigModel::dialRange, is protocol.
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
        doc /* The exchanges with the radio on a scripted serial port. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-06'; }
        @TestedBy {
            test = "server/tests/radio_control.rs; "
                + "server/src/radio_level_tests.rs::a_transmit_hold_refuses_the_lease_at_once";
        }
    }

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
             (ControlOperation), of the AGC (ApplyAgc and at a new connection), of the
             output power (ManagedPower) and of a menu item (ApplyRecommended).
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
        doc /* Frequency, mode, data mode and a menu item are read before they are set. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-09'; }
        @TestedBy {
            test = "server/tests/radio_control.rs; server/src/radio_control/executor.rs";
        }
    }

    verification 'TC-044-008' {
        doc /* The AGC is read before it is set. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-09'; }
        @TestedBy { test = "server/src/radioControl/radio_agc_tests.rs"; }
    }

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

    requirement 'CL-008-13' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the transmit frequency of a split operation around
             the key as SplitKeying says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-008-13'; }

    attribute def SplitKeying {
        doc /* A KeyRequest with KeyRequest::split rig or fakeIt, before its key command:
             rig sets the radio's split on with the transmit VFO at the dial radio control
             confirmed last plus KeyRequest::shiftHz; fakeIt sets the dial to that
             frequency. Each is read back; one that fails answers the KeyRequest with
             KeyFailed as the key would fail, and nothing is keyed. After the confirmed
             unkey of a key with fakeIt the dial is set back and read back. The facts of
             the radio are not read between the setting and the setting back, and the
             dial fact keeps the dial from before. With none, split stays as the radio
             has it. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Settings > Radio, Split Operation; "
                + "MainWindow::setXIT";
        }
    }

    verification 'TC-009-007' {
        doc /* Keying and unkeying on a scripted IC-7300. */
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
