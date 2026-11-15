package WstxTransmitControl {
    private import ScalarValues::*;
    private import ModelBindings::ImplementedIn;
    private import ModelNotes::Conflict;
    port def TransmitControlPort {
        out item command : TransmitCommand;
        in item 'state' : TransmitState;
    }
    item def TransmitCommand {
        doc /* A command of the station service to the transmit function. */
        attribute kind : TransmitCommandKind;
        attribute enable : Boolean[0..1] {
            doc /* For tune: Tune on or off (WstxTransmit::SetTune enable). */
        }
        attribute safetyRevision : Integer[0..1] {
            doc /* For tune on: the station's safety revision (WstxTransmit::SetTune
                 safetyRevision). */
        }
    }
    enum def TransmitCommandKind {
        doc /* halt: WstxTransmit::HaltTransmit; tune: WstxTransmit::SetTune. */
        enum halt;
        enum tune;
    }
    item def TransmitState {
        doc /* The transmit state the transmit function reports: the transmit view of
             TransmitWire, one feature per member. */
        attribute capability : TransmitCapability;
        attribute armState : ArmState;
        attribute lastDisarmCause : DisarmCause;
        attribute lastArmCause : ArmCause[0..1];
        attribute tune : Boolean {
            doc /* Tune is on (WstxTransmit::SetTune). */
        }
        attribute pendingSequence : Integer[0..1] {
            doc /* The requestSequence of the TransmitRequest that waits to be keyed. */
        }
        attribute lastText : String[0..1] {
            doc /* The messageText of the last TransmitRequest. */
        }
        attribute lastPeriodUtcMs : Integer[0..1] {
            doc /* The period start of the last transmitted period, Unix ms. */
        }
        attribute haltState : HaltState;
        attribute refusal : String[0..1] {
            doc /* The last refusal, a WstxOperatingChain TransmitRefusal by its snake_case
                 name. */
        }
    }
    interface def TransmitControl {
        doc /* The station service commands the transmit function; transmit reports its state. */
        end station : TransmitControlPort;
        end transmit : ~TransmitControlPort;
    }
    enum def ArmState { enum disarmed; enum armed; }
    enum def DisarmCause {
        enum operator; enum halt; enum contactCompleted; enum contactCancelled;
        enum txWatchdog; enum refused; enum failed; enum deviceLost; enum startup;
        enum authorityChanged;
        enum partnerWorksOther; enum modeChanged; enum bandChanged; enum runEnded;
    }
    enum def ArmCause { enum operator; enum auto; }
    enum def TransmitCapability { enum unsupported; enum unavailable; enum available; }
    enum def HaltState { enum idle; enum pending; enum stopped; }
    attribute def TransmitHaltUse {
        doc /* HALT is the operator's emergency stop only: the browser HALT buttons and Alt+H,
             and the remote emergency stop MCP wstx_transmit_halt; UDP is send-only and has
             no Halt Tx (CL-040-03). */
        doc /* The station and its automation never send HaltTransmit in normal flow: a
             completed contact and ending a run disarm, and the partner-works-other stop and
             Abort QSO use AbortTransmission. */
        @Conflict {
            what = "This element says only the operator sends HaltTransmit. CL-044-14 and "
                + "server/src/radio_level.rs halt on a clear SWR fault, and "
                + "WstxMcp::OperatingAutomation answers a halt that raced its arming with a "
                + "new HaltTransmit. Open in #176.";
        }
    }
    attribute def TransmitWatchdog {
        doc /* The transmit owner holds the limit of the Tx watchdog (WstxQsoControl::TxWatchdog),
             1..99 repetitions, default 6 at each start, and no count. */
        doc /* The contact consumer compares its dialogue Rep with the limit and reports that
             Rep for tx_remaining_calls (the Tx watchdog's only; a strategy run's own contact,
             which has no stop while attended, reports none: WstxStrategy::StrategyWatchdog,
             LeaveCountLabel; a busy partner's paused calls are not counted:
             WstxOperatingChain::BusyPartner). */
        doc /* GET /transmit watchdog.tx_remaining_calls carries that value
             (WstxQsoControl::TxWatchdog), and 0 while disarmed. */
        doc /* The receive page's transmit line (recording) shows "WD <n> calls" for an integer
             and leaves the WD part out for null; MCP wstx_read passes it on. */
        doc /* At the consumer's stop the owner disarms (txWatchdog) without keying, so PTT is
             never keyed for that send and no halt happens (TransmitHaltUse), and reports
             tx_expired until the next Arm. */
        doc /* A request submitted directly on the transmit route has no dialogue and is not
             bounded by it: each one is its own browser request. */
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/contact.rs"; }
    }
    attribute def TransmitWire {
        doc /* Selected-profile routes with the existing authentication, exact Origin on
             mutations, JSON media rules, 1024-byte bodies and the error envelope;
             identity-coded (not in the compressed GET allowlist); no StatusReply change. */
        doc /* Pushed state (WstxStationLink::PushedStationState): a versioned WebSocket event
             exactly {v:1,type:"transmit.state",data:{profile_id,boot_id,transmit_revision,
             changed}}, at most 1024 bytes, sent to each peer with a display subscription when
             the fields below change, coalesced to at most one per second per peer and sent
             within 1 s of a change; below Detailed a change of only
             watchdog.tune_remaining_seconds at most once per 5 s. */
        doc /* transmit_revision is a station-wide counter, a safe integer, increasing at each
             change of GET /transmit except clock_measurement.age_ms. */
        doc /* changed: on a peer's first event every field of GET /transmit except v,
             profile_id, boot_id and outcomes; later only the changed fields, of transmit and
             watchdog only the changed members, clock_measurement whole and not for its age_ms
             alone. */
        doc /* A browser of a transmit-configured
             profile holds this state from the events and reads no GET /transmit; GET
             /transmit stays for other clients. Ages it shows (clock_measurement.age_ms) advance
             locally from the event. */
        doc /* The safety decisions are the owner's (WstxStationLink::PushedStationState); the
             keyed/transmitting indication also
             follows station.tick (one extra tick at each transmit start/stop). */
        doc /* GET /transmit: exactly {v:1,profile_id,boot_id,transmit,ptt,transmitting,clock,
             clock_measurement,clock_warning,watchdog,outcomes,startup_release}; enum values
             snake_case. */
        doc /* transmit is TransmitState exactly {capability,arm_state,last_disarm_cause,
             last_arm_cause,tune,pending_sequence,last_text,last_period_utc,halt_state,refusal},
             last_arm_cause operator, auto or null (WstxTransmit::TransmitArming lastArmCause). */
        doc /* ptt is released|keyed|indeterminate; clock is synchronized|unsynchronized, the
             station clock of TransmitClock and AirClock, never unknown; clock_warning is null,
             pc_clock_off, ntp_unreachable or stations_off (AirClock, CL-043-03). */
        doc /* clock_measurement is null before the first answer, else exactly the latest
             measurement {server,offset_ms,round_trip_ms,age_ms}, server as configured and the
             age at the read. */
        doc /* watchdog is exactly {tx_calls,tx_remaining_calls,tx_expired,tune_seconds,
             tune_remaining_seconds}, tx_remaining_calls an integer or null (TransmitWatchdog). */
        doc /* outcomes are the last 8 {outcome_sequence,request_sequence,kind,refusal,failure,
             audio_start_utc_ms}; startup_release is the StartupSafetyRelease state. */
        doc /* POST /transmit/command: exactly {v,profile_id,boot_id,command_id,action} plus the
             action's parameters: arm {safety_revision}; disarm {}; request
             {request_sequence,mode ft8|ft4,period_start_utc_ms,message_text,tx_offset_hz};
             tune {enabled} or {enabled true,tx_offset_hz}; set_watchdogs
             {tx_calls,tune_seconds}. */
        doc /* It answers 200 {v:1,profile_id,boot_id,command_id,result}: result is the
             TransmitOutcome of a request, otherwise {accepted,refusal}. */
        doc /* A retained command_id (last 16) with the identical body returns the same reply
             without effect, and a different body is state_conflict; another boot is
             state_conflict. */
        doc /* POST /transmit/halt is HaltTransmit. */
        @ImplementedIn { module = "server/src/transmit_http.rs"; }
    }
}
