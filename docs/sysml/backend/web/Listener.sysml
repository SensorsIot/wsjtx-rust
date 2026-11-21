package WstxListener {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxWebPart::WebAdapter;
    private import WstxWebControl::*;
    private import WstxStationLink::*;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* web's own functions: the listener, the browser client it serves, the sockets and
         requests it holds, and the log of the bytes on the link. */

    requirement 'CL-003-07' {
        subject web : WebAdapter;
        doc /* web MUST take its listener as ListenRule says and refuse a request of
             another origin (WstxStationLink::RequestOrder). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-07'; }

    attribute def ListenRule {
        doc /* On Listen web listens on the address and port of WebContext::endpoint.
             The endpoint alone gives the address and the origin: a start whose
             environment holds WSTX_BIND or WSTX_ORIGIN, also with an empty value, ends
             with invalidRuntimeConfiguration (WstxStartup::StartupOutcome) before the
             profile is opened. A creation (WstxStartup::LaunchRule) reads none of the
             variables of this rule.
             The environment variables WSTX_TLS_CERT and WSTX_TLS_KEY name the TLS
             certificate chain and its private key; with both, web listens with TLS
             only. WSTX_TOKEN gives the access token of the station's browsers: 32 to 128
             characters, each an ASCII letter or digit. TLS needs the token, and the
             token needs TLS. A listener on an address other than loopback needs TLS and
             a stored origin. The station's origin is the stored origin, whose scheme is
             the listener's, else the scheme, address and port of the listener.
             ListenRefused: invalidRuntimeConfiguration for one of the two TLS variables
             without the other, a WSTX_TOKEN of another form (also empty), TLS without the
             token or the token without TLS, a listener beyond loopback without TLS or
             without origin, and an origin of the other scheme; resourceUnavailable for a
             file that cannot be read and a listener that cannot be opened; endpointInUse
             for a port another process listens on.
             Listening: web writes the lines WSTX address, the scheme, :// and the address
             and port, and WSTX listening and the origin, to the output of the process. On
             ProcessEnds web closes its sockets. */
        @FollowsSource { reference = "RFC 8446 (TLS 1.3); RFC 7468 (PEM); RFC 5280; RFC 5958"; }
    }

    verification 'TC-003-001' {
        doc /*
    A request of another origin, or a change without one, is refused and changes nothing.
        */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-07'; }
        @TestedBy {
            test = "tests/communication.test.cjs::"
                + "TLS login, unauthorized/origin denial, plaintext refusal";
        }
    }
    verification 'TC-003-002' {
        doc /*
    With both TLS files the listener takes TLS only; beyond loopback it refuses no TLS or no origin.
        */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-07'; }
        @TestedBy {
            test = "tests/communication.test.cjs::"
                + "TLS login, unauthorized/origin denial, plaintext refusal";
        }
    }

    requirement 'CL-003-01' {
        subject web : WebAdapter;
        doc /* web MUST serve the browser client as ClientFiles says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-01'; }

    attribute def ClientFiles {
        doc /* The GET of / gives the page; the GET of the file name of each of its scripts
             and styles gives that file. The client's files are built into the station's
             program; they hold no state of the station. The page carries the build it was
             served with as data-build of its body (ClientBuild). web serves the web app
             manifest of the page with the station's displayName, its origin as start and
             scope and the display standalone, so that the page installs as an app
             (WstxOperatingScreen::AppWindow). */
    }

    verification 'TC-021-006' {
        doc /* The page and its files in a real browser, in two clients. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-01'; }
        @TestedBy {
            test = "tests/communication.test.cjs::"
                + "TC-021-006: real browser, two clients, desktop and mobile layout";
        }
    }

    requirement 'CL-051-01' {
        subject web : WebAdapter;
        doc /* web MUST name the browser client it serves by its ClientBuild. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-051-01'; }

    attribute def ClientBuild {
        doc /* The first hexDigits lower-case hexadecimal digits of the SHA-256 over the
             client's files as served, the page first, then the others in the order of
             their routes. station.status carries it (WstxStationLink::SocketProtocol);
             equal builds mean the page's client is the station's. */
        @FollowsSource { reference = "FIPS 180-4 (SHA-256)"; }
        attribute hexDigits : Integer = 16;
    }

    requirement 'CL-033-01' {
        subject web : WebAdapter;
        doc /* web MUST name the source of its program on every page as SourceCommit
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-033-01'; }

    attribute def SourceCommit {
        doc /* Every answer to the GET of / carries exactly one header
             x-wstx-source-commit: the 40 lower-case hexadecimal digits of the commit the
             program was built from (WSTX_SOURCE_COMMIT when it was built), or unknown when
             the build had none or one of another form. */
    }

    requirement 'CL-003-02' {
        subject web : WebAdapter;
        doc /* web MUST hold one socket per browser as SocketRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-02'; }

    attribute def SocketRule {
        doc /* Each browser's socket follows WstxStationLink::SocketProtocol. An answer goes
             on the socket its message came on, in the order of the messages, with their id.
             The sockets of several browsers are independent: one that is slow or silent
             delays no other. */
    }

    requirement 'CL-003-03' {
        subject web : WebAdapter;
        doc /* web MUST check every request and answer a refusal as RequestRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-03'; }

    attribute def RequestRule {
        doc /* web checks each request in the order of WstxStationLink::RequestOrder and
             answers the first failed check with WstxStationLink::ErrorBody and the status
             of WstxStationLink::StatusRule. A refused request changes nothing and leaves
             the station and the socket available. */
    }

    requirement 'CL-003-08' {
        subject web : WebAdapter;
        doc /* web MUST carry every feature of the station boundary as ViewRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-08'; }

    attribute def ViewRule {
        doc /* web carries each command, read and answer of
             WstxStationCommands::StationOperations as WstxStationLink::WireRule says, and
             each view both by its GET and as its event (WstxStationLink::SocketProtocol),
             so that a browser holds the station's state from one read per socket and the
             events, without reading on a timer. Every command is answered. The messages
             have no coding of their own; an answer is coded only as
             WstxContentCoding::CodingRule says. */
    }

    requirement 'CL-003-06' {
        subject web : WebAdapter;
        doc /* web MUST bound its sockets and their output and close a silent socket as
             BoundsRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-06'; }

    attribute def BoundsRule {
        doc /* The number of sockets and the output waiting on each are bounded; a socket
             beyond the number is refused with 503. A socket whose browser answers no ping
             for a bounded time is closed at the next heartbeat, and a socket that cannot
             take its output within a bounded time is closed; neither delays the answers
             of another socket. The bounds are values of the code. */
    }

    requirement 'CL-003-05' {
        subject web : WebAdapter;
        doc /* web MUST log the bytes of the link as LinkTrafficLog says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-05'; }

    attribute def LinkTrafficLog {
        doc /* web counts the bytes between each client and itself and writes them to
             fileName in the profile's folder: one JSON line per client that had traffic,
             at the end of each period; at rotateBytes the file moves to
             link-traffic.1.log in the place of the older one. Nothing of the log goes on a
             socket or into an answer; counting never makes a request wait.
             Period: that of the station's operating mode (WstxModeProcessing::Mode),
             aligned to the starts of the periods in UTC; a change of the mode ends the open period
             at once, and the next runs to the next start of the new mode.
             Client: browser and the remote address for the page, the routes and the
             sockets; mcp and the remote address for the requests of MCP.
             Line: {utcMs, periodMs, mode, client, display, toClient, fromClient}:
             display the DisplayProfile of each of the client's sockets at the period's end
             (none without one); toClient and fromClient each {bytes, other, estimate,
             types}. bytes: the bytes written and read on the client's connections below
             TLS. types: per message type its count and bytes, a type being ws and the
             message's type for a message on a socket, ws ping, ws pong and ws close, and
             the method and the route's template for an HTTP exchange (OTHER for another
             method, unrouted for a request without route), so that no text of a client
             becomes a type. other: bytes less the sum of the types. estimate: bytes plus
             headerBytesPerSegment for each segment of segmentBytesMax of this direction
             and reverseAckBytesPerSegment for each of the other, each message counted with
             tlsRecordOverheadBytes per record of tlsRecordPayloadMax on TLS, so that the
             numbers compare with WstxStationLink::ThinLinkBudget. */
        attribute fileName : String = "link-traffic.log";
        attribute rotateBytes : Integer = 4194304;
        attribute segmentBytesMax : Integer = 512;
        attribute headerBytesPerSegment : Integer = 80;
        attribute reverseAckBytesPerSegment : Integer = 80;
        attribute tlsRecordOverheadBytes : Integer = 29;
        attribute tlsRecordPayloadMax : Integer = 16384;
    }

    verification 'TC-021-005' {
        doc /* The socket's messages, the refusals of bad input and the size bounds. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-02'; verify 'CL-003-03'; }
        @TestedBy {
            test = "tests/communication.test.cjs::"
                + "TC-021-005: actual-server correlation, negative cases and size boundaries; "
                + "server/src/protocol_tests.rs::protocol_returns_specified_response_and_errors";
        }
    }
    verification 'TC-021-008' {
        doc /*
    A socket beyond the bound is refused; a silent or stalled socket is closed and delays no other.
        */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-06'; }
        @TestedBy {
            test = "server/src/web/liveness_tests.rs; "
                + "server/src/web/socket_bounds_tests.rs::"
                + "a_socket_beyond_16_is_refused_with_503_and_the_16_keep_answering; "
                + "server/src/web/socket_bounds_tests.rs::"
                + "a_socket_that_takes_no_output_for_2_s_is_closed_and_delays_no_other; "
                + "server/src/web/socket_bounds_tests.rs::"
                + "a_socket_whose_event_stays_unflushed_for_2_s_is_closed; "
                + "server/src/protocol_tests.rs::"
                + "optional_readiness_skips_without_waiting_and_retains_at_most_one_frame";
        }
    }
    verification 'TC-007-005' {
        doc /* The views as events, without reads on a timer. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-08'; }
        @TestedBy {
            test = "tests/contact.test.cjs; tests/ui-operating.test.cjs; "
                + "server/src/contact_http_tests.rs; server/src/receive_http_tests.rs";
        }
    }
    verification 'TC-082-003' {
        doc /* The open Tx slots as a view and as events, at thin and detail only. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-08'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_082_003_free_tx_slots_on_the_socket_and_in_the_snapshot_without_a_run";
        }
    }
    verification 'TC-092-009' {
        doc /* The clock's view as events to every socket. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-08'; }
        @TestedBy {
            test = "server/src/transmit/clock_http_tests.rs::"
                + "clock_state_is_pushed_to_every_profile; "
                + "server/src/transmit/clock_http_tests.rs::"
                + "a_revision_never_carries_older_clock_values";
        }
    }
    verification 'TC-111-007' {
        doc /* The causes of transmit as wire names in the view and its event. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-08'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "contact_snapshot_is_exact_identity_coded_and_bounded";
        }
    }
    verification 'TC-010-002' {
        doc /* The rows of a replay and an import to sockets at off, thin and detail. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-02'; }
        @TestedBy { test = "tests/recording.test.cjs; server/src/protocol_tests.rs"; }
    }
    verification 'TC-010-005' {
        doc /* The detailed rows on the wire and their refusals. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-02'; }
        @TestedBy {
            test = "tests/recording.test.cjs; tests/ui-operating.test.cjs; "
                + "server/src/protocol_tests.rs";
        }
    }
    verification 'TC-033-001' {
        doc /* The page names the source commit. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-033-01'; }
        @TestedBy { test = "server/src/protocol_tests.rs"; }
    }
    verification 'TC-051-001' {
        doc /* The page and station.status carry the client's build. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-051-01'; }
        @TestedBy { test = "tests/communication.test.cjs; server/src/protocol_tests.rs"; }
    }
    verification 'TC-080-001' {
        doc /* The link byte log. */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-05'; }
        @TestedBy { test = "server/src/web/link_log_tests.rs"; }
    }
}
