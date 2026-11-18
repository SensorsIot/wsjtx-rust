package WstxClockPart {
    private import ScalarValues::*;
    private import WstxStationTime::StationTimePort;
    private import WstxStationTime::ClockStatusPort;
    private import WstxStationTime::StationsHeardPort;
    private import WstxTimeSource::TimeSourcePort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelNotes::CodeDiffers;

    part def ClockService {
        doc /* The station's clock. It holds station time, corrects it from the stations
             heard, checks the PC clock against a time server, and gives time to the
             functions that keep time. */
        @ImplementedIn {
            module = "server/src/transmit/air.rs; server/src/transmit/clock.rs; "
                + "server/src/transmit/windows_time.rs; server/src/transmit/clock_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/main.rs, server/src/transmit/air.rs, "
                + "server/src/transmit/clock.rs, server/src/transmit/clock_http.rs, "
                + "server/src/transmit/windows_time.rs, outside server/src/clock/ and "
                + "client/src/clock/.";
        }
        port time : StationTimePort;
        port status : ClockStatusPort;
        port heard : ~StationsHeardPort;
        port timeSource : TimeSourcePort;
    }
}
