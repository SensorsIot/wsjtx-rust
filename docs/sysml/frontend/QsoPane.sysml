package WstxQsoPane {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-025';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The QSO pane: the running contact, its dialogue, the stations calling, the period
         bar, the direct buttons and the messages Tx1 to Tx6. */

    requirement 'CL-037-04' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the running contact in a pane of fixed height as
             PaneLayout says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-04'; }

    attribute def PaneLayout {
        doc /* The pane stands at the top of the workspace's right column. Its height depends
             on the window only, never on its content, so the control panel and the error
             field below never move. Top to bottom: the header; the direct buttons
             (PaneButtons) and the fold-out Tx1-Tx6 (MessagesFoldOut); the message lines
             (MessageLines); the QSO section, the dialogue (DialogueTable), qsoRows rows high
             (narrowQsoRows on a narrow window), scrolling inside and kept at its newest row,
             "No QSO" while none runs; the Calling me section (CallingMe), at least
             callingRows rows high. The open fold-out covers the two sections and moves
             nothing.
             The header: the partner's call and grid; below them the shown name and continent
             of the partner's entity, the distance from the station's locator with the
             azimuth to the partner's grid (~n km for the entity's distance without a grid),
             in km or in miles (FrontendConfig::distanceInMiles), and the reports sent and
             received; "No contact
             selected" without a contact; "Calling CQ" with "Tx even (1st)" or "Tx odd (2nd)"
             while the own CQ runs; and a badge: Ready, Tx on, Transmitting, or Receive only
             while the station cannot transmit, then with CQ, Tune and the starts disabled
             with the reason beside them. A running contact is one with a partner from replying
             to signoff (WstxQsoControl::SequenceState); a completed or cancelled one leaves the
             pane. Everything follows the view qso; a reload or another browser shows the
             same. */
        attribute qsoRows : Integer = 12;
        attribute narrowQsoRows : Integer = 6;
        attribute callingRows : Integer = 5;
    }

    attribute def CallingMe {
        doc /* One line per station that calls the station's call in the latest two periods
             (as myCall of WstxBandActivityPane::Highlight), from any station but the
             partner, on any frequency, as soon as its record is shown, at most callingLines
             lines, oldest first: the call as decoded, the SNR, the grid of its message and
             the country of its entity. While a contact runs, a caller within crowdingHz of
             the Rx or the Tx offset is marked ⚠. A double-click or Enter on a line gives
             Reply, with replace while a contact runs. A line carries the colour and the tip of
             Band Activity's marks of its sender, without myCall. With no caller: "Nobody is
             calling". */
        attribute callingLines : Integer = 8;
        attribute crowdingHz : Integer = 50;
    }

    requirement 'CL-060-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the running contact's dialogue as DialogueTable
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-060-01'; }

    attribute def DialogueTable {
        doc /* The dialogue of the view qso (WstxQsoControl::QsoContact::dialogue) as a table
             with the header "UTC | Direction | Exchange | Rep | Rx SNR | Tx SNR", one row per
             entry, oldest first. UTC: the period start, HH:MM:SS. Direction: the two calls in
             the order of the message, the addressee first and the sender second, with ◂
             between them pointing at the addressee ("HB9BLA ◂ CT1BFP" received, "CT1BFP ◂
             HB9BLA" sent), a hashed call as decoded; a CQ is "CQ <call>" or "CQ DX <call>"
             without the arrow, its grid the Exchange. Exchange: the message after the two
             calls; a free text is all Exchange. Rep: ×N for a message counted N times in a
             row, empty for once. On every row, received or sent, Rx SNR is the station's SNR
             of the latest received entry up to that row and Tx SNR the latest report the
             partner sent up to that row ("R-02" gives −2), each empty while none exists. Sent
             rows have a colour of their own. On a narrow window the titles shorten to UTC,
             Dir, Exch, Rep, Rx, Tx. */
    }

    requirement 'CL-050-05' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show what the station sends next as MessageLines
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-050-05'; }

    attribute def MessageLines {
        doc /* One fixed area of lines below the buttons:
             the last message of the partner with its SNR, and ×N when it came N times in a
             row;
             while the station transmits (the view transmit), "▶ TX now: <message>" with
             "<n> s left", or "▶ TX now: Tune" with the seconds of Tune left; while the
             transmit state is on otherwise, "▸ next: <message> · Tx in <n> s";
             while Auto Seq is off in a contact or CQ, "Auto Seq off" with an Auto Seq on
             button, and when the sequence would choose a message (QsoContact::suggestedSlot)
             "<call> expects" with a button "Send <exchange> next" (SendNext);
             a contact that waits to be logged (QsoState::logPending), "Log <call>?" with its
             calls, reports and times, and the buttons Log QSO (ConfirmLog) and Discard
             (DiscardLog);
             after a contact is logged, "✓ Logged <call>" for loggedSeconds; a contact the
             log refused, "Not logged <call> · <reason>" while that holds (the view
             logAttempt), as "same station as the last log entry" for a repeat;
             for a contact in progress, by hand or by Auto, with PSK Reporter in use, the
             two lines of the view target: "Hears us: <age> ago · <dB> dB", "Hears us: no" or
             "Hears us: unknown", and "Tx <hz> Hz · open at his end: yes", "no" or "unknown";
             the sends left of the message due (QsoState::repetitionsLeft);
             a refused command's reason, until the next command. */
        attribute loggedSeconds : Integer = 8;
    }

    requirement 'CL-050-03' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the progress of the period on station time as
             PeriodBar says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-050-03'; }

    attribute def PeriodBar {
        doc /* With the message line, a bar shows the part of the current period gone by
             (FT8 15 s, FT4 7.5 s), on station time (clock.time,
             WstxOperatingScreen::TimeRule), never the browser's clock, and restarts at the
             start of the period the transmitter keys on. It is red in a period of the own Tx
             parity while the transmit state is on, and whenever the station transmits; green
             in every other period. */
    }

    requirement 'CL-037-06' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the QSO pane's direct buttons as PaneButtons
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-06'; }

    attribute def PaneButtons {
        doc /* In one row: CQ (CallCq, WstxQsoControl), Auto and PSK (AutoControls), Tune
             (Tune on and off, with the seconds left while on), HALT
             (WstxOperatingScreen::HaltRule), Abort QSO (Esc) (HaltQso, while a contact is in
             progress) and Log QSO (Alt+Q): ConfirmLog while a contact waits to be logged,
             else WstxLogControl::ResendLast, which gives the newest record of the logbook
             again. Log QSO closes no contact. Each button shows the state of the views only. */
    }

    requirement 'CL-039-31' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer Auto and the use of PSK Reporter as AutoControls
             says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-025'; end #derive ::> 'CL-039-31'; }

    attribute def AutoControls {
        doc /* Auto is a toggle among the direct buttons: on gives SwitchAuto on, off
             SwitchAuto off (WstxAutoControl); its title says what off does with a contact in
             progress. Auto's line stands beside the strategy selector
             (WstxBandActivityPane::StrategyElement) and follows the view auto: on and
             waiting, with the wait reason in words ("waiting · outside period"); in a contact,
             the partner's call, or "your QSO" in a contact the operator started; "calling
             CQ"; the leave count while a station is called; the periods left of the CQ
             pause; off after it was on, with the reason in words ("stopped · transmit
             refused"); a refused switch on, with its reason. PSK, titled "Use PSK Reporter",
             is a toggle of the spots' use switch (WstxHearing::SpotsConfig), saved with the
             shack's settings (saveShack); it is disabled, with the title "PSK Reporter is off
             in Settings", while listening to PSK Reporter is off. */
    }

    requirement 'CL-111-09' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the six messages and the activity as
             MessagesFoldOut says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-111-09'; }

    attribute def MessagesFoldOut {
        doc /* The fold-out "Messages Tx1-Tx6" holds the six messages of the contact, each
             with its Next choice (ChooseNext) and its text, which can be edited
             (EditMessage): Tx5 whenever a contact exists, for free text, offering the Tx
             macros of the shack (WstxQsoControl::QsoShared::macros) as the operator types,
             the others once they have a message; Skip Tx1 (SetTx1Skip), RRR or RR73 (SetTx4)
             and Cancel
             contact (CancelContact). Above them the Activity choice, None, NA VHF, EU VHF, WW
             Digi, ARRL Digi, Field Day, RTTY Roundup, Hound, with the Exchange beside it for
             Field Day and RTTY Roundup, both values of the station config
             (WstxQsoControl::QsoConfig activity, exchange); the next serial shows while the
             activity sends one. A choosing of a message never starts a transmission. */
    }

    verification 'TC-037-003' {
        doc /* The pane of fixed height with its two sections. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-04'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-007-003' {
        doc /* Rows, the partner's selection and the pane. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-04'; }
        @TestedBy { test = "server/src/contact_http_tests.rs; tests/contact.test.cjs"; }
    }
    verification 'TC-060-001' {
        doc /* The dialogue table. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-060-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-050-005' {
        doc /* The pane while calling CQ and transmitting. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-05'; }
        @TestedBy { test = "tests/ui-operating.test.cjs; tests/contact.test.cjs"; }
    }
    verification 'TC-085-005' {
        doc /* What the operator sees of a repeat the log refuses. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-05'; }
        @TestedBy { test = "tests/contact.test.cjs; server/src/contact_http_tests.rs"; }
    }
    verification 'TC-050-003' {
        doc /* The period bar's colour on station time. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-03'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-081-006' {
        doc /* Auto's toggle says what off does. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-31'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-024-006' {
        doc /* The activity choice in the fold-out. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-024-009' {
        doc /* Field Day and RTTY Roundup with their exchange. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-024-013' {
        doc /* The Hound in the fold-out. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-099-003' {
        doc /* EU VHF in the fold-out. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
}
