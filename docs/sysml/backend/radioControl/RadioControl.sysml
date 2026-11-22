package WstxRadioControlPart {
    private import ScalarValues::*;
    private import WstxRadioControl::RadioControl;
    private import WstxRadioControl::RadioAccess;
    private import WstxRadioControl::NativeControlPort;
    private import WstxRadioControl::RadioConfig;
    private import WstxRadioControl::RadioRecords;
    private import WstxKeying::Keying;
    private import WstxCat::CatPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;

    part def RadioControlInterface {
        doc /* The control of the station's radio. It keeps the connection to the radio
             the profile names, reads what the radio is set to, sets frequency, mode and
             the settings the station looks after, keys the transmitter for transmit, and
             finds and sets up a radio on the operator's request.
             The rig is the operator's choice from Hamlib's list (ControlSelection::rig);
             radio control has the rules of the rigs its catalogue names, today the
             IC-7300. The radio is reached on one of two connections, by the profile's
             radio type: a serial port through the CAT adapter, or
             the native network connection of a radio through its own adapter. */
        @ImplementedIn {
            module = "server/src/radioControl/mod.rs; server/src/radioControl/actor.rs; "
                + "server/src/radioControl/executor.rs; server/src/radioControl/catalogue.rs; "
                + "server/src/radioControl/setup.rs; server/src/radioControl/codec.rs; "
                + "server/src/radioControl/cat_lifecycle.rs; "
                + "server/src/radioControl/radio_agc.rs; server/src/radioControl/radio_setup.rs; "
                + "server/src/radioControl/radio_http.rs; server/src/radioControl/windows.rs; "
                + "server/src/radioControl/radio_connection.rs";
        }
        @DetailTests {
            tests = "server/tests/radioControl/radio_control.rs; "
                + "server/src/radioControl/setup_tests.rs; "
                + "server/src/radioControl/radio_connection_tests.rs";
            covers = "the making of the native port values inside the exchange thread; "
                + "the refusal of an incomplete connection identity before a port is "
                + "opened; the text form of a menu value and its coding; the built-in "
                + "list of the commands the station has for a model";
        }
        attribute config : RadioConfig {
            doc /* Its configuration, as the last ControlAssignment gave it. */ }
        attribute records : RadioRecords {
            doc /* Its records, as the last RadioMemory of the supervisor gave
                 them. */ }
        port supervisor : ~RadioControl;
        port transmit : ~Keying;
        port backend : RadioAccess;
        port native : NativeControlPort;
    }

    part def CatAdapter {
        doc /* Joins radio control to the serial port of a radio: it finds the port the
             station names, opens it, sets the serial line, and passes frames out and
             bytes in.
             A radio is held by one station process of the PC at a time. An OpenRadio
             for a device another station process holds is refused with resourceInUse,
             and Windows opens the port for one program only; a station loses the
             device when its port is closed. A ReserveDevice keeps the radio on its port
             for this station process until the process ends, also while the port is
             closed; another station process is refused it with resourceInUse. */
        @ImplementedIn {
            module = "server/src/radioControl/windows.rs; server/src/radioControl/radio_setup.rs";
        }
        @DetailTests {
            tests = "server/tests/radioControl/radio_native.rs; "
                + "server/src/radioControl/windows_tests.rs";
            covers = "reading and writing with a time limit and a withdrawal; the "
                + "finding of a port by its exact name; the serial line of an opened port";
        }
        port serial : ~RadioAccess;
        port radio : CatPort;
    }
}
