package WstxOperatingScreen {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-017';
    private import WstxRequirements::'FR-019';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The operating screen as a whole: its window, its regions, the top bar, HALT, the
         keys, the link to the station, a new start of the station and a new client, what
         the screen tells of the station's health and transmit state, and the help. */

    requirement 'CL-010-16' {
        subject browser : BrowserClient;
        doc /* The browser client MUST present the operating screen as ScreenLayout says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-010-16'; }

    attribute def ScreenLayout {
        doc /* One screen per station, in its own app window (AppWindow). From a window of
             minWidthPx by minHeightPx on, the whole screen fits the window and only lists
             scroll inside it; on a narrower window the regions stack and the workspace
             scrolls up and down, never sideways, down to phoneWidthPx.
             Top to bottom: the top bar; the signal area, the spectrum and the waterfall
             over the full width with the Rx/Tx strip below them (WstxSignalArea); a divider
             that sets the height of the signal area by pointer and by keys; the workspace.
             The top bar holds only: the band and the mode of the selection
             (WstxStationCommands::SelectBand, SelectMode; the band selector offers each
             band's working frequencies for the mode; a change during a contact or a
             transmission asks first), the dial frequency, the station's UTC (TimeRule),
             Logbook (LogbookPage), Settings (WstxSettings::SettingsDrawer), ? (HelpRule) and
             HALT (HaltRule).
             The workspace: Band Activity with the strategy element above it on the left
             (WstxBandActivityPane), and on the right one column of the QSO pane
             (WstxQsoPane), the control panel and the error field (WstxLowerPanel), all three
             of the QSO pane's width; on a narrow window the column goes below Band Activity.
             Receive follows the selection of band and mode; a contact's transmission follows
             its starts; the station's healthy state is shown in Settings > Expert, and the
             error field lists only what the operator must act on.
             Lists, frequencies and messages are written in a fixed-width font; colours keep
             the meanings of WSJT-X (WstxBandActivityPane::Highlight). The theme follows
             FrontendConfig::theme and themeSwitch. The window's title and the top bar name the
             station by its displayName. */
        attribute minWidthPx : Integer = 1366;
        attribute minHeightPx : Integer = 768;
        attribute phoneWidthPx : Integer = 360;
    }

    requirement 'CL-103-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST run as an app window as AppWindow says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-103-01'; }

    attribute def AppWindow {
        doc /* The screen fills a window of its own without tabs, address bar or toolbars.
             The operator installs the station's page as an app on a PC, an Android phone or
             an iPhone from the web app manifest web serves (WstxListener::ClientFiles), with
             the station's name, its origin as start and scope and the display standalone,
             or opens it as an app window by a shortcut; on a single PC the station opens its
             own app window (WstxStartup::LaunchRule). Each station has its own window. */
        @FollowsSource { reference = "W3C Web Application Manifest (display standalone)"; }
    }

    requirement 'CL-037-03' {
        subject browser : BrowserClient;
        doc /* The browser client MUST keep one HALT on screen at all times as HaltRule
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-03'; }

    attribute def HaltRule {
        doc /* In the operating view the HALT is the QSO pane's (WstxQsoPane::PaneButtons);
             the top bar's HALT shows whenever that one is not wholly on screen (a page or the
             Settings drawer covers the workspace, or a narrow window has scrolled it away),
             so one HALT is always on screen. A confirmation popup carries a HALT of its own,
             because the rest of the screen cannot be used while it is open. Every HALT and
             the key Alt+H give Halt (WstxTransmitControl) at once, without a question.
             Esc gives HaltQso (WstxQsoControl); a held Esc that repeats gives nothing more,
             and an open dialog or menu takes Esc first to close. */
    }

    requirement 'CL-010-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST be fully usable by keyboard and on a narrow window,
             and show the station's texts as KeyRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-010-08'; }

    attribute def KeyRule {
        doc /* Every control is reached and used by keyboard, with visible focus; the divider
             of the signal area moves by keys. A text of the station (a call, a message, a
             name) is shown as text, never read as markup.
             The keys of WSJT-X where the function exists: Alt+H Halt; Esc HaltQso; F1, F3,
             F5 and ? the help; F2 Settings; F4 CancelContact; Alt+1 to Alt+6 ChooseNext of
             Tx1 to Tx6; Alt+T Tune; Alt+Q Log QSO (WstxLogControl::ResendLast); F11 and F12
             the Rx offset down and up by 1 Hz; Shift+F11 and Shift+F12 the Tx offset by
             txStepFt8Hz in FT8 and txStepFt4Hz in FT4; Ctrl+F11 and Ctrl+F12 both offsets by
             1 Hz (SetFrequency). A letter key and ? act only while no text field has the
             focus; Esc and Alt+H act always. */
        @FollowsSource { reference = "WSJT-X at the behaviour baseline: keyboard shortcuts"; }
        attribute txStepFt8Hz : Integer = 60;
        attribute txStepFt4Hz : Integer = 90;
    }

    requirement 'CL-010-14' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the station's time as TimeRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-010-14'; }

    attribute def TimeRule {
        doc /* The top bar shows the UTC of station time (clock.time,
             WstxStationLink::SocketProtocol), the time the transmitter keys on, never the
             browser's own clock; the progress of the period is the QSO pane's bar
             (WstxQsoPane::PeriodBar). While the link is stale the time is marked stale. */
    }

    requirement 'CL-003-04' {
        subject browser : BrowserClient;
        doc /* The browser client MUST keep its link to the station as LinkRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-003-04'; }

    enum def LinkState {
        doc /* connecting: the socket is being opened, or its first reads are on the way.
             connected: the views are current. stale: the link is lost; the views show
             their last values, marked stale. */
        enum connecting;
        enum connected;
        enum stale;
    }
    attribute def LinkRule {
        doc /* The page opens its one socket (WstxStationLink::SocketProtocol) and reads
             each view once; it shows connected only when those reads have arrived. A socket
             that closes, or that brings no message for silenceMs, makes the link stale at
             once, without waiting for the old socket to end, and the error field names it.
             A new socket follows after retryMs, then twice that, up to retryMaxMs between
             attempts; one that is not open within connectMs is given up and the next
             attempt follows. A command is never sent again by a new socket; its outcome is
             learned from the views. */
        attribute 'state' : LinkState;
        attribute silenceMs : Integer = 12000;
        attribute retryMs : Integer = 1000;
        attribute retryMaxMs : Integer = 4000;
        attribute connectMs : Integer = 5000;
    }

    requirement 'CL-074-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST follow a new start of the station as BootRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-074-01'; }

    attribute def BootRule {
        doc /* When the page learns a bootId other than the one a view's values belong to,
             that view drops them at once and shows what a freshly loaded page shows before
             its reads; it never shows a value of the earlier start, alone or with values of
             the new one, and an answer that names another start is not used. Once the new
             start's reads and first events have arrived, the page equals a freshly loaded
             one, without a reload. */
    }

    requirement 'CL-051-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST take up a new client of the station as PageUpdate
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-051-02'; }

    attribute def PageUpdate {
        doc /* When station.status names a build other than the page's own
             (WstxListener::ClientBuild), the page loads itself again, once for that build,
             keeping FrontendConfig. It waits while a contact is in progress, the transmit
             state is on or Tune is on, a popup is open or Settings has unsaved changes; the
             error field then shows "Station updated · reload", whose click loads the page
             again. A second mismatch for a build the page loaded already shows the entry and
             loads nothing by itself. */
    }

    requirement 'CL-051-03' {
        subject browser : BrowserClient;
        doc /* The browser client MUST tell the operator of station data it cannot read as
             DataNotUnderstood says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-051-03'; }

    attribute def DataNotUnderstood {
        doc /* A view, an answer or a row that is not the form of its item is not shown: the
             error field shows "Station data not understood (<which>) · reload", whose click
             loads the page again; the next one of that kind in its form clears the entry. */
    }

    requirement 'CL-010-07' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the station's abilities apart as HealthRule
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-010-07'; }

    attribute def HealthRule {
        doc /* Audio, radio control, decoding and transmit are shown each on its own, from
             its own view; a connected link says nothing of any of them. A value that is
             not known is shown as not known, never as a default. A control the station
             cannot carry out now is disabled with its reason beside it. A radio port held by
             another program is named: "<port> in use by another program". */
    }

    requirement 'CL-111-04' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the transmit state and its cause as TxStateLine
             says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-111-04'; }

    attribute def TxStateLine {
        doc /* On a station that can transmit, the screen shows the transmit state and the
             cause of its last change at all times, in every region and at every width, from
             the view transmit alone (WstxTransmitControl::TransmitStatus); it takes no input.
             On: "Tx on", and "Tx on · Auto" for a start of Auto. Off: "Tx off" after
             startup; then by DisarmCause: contactCompleted "· QSO complete",
             contactCancelled "· QSO cancelled", halt "· halted", txWatchdog "· Tx watchdog:
             same message sent N times", deviceLost "· radio lost", refused "· Tx refused ·
             <reason>", failed "· Tx failed · <failure>", modeChanged "· mode changed",
             bandChanged "· band changed". */
    }

    requirement 'CL-017-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the help as HelpRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-017'; end #derive ::> 'CL-017-01'; }

    attribute def HelpRule {
        doc /* ? in the top bar, and F1, F3 and F5, open the help over the screen; its close
             control or a click outside closes it. It shows the keys (KeyRule) and what the
             pointer does in the waterfall and in Band Activity; the station's version and
             build; the notice that this program is an independent port of WSJT-X, not made
             or endorsed by its authors; its license, GPL-3.0-only, with the text of the
             license; and the sources it uses: WSJT-X, the country file of AD1C, the Most
             Wanted list of Club Log and PSK Reporter. It links to WSJT-X's online guide, for
             the modes and the practice of operating, and to the station's own guide once
             that exists.
             Every control shows a short help on hover and on keyboard focus, written for the
             operator in the words of operating: what the control does for the operator and
             when to use it, its key where it has one, and while it is disabled, why.
             What the station's rig cannot do is shown disabled and cannot be chosen or
             changed: a control of a radio function the rig lacks
             (WstxRadioControl::RadioStatus::abilities), whose help says "<rig> cannot
             <function> over CAT", and a band or working frequency outside the rig's
             transmit ranges (WstxRadioControl::RadioStatus::txRanges), whose help says
             "<rig> cannot transmit on <band>". */
    }

    attribute def LogbookPage {
        doc /* Logbook in the top bar opens the logbook over the workspace: its records page
             by page, newest first (WstxLogControl::ReadHistory), the export as an ADIF file
             (ExportLog) and the update from an ADIF file (WstxSettings::LogbookUpdate); its
             close control returns to the operating view. */
    }

    verification 'TC-010-009' {
        doc /* The UTC, the period bar and the level meter on station time. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-010-14'; }
        @TestedBy { test = "server/src/contact_http_tests.rs; tests/contact.test.cjs"; }
    }
    verification 'TC-021-007' {
        doc /* A lost link, the bounded retries and the fresh reads. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-04'; }
        @TestedBy {
            test = "tests/communication.test.cjs::"
                + "TC-021-007: dropped connection, bounded retries, fresh snapshot";
        }
    }
    verification 'TC-007-002' {
        doc /* The screen's regions, its abilities shown apart, keys and narrow windows. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-16'; verify 'CL-010-07'; verify 'CL-010-08'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-007-002 operating screen exposes literal identity and truthful "
                + "unsupported controls; "
                + "tests/ui-operating.test.cjs::"
                + "TC-007-002 operating split, drawer and pages remain accessible at narrow "
                + "and zoom equivalent sizes; "
                + "tests/ui-operating.test.cjs::"
                + "TC-007-002 readable text reflows throughout every operating region at 200 "
                + "percent; "
                + "tests/ui-operating.test.cjs::"
                + "TC-007-002 the transmit controls and badge follow the pushed transmit "
                + "capability";
        }
    }
    verification 'TC-007-009' {
        doc /* The one screen at 1366x768, the themes and the keys. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-16'; verify 'CL-010-08'; verify 'CL-037-03'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-007-009 one fixed operating screen at 1366x768 holds only the operating "
                + "items; "
                + "tests/ui-operating.test.cjs::"
                + "TC-007-009 Day, Dark and Night themes switch manually and by time without a "
                + "station request; "
                + "tests/ui-operating.test.cjs::"
                + "TC-007-009 the Rx/Tx strip, marker drag and WSJT-X keys send exactly the "
                + "expected requests";
        }
    }
    verification 'TC-051-002' {
        doc /* A held update and data the page cannot read. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-051-02'; verify 'CL-051-03'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-074-001' {
        doc /* A page kept open across a station restart. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-074-01'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-074-001 a page kept open across a station restart shows the new boot "
                + "strategy line without a reload";
        }
    }
    verification 'TC-074-003' {
        doc /* Every view on a new start. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-074-01'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs::"
                + "TC-074-003 on a new boot every view drops the previous boot at once, "
                + "discards its late replies and ends as a fresh page";
        }
    }
}
