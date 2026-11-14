package WstxSpotsPart {
    private import ScalarValues::*;
    private import WstxHearing::HearingPort;
    private import WstxPskReporter::PskReporterPort;
    part def SpotsService {
        doc /* PSK Reporter: who hears me. */
        port hearing : HearingPort;
        port pskReporter : PskReporterPort;
    }
}
