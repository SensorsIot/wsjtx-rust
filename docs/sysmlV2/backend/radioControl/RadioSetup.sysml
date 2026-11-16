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

    // ---- Finding the radios of the PC ---------------------------------------------------

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
        doc /* Detection reads and does not write.
             Setup: the asking of a port on scripted serial ports that record every
             rate and frame; for (h) the station with its radio connection ready on a
             scripted IC-7300 on COM3 and a scripted list of ports. No radio.
             (a) An IC-7300 at 94 that answers the question to all at 19200 only,
             with the echo of every frame: found at 94 and 19200, a model the station
             can control; 9600 is set first and 38400 is not set.
             (b) An IC-705 at A4 that answers only its own address at 115200: found at
             A4 and 115200, a model the station names only; the rates set are 9600,
             19200, 38400 and 115200.
             (c) A collision frame and noise before the answer: one radio, at 94 and
             9600.
             (d) A silent port, and a port whose reads end with timeout: nothing
             found after four rates and twenty frames, one to all and four to the
             known addresses at each rate.
             (e) The identity 99 from the address 70: reported with both, no model.
             (f) The menu items usbSend DTR, usbKeyingCw OFF, usbKeyingRtty RTS,
             dataOffMod MIC, dataMod USB, civTransceive ON, and usbModLevel refused:
             blocking, ok, blocking, information, ok, advice, unreadable.
             (g) usbModLevel 0: blocking. dataMod MIC/USB: advice; MIC: blocking.
             (h) The station's own port COM3, an IC-705 on COM5, COM7 held by another
             program, COM8 silent, COM9 on another serial adapter: the ports opened
             are 5, 7 and 8; the states are stationCat, identified, inUse, noReply and
             notRadioBridge; the seven items of COM3 are read through the connection;
             no menu item is written.
             (i) In (a) to (d), (f) and (h) every frame sent is a read of the
             identity or of one of the seven menu items.
             (j) The serial line at 9600, 19200, 38400 and 115200: DTR and RTS off,
             no handshake. */
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
        doc /* The place of a radio's port, the proposal and the refusals.
             Setup: hand-written lists of ports and sound endpoints with their
             containers and hubs; the station on a throw-away profile with a scripted
             list of ports. No radio.
             (a) The station's own IC-7300 on COM3 at 9600: the proposal is COM3,
             IC-7300, the endpoint "icom7300://COM3?baud=9600&radio=94&controller=e0",
             PTT by CAT, AGC slow; the capture and the render endpoint under the
             port's hub go with it and a microphone under another hub does not. The
             endpoint is one RadioConnection takes.
             (b) No own connection, an IC-7300 on COM4 that answers at 19200: the
             endpoint "icom7300://COM4?baud=19200&radio=94&controller=e0"; its menu
             items are read on the opened port.
             (c) Two IC-7300: two radios the station can control, no proposal.
             (d) An endpoint under the hub of the port: at the radio's place. Two
             capture endpoints under that hub: neither is the radio's, the one render
             endpoint is. The same container under different hubs: at the radio's
             place. Only a root hub in common, and the container Windows gives a
             device without one: not at the radio's place.
             (e) DetectRadios without the confirmation: confirmationRequired. While
             a detection runs: busy. No port on the PC: an empty report without a
             proposal. */
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

    // ---- The recommended menu items -----------------------------------------------------

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
        doc /* The recommended menu items are set.
             Setup: the station on a throw-away profile, its radio connection ready on
             a scripted IC-7300 with usbSend DTR, usbKeyingCw OFF, usbKeyingRtty RTS,
             dataMod MIC and civTransceive ON. No radio.
             (a) Apply: usbSend OFF, usbKeyingRtty OFF, dataMod USB and civTransceive
             OFF are written in this order, each followed by its read; usbKeyingCw is
             not written.
             (b) Apply again: nothing is written.
             (d) The radio reports that it transmits: the outcome names usbSend and
             busy, and nothing is written. Another connection
             number: stateConflict. The transmitter armed: transmitArmed, nothing
             written.
             (e) The radio refuses the write of usbKeyingRtty: the outcome names it
             and rejected; usbSend was written.
             (f) The radio acknowledges dataMod and keeps MIC: the outcome names
             dataMod and readbackMismatch.
             (g) The radio answers with the identity A4: unsupportedRadio, nothing
             written.
             (h) In (a), (b) and (g) no key command and no write of frequency, mode
             or data mode goes out. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-04'; }
        @TestedBy { test = "server/src/radio_setup_tests.rs"; }
    }

    // ---- The AGC ------------------------------------------------------------------------

    requirement 'CL-044-10' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the AGC of its configuration on the radio whenever
             a connection becomes ready and whenever the station service asks for it
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
             On ApplyAgc, inside the reservation of the station service, at once.
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
        doc /* The wanted AGC is set at a connection and within a change of the
             selection, and reported.
             Setup: the station on a throw-away profile that wants the AGC SLOW, its
             radio connection ready on a scripted IC-7300. No radio.
             (a) The radio at MID: before the first look no status. Then the read,
             the write of SLOW and the read; the status is target SLOW, value SLOW,
             written, connect, with the number of the connection. A further look
             sends nothing.
             (b) The radio at SLOW: the read alone; unchanged.
             (c) The radio transmitting: busy and no write; 100 ms later still none;
             2 s later, the radio receiving: written.
             (d) The transmitter armed: no frame of the AGC and no status.
             (e) The radio turned to FAST, then a band change to 20 m in FT8: SLOW is
             written after the frequency; written, selection.
             (f) A change of the mode to FT4 with the radio at SLOW: the read of the
             AGC alone; unchanged, selection.
             (g) The proposal of a detection carries the AGC slow. */
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

    // ---- The radio of the profile at station start --------------------------------------

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
        doc /* The radio of the profile at station start.
             Setup: the station on a throw-away profile with
             RadioRecords::keyingConfirmed true, and a scripted list of ports, held
             ports and radios that records every opening and frame. No radio.
             (a) The profile's COM3 answers, and so does COM5: kept; COM3 alone is
             opened.
             (b) The profile's COM3 and COM4 held, COM5 silent, an IC-7300 on COM6 at
             19200: RadioDiscovered with the endpoint
             "icom7300://COM6?baud=19200&radio=94&controller=e0" and the PTT the
             profile had, disabled; the ports opened are 3, 4, 5 and 6.
             (c) The profile's COM3 silent and COM4 held: kept.
             (d) A profile saved with the mode disabled, a radio present: no port is
             opened.
             (e) A profile never saved, a port on another serial adapter, an IC-705
             on COM5 and an IC-7300 on COM6 at 9600: COM6 with PTT by CAT; the ports
             opened are 5 and 6.
             (f) Three stations in turn, IC-7300 on COM3 and COM6: the first takes
             COM3, the second COM6; the third, whose profile names COM3, keeps its
             control. A port reserved by one holder is refused to a second, another
             port is granted, and the first is granted again after the release.
             (g) Without the KeyingConfirmation, on a profile never saved and on one
             that names COM3: no port is opened and keyingConfirmed is false.
             DetectRadios without the confirmation: refused, and no record. With it:
             the record is there and keyingConfirmed is true; the next DiscoverRadio
             opens COM3.
             (h) Three silent ports and 200 ms in all: the first alone is opened,
             and it ends within 2 s.
             (i) In (a), (b) and (e) every frame sent is a read of the identity. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-15'; }
        @TestedBy {
            test = "server/src/radio_setup_tests.rs";
        }
    }
}
