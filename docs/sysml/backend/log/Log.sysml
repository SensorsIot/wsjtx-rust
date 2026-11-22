package WstxLogPart {
    private import ScalarValues::*;
    private import WstxLogControl::LogControlPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxOperatingChain::LoggedContactPort;
    private import WstxOperatingChain::WorkedBeforePort;
    private import WstxDecodes::DecodesPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def LogService {
        doc /* The log of the station. It keeps the operator's logbook, stores every
             finished contact in it, takes in the log of another program, and tells
             what has been worked and to which entity a call belongs.
             The logbook and the operator's country file lie in the shack's folder,
             shared by the shack's stations. */
        @ImplementedIn {
            module = "server/src/log/logbook.rs; server/src/log/dxcc.rs; "
                + "server/src/log/logbook_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/operating/qso/contact_http.rs, outside "
                + "server/src/log/ and client/src/log/.";
        }
        @DetailTests {
            tests = "server/src/log/logbook_http_tests.rs";
            covers = "the log routes of a station without a profile; the log routes' admission "
                + "by the grant or the runtime token and their publication only under a "
                + "current grant";
        }
        port control : ~LogControlPort;
        port completed : ~CompletedContactPort;
        port logged : LoggedContactPort;
        port workedBefore : WorkedBeforePort;
        port decodes : ~DecodesPort;
    }
}
