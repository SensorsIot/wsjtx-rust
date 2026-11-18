package WstxEndpoints {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioControl::*;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::CodeDiffers;

    requirement 'CL-044-07' {
        subject audio : AudioInterface;
        doc /* Audio MUST list the sound endpoints of the PC by name, so that the operator
             can tell them apart and sees which one belongs to the radio
             (EndpointNaming). */
        @Status { build = ImplementationState::partial; }
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
        @CodeDiffers {
            what = "The code checks only the present endpoints: the not present endpoint of "
                + "AudioConfig counts toward no maxEndpoints, and its last known name is not "
                + "held to maxTextBytes (endpoints_view in server/src/radio_setup.rs).";
        }
        attribute maxEndpoints : Integer = 64;
        attribute maxTextBytes : Integer = 256;
    }

    verification 'TC-044-006' {
        doc /* The endpoint list: names, labels and remembered names. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-07'; }
        @TestedBy {
            test = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
        }
    }
}
