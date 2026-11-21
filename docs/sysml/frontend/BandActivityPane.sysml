package WstxBandActivityPane {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-019';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxBrowserClientPart::HighlightSlot;
    private import WstxBrowserClientPart::SortField;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::CodeDiffers;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* Band Activity: the decoded stations of the latest periods, their order, colours and
         marks, what the pointer does on a row, and the strategy element above it. */

    requirement 'CL-010-09' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show each decoded record in Band Activity as RowFields
             says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-010-09'; }

    attribute def RowFields {
        doc /* A row shows UTC, dB, DT, Freq, Message, DXCC and Distance of one record (the
             read records, WstxReceiveControl::RecordsPage, with the view decodedFacts):
             UTC the start of its period, HH:MM:SS in FT8 and HH:MM:SS.S in FT4; dB the SNR
             in whole dB; DT signed with one decimal, +0.0 for zero; Freq the lowest tone in
             Hz; the message as the station gives it, a hashed call as <CALL> or <...>, and
             after it, apart from the text, aN for a frame decoded with a-priori help; DXCC
             the shown name of the sender's entity, with its continent and zones on the
             pointer; Distance the distance from the station's locator to a grid in the
             message with the azimuth to it (4523 km 285°), else the distance to the sender's
             entity written ~n km, in km or in miles as FrontendConfig::distanceInMiles says.
             A value the
             station does not give is shown as unknown, never guessed. A period without a
             station shows "No stations decoded"; "Loading results" shows while records of the
             view are still read. Sorting, colouring and the marks are the page's alone and
             change nothing at the station. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Band Activity's columns and the "
                + "a-priori marker";
        }
    }

    requirement 'CL-057-03' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the latest periods in Band Activity as Periods
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-057-03'; }

    attribute def Periods {
        doc /* Band Activity shows the latest period on top, all its records, and below a
             divider with its UTC the period it followed when that one has the other parity:
             the latest even and the latest odd period. When a period comes, the older one of
             its parity goes; a period of the same parity as the one before (a period was
             skipped), or one without a time, leaves the latest alone. Older periods are
             neither kept nor read again; after the page is loaded only the latest period
             shows until the next comes. A new receive (a start, a stop, a new band, mode or
             input, a new start of the station) begins an empty Band Activity. Each period is
             sorted by Ordering. */
    }

    requirement 'CL-057-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show a new period's records at once as Promptness
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-057-01'; }

    attribute def Promptness {
        doc /* When the view receive announces a new or grown period, the page reads that
             period's records at once, page after page, until it holds them all; on a LAN
             every row is shown within paintMs of the station's publication. The page reads
             no records on a timer. */
        attribute paintMs : Integer = 300;
    }

    requirement 'CL-061-03' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show a period the station transmitted in as TxPeriod
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-061-03'; }

    attribute def TxPeriod {
        doc /* While the latest period is one the station transmitted in (the view receive
             marks it), Band Activity shows one row "Tx <UTC> · this station transmitted · no
             decode" on top and its header reads "Tx · <MODE> period <UTC> UTC · this station
             transmitted, no decode"; the receive period below it stays with its divider and
             no "No stations decoded" block is added. When the next period comes, the Tx row
             goes and the receive period below stays below the new one. */
    }

    requirement 'CL-061-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST keep the operator's display across a loss of audio as
             LossEpoch says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-061-01'; }

    attribute def LossEpoch {
        doc /* When the view receive shows a new loss of audio within the same receive (the
             same profile, start, mode and input, a larger count of losses, no command of
             this page that changed receive), Band Activity keeps the periods it shows until
             the first period after the loss comes, and the waterfall keeps its rows with one
             grey gap row for the loss. The error field shows nothing for it. A row kept from
             before the loss stays bound to the receive it came from. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the display survives an audio gap";
        }
    }

    requirement 'CL-055-04' {
        subject browser : BrowserClient;
        doc /* The browser client MUST order Band Activity as Ordering says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-055-04'; }

    attribute def Ordering {
        doc /* By default (FrontendConfig::sortField value) each period is ordered by the
             value of its rows, best first: 1 calling the station's call; 2 a rank of the
             strategy, in the order of the ranking (WstxRankingControl::RankedList); 3 a new
             DXCC or continent; 4 a new DXCC or continent on the band; 5 a new CQ or ITU zone,
             also on the band; 6 a new grid, also on the band; 7 a new call, also on the band;
             8 none of these. Equal values follow the SNR, strongest first, then the order of
             decoding. A click on the header of Freq, dB, DT or Message orders by that column,
             a second click turns the direction; the header of DXCC returns to the value. An
             unknown value goes last in either direction. The choice is kept for this browser
             (FrontendConfig::sortField, sortDescending). */
    }

    requirement 'CL-050-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST colour Band Activity as Highlight says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-050-02'; }

    attribute def Highlight {
        doc /* The highlight slots (HighlightSlot) have WSJT-X's colours and priority; the
             slots that are on are FrontendConfig::highlight, chosen in Settings > General >
             Display. myCall holds for a message to the station's call, also as a filled-in
             hash or the addressee of a nonstandard message; each new slot holds for the
             sender of every decoded message whose flags (the view decodedFacts) carry it. A
             row takes the highest slot that is on and holds, and colours as RowMarks says. A
             row with no such slot has no colour: being worked before colours nothing. The
             strategy's mark is an accent of the row, never its colour. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: DecodeHighlightingModel, its colours, "
                + "priority and defaults";
        }
        @DiffersFromSource {
            what = "WSJT-X colours only CQ and QRZ lines and lines to my call, has a slot for "
                + "every CQ, and has New call off; the station colours the sender of every "
                + "message, has no CQ slot, and has both new-call slots on.";
        }
    }

    requirement 'CL-050-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST mark each row by what makes it interesting as RowMarks
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-050-08'; }

    enum def RowMark {
        doc /* The mark of a row, highest first; a row takes the first that holds.
             partner: its sender is the partner of the contact in progress (the view qso).
             callsMe: a message to the station's call from another station.
             newWholeRow: a CQ or QRZ whose sender has a slot of Highlight.
             newSenderOnly: any other message whose sender has such a slot.
             plain: everything else. */
        enum partner;
        enum callsMe {
            @CodeDiffers { what = "The code marks such a row with the class ba-tome."; }
        }
        enum newWholeRow {
            @CodeDiffers {
                what = "The code marks such a row by its slots in data-hl, without the class "
                    + "ba-sender.";
            }
        }
        enum newSenderOnly {
            @CodeDiffers { what = "The code marks such a row with the class ba-sender."; }
        }
        enum plain;
    }
    attribute def RowMarks {
        doc /* partner: from the contact's preparation until it is completed or cancelled,
             the partner's rows stand at the top of Band Activity, newest period first, above
             a red divider, each with a red bar at its left, ◆ QSO after its message and the
             message in bold, without the colour of a slot. callsMe: the whole row in the
             colour of myCall, also when the sender was worked before. newWholeRow: the whole
             row in its slot's colour. newSenderOnly: only the sender's call in the message in
             that colour. plain: no colour. With myCall off a callsMe row falls back to its
             new slots.
             A row with a reason of its colour that the row does not show carries one tip
             line on the pointer and on keyboard focus: per kind (continent, DXCC, zone,
             grid, call) the strongest reason that is on, "New continent <cont>" or "New
             continent on <band>", "New DXCC" or "New DXCC on <band>", "New CQ zone <cq>",
             "New ITU zone <itu>" or their forms on <band>, "New grid <square>" or "New grid
             on <band>", "New call" or "New on <band>"; then the strategy's verdict
             ("Strategy <name>: #<rank>", or for a CQ not for the station "Directed CQ, not
             calling us"); joined by " · ". The country, the continent, the
             distance and a call to the station are not in the tip; their columns show them. */
    }

    requirement 'CL-055-05' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show many stations at once as Density says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-055-05'; }

    attribute def Density {
        doc /* Rows are as tight as the normal size of text allows, so that many stations
             show at once; with a touch pointer a row stays tall enough to tap; on a narrow
             window a row is a compact row of two lines without field names. */
    }

    requirement 'CL-037-05' {
        subject browser : BrowserClient;
        doc /* The browser client MUST act on the pointer and the keys on a row as RowActions
             says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-037-05'; }

    attribute def RowActions {
        doc /* A click on a row gives SelectRow (WstxQsoControl), which prepares and never
             transmits. While a contact is in progress a click offers a change only on a row
             that can start a contact for the station, a CQ or QRZ the directed-CQ rule lets
             it answer (WstxValueOrder::DirectedCqRule) or a message to its call, as "Change
             contact to <call>" naming the sender; on any other row it offers nothing.
             A double-click gives Reply, with replace on a row of another station while a
             contact or the own CQ is in progress, as WSJT-X's double-click with quick call;
             on a row of a QSO between others the command line reads "Call <sender>". A
             double-click whose row is drawn again between its two clicks still replies. A
             CQ not for the station first shows the warning of the directed-CQ rule; only
             its confirmation selects (directiveConfirmed).
             The other mouse button, the menu key and Shift+F10 open the row's menu: Reply,
             Select, Set Rx here (SetFrequency), and for a row with a resolved sender "Ignore
             <call>" or "Stop ignoring <call>" (WstxRankingControl::IgnoreCommand) and
             "Wanted <call>" or "Not wanted <call>" (the collection wantedList of
             WstxProfileAccess). Enter selects. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: widgets/mainwindow.cpp "
                + "handleDecodeSelection with quick call";
        }
    }

    requirement 'CL-039-04' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the strategy above Band Activity as
             StrategyElement says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-039-04'; }

    attribute def StrategyElement {
        doc /* Above Band Activity, in one line: the strategy selector (Default, then the names,
             grouped Strategy and Contest; a choice gives SelectStrategy,
             WstxStrategies); edit, which opens the editor (WstxSettings::StrategyEditor);
             Value, which returns the order to the value (Ordering); with a contest in force
             Show all; the ignore field (IgnoreField); and Auto's line
             (WstxQsoPane::AutoControls). While a strategy other than Default is active, Band
             Activity lists only the rows the strategy ranks (the view ranked), the messages to the
             station's call and the partner's rows; a row the strategy filters out is not shown.
             Show all, off by default and kept in the page only, shows every row. The rows are drawn
             after each new period. A selection restarts no receive. */
    }

    requirement 'CL-063-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show a contest's stations as ContestFilter says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-063-08'; }

    attribute def ContestFilter {
        doc /* With a contest in force Band Activity lists the stations the contest can work,
             as StrategyElement says for every strategy. A callable station is
             coloured, a new multiplier apart; a dupe and a CQ directed elsewhere are dimmed
             (WstxRankingControl::ContestVerdict). The line shows the contest, its period, the
             strategy and the tally (qsos, multipliers, score). Every row stays selectable
             with Show all, so a contest also runs by hand. */
    }

    requirement 'CL-042-06' {
        subject browser : BrowserClient;
        doc /* The browser client MUST offer the ignore list on the operating screen as
             IgnoreField says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-019'; end #derive ::> 'CL-042-06'; }

    attribute def IgnoreField {
        doc /* The one ignore list (WstxRankingControl::IgnoreLists) is one field of entries
             separated by commas, each a call or a pattern; an entry added gives
             IgnoreCommand with ignore true, one removed with ignore false, and the erase
             button ClearIgnoreList. The field shows the list as the view ranking last gave
             it. */
    }

    verification 'TC-007-006' {
        doc /* The latest period's rows, their timing and their states. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective { verify 'CL-010-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs; server/src/recording_tests.rs"; }
    }
    verification 'TC-024-004' {
        doc /* Free text in Tx5 and rows to <MYCALL>. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-09'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-055-004' {
        doc /* The DXCC column and the distance. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-010-09'; }
        @TestedBy { test = "tests/contact.test.cjs"; }
    }
    verification 'TC-057-004' {
        doc /* Only the latest even and odd periods. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-057-03'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-057-001' {
        doc /* A busy period reaches Band Activity at once. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-057-01'; }
        @TestedBy {
            test = "server/src/receive_http_tests.rs; tests/frontend/receive-latency.test.cjs";
        }
    }
    verification 'TC-061-004' {
        doc /* A transmitted period shows its Tx row and no empty block. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-03'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-061-001' {
        doc /* A loss of audio keeps the waterfall and Band Activity. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-055-006' {
        doc /* The colours, the tips and the value order for every sender. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-04'; }
        @TestedBy { test = "server/src/dxcc_tests.rs; tests/ui-operating.test.cjs"; }
    }
    verification 'TC-050-002' {
        doc /* WSJT-X's highlight colours and the station's differences. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-02'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-050-008' {
        doc /* The marks: the partner first, a call to the station, the tip. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-08'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs; tests/frontend/receive-page.test.cjs; "
                + "server/src/receive_http_tests.rs";
        }
    }
    verification 'TC-055-007' {
        doc /* Tight rows. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-05'; }
        @TestedBy {
            test = "tests/ui-operating.test.cjs; "
                + "tests/receive-integration.test.cjs::"
                + "real native audio reaches Rust manager HTTP and literal browser callsign";
        }
    }
    verification 'TC-037-004' {
        doc /* A change of contact only on a row that can start one. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-037-05'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-039-006' {
        doc /* The strategy selector and its marks. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-04'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-063-008' {
        doc /* The callable list of a contest and Show all. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-063-08'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
}
