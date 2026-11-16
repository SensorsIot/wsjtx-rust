package WstxCatLifecycle {
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
        doc /* The radio connection is kept by itself.
             Setup: the keeping of the connection with time given by the test; the
             station with a scripted radio that counts every opening, frame and close;
             for (m) and (o) the station on a throw-away profile. The control is CAT
             with an endpoint that is taken unless said otherwise. No radio.
             (a) No radio: one attempt at once. After each of seven failures the next
             attempt follows after 1, 2, 4, 8, 8, 8 and 8 s, not 10 ms earlier;
             meanwhile retryWaiting with unavailable. An hour without a look: one
             attempt.
             (b) Three failures, an attempt that is still connecting, a failure: the
             wait is 8 s. Then ready, and a failure 60 s later: 1 s.
             (c) Disabled and an endpoint that is not taken, 600 s each: no attempt;
             on the station no port opened and no frame. A connection that is
             connecting, ready or failed: closed. Then an endpoint that is taken and
             the port closed: one attempt at once.
             (d) Another assignment while connecting to a silent radio: closed within
             250 ms, then one attempt, and RadioStatus::connectionNumber is another.
             (e) A port that does not close: quarantined with failedClose over
             7200 s; disabled and then another assignment: still no attempt. On the
             station over 4000 s: the attempts stay at one.
             (f) No radio, then a radio from 3 s on: attempts at 0, 1.1 and 3.2 s;
             ready with 7074000 Hz. The cable removed: retryWaiting with 1000 ms. The
             radio back: four openings in all, and every frame sent was one of the
             five reads.
             (g) A port another program holds: retryWaiting with resourceInUse and
             1000 ms after one opening and no close. A silent radio: timeout after
             one opening and one close.
             (h) Ready, then disabled: closed within 250 ms; over 200 s no attempt and
             no frame. CAT again: one attempt at once.
             (i) An attempt refused before a port is opened: retryWaiting with
             invalidRequest and 1000 ms; the next after 1 s, then 2000 ms; no
             opening.
             (j) An attempt that cannot start, four times within 0.2 s: tried again
             each time. The first failure after it waits 1 s.
             (k) A change of the frequency by the station service on the ready
             connection, with the connection looked at and its status read all the
             while: no attempt, one opening and no close; afterwards only reads; no
             key command in all of it.
             (l) The control disabled while such a change waits for a silent radio:
             closed within 250 ms, the change ends with unavailable; then no opening
             and no frame, and the radio's frequency is as before.
             (m) Ready with 7074000 Hz after one opening. The profile renamed:
             waitingForDevice, then a second opening. Every frame was a read.
             (o) No radio: retryWaiting with unavailable and 1 to 1000 ms; the state
             unavailable, the frequency not confirmed. */
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
