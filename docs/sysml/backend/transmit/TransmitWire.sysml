package WstxTransmitWire {
    private import ScalarValues::*;
    attribute def TransmitWire {
        doc /* Selected-profile routes, existing authentication, exact Origin on mutations,
             JSON media rules, 1024-byte bodies and error envelope; identity-coded (not
             in the compressed GET allowlist); no StatusReply change. Pushed state
             (WstxStationProtocol::PushedStationState, #10 2026-11-04): a versioned
             WebSocket event exactly {v:1,type:"transmit.state",data:{profile_id,boot_id,
             transmit_revision,changed}}, at most 1024 bytes, sent to each peer with a display
             subscription when the fields below change (transmit_revision a station-wide
             counter, safe integer, increasing at each change of GET /transmit except
             clock_measurement.age_ms), coalesced to at most one per second per peer and
             sent within 1 s of a change; below Detailed a change of only
             watchdog.tune_remaining_seconds at most once per 5 s. changed: on a peer's
             first event every field of GET /transmit except v, profile_id, boot_id and
             outcomes; later only the changed fields, of transmit and watchdog only the
             changed members, clock_measurement whole and not for its age_ms alone (#10
             2026-11-06, operator rule 2026-11-04). A browser of a transmit-configured
             profile holds this state from the events and reads no GET /transmit; GET
             /transmit stays for other clients. Ages it shows (clock_measurement.age_ms) advance
             locally from the event. HALT, PTT keying/release and the watchdogs are decided by the owner
             and never wait for a browser; the keyed/transmitting indication also
             follows station.tick (one extra tick at each transmit start/stop).
             GET /transmit: exactly {v:1,profile_id,boot_id,transmit,ptt,transmitting,
             clock,clock_measurement,clock_warning,watchdog,outcomes,startup_release} (no clock_source since #92) with transmit exactly the WstxContact read view
             without its safety_revision: {capability,arm_state,last_disarm_cause,last_arm_cause,tune,
             pending_sequence,last_text,last_period_utc,halt_state,refusal} (last_arm_cause
             operator, auto or null: TransmitArming lastArmCause), ptt released|keyed|indeterminate,
             clock synchronized|unsynchronized (the station clock: TransmitClock
             and AirClock, never unknown, #92), clock_warning null, pc_clock_off,
             ntp_unreachable or stations_off (AirClock, CL-043-03),
             clock_measurement null before the first answer, else exactly the latest
             measurement {server,offset_ms,round_trip_ms,age_ms} (server as configured,
             age at the read), watchdog exactly {tx_calls,
             tx_remaining_calls (integer, or null for a strategy run's own contact, #97,
             TransmitWatchdog),tx_expired,tune_seconds,tune_remaining_seconds} and
             outcomes the last 8 {outcome_sequence,request_sequence,kind,refusal,failure,
             audio_start_utc_ms} and startup_release the StartupSafetyRelease state;
             enum values snake_case.
             POST /transmit/command: exactly {v,profile_id,boot_id,command_id,action}
             plus the action's parameters: arm {safety_revision}; disarm {};
             request {request_sequence,mode ft8|ft4,period_start_utc_ms,message_text,
             tx_offset_hz}; tune {enabled} or {enabled true,tx_offset_hz};
             set_watchdogs {tx_calls,tune_seconds}. 200 {v:1,profile_id,boot_id,
             command_id,result}: result is the TransmitOutcome of a request, otherwise
             {accepted,refusal}. A retained command_id (last 16) with the identical body
             returns the same reply without effect, a different body is state_conflict;
             another boot is state_conflict. POST /transmit/halt: HaltTransmit. */
    }
}
