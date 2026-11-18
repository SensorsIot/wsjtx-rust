package WstxWebPart {
    private import ScalarValues::*;
    private import WstxStationLink::BrowserExchange;
    private import WstxStationCommands::StationOperations;
    private import WstxWebControl::WebControlPort;
    private import WstxWebControl::WebContext;
    private import WstxDisplayData::DisplayDataPort;
    private import WstxStationTime::StationTimePort;
    private import WstxModelBindings::ImplementedIn;

    part def WebAdapter {
        doc /* The station's door for its browsers: it listens, serves the browser client,
             and carries the features of the station boundary between the browsers and the
             supervisor as the station link says (WstxStationLink). It decides nothing of
             the station's state. */
        @ImplementedIn {
            module = "server/src/main.rs; server/src/web/link_log.rs; "
                + "server/src/http_compression.rs";
        }
        item context : WebContext {
            doc /* Its context, as the supervisor last gave it. */ }
        port client : ~BrowserExchange { doc /* The browsers of the station. */ }
        port supervisor : StationOperations {
            doc /* The browsers' commands and reads to the supervisor, its answers and
                 views back. */ }
        port control : ~WebControlPort {
            doc /* The supervisor: the context, the start of the listener and the end of
                 the process. */ }
        port display : ~DisplayDataPort { doc /* The rows from receive. */ }
        port time : ~StationTimePort { doc /* Station time from the clock. */ }
    }
}
