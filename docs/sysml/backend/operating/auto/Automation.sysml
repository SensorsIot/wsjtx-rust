package WstxMcp {
    private import ScalarValues::*;
    doc /* Canonical contract of MCP access and configured FT4/FT8 operating automation
         (issue #12, CL-012-01..04 in WstxRequirements; verification TC-020-001..003).
         Nothing here is an execution result.

         Decisions (issue #12, 2026-11-01, recorded by the implementing CR; the earlier
         private preparation package, manifest SHA-256 ff58a74e..., proposed a separate
         stdio adapter process holding lease custody against then-provisional providers;
         the delivered #9/#10/#11/#22 station services make that layer unnecessary):
         D1 Transport: Streamable HTTP on the station's own listener and TLS, POST /mcp.
            Claude Code and Codex on HB9BLA both support HTTP servers with configured
            headers; an HTTP endpoint keeps the one authoritative process, adds no client
            child process whose exit (Claude Code may kill stdio children within 300 ms on
            Windows) would own station lifecycle, and needs no lease custody or delegated
            renewal: station state, grant and transmit authority stay in the station.
         D2 Eras: modern 2026-07-28 and legacy 2025-11-25 (also 2025-06-18), both
            stateless with JSON responses; no SSE, sessions, subscriptions, sampling,
            elicitation, resources or prompts. 2025-03-26 is not offered: it requires
            JSON-RPC batches, which this endpoint refuses (review finding 6).
         D3 Authorization (operator decision on #58, 2026-11-02, replacing the #12 choice
            of an auth-v1 grant per MCP client): an MCP client holds an MCP client token of
            its own (McpCredential, WstxStationLink::McpClientCredential), created and revoked
            by the browser in Settings > General > Access & grants; it is separate from the
            station access token (WSTX_TOKEN) and from every browser grant. POST /mcp
            accepts only such a token; browser routes refuse it; it is never exchanged for
            a browser cookie or grant. The station attaches the principal of every request
            at the auth boundary from its credential (WstxStationProtocol::RequestPrincipal), so
            whichever route a request takes, MCP is never counted as the browser operator.
            No OAuth server or MCP-only permission; the safety-revision and transmit grant
            rules apply to its in-process requests as they do to browsers.
         D4 Surface: six tools, each exactly one existing station route; no receive
            start/stop, radio, profile edit, strategy edit or log save tool (the browser
            keeps them); reads cover every operating view. Since #39 the browser also
            shows the strategy (GET /strategy) and its verdicts (POST /strategy/evaluate,
            value rank and greyed directed CQs); #12 CR 2026-11-03 adds the view
            strategy and the read-only tool wstx_strategy_evaluate, so an MCP client sees
            the strategy a strategy run uses and the directed-CQ verdicts before it
            selects; PUT /strategy stays browser-only.
         D5 Automation: station-owned, volatile (unconfigured, no run after every boot),
            driving the contact engine only through ContactCommand select_row and
            enable_tx with the starting request's grant; WstxStandardQso::AutoSequence
            progresses the contact and the #9 owner transmits. Each completed contact
            is logged by WstxLogbook::DirectLog (#41), as for a browser-driven one.
         D6 Selection: only plain CQ from a resolved call of the latest completed receive
            publication; three explicit rankings; no worked-before filter, directed CQ,
            CQ calling or attempt counter in this CR (max_unanswered_periods and
            max_contacts bound a run; the Tx watchdog stays in force unchanged).
         D7 Run lifetime (supervisor decision on the #12 review, 2026-11-01; #58): a run lives
            no longer than the starting request's transport (its 8 h deadline, a newer proof
            of that browser grant, revocation of that grant or MCP client, or a safety edit
            stop it authority_lost; a browser proof never ends an MCP client's run) and no
            longer than max_run_minutes (default 120, 1..480; stop time_limit); a strategy run
            follows its grant instead, D8 and WstxAutoControl::StrategyRun. A running
            automation is shown read-only in the browser station bar (AutomationIndicator).
         D8 Strategy runs (#39, WstxAutoControl::StrategyRun): a selected strategy with Auto on
            (WstxAutoControl::AutoToggle, the browser only) is a run of this owner in which the active strategy chooses and
            orders stations; it has no contact limit, its own limit of 8 hours (run_limit) and never stops no_answer. An
            MCP client cannot select one: the configuration key strategy true is refused
            operator_required, PUT /strategy has no MCP tool. For every run
            (D6 included; a strategy run's own contact only when unattended, otherwise it has
            no stop: WstxStrategy::StrategyWatchdog) the Tx watchdog limits the repetitions of one message; only an
            Enable Tx, a strategy selection or an Auto on from the browser ends its stop, never the run's commands
            or an MCP request (including starting or restarting a run)
            (WstxStrategy::WatchdogFromOperator, coordinator default for the operator's
            rule, recorded on #39/#12, 2026-11-02, amending D5/D7; repetition form 2026-11-06);
            an MCP Enable Tx or run arm is refused tx_watchdog after a stop
            or when no browser action was seen this boot; set_watchdogs through MCP is refused operator_required (only the
            browser sets the watchdog); a watchdog disarm stops tx_watchdog, for an unattended strategy
            run no_client or run_limit (WstxStrategy::StrategyWatchdog). */

    enum def Ranking { enum first_seen; enum strongest_snr; enum lowest_frequency; }
    enum def CompletionAction { enum stop; enum next_candidate; }
    attribute def AutomationConfiguration {
        attribute modes : String[1..2];
        attribute ranking : Ranking;
        attribute minSnrDb : Integer[0..1];
        attribute allowedCalls : String[0..16];
        attribute blockedCalls : String[0..16];
        attribute maxContacts : Integer;
        attribute maxUnansweredPeriods : Integer;
        attribute completionAction : CompletionAction;
        attribute maxRunMinutes : Integer = 120;
        attribute strategy : Boolean = false;
        attribute pounce : String[0..1];
        assert constraint runLimit { maxRunMinutes >= 1 and maxRunMinutes <= 480 }
        assert constraint contactLimit { maxContacts >= 1 and maxContacts <= 100 }
        assert constraint answerLimit { maxUnansweredPeriods >= 1 and maxUnansweredPeriods <= 20 }
        doc /* Wire keys exactly modes, ranking, min_snr_db, allowed_calls, blocked_calls,
             max_contacts, max_unanswered_periods, completion_action, all required, and
             max_run_minutes, optional (absent: 120; D7), and strategy, optional boolean
             (absent or false; true is refused 409 operator_required strategy: a strategy
             run starts only by a browser's selection, D8), and pounce, optional (absent or null: no pounce; else one
             call of 3..13 A-Z 0-9 / passing WstxStrategy::SaneCall, and
             not in blocked_calls, else invalid_request pounce; #42 WstxStrategy::Pounce);
             null is the unconfigured state; the snapshot always shows
             max_run_minutes, strategy and pounce. modes: nonempty unique subset of
             ft8, ft4. min_snr_db null or integer -50..49. Calls: unique, 3..13 of A-Z,
             0-9, /, at most 16 per list, never in both. No default selection policy is
             filled in. */
    }
    attribute def CandidateSelection {
        doc /* Input: the records [first_sequence, next_sequence) of the latest receive
             publication (latest_decode) with complete true, newer than the run's last seen
             publication and of the run's live identity. Eligible: status decoded, standard
             fields, to token "CQ" exactly, from a resolved call not the profile callsign,
             not completed in this run, in allowed_calls when that list is nonempty, not in
             blocked_calls, snr_db >= min_snr_db when set (unknown SNR then excluded);
             strongest_snr also excludes unknown SNR. One candidate per call (its lowest
             sequence). Order: first_seen by sequence; strongest_snr by SNR descending;
             lowest_frequency by frequency ascending; ties by call (ASCII) then sequence.
             Exact published values; no tolerance or epsilon. The first candidate is
             chosen, once per publication. */
    }
    enum def RunState { enum waiting; enum contact_active; enum calling_cq; enum manual; enum stopped; }
    enum def StopReason {
        enum stopped; enum completed; enum limit_reached; enum no_answer; enum halted;
        enum transmit_stopped; enum contact_changed; enum authority_lost;
        enum context_changed; enum transmit_refused; enum provider_error;
        enum time_limit; enum tx_watchdog; enum strategy_missing; enum band_changed; enum no_client; enum run_limit;
    }
    attribute def OperatingAutomation {
        attribute runState : RunState;
        attribute stopReason : StopReason[0..1];
        doc /* One owner per station beside the contact engine; one run at a time. Start
             captures the configuration, mode, live identity (source, job, generation),
             the request's grant and its grant transport (memory only), the station's
             current safety revision (equal to the start's), the HaltTransmit count, the
             run deadline (start + max_run_minutes) and the latest publication id (earlier
             publications are never used).
             Each station step (after the contact step, with the publication descriptor
             read before it), in this order: any HaltTransmit since start (browser button,
             Alt+H or MCP) stops halted; a different live identity, live mode or operating
             mode stops context_changed; the starting transport no longer this grant's
             current unexpired transport stops authority_lost; the run deadline stops
             time_limit; a contact armed by the run is disarmed (Enable Tx off, never a
             Halt) on these and on contact_changed (run's contact gone or replaced) and
             no_answer, except that a started QSO is finished at time_limit, at a stop and when
             an Auto on ends the run (#81, WstxStrategy::StartedQso).
             waiting: a contact calling or in progress that the run did not create (an
             operator's CQ or contact) stops contact_changed and is left as it is (a strategy
             run: state manual, WstxStrategy::ManualIntervention); on a
             fresh publication record last_decision {period_start_utc, candidates,
             selected_call}; with a candidate send ContactCommand select_row {row, replace
             false} then enable_tx {enabled true, safety_revision} with the grant. Refusal
             of select_row stops provider_error; refusal of enable_tx cancels the selected
             contact and stops transmit_refused. After an accepted enable_tx the HaltTransmit
             count is read again; a Halt since start (one that raced the arming) is answered
             with a new HaltTransmit, never only a disarm, and stops halted. Otherwise
             contact_active with that contact.
             contact_active: completed adds the call to the run's worked list and counts it;
             reaching max_contacts stops limit_reached, completion_action stop stops
             completed, else waiting; cancelled or idle stops contact_changed (a strategy run:
             ManualIntervention); not armed
             stops transmit_stopped; each fresh publication of the partner's period parity
             (the opposite of the contact's own; unknown period: not counted) without a
             change of (state, report_rcvd) since the selection or the last change counts
             unanswered, at max_unanswered_periods stop no_answer.
             Stopped runs stay visible until the next start. A run with strategy true
             follows WstxAutoControl::StrategyRun instead of CandidateSelection, its bounds,
             its context_changed stop and the no_answer stop; a run with pounce follows
             WstxStrategy::Pounce instead of CandidateSelection, its completion and no_answer
             rules, and stops band_changed on a station band change; a disarm by the Tx watchdog stops
             tx_watchdog for every run, an unattended strategy run naming no_client or run_limit
             instead (WstxStrategy::StrategyWatchdog); a refused enable_tx with code tx_watchdog stops
             tx_watchdog. Run commands are automatic: they never end a Tx watchdog stop. */
    }
    attribute def AutomationWire {
        attribute receiptsRetained : Integer = 16;
        attribute bodyBytesMax : Integer = 1024;
        doc /* GET /automation (AutomationSnapshot): exactly {v:1, profile_id, boot_id,
             policy_revision, run_revision, configuration (null or the configuration),
             run (null or {id, state, reason, mode, completed_contacts, unanswered_periods,
             contact_id, selected (null or {source_id, job_id, generation, sequence, call}),
             last_decision, given_up (calls the operator gave up in a strategy run), left (null
             or {call, reason repetitions|gone|tx_changes|caller}, the last station a strategy or
             contest run left, WstxStrategy::LeaveRule, #97), quiet ([{call, band, mode, remaining_s}],
             WstxStrategy::QuietTime, the retry pause), hearing (null or {state heard|no|unknown,
             reports, spot_utc_s, snr_db}, WstxHearingFeed::PskrUse), tx_slot (null or {hz, power_db, his_end
             yes|no|unknown}, power_db the slot's whole-dB rise above the passband floor clamped at 0 (#66),
             WstxStrategy::FreeTxSlot), slot_check (null or {repetitions, case
             heard|not_heard|no_reports, hears_us, moved, hz}, WstxStrategy::StrategyWatchdog,
             TxMoveRule), leave (null or {mode, remaining, busy, paused, staying},
             WstxStrategy::LeaveCountLabel, #97), pounce (null or
             {call, band}, #42)), strategy_refusal (null or why the last selection started no run,
             WstxAutoControl::StrategyRun), free_tx_slots (the station's open slots, with
             or without a run: null without a live receive, else the latest built value,
             WstxAutoControl::FreeTxSlots, #82)};
             existing auth and Origin rules of GET routes.
             POST /automation/command (AutomationCommand): exactly {v, profile_id, boot_id,
             command_id, action} plus configure {expected_policy_revision, configuration};
             start {expected_policy_revision, expected_run_revision, mode ft8|ft4,
             safety_revision >= 1}; stop {run_id}. Order after route/Origin/auth/size/media:
             keys, v (unsupported_version), UUIDs and safe integers, configuration, then
             profile (403 wrong_profile), boot (409 state_conflict). A retained command_id
             with the same body returns its receipt (200) with no effect, another body 409
             state_conflict command_id. configure: stale_revision on
             expected_policy_revision, state_conflict run while a run is active, then
             policy_revision + 1. start: stale_revision on either revision, state_conflict
             run, not_configured, operator_required strategy (a configuration a strategy run left), not_ready mode (configuration), not_ready receive,
             not_ready mode (live job or operating mode), not_ready auto_seq, not_ready
             call (a nonstandard profile callsign: automation stays standard-only, #24
             CL-024-01), not_ready activity (a contest activity other than none, or hound, is set:
             automation only observes in contests and as a Hound, #24 CL-024-02, CL-024-04), not_ready band (a pounce without a known station band),
             state_conflict contact, transmit_unavailable (no grant transport, no transmit
             owner or no current safety revision), stale_revision safety_revision; then
             run_revision + 1 and a new run id. stop: a current
             unstopped run id, else 409 stale_request; dispatch ends before the receipt,
             then the run's contact is disarmed, unless it is a started QSO, which is finished
             (#81, WstxStrategy::StartedQso). Accepted: 202 {v:1, profile_id, boot_id,
             command_id, accepted:true, policy_revision, run_revision, run_id, state
             off|waiting|contact_active|calling_cq|manual|stopped} (calling_cq: only a contest Run, WstxAutoControl::ContestRun). run_revision also advances on every run
             change (selection, contact transition, counters, stop). Counters at
             9007199254740991 refuse counter_exhausted. Accepted means admitted, not keyed. */
    }
    dependency contactPath from OperatingAutomation to WstxQsoControl::ContactCommand;
    dependency haltPath from OperatingAutomation to WstxTransmit::HaltTransmit;
    dependency automationClause from OperatingAutomation to WstxMcpEndpoint::'CL-012-03';
    dependency policyClause from CandidateSelection to WstxMcpEndpoint::'CL-012-04';
    dependency configurationClause from AutomationConfiguration to WstxMcpEndpoint::'CL-012-04';
}
