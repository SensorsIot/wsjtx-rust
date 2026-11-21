package WstxPskReporter {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementedIn;

    doc /* PSK Reporter in both directions: the feed of spots, which the station reads as
         a subscriber at a broker, and the reception reports the station sends to a
         collector. */

    item def Subscription {
        doc /* One topic filter the station asks the broker for, or gives up. */
        attribute topicFilter : String;
    }
    item def Spot {
        doc /* One reception report as the feed delivers it. Of the payload the station
             reads the fields below; a text field has 1 to FeedSession::maxFieldLength
             characters. A payload that does not give them in this form is no spot. */
        @FollowsSource { reference = "PSK Reporter MQTT feed, the payload of a spot"; }
        attribute sender : String { doc /* The call that was heard (sc). */ }
        attribute receiver : String { doc /* The call that heard it (rc). */ }
        attribute mode : String { doc /* The mode (md). */ }
        attribute band : String { doc /* The band (b). */ }
        attribute frequencyHz : Integer { doc /* The frequency of the signal (f). */ }
        attribute sentSeconds : Integer {
            doc /* When the sender transmitted, in seconds of UTC since 1970 (t_tx); the
                 time of the report (t) where the payload names no t_tx. */ }
        attribute reportedSnrDb : Integer[0..1] {
            doc /* The signal-to-noise ratio the receiver reported (rp), a whole number
                 from -99 to 99. Absent for a payload without it or with another value;
                 the spot counts all the same. */ }
    }

    enum def FeedError {
        doc /* Why a session ended or did not begin.
             resolveFailed: the broker's name was not resolved.
             connectFailed: no address of the broker took the connection.
             tlsFailed: the secured connection was not made or the certificate was not
             accepted.
             connectionRefused: the broker answered the greeting with a refusal.
             connectionTimeout: the broker did not answer the greeting in time, or sent
             nothing for one and a half times the keep-alive.
             connectionLost: reading or writing failed.
             connectionClosed: the broker closed the connection.
             protocolError: a packet longer than FeedSession::maxPacketBytes or one a
             subscriber does not receive.
             subscribeRefused: the broker refused a subscription. */
        enum resolveFailed;
        enum connectFailed;
        enum tlsFailed;
        enum connectionRefused;
        enum connectionTimeout;
        enum connectionLost;
        enum connectionClosed;
        enum protocolError;
        enum subscribeRefused;
    }

    port def PskReporterPort {
        doc /* Written from the station's side; the broker uses the conjugate. */
        out item subscription : Subscription;
        in item spot : Spot;
    }
    interface def PskReporter {
        doc /* The spots function and the PSK Reporter broker. */
        @FollowsSource { reference = "MQTT 3.1.1 (OASIS); PSK Reporter MQTT feed"; }
        end spots : PskReporterPort;
        end broker : ~PskReporterPort;
    }

    requirement 'CL-039-27' {
        subject feed : PskReporter;
        doc /* The station MUST take part in the PSK Reporter feed as a subscriber to the
             spots of its own call and of the target it follows, and wait longer after
             each ended session before it connects again (FeedSession). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/operating/qso/pskr.rs"; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-039-27'; }

    attribute def FeedSession {
        doc /* How the station speaks with the broker.
             The broker is WstxHearing::SpotsConfig::feedBroker. With mqtts the
             station speaks TLS and accepts the broker's certificate only for the
             broker's host name and only under the roots built into the station, ISRG
             Root X1 and X2; with mqtt it speaks without TLS. A changed broker ends
             the session and forgets every Spot; the next session goes to the new
             broker.
             The station gives the client identifier wstx, then the letters and digits
             of the profile's call, then four letters and digits of the station's boot
             identity, at most 23 characters in all. It gives no login name, no
             password and no will, asks for a clean session and subscribes at QoS 0.
             The station sends the greeting, its subscriptions and their removal, pings
             and the farewell, and nothing else.
             A session begins when the feed is switched on, the profile has a call and
             the wait since the last session is over.
             In every session the station subscribes to the spots sent by the profile's
             call: pskr/filter/v2/+/+/<call>/+/#. While the operator's two switches are
             on and a target is followed it also subscribes to the spots received by
             the target: pskr/filter/v2/+/+/+/<target>/#. When the target changes or
             the second switch goes off, that subscription is removed and the one of
             the next target is made.
             A call forms a filter only when it has 1 to maxFieldLength characters, each
             a capital letter or a digit. Every other call gets no subscription.
             The station pings before its own silence reaches the keep-alive.
             The station ends a session with the farewell when the feed is switched off
             or on again, when the profile's call changes and when the station stops.
             Every other end is a FeedError.
             After every end of a session the station waits before the next attempt:
             firstRetrySeconds, then twice as long each time up to maxRetrySeconds. An
             attempt that lasted stableSessionSeconds starts the wait at
             firstRetrySeconds again. A change of a switch does not shorten the wait. */
        attribute keepAliveSeconds : Integer = 60 {
            doc /* The keep-alive the station names in its greeting. */ }
        attribute firstRetrySeconds : Integer = 5;
        attribute maxRetrySeconds : Integer = 300;
        attribute stableSessionSeconds : Integer = 60;
        attribute maxPacketBytes : Integer = 4096 {
            doc /* A longer packet from the broker ends the session. */ }
        attribute maxFieldLength : Integer = 16;
    }

    verification 'TC-039-052' {
        doc /* The session with a broker. */
        subject feed : PskReporter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-27'; }
        @TestedBy {
            test = "server/src/operating/qso/pskr_tests.rs::"
                + "filters_are_exact_and_no_call_makes_a_wildcard; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "client_id_carries_the_call_and_stays_legal; "
                + "server/src/operating/qso/pskr_tests.rs::packets_match_the_specification; "
                + "server/src/operating/qso/pskr_tests.rs::next_packet_parses_and_bounds; "
                + "server/src/operating/qso/pskr_tests.rs::backoff_doubles_to_the_bound; "
                + "server/src/operating/qso/pskr_tests.rs::session_against_a_local_peer; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "reconnect_backs_off_against_a_failing_peer_and_recovers; "
                + "server/src/operating/qso/pskr_tests.rs::the_status_follows_the_switch; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "a_refusing_or_broken_peer_is_a_named_error; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "the_compiled_roots_validate_the_captured_broker_chain; "
                + "server/src/operating/qso/pskr_tests.rs::a_peer_without_tls_is_refused";
        }
    }

    attribute def ReportedStation {
        doc /* One station the station has decoded, as it is reported. */
        attribute call : String { doc /* The sender's call. */ }
        attribute grid : String[0..1] { doc /* The sender's grid; absent when unknown. */ }
        attribute frequencyHz : Integer {
            doc /* The frequency of the signal: the dial plus its audio offset. */ }
        attribute mode : String { doc /* FT8 or FT4. */ }
        attribute snrDb : Integer;
        attribute sentSeconds : Integer {
            doc /* The start of the period it was decoded in, in seconds of UTC since
                 1970. */ }
    }
    item def ReceptionReport {
        doc /* One sending to the collector: who receives, and the stations received. */
        @FollowsSource {
            reference = "PSK Reporter, the IPFIX form of a reception report; WSJT-X at "
                + "the behaviour baseline: Network/PSKReporter.cpp";
        }
        attribute receiverCall : String { doc /* The profile's call. */ }
        attribute receiverGrid : String { doc /* The profile's locator. */ }
        attribute software : String { doc /* WSTX-Rust and its version. */ }
        attribute stations : ReportedStation[1..*];
    }
    port def ReportCollectorPort {
        doc /* Written from the station's side; the collector uses the conjugate. Nothing
             comes back. */
        out item report : ReceptionReport;
    }
    interface def ReportCollector {
        doc /* The spots function and the PSK Reporter collector of reception reports. */
        end spots : ReportCollectorPort;
        end collector : ~ReportCollectorPort;
    }
}
