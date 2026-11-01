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
         D3 Authorization: the auth-v1 grant model of CL-022-01 unchanged. An MCP client
            enrolls its own P-256 key with the bootstrap token like a browser and proves
            it for a grant transport, presented as Authorization: Bearer. No new credential
            store, OAuth server or MCP-only permission; the grant cap, revocation and
            safety-revision rules apply as they do to browsers.
         D4 Surface: five tools, each exactly one existing station route; no receive
            start/stop, radio, profile edit or log save tool in this CR (the browser keeps
            them); reads cover every operating view.
         D5 Automation: station-owned, volatile (unconfigured, no run after every boot),
            driving the contact engine only through ContactCommand select_row and
            enable_tx with the starting request's grant; WstxContact::AutoSequence
            progresses the contact and the #9 owner transmits. Logging stays the
            operator's WstxContact log review (no automatic save).
         D6 Selection: only plain CQ from a resolved call of the latest completed receive
            publication; three explicit rankings; no worked-before filter, directed CQ,
            CQ calling or attempt counter in this CR (max_unanswered_periods and
            max_contacts bound a run; the Tx watchdog stays in force unchanged).
         D7 Run lifetime (supervisor decision on the #12 review, 2026-11-01): a run lives no
            longer than the starting request's grant transport (its 8 h deadline, a newer
            proof of the grant, revocation or a safety edit stop it authority_lost) and no
            longer than max_run_minutes (default 120, 1..480; stop time_limit). A running
            automation is shown read-only in the browser station bar (AutomationIndicator). */

    attribute def McpEndpoint {
        attribute route : String = "POST /mcp";
        attribute bodyBytesMax : Integer = 8192;
        attribute stationResponseBytesMax : Integer = 65536;
        doc /* Selected-profile mode only (environment-only mode: 404). Validation order:
             a present Origin must be exactly the station origin (else 403, JSON-RPC error
             without id); McpCredential (else 401 with WWW-Authenticate: Bearer
             realm="wstx"); no query (400 -32600); Content-Type application/json with
             optional charset=utf-8 (415); body at most bodyBytesMax (413); JSON (400
             -32700); one object with jsonrpc "2.0", string method, id absent, string or
             integer, params absent or an object (400 -32600; batches refused).
             Notifications (no id) under notifications/ return 202 with no body; other
             notifications 400. GET and DELETE /mcp return 405 Allow: POST. Responses are
             application/json; Mcp-Session-Id is never issued and is ignored. */
    }
    attribute def ProtocolEras {
        attribute modern : String = "2026-07-28";
        attribute legacy : String[2];
        doc /* legacy = 2025-11-25, 2025-06-18; supported list in this order:
             modern then legacy. Modern: a request whose params._meta carries
             io.modelcontextprotocol/protocolVersion; another value is 400 -32022 with
             data {supported, requested}; MCP-Protocol-Version must equal it, Mcp-Method the
             method and, for tools/call, Mcp-Name (Base64 sentinel decoded) params.name
             (else 400 -32020). Methods server/discover {supportedVersions, capabilities
             {tools {listChanged false}}, _meta serverInfo, instructions}, ping, tools/list,
             tools/call; results carry resultType "complete"; unknown method 404 -32601,
             unknown tool or non-object arguments 400 -32602. Legacy: initialize answers
             {protocolVersion (the requested legacy version, else 2025-11-25),
             capabilities, serverInfo, instructions} statelessly; later requests use the
             MCP-Protocol-Version header (absent: 400 -32020); another value 400 -32022,
             the modern value without _meta 400 -32020; JSON-RPC errors of known requests
             are HTTP 200 and results carry no resultType. Era handling never changes
             station idempotency: the JSON-RPC id is correlation only. */
    }
    attribute def McpCredential {
        doc /* Exactly one Authorization field "Bearer " plus a 43-character base64url
             256-bit token; the token must be a current auth-v1 grant transport of this
             station (WstxRequirements::'CL-022-01'), validated per request by the same
             authority owner and lock as GET /profile. Cookies on /mcp are never read; a
             plaintext profile (no grant authority) has no MCP access. The in-process
             station dispatch presents only that validated token as the station session
             credential, with the station Origin. Expiry (8 h transport), revocation or a
             safety edit makes MCP refuse 401 until the client proves its key again.
             The operator helper tools/wstx-mcp-credential.cjs (Node, no dependency)
             enrolls a key with WSTX_MCP_BOOTSTRAP_TOKEN into WSTX_MCP_KEY and, as the
             Claude Code headersHelper, prints {"Authorization":"Bearer <transport>"}. */
    }
    enum def ToolName {
        enum wstx_read;
        enum wstx_results;
        enum wstx_contact_command;
        enum wstx_transmit_halt;
        enum wstx_automation_command;
    }
    attribute def ToolCatalog {
        attribute tools : ToolName[5];
        doc /* Fixed order as above, identical in both eras; each inputSchema has
             additionalProperties false and an outputSchema for ToolResult.
             wstx_read {view: profile|receive|selection|radio|transmit|contact|automation}
             -> GET /profile, /receive, /receive/selection, /radio, /transmit, /contact,
             /automation. wstx_results {source_id, job_id: UUID; generation, cursor: safe
             integer; limit optional 1..16} -> GET /receive/results. wstx_contact_command
             {command: WstxContact::ContactCommand} -> POST /contact/command.
             wstx_transmit_halt {halt: HaltTransmit body} -> POST /transmit/halt.
             wstx_automation_command {command: AutomationCommand} -> POST
             /automation/command. Missing, extra or mistyped arguments, an unknown view or a
             non-UUID id are a tool error {status 400, error invalid_request with the field}
             without a station call. */
    }
    attribute def ToolResult {
        doc /* structuredContent exactly {v:1, tool, status, result}: status is the station
             route's HTTP status, result its JSON body (snapshot, receipt or the station's
             own error {code, field}). content is one text item whose text is the same
             serialized structuredContent; isError is status >= 400. A station refusal is a
             tool error, never a JSON-RPC error; no MCP-specific code replaces it. */
    }

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
        assert constraint runLimit { maxRunMinutes >= 1 and maxRunMinutes <= 480 }
        assert constraint contactLimit { maxContacts >= 1 and maxContacts <= 100 }
        assert constraint answerLimit { maxUnansweredPeriods >= 1 and maxUnansweredPeriods <= 20 }
        doc /* Wire keys exactly modes, ranking, min_snr_db, allowed_calls, blocked_calls,
             max_contacts, max_unanswered_periods, completion_action, all required, and
             max_run_minutes, optional (absent: 120; D7); null is the unconfigured state;
             the snapshot always shows max_run_minutes. modes: nonempty unique subset of
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
    enum def RunState { enum waiting; enum contact_active; enum stopped; }
    enum def StopReason {
        enum stopped; enum completed; enum limit_reached; enum no_answer; enum halted;
        enum transmit_stopped; enum contact_changed; enum authority_lost;
        enum context_changed; enum transmit_refused; enum provider_error;
        enum time_limit;
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
             Esc or MCP) stops halted; a different live identity, live mode or operating
             mode stops context_changed; the starting transport no longer this grant's
             current unexpired transport stops authority_lost; the run deadline stops
             time_limit; a contact armed by the run is disarmed (Enable Tx off, never a
             Halt) on these and on contact_changed (run's contact gone or replaced) and
             no_answer.
             waiting: a contact calling or in progress that the run did not create (an
             operator's CQ or contact) stops contact_changed and is left as it is; on a
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
             completed, else waiting; cancelled or idle stops contact_changed; not armed
             stops transmit_stopped; each fresh publication of the partner's period parity
             (the opposite of the contact's own; unknown period: not counted) without a
             change of (state, report_rcvd) since the selection or the last change counts
             unanswered, at max_unanswered_periods stop no_answer.
             Stopped runs stay visible until the next start. */
    }
    attribute def AutomationIndicator {
        doc /* Browser station bar, read-only, beside the transmit state: while a run is
             waiting or in a contact it shows "Automation waiting" or "Automation in
             contact", the first 8 characters of the run id and "Halt ends it"; hidden
             otherwise. The station sends automation.state {profile_id, boot_id,
             policy_revision, run_revision} (an optional write paced with contact.state)
             after each change since boot, also once to a peer that subscribes while
             either revision is nonzero; the browser then reads GET /automation. No event
             or request while automation is never used. */
    }
    attribute def AutomationWire {
        attribute receiptsRetained : Integer = 16;
        attribute bodyBytesMax : Integer = 1024;
        doc /* GET /automation (AutomationSnapshot): exactly {v:1, profile_id, boot_id,
             policy_revision, run_revision, configuration (null or the configuration),
             run (null or {id, state, reason, mode, completed_contacts, unanswered_periods,
             contact_id, selected (null or {source_id, job_id, generation, sequence, call}),
             last_decision})}; existing auth and Origin rules of GET routes.
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
             run, not_configured, not_ready mode (configuration), not_ready receive,
             not_ready mode (live job or operating mode), not_ready auto_seq,
             state_conflict contact, transmit_unavailable (no grant transport, no transmit
             owner or no current safety revision), stale_revision safety_revision; then
             run_revision + 1 and a new run id. stop: a current
             unstopped run id, else 409 stale_request; dispatch ends before the receipt,
             then the run's contact is disarmed. Accepted: 202 {v:1, profile_id, boot_id,
             command_id, accepted:true, policy_revision, run_revision, run_id, state
             off|waiting|contact_active|stopped}. run_revision also advances on every run
             change (selection, contact transition, counters, stop). Counters at
             9007199254740991 refuse counter_exhausted. Accepted means admitted, not keyed. */
    }

    dependency adapterOwner from McpEndpoint to WstxArchitecture::McpAdapter;
    dependency contactPath from OperatingAutomation to WstxContact::ContactCommand;
    dependency haltPath from OperatingAutomation to WstxTransmit::HaltTransmit;
    dependency endpointClause from McpEndpoint to WstxRequirements::'CL-012-01';
    dependency toolsClause from ToolCatalog to WstxRequirements::'CL-012-02';
    dependency credentialClause from McpCredential to WstxRequirements::'CL-012-03';
    dependency automationClause from OperatingAutomation to WstxRequirements::'CL-012-03';
    dependency policyClause from CandidateSelection to WstxRequirements::'CL-012-04';
    dependency configurationClause from AutomationConfiguration to WstxRequirements::'CL-012-04';
}
