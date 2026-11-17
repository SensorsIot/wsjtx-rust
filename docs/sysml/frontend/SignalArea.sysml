package WstxSignalArea {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-010';
    private import WstxBrowserClientPart::BrowserClient;
    private import WstxBrowserClientPart::FrontendConfig;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* The signal area: the spectrum and the waterfall of 0 to 3000 Hz, the pointer and
         the Rx and Tx lines on them, the Rx/Tx strip and the marks of the open slots. */

    requirement 'CL-006-08' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the station's rows as SignalLayout says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-006-08'; }

    attribute def SignalLayout {
        doc /* The signal area spans the screen's width above the workspace: the frequency
             ruler of 0 to 3000 Hz, the waterfall below it with a ruler of seconds at its
             side, the spectrum line above it when FrontendConfig::spectrumLine is on, and the
             Rx/Tx strip below (RxTxStrip). The whole span of 0 to 3000 Hz fits the width at
             every width; the divider below the area sets its height by pointer and by keys,
             kept as FrontendConfig::signalHeight. At the default height and speed the
             waterfall holds about two FT8 periods.
             The waterfall asks for the rows of FrontendConfig::display: detail the detailed
             rows, thin the thin rows, off none (WstxStationLink::DisplayRows); newest at the
             top, older rows moving down at the time scale of DisplayLevels, so a row's height
             is its time. A row is drawn as the station gave it, each level in its own cell,
             without smoothing; a row the station did not give within its window is a grey
             gap, and only such a row. On live receive a thin line crosses the waterfall at
             the start of each period, without text. A new job, a new profile and a new start of the
             station begin an empty waterfall. The pointer over the waterfall reads the
             frequency and the level under it. */
    }

    requirement 'CL-054-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST colour the waterfall as DisplayLevels says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-054-02'; }

    attribute def DisplayLevels {
        doc /* A fixed mapping of level to colour, as WSJT-X's Wide Graph: the black of the
             scale lies referenceDbfs below full scale, moved by Sensitivity
             (FrontendConfig::sensitivityDb, as WSJT-X's Zero), and the scale spans Range
             (rangeDb, as WSJT-X's Gain). No level follows the signal over time, and a new
             job, source or profile changes none. Below the scale is dark, above it the
             strongest colour; a gap is grey. Flatten (FrontendConfig::flatten) evens out the
             passband's shape across frequency in each row, as WSJT-X's flattening; it
             changes no level over time, and the readout keeps the station's level. The
             spectrum line's scale runs from the scale's black to full scale. Speed
             (FrontendConfig::speed, in steps of speedStep) sets the time scale of the
             waterfall. Sensitivity, Range and Speed sit in a corner of the waterfall, each
             with its value; Flatten and the spectrum line in Settings; every choice applies
             at once and is kept for this browser. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the Wide Graph (Zero, Gain, Flatten)";
        }
        attribute referenceDbfs : Integer = -85;
        attribute speedStep : Real = 0.5;
    }

    requirement 'CL-054-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST draw the rows in their order as RowOrder says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-054-01'; }

    attribute def RowOrder {
        doc /* Rows are drawn in the order of their sequence. A detailed row that comes late
             after a stall of the station is drawn in its place, so a stall delays rows and
             loses none within the station's window (WstxStationLink::DisplayRows); a thin row
             the station paces out between two sent rows is drawn with the next. */
    }

    requirement 'CL-061-05' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show a transmitted period in the waterfall as TxBand
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-061-05'; }

    attribute def TxBand {
        doc /* Each run of rows the station marks tx is one thin dark red band instead of its
             time, so the waterfall holds still while the station transmits and receive rows
             keep the time scale. The ruler of seconds stays true beyond the band: a time
             below the band counts without the band's time. A row missing between two tx
             rows of one transmitted period belongs to the band, not to a gap. In every
             theme the waterfall keeps its dark ground and the band its dark red. */
        @DiffersFromSource {
            what = "WSJT-X's waterfall shows the transmitted period at its full time; the "
                + "station collapses it to a thin band.";
        }
    }

    requirement 'CL-050-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST set the Rx and Tx offsets from the waterfall and the
             strip as PointerRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-050-01'; }

    attribute def PointerRule {
        doc /* In the waterfall a click sets Tx, and a double-click sets Rx and Tx with one
             SetFrequency (WstxQsoControl); a key held with the click changes nothing, and
             a click of the other mouse button sets nothing. The Rx line (green) and the Tx
             line (red) run over the waterfall's height without text; each is dragged to a
             new place, and its release gives one SetFrequency. The help names this mapping
             (WstxOperatingScreen::HelpRule). No pointer action switches transmission on. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the Wide Graph's mouse use";
        }
    }
    attribute def RxTxStrip {
        doc /* Below the waterfall, in one line: Rx with its offset and - and + buttons, Tx
             with its offset and - and + buttons, Tx=Rx, Rx=Tx, and SwrValue. An offset is
             typed exactly in Hz, or stepped by stepHz with the buttons, the mouse wheel or
             the arrow keys, by shiftStepHz with Shift. Each change gives one SetFrequency;
             the fields show the offsets of the view qso only, so a value typed is shown as
             set once the station has it. */
        attribute stepHz : Integer = 1;
        attribute shiftStepHz : Integer = 10;
    }

    requirement 'CL-050-07' {
        subject browser : BrowserClient;
        doc /* The browser client MUST place the pointer, the lines and the ruler on one
             frequency scale as FrequencyMapping says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-050-07'; }

    attribute def FrequencyMapping {
        doc /* The waterfall's own width carries 0 Hz at its left edge and 3000 Hz at its
             right edge; the pointer, the Rx and Tx lines and the ticks of the ruler use this
             one scale, so a line and the tick of a frequency stand where the pointer that
             chose it stood, at every width, display choice and pixel density. Each line marks
             the lowest tone of the signal and carries WSJT-X's bracket of its colour at the
             top of the waterfall over the width the signal takes to its right, by the
             station's operating mode. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the Wide Graph's Rx and Tx markers";
        }
    }

    requirement 'CL-068-01' {
        subject browser : BrowserClient;
        doc /* The browser client MUST show the last SWR in the strip as SwrValue says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-068-01'; }

    attribute def SwrValue {
        doc /* The strip ends with SWR and the last SWR reading of the view txLevel
             (WstxTransmitControl::TxLevelStatus), with one decimal, while that view has a
             managed level and a reading; otherwise it shows none. The reading stays until a
             newer one, also after the transmission or Tune that made it and across a change
             of the band. It is in the error colour above redAboveSwr. It takes no input. */
        attribute redAboveSwr : Real = 2.0;
    }

    requirement 'CL-065-02' {
        subject browser : BrowserClient;
        doc /* The browser client MUST mark the open Tx slots above the waterfall as
             OpenSlotMarks says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-010'; end #derive ::> 'CL-065-02'; }

    attribute def OpenSlotMarks {
        doc /* Each open range of the view openSlots (WstxQsoControl::OpenSlots) is a green
             bar in the frequency ruler directly above the waterfall over that range, on the
             scale of FrequencyMapping, always, whoever runs the contact. Two touching ranges
             show a gap between their bars; the bars carry no text and take no input; their
             green stands clearly apart from the Rx and Tx lines and from the ruler in every
             theme. Each new view redraws them; an absent view, a view without ranges, a new
             start of the station and the display off remove them. */
    }

    verification 'TC-010-003' {
        doc /* The signal area, its divider and its regions at every size. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-08'; }
        @TestedBy { test = "tests/recording.test.cjs"; }
    }
    verification 'TC-010-007' {
        doc /* Rows move down by their time at each speed; gaps and stops. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-08'; }
        @TestedBy { test = "tests/recording.test.cjs"; }
    }
    verification 'TC-010-006' {
        doc /* The colours of known levels under each Sensitivity, Range and Speed. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-054-02'; }
        @TestedBy { test = "tests/recording.test.cjs"; }
    }
    verification 'TC-054-002' {
        doc /* The fixed mapping, Zero and Gain, Flatten and the spectrum line. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-054-02'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-054-001' {
        doc /* Detailed rows in order after a stall; gaps only for real gaps. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-054-01'; }
        @TestedBy { test = "server/src/protocol_tests.rs; tests/ui-operating.test.cjs"; }
    }
    verification 'TC-061-008' {
        doc /* A transmitted period is a thin band, and the ruler stays true. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-05'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-061-006' {
        doc /* Transmitted rows, and the level warnings of receive periods only. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-05'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-050-001' {
        doc /* The pointer, the lines and a double-click on a row. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-01'; }
        @TestedBy { test = "tests/contact.test.cjs; tests/ui-operating.test.cjs"; }
    }
    verification 'TC-010-008' {
        doc /* The pointer in the waterfall and the offsets of the strip. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-01'; }
        @TestedBy { test = "tests/contact.test.cjs"; }
    }
    verification 'TC-050-007' {
        doc /* The pointer, the lines and the ruler on one scale; the brackets. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-050-07'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-068-001' {
        doc /* The SWR at the end of the strip. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-068-01'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-082-004' {
        doc /* The open slot marks always above the waterfall. */
        subject browser : BrowserClient;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-065-02'; }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
}
