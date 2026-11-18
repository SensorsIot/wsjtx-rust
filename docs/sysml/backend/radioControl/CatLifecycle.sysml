package WstxCatLifecycle {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-022-03' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST connect the profile's radio by itself and keep it
             connected while the profile's control is CAT with an endpoint it takes,
             and reach no radio otherwise (ControlGate). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-022-03'; }

    attribute def ControlGate {
        doc /* What radio control does with the ControlAssignment it has.
             With the mode disabled no port is opened and nothing is sent; a
             connection that is connecting, ready or failed is closed. The condition
             of AutomaticCatStatus is disabled.
             With the mode cat and an endpoint RadioConnection does not take, no port
             is opened; the condition is waitingForDevice with invalidRequest.
             With the mode cat and an endpoint it takes, radio control makes one
             attempt to connect at once: at station start and for every other
             assignment (ControlAssignment).
             For another assignment the connection that exists is closed first, and
             the attempt follows when its port is closed. Until radio control has
             acted on an assignment, its condition is waitingForDevice.
             What radio control sends by itself on the connection are the five reads,
             the AGC of the assignment, and the unkey of a connection that closes
             while the radio may be keyed. */
    }

    requirement 'CL-022-04' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST try to connect again by itself after an attempt has
             failed and its port is closed, waiting longer each time up to a limit
             (RetryCadence). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-022-04'; }

    attribute def RetryCadence {
        doc /* When the next attempt to connect is made.
             After a failed attempt whose port is closed, the next attempt follows
             after firstRetrySeconds; after each further failure in a row the wait is
             twice as long, up to maxRetrySeconds. The wait starts when radio control
             finds the failure. AutomaticCatStatus gives the condition retryWaiting,
             the error of the failed attempt and the time left.
             One attempt is in work at a time. A wait that has long passed gives one
             attempt.
             The row of failures starts anew when the state is ready, and not
             before.
             An attempt that cannot start because radio control is reserved or an
             operation is in work is no failure: it is made at the next occasion, and
             no wait grows.
             An attempt that is refused before a port is opened is a failed attempt.
             A port that did not close is left alone: the condition is quarantined
             with failedClose, and no attempt follows for as long as the station
             process runs, whatever assignment comes. */
        attribute firstRetrySeconds : Integer = 1;
        attribute maxRetrySeconds : Integer = 8;
    }

    verification 'TC-022-009' {
        doc /* The radio connection is kept by itself. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-022-03';
            verify 'CL-022-04';
        }
        @TestedBy {
            test = "server/src/radioControl/cat_lifecycle_tests.rs; "
                + "server/src/auth_tests.rs";
        }
    }
}
