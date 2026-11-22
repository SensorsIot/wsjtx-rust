package WstxClockPart {
    private import ScalarValues::*;
    private import WstxStationTime::StationTimePort;
    private import WstxStationTime::ClockStatusPort;
    private import WstxStationTime::StationsHeardPort;
    private import WstxTimeSource::TimeSourcePort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def ClockService {
        doc /* The station's clock. It holds station time, corrects it from the stations
             heard, checks the PC clock against a time server, and gives time to the
             functions that keep time. */
        @ImplementedIn {
            module = "server/src/clock/air.rs; server/src/clock/clock.rs; "
                + "server/src/clock/windows_time.rs; server/src/clock/clock_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/main.rs, outside server/src/clock/ and "
                + "client/src/clock/.";
        }
        @DetailTests {
            tests = "server/tests/transmit/transmit_clock.rs";
            covers = "the reading of the PC's clocks and a wait of at least its duration";
        }
        port time : StationTimePort;
        port status : ClockStatusPort;
        port heard : ~StationsHeardPort;
        port timeSource : TimeSourcePort;
    }
}
