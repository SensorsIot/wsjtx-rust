package WstxBrowserClientPart {
    private import ScalarValues::*;
    private import WstxStationLink::BrowserExchange;
    private import WstxStationLink::DisplayProfile;
    private import WstxStrategies::AlertSound;
    private import WstxOperatorInteraction::OperatorInteractionPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def BrowserClient {
        doc /* One browser window of a station: it shows the station's views to the operator
             and sends the operator's commands and reads. It holds copies of the station's
             state only (M5.2) and decides nothing of it; what it keeps of its own is the
             operator's display choices (FrontendConfig). */
        @ImplementedIn {
            module = "client/src/frontend/index.html; client/src/frontend/app.js; "
                + "client/src/frontend/contact.js; client/src/frontend/recording.js; "
                + "client/src/frontend/logbook.js; client/src/frontend/style.css; "
                + "client/src/frontend/recording.css; client/src/frontend/authorization.js";
        }
        @DetailTests {
            tests = "tests/communication.test.cjs; tests/profiles.test.cjs; "
                + "tests/radio-selection.test.cjs; tests/ui-operating.test.cjs";
            covers = "the label each stale path names on the station-stale event; the silence "
                + "bound while a client file downloads; the browser's grant: the token login "
                + "and its retries, the retained credential, its renewal and faults, and the "
                + "transport cookie; a selection whose answer is lost; the job a live frame "
                + "belongs to inside the page, and the screen's behaviour no clause states yet";
        }
        attribute config : FrontendConfig;
        port station : BrowserExchange { doc /* The station, through web. */ }
        port operator : OperatorInteractionPort { doc /* The operator at the screen. */ }
    }

    enum def Theme {
        doc /* day: light. dark: dark. night: dim and warm, for eyes adapted to the dark. */
        enum day;
        enum dark;
        enum night;
    }
    enum def ThemeSwitch {
        doc /* manual: the chosen theme stays. byTime: day and night at two local times.
             bySun: day and night at sunrise and sunset at the station's locator. */
        enum manual;
        enum byTime { @CodeDiffers { what = "The code names it time."; } }
        enum bySun { @CodeDiffers { what = "The code names it sun."; } }
    }
    enum def HighlightSlot {
        doc /* The highlight slots of Band Activity, in their priority, highest first. */
        enum myCall;
        enum newContinent;
        enum newContinentBand;
        enum newCqZone;
        enum newCqZoneBand;
        enum newItuZone;
        enum newItuZoneBand;
        enum newDxcc;
        enum newDxccBand;
        enum newGrid;
        enum newGridBand;
        enum newCall;
        enum newCallBand;
    }
    enum def SortField {
        doc /* What Band Activity is sorted by: its value, or one of its columns. */
        enum 'value';
        enum frequency;
        enum snr;
        enum dt;
        enum 'message';
    }
    attribute def FrontendConfig {
        doc /* The operator's display choices of one browser for one station: kept in that
             browser for the station's origin, never sent to the station, and the same in
             every window of that browser for that station. A choice that cannot be read or
             kept leaves its default, and the screen works without it. */
        attribute theme : Theme = Theme::dark;
        attribute themeSwitch : ThemeSwitch = ThemeSwitch::manual;
        attribute display : DisplayProfile = DisplayProfile::detail {
            doc /* The rows the waterfall asks for (WstxSignalArea::SignalLayout). */ }
        attribute sensitivityDb : Integer = 0 {
            doc /* WSJT-X's Zero (WstxSignalArea::DisplayLevels). */ }
        attribute rangeDb : Integer = 50 {
            doc /* WSJT-X's Gain (WstxSignalArea::DisplayLevels). */ }
        attribute speed : Real = 1.0 {
            doc /* The waterfall's speed (WstxSignalArea::DisplayLevels). */ }
        attribute flatten : Boolean = false {
            doc /* Even out the passband (WstxSignalArea::DisplayLevels). */ }
        attribute spectrumLine : Boolean = false {
            doc /* Show the spectrum above the waterfall (WstxSignalArea::SignalLayout). */ }
        attribute signalHeight : Integer[0..1] {
            doc /* The height the operator gave the signal area with the divider; absent:
                 the default (WstxSignalArea::SignalLayout). */ }
        attribute highlight : HighlightSlot[0..13] {
            doc /* The highlight slots that are on (WstxBandActivityPane::Highlight); by
                 default every slot but newItuZone, newItuZoneBand, newGrid and
                 newGridBand. */ }
        attribute sortField : SortField = SortField::'value' {
            doc /* The order of Band Activity (WstxBandActivityPane::Ordering). */ }
        attribute sortDescending : Boolean = true;
        attribute distanceInMiles : Boolean = false {
            doc /* Distances in miles instead of km. */
            @CodeDiffers { what = "The code has no choice of miles: it shows distances in km."; }
        }
        attribute callSound : AlertSound[0..1] = AlertSound::oldPhone {
            doc /* The sound of a station calling (WstxSettings::CallAlert); absent: Off. */
            @CodeDiffers { what = "The code plays no sound for a station calling."; }
        }
        attribute alertSound : Boolean = false {
            doc /* A tone for each new alert (WstxSettings::AlertDisplay). */ }
        attribute alertNotify : Boolean = false {
            doc /* A notification of the browser for each new alert. */ }
        assert constraint ranges {
            sensitivityDb >= -30 and sensitivityDb <= 30 and rangeDb >= 10 and
            rangeDb <= 80 and speed >= 0.5 and speed <= 8.0
        }
    }
}
