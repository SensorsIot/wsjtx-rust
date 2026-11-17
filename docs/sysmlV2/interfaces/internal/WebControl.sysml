package WstxWebControl {
    private import ScalarValues::*;
    private import WstxProfileAccess::Endpoint;
    private import WstxTransmitControl::ProcessEnds;

    doc /* What the supervisor gives the web function (its context, the request to take
         its listener, the end of the process) and how web answers. */

    port def WebControlPort {
        doc /* Written from the supervisor's side; web uses the conjugate. */
        out item context : WebContext;
        out item listen : Listen;
        out item processEnds : ProcessEnds;
        in item listening : Listening;
        in item listenRefused : ListenRefused;
    }
    interface def WebControl {
        doc /* The supervisor starts web's listener; web answers. */
        end supervisor : WebControlPort;
        end web : ~WebControlPort;
    }

    item def WebContext {
        doc /* web's context. The supervisor gives it at station start, before Listen. */
        attribute profileId : String;
        attribute bootId : String { doc /* The start of the station process. */ }
        attribute endpoint : Endpoint {
            doc /* The profile's endpoint (WstxProfileAccess::ProfileConfig::endpoint). */ }
    }
    item def Listen {
        doc /* Take the listener of the endpoint (WstxListener::ListenRule). Answered by
             Listening or ListenRefused. */
    }
    item def Listening {
        doc /* web listens. */
        attribute origin : String { doc /* The station's origin. */ }
    }
    enum def ListenRefusal {
        doc /* Why web cannot listen; the start ends with the same outcome
             (WstxStartup::StartupOutcome).
             invalid_runtime_configuration: the TLS files or the origin are not as
             ListenRule asks.
             resource_unavailable: a TLS file cannot be read, or the listener cannot be
             opened.
             endpoint_in_use: another process listens on the port. */
        enum invalid_runtime_configuration;
        enum resource_unavailable;
        enum endpoint_in_use;
    }
    item def ListenRefused { attribute reason : ListenRefusal; }
}
