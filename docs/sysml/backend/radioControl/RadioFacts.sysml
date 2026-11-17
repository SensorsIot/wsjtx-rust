package WstxRadioFacts {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-008-05' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST report of the radio only what the radio itself has
             answered, and mark a fact as not confirmed from the moment it may no
             longer hold (FactRules). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-008-05'; }

    attribute def FactRules {
        doc /* How RadioFacts and the state of RadioStatus are kept.
             What the profile wants (ControlSelection), what a request asks for and
             what the radio reported are kept apart: a fact is set by the radio's
             answer to the read of that fact and by nothing else. An acknowledgement,
             the echo of a frame and a wanted value set no fact.
             Every answer that sets a fact gets the next Fact::querySequence. The read
             of one fact leaves the four others as they are.
             A fact stops being confirmed, and keeps its value and its time:
             from the moment a change of its value is begun until it is read again
             (receiveSetup: frequency, mode and data mode; a key or unkey: the
             transmit fact); and all five when the state leaves ready or the
             connection is asked to close.
             An answer that arrives after the connection was asked to close sets the
             value and leaves it not confirmed.
             A new connection starts with the frequency the radio answered with as its
             first fact and with the four others empty.
             The state is ready only after the radio has answered, and it is not ready
             again after a request to close. */
    }

    verification 'TC-009-006' {
        doc /* The facts follow the radio's answers and nothing else. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-05'; }
        @TestedBy {
            test = "server/tests/radio_control.rs::"
                + "query_provenance_does_not_freshen_unqueried_facts_and_partial_setup_"
                + "stales_targets; "
                + "server/src/radio_control/executor.rs::"
                + "closing_publication_survives_late_attach_and_query; "
                + "server/src/radioControl/cat_lifecycle_tests.rs::"
                + "station_absent_then_returns_then_cable_removed_and_returns_with_"
                + "query_bytes_only; "
                + "server/tests/radio_control.rs::"
                + "partial_writes_and_failed_close_keep_truthful_connection_state";
        }
    }
}
