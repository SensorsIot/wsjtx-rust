package WstxRequirementsWeb {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-003-03' {
        doc /* The server MUST validate request structure, protocol version, command and message size in the contract's order. Rejected input MUST follow the defined error/close behavior; recoverable errors MUST leave the server available without exposing internal details. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_03_to_FR_021 from 'CL-003-03' to 'FR-021';
    requirement 'CL-003-06' {
        doc /* Application output buffering and active connections MUST have explicit bounds (WstxStationProtocol::Limits; design bounds, checked by review). A peer that stops answering (no Pong for more than 15 s) MUST be removed at the next heartbeat tick, without delaying another client's status requests (#80: the one liveness case that matters in normal operation, a browser that vanishes without closing). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs; client/app.js";
    }
    dependency CL_003_06_to_FR_021 from 'CL-003-06' to 'FR-021';
    verification 'TC-021-005' {
        doc /* #### TC-021-005 — Message exchange and invalid-input handling

             **Clauses:** CL-003-02, CL-003-03. **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, actual candidate Rust server on a temporary loopback
             port, independent WebSocket test peer; the parser examples also run as Rust unit tests.

             **Inputs/actions and expected results:**

             1. Send the contract's valid station.get example. Expect the specified station.status
                envelope, matching ID, candidate package version, radio state unconfigured and
                the ClientBuild (#51) computed independently from the client files; the page
                carries the same build.
             2. Send different request IDs through two concurrent connections. Expect each response
                on its originating connection with its own ID and authoritative state.
             3. Send malformed JSON, a non-object, unknown command, unsupported version, missing ID,
                wrong ID type, out-of-range ID, invalid type field and an extra field. Expect the
                contract's error for each input. A request combining an unsupported version with an
                invalid type MUST follow shape-before-version validation. A valid peer MUST remain usable.
             4. Send a valid request padded to the message-size boundary. Expect its normal response.
                Exceed the boundary by one byte and expect transport rejection/closure while the other
                peer remains usable. Send a binary frame and expect the specified close behavior.

             **Oracle:** hand-authored contract examples, candidate version and
             [message/error rules](../../StationProtocol.sysml).
             **Executable trace:** [communication.test.cjs](../../../../tests/communication.test.cjs),
             `TC-021-005: actual-server correlation, negative cases and size boundaries`;
             [protocol_tests.rs](../../../../server/src/protocol_tests.rs),
             `protocol_returns_specified_response_and_errors`. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-02';
            verify 'CL-003-03';
        }
        attribute executable : String = "tests/communication.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-021-008' {
        doc /* #### TC-021-008 — Dead peer removal

             **Clauses:** CL-003-02, CL-003-06. **Promise:** FR-021. **Level:** 2 — Isolated automated tests.
             **Where it runs:** Windows PC, the actual router in the test process; the connection loop's
             clock is the runtime's and the test drives it (no real wait); the test holds each peer's
             transport; the connections run without authorization (plaintext loopback). #80 (operator 2026-11-09): the 32 kbit/s budget variant and the real-time
             stalled-reader variant are retired; the link budget is judged from the link byte log
             (TC-080-001); the write and flush deadlines are design bounds checked by review.

             **Inputs/actions and expected results:**

             1. Peer A subscribes Thin, then neither reads nor answers Ping; its transport keeps
                accepting writes (a vanished browser behind a kernel buffer). Expect A closed with
                reason "no pong for 15 s" at the first heartbeat tick more than 15 s after its last
                Pong (driven time in (15 s, 20 s]), never earlier.
             2. Peer B sends station.get every 5 s throughout. Expect each answered within 2 s, and
                B usable after A's removal.
             3. Control: a peer answering every Ping stays open through 60 s of driven time.

             **Oracle:** Limits stalePongMs 15000 and heartbeatMs 5000 and the Heartbeat rule
             ("on the next heartbeat tick, >15 s without Pong disconnects that peer") in the
             [liveness rules](../../StationProtocol.sysml). Removing the Pong check (#70 mutation M8)
             must turn case 1 red. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-003-02';
            verify 'CL-003-06';
            verify 'FR-021';
        }
        attribute executable : String = "server/src/liveness_tests.rs";
    }
    dependency CL_003_03_verified_by_TC_021_005 from 'CL-003-03' to 'TC-021-005';
    dependency CL_003_06_verified_by_TC_021_008 from 'CL-003-06' to 'TC-021-008';

    // #51 An open page recovers after a station update (chosen defaults: WstxStationProtocol::PageUpdate).
    requirement 'CL-051-01' {
        doc /* The station identifies the browser client it serves with WstxStationProtocol::ClientBuild: the first 16 lower-case hex digits of the SHA-256 over its served client files in route order. The served page carries it as body data-build and every station.status reply carries it as data.build (data exactly {version, radio, build}). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/main.rs";
    }
    dependency CL_051_01_to_FR_021 from 'CL-051-01' to 'FR-021';
    dependency CL_051_01_verified_by_TC_051_001 from 'CL-051-01' to 'TC-051-001';
    dependency CL_051_01_verified_by_TC_051_003 from 'CL-051-01' to 'TC-051-003';
}
