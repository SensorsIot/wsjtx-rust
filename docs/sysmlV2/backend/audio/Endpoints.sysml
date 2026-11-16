package WstxEndpoints {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioControl::*;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-044-07' {
        subject audio : AudioInterface;
        doc /* Audio MUST list the sound endpoints of the PC by name, so that the operator
             can tell them apart and sees which one belongs to the radio
             (EndpointNaming). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/radio_setup.rs; server/src/radio_control/setup.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-044-07'; }

    attribute def EndpointNaming {
        doc /* How the EndpointList is made.
             The inputs are the active capture endpoints, the outputs the active render
             endpoints; none is opened for the list.
             The name is the friendly name with every run of blanks made one, without
             blanks at its ends, after an opening bracket or before a closing one.
             The label is the name. Present endpoints of one list with the same name
             each get " #n" after it, n from 1 in the order of their ids.
             The one endpoint of a list that is at the radio's place (RadioPlace) has
             the radio's model as radio, and its label ends with " — " and the model.
             With none or several at that place, and without a RadioPlace, no endpoint
             is the radio's.
             An endpoint of AudioConfig that is not present is one more entry of its
             list: not present, without radio, with its last known name and the label
             "<name> · not present", or "Unknown device · not present" without a name.
             The last known name of each endpoint of AudioConfig is
             AudioRecords::lastNames. Audio renews it at station start and with every
             list, keeps the name of no other endpoint, and hands the changed record
             over to be kept (AudioMemory). Without a record no name is known.
             The list is refused with deviceLimit when a list would be longer than
             maxEndpoints or an id or a name is empty or longer than maxTextBytes, and
             with audioUnavailable when the endpoints cannot be read. */
        attribute maxEndpoints : Integer = 64;
        attribute maxTextBytes : Integer = 256;
    }

    verification 'TC-044-006' {
        doc /* The endpoint list: names, labels and remembered names.
             Setup: hand-written lists of endpoints and ports, and the station on a
             throw-away profile with a scripted list; no sound device and no radio.
             (a) "Microphone (USB Audio CODEC )" on the radio's USB hub: the name
             "Microphone (USB Audio CODEC)", the label
             "Microphone (USB Audio CODEC) — IC-7300", radio IC-7300.
             (b) Two inputs named "Headset Microphone (Sennheiser Communication Audio)",
             one of them written with two blanks after Headset:
             the labels end with " #" and the numbers 1 and 2, in the order of their ids.
             (c) Without a radio in the profile: the same names, no radio and no ending.
             (d) The profile's input not present, with a remembered name: the label
             "Microphone (USB Audio CODEC) · not present"; without one:
             "Unknown device · not present".
             (e) After a list AudioRecords holds the name of the profile's input only.
             With that input unplugged the list shows it as in (d). At station start,
             with no endpoint readable, the names of the record are known and no
             other.
             (f) Endpoints that cannot be read: refused with audioUnavailable.
             (g) Planned, no test yet: 65 inputs, and an endpoint whose name has 257
             characters: refused with deviceLimit. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-07'; }
        @TestedBy {
            test = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
        }
    }
}
