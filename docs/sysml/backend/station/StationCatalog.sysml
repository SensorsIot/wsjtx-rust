package WstxRequirementsStation {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    private import WstxLiveReceive::'TC-009-002';
    private import WstxStationProtocol::'TC-009-005';
    requirement 'CL-008-07' {
        doc /* Coordinate receive-only operating mode and preferred band changes through the existing station/receive owner and typed CAT actor, with explicit nominal/observed truth, actual release barriers, per-query provenance and cancellation fencing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/selection.rs; server/src/selection_http.rs; server/src/radio_http.rs; server/src/radio_control/actor.rs; client/recording.js";
    }
    dependency CL_008_07_to_FR_002 from 'CL-008-07' to 'FR-002';
    dependency CL_008_07_to_FR_009 from 'CL-008-07' to 'FR-009';
    dependency CL_008_07_to_FR_019 from 'CL-008-07' to 'FR-019';
    dependency CL_008_07_to_FR_021 from 'CL-008-07' to 'FR-021';
    dependency CL_008_07_verified_by_TC_009_002 from 'CL-008-07' to 'TC-009-002';
    dependency CL_008_07_verified_by_TC_009_005 from 'CL-008-07' to 'TC-009-005';
    // Live finding 2026-11-06 (#44 comment 6683284855): a band change from the operator must simply work.
    requirement 'CL-044-16' {
        doc /* A selection of POST /receive/select that finds the CAT lease held by the 1 s poll, a menu or AGC exchange or another transition waits for it up to 3 s, without a queue, off the async runtime, and then proceeds: a poll no longer refuses a band change. After the wait the preflight runs again as before. A lease still held at 3 s refuses busy, as does a transmit hold, at once, since a transmission lasts far longer than the wait. The busy refusal of a held lease comes at 3 s from the request, never before, with a margin of at most 250 ms for scheduling and request handling: on the development PC (HB9BLA, 2026-11-07, 35 runs) it came 2 to 82 ms after 3 s, the most beside a build, so 250 ms is about three times the worst seen and well below a 3.5 s wait. A refusal changes nothing: the operating revision and the selection stay as they were, and the Band control shows the band the station is on, with "Selection refused · busy". */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/actor.rs; server/src/recording.rs; server/src/selection.rs; server/src/selection_http.rs";
    }
    dependency CL_044_16_to_FR_009 from 'CL-044-16' to 'FR-009';
    verification 'TC-044-023' {
        doc /* TC-044-023 — A band change meets a held CAT lease
             CL-044-16
             Setup: the actual router, Recording and CAT actor on a scripted IC-7300; Chromium with one refusal injected.
             Steps: (a) POST /receive/select while the lease is held for 300 ms; (b) while it stays held; (c) reserve the lease under a transmit hold; (d) in the browser, select a band and answer 409 busy.
             Expected: (a) 202 after the wait; (b) 409 busy at least 3000 ms and under 3250 ms after the request (3 s plus the 250 ms margin of CL-044-16; a red under load is rerun once), with the operating revision and selection unchanged; (c) Busy at once; (d) "Selection refused · busy" and the Band control back on the current band.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-16';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; tests/radio-selection.test.cjs";
    }
    dependency CL_044_16_verified_by_TC_044_023 from 'CL-044-16' to 'TC-044-023';
}
