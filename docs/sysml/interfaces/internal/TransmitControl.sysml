package WstxTransmitControl {
    private import ScalarValues::*;
    // ------------------------------------------------------------------
    // #9 slice B transmit owner (delivered; consumer contract of WstxContact #10,
    // supervisor decision 2026-10-31 on #10). Implementation:
    // server/src/transmit/service.rs (owner), server/src/radio_control/actor.rs and
    // executor.rs (PttControl), server/src/playback.rs (AudioPlayback),
    // server/src/transmit_http.rs (station hardware, TransmitWire).
    enum def ArmState { enum disarmed; enum armed; }
    attribute def TransmitHaltUse {
        doc /* HALT is the operator's emergency stop only (operator decision #39,
             2026-11-04): the browser HALT buttons and Alt+H, and the remote emergency
             stop MCP wstx_transmit_halt (UDP is send-only and has no Halt Tx, CL-040-03).
             The station and its automation
             never send HaltTransmit in normal flow: a completed contact and ending a run
             disarm, the partner-works-other stop and Abort QSO use
             AbortTransmission. */
    }
    attribute def TransmitWatchdog {
        doc /* WstxQsoControl::TxWatchdog (#39, 2026-11-06): the owner holds the limit, 1..99
             repetitions (default 6 at each start), and no count: the contact consumer
             compares its dialogue Rep with the limit and reports that Rep for
             tx_remaining_calls (the Tx watchdog's only; a strategy run's own contact, which has
             no stop while attended, reports none: WstxStrategy::StrategyWatchdog, LeaveCountLabel;
             a busy partner's paused calls are not counted: WstxOperatingChain::BusyPartner). GET /transmit
             watchdog.tx_remaining_calls is therefore an integer or null: null exactly while armed for
             such a contact (never the leave count and never the limit minus the Rep as a fallback);
             0 while disarmed as before. The receive page's transmit line (recording) shows "WD <n>
             calls" for an integer and leaves the WD part out for null; MCP wstx_read passes it on. At the consumer's stop the owner disarms (txWatchdog)
             without keying, so PTT is never keyed for that send and no halt happens (HALT
             is the operator's emergency stop only), and reports tx_expired until the next
             Arm. A request submitted directly on the transmit route has no dialogue and
             is not bounded by it: each one is its own browser request. */
    }
    attribute def TransmitWire {
        doc /* Selected-profile routes, existing authentication, exact Origin on mutations,
             JSON media rules, 1024-byte bodies and error envelope; identity-coded (not
             in the compressed GET allowlist); no StatusReply change. Pushed state
             (WstxStationLink::PushedStationState, #10 2026-11-04): a versioned
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
