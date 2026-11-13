package WstxCatLifecycle {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-009';
    private import WstxRequirements::'FR-021';
    private import WstxRadioIO::'TC-022-009';
    private import WstxOperatingLayout::'TC-022-010';
    requirement 'CL-022-04' {
        doc /* Selected target cadence: after confirmed released failed attempt wait
             1,2,4,8seconds on successive failures, then8seconds capped. Use one timer
             and one in-flight task under existing station authority; no catch-up or
             backlog. Delays use monotonic time, start after attempt completion and
             confirmed release; reset only after actual fresh successful readback.
             Startup/explicit enable/new valid selected configuration gets one immediate
             attempt; disable/identity change/revocation/invalid commissioning cancels
             timer and current attempt. Re-enable starts a fresh series only after
             release confirmation. Simultaneous browsers do not create extra attempts.
             Preserve setup<=5s, exchange<=1s, cancellation checkpoint<=50ms and ordinary
             RF-context release<=250ms. Bounds are not permissions to assume release.
             Real close failure quarantines the resource; no timed reopen until an
             explicit recovery proves release. Stop/Halt invalidates relevant receive/
             RF-operation tokens and pending resume; CAT housekeeping may not restart
             audio or setters. Late results are identity/generation fenced. Existing
             shared native owner/resource arbitration with RF work stays authoritative.
             Delivered: one station-wide50ms lifecycle tick (one timer, at most one
             tick and one actor in flight) evaluates the grant/commissioning gate under
             the profile store and authority locks, then the policy. A delay starts at
             the first tick observing the confirmed released failure (<=one tick
             after release). Explicit recovery from a failed-close quarantine is a
             station restart; no in-process action clears it. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/cat_lifecycle.rs; server/src/recording.rs; server/src/authorization_http.rs; server/src/main.rs";
    }
    dependency CL_022_04_to_FR_008 from 'CL-022-04' to 'FR-008';
    dependency CL_022_04_to_FR_009 from 'CL-022-04' to 'FR-009';
    dependency CL_022_04_to_FR_021 from 'CL-022-04' to 'FR-021';
    dependency CL_022_04_verified_by_TC_022_009 from 'CL-022-04' to 'TC-022-009';
    dependency CL_022_04_verified_by_TC_022_010 from 'CL-022-04' to 'TC-022-010';

    enum def AutomaticCatCondition { enum disabled; enum unauthorized; enum commissioningRequired; enum waitingForDevice; enum connecting; enum ready; enum retryWaiting; enum closing; enum quarantined; }
    enum def AutomaticCatEvent { enum eligible; enum readbackConfirmed; enum attemptFailedReleased; enum delayElapsed; enum disabledOrRevoked; enum identityChanged; enum releaseFailed; enum recoveryConfirmed; }
    attribute def AutomaticCatStatus {
        doc /* Target current condition, not behavioral states or another actor. One
             authority-owned observation per selected radio; boot/connection generation
             and query sequence still fence every fact. A retained frequency is not
             fresh in any condition except ready with its matching observation proof.
             Existing strict version1 status objects remain unchanged; expose this
             additive target status via POST /authorization/v1/status with
             AuthStatusRequest; same-origin browser POST supplies actual Origin, not a
             script-forged header. Preserve exact Origin/TLS before auth, active scoped
             grant (401 otherwise), no CORS and Cache-Control:no-store. Missing/wrong
             Origin on accepted POST403; legacy GET/profile absence policy is unchanged.
             Read-only snapshot: no identity/grant/session/receipt/native effects or
             CAT retry scheduling. GET on this new path405/no effects; no fallback.
             Strict response version1,scope (AuthWireScope projection),condition,
             error,retry_after_ms,commissioned,receive_state. Error is bounded mapped
             code/null, retry_after_ms safe integer0..8000/null, commissioned Boolean;
             receive_state is existing authoritative audio/decoder summary, no copied
             numerical/result state. Logical response<=1024bytes, reuse existing status
             publication/heartbeat and accounting; no parallel timer/poll stream. */
        attribute scope : WstxStationProtocol::SelectedRadioAuthorizationScope;
        attribute condition : AutomaticCatCondition;
        attribute retryAfterMilliseconds : Integer[0..1];
        attribute errorCode : String[0..1];
    }
    action def MaintainCommissionedCat {
        doc /* Target CL-022-03/04 action under existing selected-radio authority and
             radio actor/executor. Preconditions: control enabled, matching unrevoked
             grant, durable current commissioning and confirmed resource release.
             One immediate attempt at eligible startup/enable/new valid configuration;
             absence/open failure/timeout retries after confirmed failure release at
             1,2,4,8,8seconds monotonic delays. One timer and task across all browsers;
             no catch-up, backlog, extra actor/native builder or endpoint discovery.
             Reset series only on actual fresh readback. Disable/last-grant revocation/
             invalid commissioning/identity change cancels timer and task; re-enable
             waits for release. Existing setup5s/exchange1s/cancel50ms/RFrelease250ms
             remain hard bounds. Failed close quarantines; no timed reopen until
             explicit recovery proves release. Late completions are identity fenced.
             Automatic I/O is read-only queries only, no setters/PTT/audio start or
             replay, except the WstxTransmit::StartupSafetyRelease (one off-only PTT
             release with readback per boot, only when TX is observed before the boot
             ever keyed). Stop/Halt clears receive/RF tokens and pending resume; background
             CAT cannot undo Stop or broaden RF ownership. Missing precondition causes
             zero native open/query/set/PTT. Confirmation itself has no native effect.
             Delivered in server/src/cat_lifecycle.rs driven by Recording::cat_maintain;
             failed-close quarantine lasts until station restart. */
        in scope : WstxStationProtocol::SelectedRadioAuthorizationScope;
        in commissioning : WstxStationProtocol::RadioCommissioningRecord;
        out current : AutomaticCatStatus;
    }
}
