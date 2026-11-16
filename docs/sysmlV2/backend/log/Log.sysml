package WstxLogPart {
    private import ScalarValues::*;
    private import WstxLogControl::LogControlPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxOperatingChain::LoggedContactPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import ModelBindings::ImplementedIn;

    part def LogService {
        doc /* The log of the station. It keeps the operator's logbook, stores every
             finished contact in it, takes in the log of another program, and tells
             what has been worked and to which entity a call belongs.
             The logbook and the operator's country file lie in the operator's folder,
             shared by the operator's stations. */
        @ImplementedIn { module = "server/src/logbook.rs; server/src/dxcc.rs"; }
        port control : ~LogControlPort;
        port completed : ~CompletedContactPort;
        port logged : LoggedContactPort;
        port workedBefore : WorkedBeforePort;
    }
}
