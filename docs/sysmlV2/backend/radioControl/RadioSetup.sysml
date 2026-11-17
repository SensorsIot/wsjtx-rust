package WstxRadioSetup {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import WstxRadioProperties::Setting;
    private import WstxRadioProperties::Agc;
    private import WstxAudioControl::RadioPlace;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-044-01' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST find the radios on the serial ports of the PC by
             reading only, and only after the operator has confirmed that opening a
             port cannot key a transmitter (RadioDetection). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-01'; }

    attribute def KeyingConfirmation {
        doc /* The operator's word, given once, that the radios of this PC do not key
             from a serial line or stand on a dummy load. It is needed because opening
             a port can raise a line for a moment (WstxCat::SerialLine).
             It is RadioRecords::keyingConfirmed. The first DetectRadios that carries
             the confirmation sets it, and radio control hands the record over to be
             kept (RadioMemory). It counts when it has come back as kept; until then,
             and without a record, the keying is not confirmed.
             RadioStatus::keyingConfirmed reports it. */
    }
    attribute def RadioDetection {
        doc /* How DetectRadios is carried out.
             Without keyingInhibitConfirmed it is refused with confirmationRequired
             and no port is opened. One detection runs at a time; a second is refused
             with busy.
             Every serial port present gets a PortReport, the first maxPorts of them.
             The port of the station's own radio connection is not opened a second
             time (PortState::stationCat); while that connection is ready, the radio's
             identity and its menu items are read through it.
             Of the other ports only those on a serial adapter of a known radio are
             opened: the Silicon Labs CP210x with the USB vendor 10C4 and product
             EA60. A port is opened as for the radio connection (OpenRadio).
             On an opened port the radio is asked for its transceiver identity at
             9600, 19200, 38400 and 115200 bits per second in this order: first every
             radio on the link at once, and when none answers, the address of each
             known model. The asking ends at the first rate at which a radio answered.
             An answer is an identity from a radio's address to the controller's; the
             echo, a collision, other frames and noise are not.
             The known models are the IC-7300 at 94, which the station can control,
             and the IC-705 at A4, the IC-9700 at A2 and the IC-7610 at 98, which it
             names only. An identity it does not know is reported as it is.
             The frames sent while detecting are the read of the identity and the
             reads of the menu items of SettingsCheck, and no other.
             Detection changes nothing on a radio and nothing in the profile.
             Detection and the asking of one port are bounded in time; a port not
             reached in time is PortState::notProbed. */
        attribute maxPorts : Integer = 64;
    }

    requirement 'CL-044-02' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST report where the port of each radio it identifies is
             attached, and propose the control of the one radio found that the station
             can control (DetectionProposal). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-02'; }

    attribute def DetectionProposal {
        doc /* What a DetectionReport says beyond the ports.
             PortReport::place is the RadioPlace of the port: the model of its radio,
             the container Windows puts the port in, and the USB hub its device hangs
             on. By it the sound endpoints of the same radio are found.
             RadioStatus::place is the same for the port the profile's endpoint names,
             read from the list of the PC's ports without opening one.
             A proposal is made when exactly one radio among all ports is one the
             station can control. Its control is the mode cat, the endpoint
             "icom7300://COMn?baud=<rate>&radio=<address>&controller=e0" with the port,
             the rate and the address the radio answered at, and PTT by CAT; its AGC
             is slow. With none or several such radios there is no proposal. */
    }

    requirement 'CL-044-03' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST read the menu items of an identified IC-7300 that
             decide whether the station can transmit through it, and say what each
             value means for that (SettingsCheck). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-03'; }

    attribute def SettingsCheck {
        doc /* The SettingFinding of each of the seven items of Setting. The items are
             read and not set.
             usbSend, usbKeyingCw, usbKeyingRtty: OFF is ok; DTR and RTS are blocking,
             because a serial line could key the transmitter. Recommended: OFF.
             dataMod: USB is ok; MIC/USB is advice; every other value is blocking,
             because the transmit audio would not come from the station. Recommended:
             USB.
             usbModLevel: 0 is blocking; every other value is ok. Not set by the
             station.
             civTransceive: OFF is ok; ON is advice. Recommended: OFF.
             dataOffMod: information. Not set by the station.
             An item the radio does not give is unreadable.
             The rate of the link is not an item the radio gives; it is reported as
             the rate the radio answered at. */
    }

    verification 'TC-044-001' {
        doc /* Detection reads and does not write. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-01';
            verify 'CL-044-03';
        }
        @TestedBy {
            test = "server/src/radio_control/setup_tests.rs; "
                + "server/src/radio_setup_tests.rs; "
                + "server/src/radioControl/windows.rs::"
                + "opened_ports_hold_dtr_and_rts_disabled";
        }
    }

    verification 'TC-044-002' {
        doc /* The place of a radio's port, the proposal and the refusals. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-01';
            verify 'CL-044-02';
        }
        @TestedBy {
            test = "server/src/radio_control/setup_tests.rs; "
                + "server/src/radio_setup_tests.rs";
        }
    }

    requirement 'CL-044-04' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the recommended menu items of the connected IC-7300
             only on the operator's request (RecommendedSettings). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-04'; }

    attribute def RecommendedSettings {
        doc /* How ApplyRecommended is carried out.
             It is refused: with stateConflict for another connection than the
             current one; with radioUnavailable unless the state is ready; with
             transmitArmed while the transmitter is armed (TransmitterActivity);
             with unsupportedRadio unless the radio answers with the identity of an
             IC-7300.
             Apply reads usbSend, usbKeyingCw, usbKeyingRtty, dataMod and
             civTransceive and sets, in this order, each one that differs from its
             recommended value (SettingsCheck). An item the radio does not give is
             not set. With nothing to set, nothing is written.
             Every item is set by ReadCompareWriteVerify. The first item that fails
             ends the request; SettingsOutcome names it and the error.
             The old values are not kept: the station sets nothing back. */
    }

    verification 'TC-044-003' {
        doc /* The recommended menu items are set. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-04'; }
        @TestedBy { test = "server/src/radio_setup_tests.rs"; }
    }

    requirement 'CL-044-10' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the AGC of its configuration on the radio whenever
             a connection becomes ready and whenever the supervisor asks for it
             within a change of the operating selection (ManagedAgc). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-10'; }

    attribute def ManagedAgc {
        doc /* When RadioConfig::agc is set on the radio, each time by
             ReadCompareWriteVerify.
             Once for every connection that becomes ready, and once more on that
             connection when the assignment names another AGC. It waits while the
             transmitter is not at rest (TransmitterActivity). An attempt that ends with
             busy is made again after retrySeconds; every other end is final for that
             connection. An attempt the radio does not answer in time ends with timeout.
             On ApplyAgc, inside the reservation of the supervisor, at once.
             Nothing is sent while the transmitter is not at rest. What comes of it
             is reported and does not fail the change it belongs to.
             Without an AGC in the configuration nothing is read or set. */
        attribute retrySeconds : Integer = 2;
    }

    requirement 'CL-044-11' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST report the AGC it wants on the radio, what the radio
             answered and what came of it, at every change (AgcReport). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-11'; }

    attribute def AgcReport {
        doc /* What AgcStatus holds.
             Without a wanted AGC every feature is absent. With one, and before the
             radio has been asked, the target alone is present.
             After an attempt: the connection it was made on, the value the radio
             reported, the outcome, and the trigger: connect for a connection that
             became ready, selection for ApplyAgc.
             An attempt that failed keeps the value last reported on the same
             connection and gives the error. */
    }

    verification 'TC-044-009' {
        doc /* The wanted AGC is set at a connection and within a change of the selection, and
             reported. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-10';
            verify 'CL-044-11';
        }
        @TestedBy {
            test = "server/src/radioControl/radio_agc_tests.rs; "
                + "server/src/radio_setup_tests.rs";
        }
    }

    requirement 'CL-044-15' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST make sure at station start, by reading only, which
             radio is the profile's, and take the next free radio the station can
             control when the profile's own does not answer (StartDiscovery). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-15'; }

    attribute def StartDiscovery {
        doc /* How DiscoverRadio is answered.
             Without the KeyingConfirmation no port is opened and the answer is
             RadioKept. So it is on a profile whose radio is on its native network
             connection.
             A profile with the mode cat and an endpoint RadioConnection takes keeps
             its radio when the port is present, answers with a radio the station can
             control and is granted to this station (ReserveDevice); no other port is
             opened.
             When it does not, and on a profile that was never saved, the other ports
             on a serial adapter of a known radio (RadioDetection) are tried in the
             order of the list of ports. The first that can be opened, answers with a
             radio the station can control and is granted to this station is the
             station's radio: RadioDiscovered gives its control, with the mode cat,
             the endpoint as in DetectionProposal, and PTT as the profile had it with
             the mode cat and by CAT otherwise.
             A port that cannot be opened, and one reserved for another station, are
             passed over; so each station of a PC takes a radio of its own.
             A profile that was saved with the mode disabled, and one whose endpoint
             RadioConnection does not take, keep their control, and no port is
             opened.
             With no radio found the answer is RadioKept.
             The frames sent are reads of the transceiver identity.
             The reservation of the radio kept or discovered lasts as long as the
             station process.
             Discovery is bounded in time: no port is opened after its limit, and the
             asking of a port ends at it. */
    }

    verification 'TC-044-020' {
        doc /* The radio of the profile at station start. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-15'; }
        @TestedBy {
            test = "server/src/radio_setup_tests.rs";
        }
    }
}
