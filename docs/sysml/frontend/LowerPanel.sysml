package WstxLowerPanel {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-019';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* Below the QSO pane: the control panel and the error field. */

    requirement 'CL-037-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the contact's settings below the QSO pane as
             ControlPanel says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-01'; }

    attribute def ControlPanel {
        doc /* Always shown below the QSO pane, of its width, its controls in rows across it:
             DX Call and DX Grid with Generate and Enter (EnterDx, WstxQsoControl); Report in
             dB (SetReport); Auto Seq and Call 1st (WstxQsoControl::QsoConfig autoSeq,
             callFirst, saved with the station config); Hold Tx (SetHoldTx); and the Tx period
             Even / 1st or Odd / 2nd (SetParity). Each control shows the value of the view
             qso or of the station config only, so a change shows once the station has it.
             The QSO pane, the control panel and the error field stand in one column at every
             width and fit the screen of 1366 by 768. */
    }

    requirement 'CL-037-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST list the problems the operator must act on as
             ErrorField says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-02'; }

    enum def EntrySeverity {
        doc /* error: something the station cannot do until the operator acts. warn: it
             works, worse than it should. */
        enum error;
        enum warn;
    }
    attribute def ErrorField {
        doc /* A small block below the control panel lists only the problems that hold now,
             each with "since HH:MM", the UTC this page first saw it hold, on one line where it
             fits; an entry goes by itself when its problem clears; there is no history and no
             acknowledgement. With no entry it shows "No problems". The block scrolls inside
             and never moves the control panel. A click on an entry opens its detail in
             Settings, or does what the entry names.
             The entries, from the views, with their severity:
             the link stale (WstxOperatingScreen::LinkRule), error, "Station connection lost ·
             reconnecting", and then no other entry;
             the transmit view's refusal transmitUnsupported, clockNotSynchronized,
             packRefused, frequencyOutOfRange or radioUnavailable, error, "Tx refused · <reason
             in words>", until a later start is accepted; the other refusals clear by
             themselves and make no entry;
             each warning of the view txLevel: alcHigh, warn, "ALC too high · audio drive
             lowered"; poLow, warn, "Output power low"; swrHigh, warn, "SWR high"; swrFault,
             error, "SWR too high · Tx stopped, check the antenna";
             the radio connection not ready, error, the radio's line (WstxSettings::RadioLine);
             the native session not ready, error, its line;
             audio unavailable, error, "Audio unavailable · <error>";
             while receive runs, the input level low, warn, "Audio level low", or too high,
             warn, "Audio overdriven";
             on a station that can transmit, station time unsynchronized, error, "Clock off ·
             Tx blocked";
             the clock's warning and the capture's warning, warn, in the words of
             WstxSettings::ClockView;
             a failed band or mode change, error, "Band/mode change failed · <error>";
             receive not running with an input set, warn, "Receive stopped · start", whose
             click gives StartLive; without an input on a sound device profile, warn, "No audio
             input";
             no continent for the station, neither set nor derived, error, "Set the station's
             continent";
             PageUpdate's and DataNotUnderstood's entries of WstxOperatingScreen. */
    }

    verification 'TC-037-001' {
        doc /* The control panel below the QSO pane. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-01'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-037-001 the Control panel sits below the QSO pane at its width with DX "
                + "call, report, Auto Seq, Call 1st, Hold Tx and Tx period always visible; "
                + "tests/contact.test.cjs::"
                + "manual DX entry and Log QSO log the contact at once without hiding Halt Tx";
        }
    }
    verification 'TC-037-002' {
        doc /* The error field lists the problems that hold. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-02'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "exception chips appear only for an exception and start, stop and explain "
                + "receive; tests/ui-operating.test.cjs::"
                + "TC-037-002 the error field lists only current problems with their time and "
                + "clears them by itself; tests/ui-operating.test.cjs::"
                + "TC-037-002 a long problem scrolls inside the error field on screen and the "
                + "Control panel stays";
        }
    }
    verification 'TC-044-018' {
        doc /* The audio drive's warnings in the error field. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-02'; }
        @TestedBy { test = "tests/ui-operating.test.cjs::Tx level in Settings > Radio > Audio"; }
    }
    verification 'TC-092-005' {
        doc /* The clock's entries in the error field. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-02'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-092-005 clock entries in the error field and the clock status line";
        }
    }
}
