package WstxMcpEndpoint {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-020';
    private import WstxArchitecture::'FR-021';
    private import WstxArchitecture::'FR-007';
    private import WstxRequirements::AutomationState;
    private import WstxArchitecture::'FR-008';
    private import WstxTransmit::'CL-039-06';

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
        attribute tokenPrefix : String = "wstx_mcp_";
        attribute refusedAttemptsPerMinute : Integer = 10;
        attribute auditFile : String = "mcp-audit.log";
        attribute auditRecentShown : Integer = 32;
        doc /* (#58) Exactly one Authorization field "Bearer " plus an MCP client token of
             this station (WstxStationProtocol::McpClientCredential): "wstx_mcp_" and 43 base64url
             characters (256 random bits), validated per request by the station's authority
             owner under the profile store -> authorization lock order by a constant-time
             comparison of its SHA-256 with the stored digests. Cookies on /mcp are never
             read; a plaintext profile (no grant authority) has no MCP access.
             Refusals: 401 with WWW-Authenticate Bearer realm="wstx" and JSON-RPC -32001
             "unauthorized"; a bearer without the prefix (the station access token or a
             browser grant transport, as configured before #58) carries data {reason
             "mcp_token_required", hint naming Settings > General > Access & grants > MCP
             clients}, no silent fallback; an unknown or revoked MCP token data {reason
             "mcp_token_invalid"}. More than refusedAttemptsPerMinute refused bearers in 60 s
             are 429 rate_limited; a valid token never waits.
             The in-process station dispatch presents an internal MCP-principal transport of
             that client (never sent to any client, reused until its 8 h deadline; revocation
             or a safety edit ends it at once) as the station session credential, with the
             station Origin; every station route reads principal mcp from it, and a
             boundary guard in front of every route refuses 401 a session credential of
             principal mcp on any route that no tool dispatches to (POST /transmit/command,
             PUT /profile, PUT /strategy, logbook, WS, settings, receive and radio control).
             Audit: every authenticated MCP request appends one JSON line {utc_ms,
             client_id, name, action (method, tool and its view or command action), status
             (the station status of a tools/call, else the HTTP status)} to auditFile in the
             profile directory (moved to mcp-audit.1.log at 1 MiB, one older file kept) and
             to the last auditRecentShown entries shown in Settings; no token is logged. */
    }
    enum def ToolName {
        enum wstx_read;
        enum wstx_results;
        enum wstx_contact_command;
        enum wstx_transmit_halt;
        enum wstx_automation_command;
        enum wstx_strategy_evaluate;
    }
    attribute def ToolCatalog {
        attribute tools : ToolName[6];
        doc /* Fixed order as above, identical in both eras; each inputSchema has
             additionalProperties false and an outputSchema for ToolResult.
             wstx_read {view: profile|receive|selection|radio|transmit|contact|automation|
             strategy|alerts} -> GET /profile, /receive, /receive/selection, /radio,
             /transmit, /contact, /automation, /strategy, /strategy/alerts (#42
             WstxStrategy::Alert, read-only; clearing stays in the browser). wstx_results {source_id, job_id: UUID; generation, cursor: safe
             integer; limit optional 1..16} -> GET /receive/results. wstx_contact_command
             {command: WstxQsoWire::ContactCommand} -> POST /contact/command; its description
             states that open_log (WstxLogbook::DirectLog) closes an unfinished contact
             (completed, Enable Tx off, nothing queued, #37).
             wstx_transmit_halt {halt: HaltTransmit body} -> POST /transmit/halt.
             wstx_automation_command {command: AutomationCommand} -> POST
             /automation/command; its description names every AutomationConfiguration
             wire key (max_run_minutes, strategy and pounce included).
             wstx_strategy_evaluate {request: the StrategyEvaluate body of
             WstxStrategy::StrategyHttp} -> POST /strategy/evaluate (readOnlyHint; it never
             changes station state; the browser's refusals, e.g. 409 not_configured
             strategy, are its tool errors). Missing, extra or mistyped arguments, an unknown view or a
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

    dependency adapterOwner from McpEndpoint to WstxArchitecture::McpAdapter;
    dependency endpointClause from McpEndpoint to WstxMcpEndpoint::'CL-012-01';
    dependency toolsClause from ToolCatalog to WstxMcpEndpoint::'CL-012-02';
    dependency credentialClause from McpCredential to WstxMcpEndpoint::'CL-012-03';

    // #12 MCP access and configured FT4/FT8 automation (decisions recorded in WstxMcp
    // and on issue #12, 2026-11-01); detailed contract in WstxMcp.
    requirement 'CL-012-01' {
        doc /* Serve MCP on the station's own listener at POST /mcp (Streamable HTTP, MCP 2026-07-28 and legacy 2025-11-25/2025-06-18, stateless, JSON responses only) and map every tool onto exactly one existing versioned station operation dispatched in-process through the station router: no second station state, modem, QSO engine, transmit-authority path, raw CAT/PTT/audio tool or MCP-owned retry. Details: WstxMcpEndpoint::McpEndpoint, ProtocolEras, ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/main.rs";
    }
    dependency CL_012_01_to_FR_020 from 'CL-012-01' to 'FR-020';
    dependency CL_012_01_to_FR_021 from 'CL-012-01' to 'FR-021';
    requirement 'CL-012-02' {
        doc /* An MCP client observes exactly the browser's station views (profile, receive, selection, radio, transmit, contact, automation, strategy, the #42 alert history and decoded result pages, and the strategy verdicts of POST /strategy/evaluate, read-only) and operates through the same ContactCommand, HaltTransmit and AutomationCommand bodies, receipts, revisions, command_id idempotency and refusal codes as the browser, for FT8 and FT4. Details: WstxMcpEndpoint::ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/contact_http.rs; server/src/automation.rs";
    }
    dependency CL_012_02_to_FR_020 from 'CL-012-02' to 'FR-020';
    dependency CL_012_02_to_FR_007 from 'CL-012-02' to 'FR-007';
    verification 'TC-020-001' {
        doc /* TC-020-001 — Shared observation
             CL-012-01, CL-012-02, CL-012-04
             Setup: (a) actual candidate router on a selected HTTPS profile (HB9BLA, JN47AA) with its auth-v1 owner, the contact engine and the #9 transmit owner on the recording hardware double, an injected FT8 live job and hand-authored codec-packed rows "CQ K1ABC FN42" 1234.6 Hz -12.4 dB and "CQ W1AW FN31" 900.0 Hz -3.0 dB; one enrolled grant; an independent JSON-RPC test client. (b) The compiled executable on a disposable HTTPS profile with a throwaway certificate and a browser-style grant that creates the MCP client token; the browser saves the strategy "NA first" (rule 1 CQ from continent NA, rule 2 any CQ, sort strongest) as active.
             Steps: modern server/discover and tools/list; wstx_read of every view and GET of the same browser route; wstx_results and the same GET /receive/results; wstx_strategy_evaluate of sequences [0, 2) with the saved strategy and the same POST /strategy/evaluate from the browser; legacy initialize, notifications/initialized, tools/list and tools/call; (b) create an MCP client token in Settings (POST /authorization/v1/mcp-clients/create), then tools/list and wstx_read profile/contact/strategy against GET /profile and GET /strategy.
             Expected (WstxMcp tables and the fixture's own identities): supportedVersions exactly [2026-07-28, 2025-11-25, 2025-06-18]; tools exactly wstx_read, wstx_results, wstx_contact_command, wstx_transmit_halt, wstx_automation_command, wstx_strategy_evaluate in this order and identical in both eras, wstx_read's view enum the nine views (alerts last, #42), wstx_strategy_evaluate readOnlyHint and the wstx_automation_command description naming every AutomationConfiguration key (max_run_minutes and strategy included); each view (strategy included: active "NA first", my_continent EU) equal to the browser response apart from the per-read monotonic_ms/utc_ms; profile_id/boot_id the fixture's; automation configuration and run null; the two rows with their literal text, frequency, SNR and sequences; the verdicts equal the browser's: K1ABC (FN42, NA) rank 0 and W1AW (FN31, NA) rank 0, W1AW first (strongest); legacy protocolVersion 2025-11-25, no Mcp-Session-Id, no resultType; the text content equals structuredContent; no PTT exchange.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router and executable, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-01';
            verify 'CL-012-02';
            verify 'CL-012-04';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs";
    }
    dependency CL_012_01_verified_by_TC_020_001 from 'CL-012-01' to 'TC-020-001';
    dependency CL_012_02_verified_by_TC_020_001 from 'CL-012-02' to 'TC-020-001';
    verification 'TC-020-002' {
        doc /* TC-020-002 — Validation and authority
             CL-012-01, CL-012-02, CL-012-03
             Setup: as TC-020-001 (a) plus a second HTTPS station with its own MCP client and a plaintext station; (b) the executable with a browser-style grant.
             Steps: no Authorization, the browser cookie alone, lower-case scheme, a malformed or unknown token, an unknown wstx_mcp_ token, another station's MCP client token, this station's own browser grant transport, two Authorization fields, the plaintext station; a foreign Origin, GET, text/plain, BODY_MAX+1 bytes, invalid JSON, a batch, jsonrpc 1.0, id null or 1.5, array params, legacy version 2024-11-05, a legacy request without MCP-Protocol-Version and with 2025-03-26; modern version 1900-01-01, Mcp-Method and Mcp-Name mismatch, a Base64-sentinel Mcp-Name, resources/list, unknown tool wstx_raw_ptt; tool arguments with an extra key, an unknown view, a query-injecting source_id, wstx_strategy_evaluate without request and with request a string; ContactCommand with another station's profile_id, a future contact_revision, action key_ptt, another job's row, another boot; automation start unconfigured, configure with max_contacts 0, start with safety_revision 4 while 3 is current; then a valid MCP enable_tx, its exact retry and a changed body with the same command_id, and an MCP Halt; (b) the browser cookie on /mcp, the same transport and the station access token as an explicit bearer.
             Expected (independent refusal catalogue): 401 with WWW-Authenticate Bearer realm="wstx" for every credential case and the plaintext station; 403, 405, 415, 413; JSON-RPC -32700, -32600 (each malformed envelope), -32022 with data {supported,requested} (also for 2025-03-26), -32020 (also for the missing legacy header), -32601 with 404, -32602; tool errors status 400 invalid_request with the field (extra, view, source_id, request twice) and no station call; station refusals 403 wrong_profile, 409 stale_revision, 400 invalid_request action, 409 row_unavailable, 409 state_conflict boot_id, 409 not_configured, 400 max_contacts, 409 stale_revision safety_revision; before the valid enable_tx the contact revision, contact, arm state, policy revision and PTT log are unchanged; enable_tx 202 and armed, retry 200 with the same receipt, changed body 409 state_conflict command_id; Halt 202 and disarmed; (b) cookie 401, both bearers 401 with reason mcp_token_required and the Settings hint.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router and executable with transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-01';
            verify 'CL-012-02';
            verify 'CL-012-03';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs; server/src/automation_tests.rs";
    }
    dependency CL_012_01_verified_by_TC_020_002 from 'CL-012-01' to 'TC-020-002';
    dependency CL_012_02_verified_by_TC_020_002 from 'CL-012-02' to 'TC-020-002';
    dependency CL_012_02_verified_by_TC_020_003 from 'CL-012-02' to 'TC-020-003';
    requirement 'CL-012-03' {
        doc /* MCP authorization is explicit and separate from the browser (#58): exactly one Authorization: Bearer field carrying an MCP client token of this station, created and revoked in Settings > General > Access & grants, shown once, stored only as its SHA-256 and compared in constant time; cookies sent to /mcp are never read, the station access token and browser grant transports are refused with a hint to the MCP client token, an MCP token is refused on every browser route and never exchanged for a browser cookie or grant, revocation takes effect at the next request, refused bearers are rate limited and every use is audited (name, action, time). Every request carries its principal (browser, mcp, automation) from its credential; only browser is an operator action. A plaintext profile has no MCP access, a present Origin must be the station's. Transmit-capable operations need the MCP client's station transport like the browser's grant. Automation is station-owned, unconfigured and stopped at every boot, starts only on an explicit start with a current grant transport and the current acknowledged safety revision, lives no longer than that transport and its maximum duration, is shown read-only in the browser station bar, never takes over an operator's CQ or contact, and stops at Halt (also one racing its arming, answered with a Halt), explicit stop, lost or replaced transport, receive context or mode change, contact change, disarm, no answer, completion or its contact limit, never replaying a transmit action or leaving a selected unarmed contact. Details: WstxMcpEndpoint::McpCredential, OperatingAutomation, AutomationIndicator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs; server/src/authorization.rs; server/src/authorization_http.rs; server/src/contact_http.rs; server/src/profile.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_012_03_to_FR_020 from 'CL-012-03' to 'FR-020';
    dependency CL_012_03_to_FR_008 from 'CL-012-03' to 'FR-008';
    requirement 'CL-012-04' {
        doc /* The exact tool catalog, schemas and result envelope, the AutomationConfiguration (every key required, no default policy), the deterministic CandidateSelection (eligibility, first_seen / strongest_snr / lowest_frequency ranking, call-then-sequence tie) and the run states, counters, receipts and bounds are those of WstxMcp; contact progression and logging remain WstxContact's. Details: WstxMcpEndpoint::ToolCatalog, AutomationConfiguration, CandidateSelection, OperatingAutomation, AutomationWire. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/automation.rs";
    }
    dependency CL_012_04_to_FR_020 from 'CL-012-04' to 'FR-020';
    dependency CL_012_04_verified_by_TC_020_001 from 'CL-012-04' to 'TC-020-001';
    dependency CL_012_03_verified_by_TC_020_002 from 'CL-012-03' to 'TC-020-002';
    verification 'TC-020-003' {
        doc /* TC-020-003 — Operating automation
             CL-012-02, CL-012-03, CL-012-04
             Setup: actual candidate router, contact engine and #9 transmit owner on the recording hardware double with virtual UTC (bench set 1 s after an even FT8 period E), injected FT8 or FT4 live job, hand-authored codec-packed rows, the MCP test client with its MCP client token; each run start follows a browser action of the operator (#39: MCP requests never start the Tx watchdog).
             Steps: (a) pure CandidateSelection table: rows 0 CQ K1ABC 1500 Hz -12, 1 CQ W1AW 900 Hz -3, 2 CQ DL1XYZ 2100 Hz unknown SNR, 3 HB9BLA K1ABC -05, 4 CQ HB9BLA, 5 CQ W1AW 950 Hz -1, 6 CQ AA1AA 900 Hz -3, under each ranking, min_snr_db -5 and -3, allowed/blocked lists and a worked call; AutomationConfiguration bounds and every malformed key. (b) A row before start; configure strongest_snr / next_candidate / max_contacts 2 and start; publish K1ABC -12, W1AW -3, DL1XYZ unknown at E; partner "HB9BLA W1AW -05" at E+30 s, "HB9BLA W1AW RR73" at E+60 s; run the own period E+15 s to its end; publish W1AW -1 and K1ABC -12; stop; publish again; stop again. (c) A second start and a configure while running; selection, MCP Halt; retry of the original start command_id; start with the old revisions; a start over the left contact, cancel, start, browser Halt while waiting. (d) first_seen with max_unanswered_periods 2: two publications without the partner; restart; a new live job; restart; revoke the MCP client in Settings. (e) FT4: configure modes [ft4], start ft8 and ft4, publish two CQ rows. (f) max_contacts 1 with next_candidate, one completed contact; then completion_action stop, another completed contact, a later CQ. (g) A Halt injected between select_row and enable_tx. (h) max_run_minutes 1 with the step clock 59 s and 61 s ahead; max_run_minutes 480, start, a newer proof of the browser's grant, a step, stop; start, clock 8 h - 60 s and 8 h + 1 s ahead. (i) While waiting: the operator's Enable Tx (CQ), then a CQ row; the operator's manual contact W1AW, then a CQ row of W1AW; while in the run's contact: operator cancel, operator Enable Tx off, operator replacement by DL1ABC. (j) start with safety_revision 4 while 3 is current; select_row refused with the profile callsign removed; enable_tx refused after transmit became unsupported.
             Expected (hand table): (a) first_seen K1ABC, W1AW, DL1XYZ, AA1AA; strongest_snr AA1AA, W1AW, K1ABC; lowest_frequency AA1AA, W1AW, K1ABC, DL1XYZ; min -5 and -3 W1AW, AA1AA; allowed K1ABC, DL1XYZ; blocked K1ABC, DL1XYZ, AA1AA; worked K1ABC excludes it; null unconfigured, every bound admitted and each malformed value refused with its field. (b) nothing selected before start or from the earlier publication; W1AW selected (candidates 2), replying, Tx1 "W1AW HB9BLA JN47", parity odd, Rx 900, armed; roger_report, signoff with Tx5 "W1AW HB9BLA 73"; after the own period completed, disarmed, last text "W1AW HB9BLA 73", run waiting with completed_contacts 1; K1ABC then selected and armed (W1AW worked); stop 202 stopped, reason stopped, disarmed, no Halt request; no later selection; second stop stale_request. (c) state_conflict run for both; armed then Halt: stopped/halted; retry 200 with the original receipt and no new run; stale_revision expected_run_revision; later rows select nothing and leave W1AW disarmed; state_conflict contact, then a waiting run ended halted by the browser Halt with the contact still cancelled. (d) W1AW selected; no_answer after the second publication, disarmed; context_changed and disarmed after the new job; authority_lost with nothing selected; MCP then 401. (e) not_ready mode for ft8; FT4 W1AW selected, Tx4 rr73, armed. (d) also: own (odd) period publications are not counted (unanswered 0 then 1 after the first even one, no_answer after the second even one). (f) limit_reached with completed_contacts 1; completed, no later selection, disarmed. (g) stopped halted, disarmed, HaltTransmit count + 2, PTT never keyed, no later arming. (h) waiting at 59 s, time_limit at 61 s; still waiting after the browser's newer proof (another credential, #58), then stopped; waiting at 8 h - 60 s, authority_lost at 8 h + 1 s. (i) contact_changed with the operator's CQ still calling and armed and not taken over by the later row; contact_changed with the manual_entry contact kept; contact_changed after cancel; transmit_stopped without a HaltTransmit; contact_changed with DL1ABC disarmed. (j) 409 stale_revision safety_revision; provider_error with no contact; transmit_refused with the selected contact cancelled (no partner left), disarmed, PTT never used.
             2 — Isolated automated functional tests; Windows development PC, simulated FT4/FT8 traffic and real station services; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-02';
            verify 'CL-012-03';
            verify 'CL-012-04';
        }
        attribute executable : String = "server/src/automation_tests.rs";
    }
    dependency CL_012_03_verified_by_TC_020_003 from 'CL-012-03' to 'TC-020-003';
    dependency CL_012_04_verified_by_TC_020_003 from 'CL-012-04' to 'TC-020-003';
    verification 'TC-020-004' {
        doc /* TC-020-004 — Separate MCP client credential (#58)
             CL-012-03, CL-039-06
             Setup: (a) actual candidate router on a selected HTTPS profile (HB9BLA, JN47AA) with its auth-v1 owner, contact engine and #9 transmit owner on the recording hardware double with virtual UTC, one enrolled browser grant and an MCP client created by it; (b) the compiled executable on a disposable HTTPS profile with a browser-style grant; (c) the browser page in Chromium with the MCP client routes answered by the test.
             Steps: (a) create "Claude Code"; list; read authorization.json; the MCP token as session cookie and as bearer on GET /contact, GET /profile, POST /contact/command and POST /automation/command; the MCP token to POST /session, MCP client list/create and auth-v1 status; the internal MCP-principal transport to MCP client list/create/revoke and auth-v1 status; the browser cookie, the browser grant transport and the station access token on /mcp; tools/list and wstx_read contact with the MCP token; list and read mcp-audit.log; revoke; the token and its internal transport again; revoke again; create 7 more and a ninth; 10 refused bearers. Watchdog: a browser set_watchdogs 1 unanswered call; an MCP Enable Tx and its one CQ; MCP set_frequency by the tool and by the internal transport straight to POST /contact/command; set_watchdogs 99 by the internal transport; the internal transport on POST /transmit/command set_watchdogs, PUT /profile, PUT /strategy, GET /contacts and GET /ws; the MCP token as cookie on /contact/command; then Enable Tx by the internal transport and by the tool. (b) as (a) through HTTPS. (c) open Settings; create "Codex"; Done; Revoke the first client and confirm.
             Expected: token "wstx_mcp_" + 43 characters; the listing names fixture agent and Claude Code with created time and last used null, without token or digest; the record holds the SHA-256 and never the token; every browser route 401 with no effect; /session 401 without Set-Cookie; MCP client routes and status 401 for both; /mcp 401 for the cookie, 401 reason mcp_token_required with the Settings > ... MCP clients hint for both legacy bearers, 200 for the MCP token; recent newest first: "tools/call wstx_read contact" status 200 then "tools/list" by Claude Code, last used set, the same line last in mcp-audit.log with the client id and no token; revoke 200 listing one client; then /mcp 401 reason mcp_token_invalid and the internal transport 401; second revoke 409; the other client and the browser unaffected; the ninth client 429; seven 401 then 429 (budget 10/60 s). Watchdog: both set_frequency 202, set_watchdogs operator_required, the five non-tool routes 401, the MCP token 401, still spent after every MCP request, both Enable Tx refused tx_watchdog, PTT keyed and released only for the one CQ. (c) nothing read before Settings opens; list "Claude <Code> · created 2026-11-02 08:00 UTC · last used never" as text, the new token shown with "shown only once", cleared by Done; the confirmation names the client; exact requests list, create, list, revoke.
             2 — Isolated automated functional tests; Windows development PC, actual candidate router, executable and Chromium with transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-012-03';
            verify 'CL-039-06';
        }
        attribute executable : String = "server/src/mcp_tests.rs; tests/mcp.test.cjs; tests/ui-operating.test.cjs";
    }
    dependency CL_012_03_verified_by_TC_020_004 from 'CL-012-03' to 'TC-020-004';
}
