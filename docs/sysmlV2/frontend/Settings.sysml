package WstxSettings {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-026';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxBrowserClientPart::FrontendConfig;
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* The settings drawer: its sections, what each shows and changes, how a change is
         saved, and the strategy editor, the Most Wanted list and the alerts. */

    requirement 'CL-227-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the settings as SettingsDrawer says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-227-01'; }

    attribute def SettingsDrawer {
        doc /* Settings in the top bar, or F2, opens the drawer over the workspace; the
             waterfall keeps running and a HALT stays on screen; its close control or a click
             outside closes it. Its sections, in this order: Station (StationSection), Radio
             (RadioSection), Flex on a profile of the native connection (FlexSection),
             Operating (OperatingSection), Strategies and contests (StrategiesSection), Files
             (FilesSection), Destinations (DestinationsSection), Display (DisplaySection) and
             Advanced (AdvancedSection). It shows the values of the views config, shack and
             definitions; what the station keeps for itself (its records) shows nowhere.
             Each value is marked as the shack's, shared by every station of the PC, or as
             this station's own.
             This station's values are changed in the form and saved by Save: one saveConfig
             of the whole station config. A value whose change restarts receive or the radio
             connection asks first while a contact is in progress or the station transmits.
             The shack's values are saved by saveShack from the revision they were read at;
             a member of a collection (a strategy, a UDP target, an entry of the wanted list,
             a Tx macro, a working frequency) is added, changed or removed on its own
             (createEntry, updateEntry, deleteEntry).
             A save refused with revisionConflict reloads the shack's values and says
             "Another station changed the shared settings; reloaded". The answer of a save is
             its outcome (SaveOutcome). Unsaved changes stay until they are saved or Reload
             is pressed. Every text of the station shows as text. */
    }
    requirement 'CL-001-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the settings check as CheckView says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-001-02'; }

    attribute def CheckView {
        doc /* Settings check stands at the top of the settings drawer. With a radio that
             can be keyed it first asks "The check sends a Tune tone. Continue?" and gives
             checkSettings with withTune by the answer. The lines of the view settingsCheck
             show as they come, each with ✓, ✗ or –, what was checked, the reason, and a link
             to the section where it is changed; the end reads "Ready to operate" or
             "<n> problems". */
    }

    attribute def StationSection {
        doc /* The station's name (displayName): offered as the chosen rig's name, as model
             and slice A to F for a FlexRadio, or "No radio", taken or typed, refused when
             another station of the PC has it; shown in the window's title and in the top
             bar. The call sign, the locator, the continent and the CQ words of the shack
             (WstxProfileAccess::ShackConfig); the CQ words proposed as the continent's code
             and the primary prefix of the call's entity, which the operator takes or
             changes. */
    }
    attribute def RadioSection {
        doc /* The rig, chosen from the rigs radio control's catalogue has, by Hamlib's name
             (WstxRadioControl::ControlSelection::rig), as WSJT-X's rig list; the control mode
             (CAT or none), the CAT port and the PTT method. RadioLine. The AGC choice with
             its line, hidden without a managed radio: "Radio AGC <value> · set and read
             back", "· read back, already as set", "· not applied · <reason>", "· not yet read
             from the radio", and the recommendation "AGC SLOW · recommended for FT8/FT4".
             Detect radio (DetectRadio) and Apply recommended settings (applyRecommended).
             The audio (AudioSection). Every control of a radio function the rig lacks is
             disabled (WstxOperatingScreen::HelpRule). The output power of the station's
             band in percent (WstxRadioControl::RadioConfig::powers) with what came of
             setting it on the radio (the view power). The audio drive: manual or automatic
             (WstxTransmitControl::TransmitConfig::levelMode, automatic by default); manual
             shows a drive slider for the station's band, as WSJT-X's Pwr; while the ALC
             cannot be read the slider shows in both modes; the meters and the drive's
             warnings show in both. Split operation, None, Rig or Fake It
             (WstxTransmitControl::TransmitConfig::split), with a radio over CAT. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Settings > Radio, Rig and Pwr";
        }
    }
    attribute def RadioLine {
        doc /* The state of the radio connection in words: ready with the dial and mode; "CAT
             unavailable · <reason> · automatic retry in <n> s"; "<port> in use by another
             program"; "Actual rig frequency unknown" while the dial is not known. The radio
             connection opens and closes by itself; there is no Connect or Disconnect. */
    }
    attribute def FlexSection {
        doc /* On a profile of the native connection: the receive antenna and the radio's
             address (WstxProfileAccess::NativeIntent), and the session's line: "Native
             FlexRadio <state> · <error> · <model, firmware, serial, address, API> · slice
             <letter, frequency, mode, antenna> · transmit unsupported", "Native FlexRadio
             status stale · station disconnected" while the link is lost. */
    }
    attribute def OperatingSection {
        doc /* Auto Seq and Call 1st, the repetition limit (WstxQsoControl::QsoConfig), the
             Tune limit in seconds (WstxTransmitControl::TransmitConfig), and the Rx and Tx
             offsets at station start. The working frequencies of the shack, each added,
             changed or removed on its own (the collection workingFrequencies), Reset
             (ResetFrequencies), and the IARU region
             (WstxStationCommands::WorkingFrequencies::region). Log automatically, the shack's
             (WstxQsoControl::QsoShared::logAutomatically). The Tx macros of the shack,
             each added, changed or removed on its own (the collection txMacros). The
             activity and its exchange stand in the QSO pane's fold-out
             (WstxQsoPane::MessagesFoldOut). */
    }
    attribute def StrategiesSection {
        doc /* The strategy editor (StrategyEditor); the wanted list, one entry added or
             removed at a time; the Most Wanted list (MostWantedDisplay); the acknowledgement
             of Auto under a contest that forbids automatic operation
             (WstxAutoControl::AutoConfig::forbiddenContests), with the wording of the
             contest's warning; a refused Auto on with notConfirmed points here. */
    }
    attribute def FilesSection {
        doc /* The logbook: the Logbook page (WstxOperatingScreen::LogbookPage) and
             LogbookUpdate. Export Cabrillo (exportCabrillo): a contest and its period, the
             contest in force and its period offered first, the header of the shack
             (WstxLogControl::LogShared::cabrillo) saved by saveShack, the claimed score
             from the view of the contest's score, the file given as a download. The
             country file in use, with its version and the date of its
             source, and Update country file (updateCountryFile). */
    }
    attribute def LogbookUpdate {
        doc /* Update logbook from ADIF: a file, then the button; the file goes in parts
             (reserveImport, importChunk) and the line reads "Logbook updated: N added, M
             already present (C confirmations updated), K skipped" or "Logbook not updated ·
             <reason>". */
    }
    attribute def DestinationsSection {
        doc /* The WSJT-X UDP interface: the station's instance name as text, "not fixed yet"
             while it has none; the targets, each address and port, enabled, the multicast TTL
             or hop limit and the interface, each with its status (active, schema, last send,
             error); the note that programs listen and send nothing to the station. PSK
             Reporter: Listen to PSK Reporter spots, and its line: "Connected · no spot yet",
             "Connected · last spot <n> min ago", "Off", "Not connected · <code> · retrying",
             or the storage error; and Use PSK Reporter, as in the QSO pane. The targets and both
             switches of PSK Reporter are the shack's. */
    }
    attribute def DisplaySection {
        doc /* The choices of this browser (FrontendConfig): the theme, Day, Dark or Night,
             and its switch, by hand, at two times, or at sunrise and sunset; the display,
             Detailed, Thin or Off, with the note that Detailed needs a fast link; Flatten and
             the spectrum line; the highlight slots, each with its colour; distances in km or
             miles; the alerts' Sound and Browser notification (AlertDisplay); the sound of
             a station calling, or Off (CallAlert). */
    }
    attribute def AdvancedSection {
        doc /* Shown and not changed: the listener's address, the origin and the connection
             type. The clock (ClockView). Diagnostics: Save FT8 decode windows
             (WstxReceiveControl::ReceiveConfig::windowDump) with the latest window's
             counters; the resume of receive at station start (StartupState); receive's
             start and stop by hand (startLive, stopLive); the recordings: "No recording
             imported", "Recording ready", "Recording unavailable", the import of a WAV file
             in parts with its progress and Cancel, and Replay (startReplay); the radio's
             facts as read; the link's details. */
    }
    attribute def ClockView {
        doc /* The view clock in words: the state of station time and its correction; the time
             server and its state; the state of the Windows time service, and for a PC clock
             that is off the remedy by that state; the stations heard, "Clock accepted
             (stations heard are not off to one side)" or how far they are off; the warning of
             the clock and of the capture, as the error field names them. */
    }

    requirement 'CL-073-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST take the answer of a save as its outcome as
             SaveOutcome says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-073-01'; }

    attribute def SaveOutcome {
        doc /* The answer to a save is its outcome. A save answered with the new values shows
             "Saved" and takes those values, as a read would. A refusal shows its reason at
             the field it names (ErrorBody::field), "Invalid callsign" for the call sign; the
             form keeps what was typed. A save with no answer, lost with the link, shows "Save
             outcome unknown. Reload saved settings before retrying." and Save stays disabled
             until Reload; nothing is sent again by itself. While a save is on its way, Save
             is disabled and no second save is sent. Reload shows "Loaded saved settings.". */
    }

    requirement 'CL-044-06' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the detection of the radio as DetectRadio says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-044-06'; }

    attribute def DetectRadio {
        doc /* Detect radio is enabled only after the operator ticks that USB SEND and USB
             keying are off or the radio is on a dummy load, and that opening a port can pulse
             DTR and RTS also on other boards of the same kind; a press gives one detectRadios
             with keyingInhibitConfirmed and clears the tick. The answer
             (WstxStationCommands::RadioDetection) shows the ports, the radio proposed with
             its menu settings and their recommended values, and the input and output proposed
             at its place; the operator takes them into the form. While radio control has not
             had the keying confirmation once, the section says that discovery waits for it. */
    }

    requirement 'CL-044-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the audio devices by name as AudioSection says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-044-08'; }

    attribute def AudioSection {
        doc /* One Audio section in Radio: the input with the Rx level meter beside it, the
             output, and the radio's recommendation. Each offers None and the endpoints of its
             direction (the read endpoints, when the drawer opens), each shown by its label and
             saved by its id; a saved endpoint that is gone shows its last known name, marked
             absent. The level meter shows the input level of the view receive, high and low
             marked, while receive runs. */
    }

    requirement 'CL-039-25' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show and update the Most Wanted list as
             MostWantedDisplay says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-25'; }

    attribute def MostWantedDisplay {
        doc /* "List from <date> · <n> entries" with the entries that map to no entity, or "No
             list; strategies call the strongest first", the source's attribution, and one
             button Update Most Wanted (updateMostWanted), fetched once on the click; a
             failure keeps the list and shows the reason in one line. */
    }

    requirement 'CL-097-12' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the strategies' editor as StrategyEditor says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-097-12'; }

    attribute def StrategyEditor {
        doc /* The editor opens over the screen with a HALT of its own; receive keeps running.
             It lists the strategies grouped Strategy and Contest, the built-ins read-only. A
             new strategy is made only as a copy of another, "<name> copy", keeping its class,
             contest and alert; a class is never switched. A strategy shows the ten decisions of
             WstxStrategies::StrategyForm, in their order: 1 the bands; 2 the filters (what
             must be new, new per, new means, the region, the minimum SNR, worked since, 73 as
             CQ, the prefix or country, US state and CQ target lists, and that callers of the
             station's call pass them too), for a contest only the three lists; 3 the order of
             the criteria, then SNR, for a contest the contest's rules; 4 calling stations
             answered first; 5 leaving a station; 6 the Tx frequency per PSK Reporter case; 7
             the busy pause; 8 CQ when idle after n periods; 9 the retry pause; 10 the alert,
             Off or one of WstxStrategies::AlertSound, each heard when chosen. A refused value
             shows at its control with its reason. The preview evaluates the unsaved form
             against the latest period (evaluate with explain) after each edit and shows each
             record's rank and why. Save gives one createEntry or updateEntry of the
             collection strategies and selects nothing; Delete gives deleteEntry, and deleting
             the active strategy ends the selection. Each strategy renamed by the station shows
             once as "Renamed <from> to <to>". The contest prompt offers a contest's period
             and its strategies. */
    }

    requirement 'CL-042-07' {
        subject browser : BrowserClient;
        doc /* The browser client MUST announce and list the alerts as AlertDisplay says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-042-07'; }

    attribute def AlertDisplay {
        doc /* Sound and Browser notification, both off by default, are choices of this
             browser; ticking Browser notification is the one place that asks the browser
             for its permission, and a permission not granted leaves it unticked with the
             reason. The history of the view alerts, newest first, each line "<HH:MM:SS>
             <call> <message> · <rule> · <band> <MODE> · <snr> dB · <dxcc>", with Clear
             (clearAlerts). An alert newer than every one the page has seen plays its
             AlertEntry::sound when Sound is on and the page is shown, and a notification
             "Alert <call>" with "<message> · <rule>" when Browser notification is on, also
             while the page is hidden; the history read when the page loads announces
             nothing. */
    }

    requirement 'CL-042-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST ring when a station calls the operator, as CallAlert
             says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-042-08'; }

    attribute def CallAlert {
        doc /* A row of Band Activity marked callsMe (WstxBandActivityPane::RowMarks) whose
             sender is not the partner of the contact in progress rings once for that
             sender until the contact in progress changes: it plays
             FrontendConfig::callSound when Sound is on and the page is shown, and gives
             the notification "<call> calls you" with the message when Browser notification
             is on, also while the page is hidden. With callSound absent it rings not. The
             rows read when the page loads ring not. */
    }

    verification 'TC-073-001' {
        doc /* A save's answer is its outcome. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-073-01'; }
        @TestedBy { test = "tests/profiles.test.cjs"; }
    }
    verification 'TC-073-002' {
        doc /* Answers that arrive are known, lost ones stay unknown. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-073-01'; }
        @TestedBy { test = "tests/profiles.test.cjs"; }
    }
    verification 'TC-044-005' {
        doc /* The Detect radio panel. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-06'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-044-022' {
        doc /* The line on the keying confirmation. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-06'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-044-007' {
        doc /* The audio section shows names, not ids. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-08'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-044-010' {
        doc /* The AGC choice and its line. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-227-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-039-021' {
        doc /* The PSK Reporter line in Destinations. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-227-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-043-003' {
        doc /* The clock in words. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-227-01'; }
        @TestedBy {
            test = "server/src/transmit/clock_http_tests.rs; tests/ui-operating.test.cjs";
        }
    }
    verification 'TC-110-005' {
        doc /* The settings after a restart of the station. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-227-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-042-007' {
        doc /* The alert history, the sound and the notification. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-07'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
}
