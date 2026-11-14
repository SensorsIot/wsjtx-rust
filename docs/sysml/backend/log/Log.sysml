package WstxLogPart {
    private import ScalarValues::*;
    private import WstxLogControl::LogControlPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxProfileAccess::ProfileAccess;
    part def LogService {
        doc /* The logbook, what has been worked before, and the country file. */
        port control : ~LogControlPort;
        port completed : ~CompletedContactPort;
        port logged : CompletedContactPort;
        port workedBefore : WorkedBeforePort;
        port contacts : ProfileAccess;
    }
}
