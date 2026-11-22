package WstxSpotsPart {
    private import ScalarValues::*;
    private import WstxHearing::HeardByPort;
    private import WstxHearing::TargetHearingPort;
    private import WstxHearing::SpotsControlPort;
    private import WstxHearing::SpotsConfig;
    private import WstxPskReporter::PskReporterPort;
    private import WstxPskReporter::ReportCollectorPort;
    private import WstxDecodes::DecodesPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;

    part def SpotsService {
        doc /* Tells the station who hears it. It reads the spots of the PSK Reporter feed
             for the profile's call and for the station of the contact in progress, and
             tells ranking which stations hear us, and auto, qso and the supervisor
             what that station hears. It reports the stations the station decodes to PSK
             Reporter. */
        @ImplementedIn {
            module = "server/src/spots/pskr.rs";
        }
        @DetailTests {
            tests = "server/src/spots/pskr_tests.rs";
            covers = "the broker a test names in the environment, on a loopback address only; "
                + "the routes of the two switches and the file that keeps them";
        }
        attribute config : SpotsConfig {
            doc /* Its configuration, as the last SpotsConfiguration gave it. */ }
        port control : ~SpotsControlPort;
        port heardBy : HeardByPort;
        port target : TargetHearingPort;
        port pskReporter : PskReporterPort;
        port decodes : ~DecodesPort {
            doc /* The records of receive, for the reception reports. */ }
        port collector : ReportCollectorPort;
    }
}
