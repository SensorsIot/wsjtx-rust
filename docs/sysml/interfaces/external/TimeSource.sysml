package WstxTimeSource {
    private import ScalarValues::*;
    private import WstxModelNotes::FollowsSource;

    item def TimeRequest {
        doc /* One SNTP client request. */
        @FollowsSource { reference = "RFC 4330, SNTP version 4"; }
    }
    item def TimeReply {
        doc /* The server's answer to one TimeRequest. It is matched to its request by the
             originate timestamp, which repeats the request's transmit timestamp. */
        @FollowsSource { reference = "RFC 4330, SNTP version 4"; }
    }
    port def TimeSourcePort {
        out item request : TimeRequest;
        in item reply : TimeReply;
    }
    interface def TimeSource {
        doc /* Written from the clock's side: the clock asks a time server over UDP port 123. */
        end clock : TimeSourcePort;
        end server : ~TimeSourcePort;
    }
}
