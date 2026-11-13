package WstxStationCommands {
    private import ScalarValues::*;

    port def StationOperations {
        out item request : StationRequest;
        in item outcome : StationOutcome;
    }

    item def StationRequest;
    item def StationOutcome;
    // CombinedLinkEvidence retired by #80 (operator 2026-11-09): no test measures the 32 kbit/s
    // link; its budget is a target judged from WstxStationProtocol::LinkTrafficLog.
    attribute def SelectionStateEvent {
        attribute maximumBytes : Integer = 2048;
        attribute radioDatesDetailedMs : Integer = 2000;
        attribute radioDatesBelowDetailedMs : Integer = 30000;
        doc /* selection.state (WstxStationLink::PushedStationState, #10): exactly
             {v:1,type:"selection.state",data:{profile_id,boot_id,snapshot_sequence,monotonic_ms,changed}}
             to a display-subscribed peer, checked once per second. changed holds the top-level
             fields of the GET /receive/selection snapshot this peer does not hold (a socket's
             first event: all of them), at most maximumBytes per event; what does not fit goes at the next
             check, so a snapshot near its 3072 B cap comes in two events and the browser waits for all fields. Each CAT poll dates the
             radio facts anew: a change of the radio field in query_sequence or observed_at_ms alone
             goes at most every radioDatesDetailedMs on Detailed and every
             radioDatesBelowDetailedMs below it; any other change goes at the next check. The
             browser builds its view of a socket from that socket's events alone and accepts it
             like a read: not with a snapshot_sequence older than the state shown, and only for the
             identity of its current status. It has no timer read. It reads GET /receive/selection
             once per socket, on a saved profile revision or boot change, on the operator's Refresh
             and after a command whose outcome is unknown; a pushed state never clears the barrier
             of an unknown outcome, also not while the command's POST is pending. A read lost on
             the link before its answer changes nothing while this socket's events hold the state. */
    }
    attribute def AuthStatusRequest {
        doc /* Strict read-only POST /authorization/v1/status JSON {version:1};
             no scope/operation/extra keys. GET on this new path405/no effects. */
        attribute version : Integer = 1;
    }
}
