package WstxLogPart {
    private import ScalarValues::*;
    private import WstxLogControl::LogControlPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxOperatingChain::LoggedContactPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxDecodes::DecodesPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelNotes::CodeDiffers;

    part def LogService {
        doc /* The log of the station. It keeps the operator's logbook, stores every
             finished contact in it, takes in the log of another program, and tells
             what has been worked and to which entity a call belongs.
             The logbook and the operator's country file lie in the shack's folder,
             shared by the shack's stations. */
        @ImplementedIn {
            module = "server/src/logbook.rs; server/src/dxcc.rs; server/src/logbook_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/contact_http.rs, server/src/dxcc.rs, "
                + "server/src/logbook.rs, server/src/logbook_http.rs, outside server/src/log/ and "
                + "client/src/log/.";
        }
        port control : ~LogControlPort;
        port completed : ~CompletedContactPort;
        port logged : LoggedContactPort;
        port workedBefore : WorkedBeforePort;
        port decodes : ~DecodesPort;
    }
}
