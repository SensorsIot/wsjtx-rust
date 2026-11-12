package WstxRequirementsMcp {
    private import ScalarValues::*;
    private import WstxRequirements::*;

    // #12 MCP access and configured FT4/FT8 automation (decisions recorded in WstxMcp
    // and on issue #12, 2026-11-01); detailed contract in WstxMcp.
    requirement 'CL-012-01' {
        doc /* Serve MCP on the station's own listener at POST /mcp (Streamable HTTP, MCP 2026-07-28 and legacy 2025-11-25/2025-06-18, stateless, JSON responses only) and map every tool onto exactly one existing versioned station operation dispatched in-process through the station router: no second station state, modem, QSO engine, transmit-authority path, raw CAT/PTT/audio tool or MCP-owned retry. Details: WstxMcp::McpEndpoint, ProtocolEras, ToolCatalog, ToolResult. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/mcp.rs; server/src/main.rs";
    }
    dependency CL_012_01_to_FR_020 from 'CL-012-01' to 'FR-020';
    dependency CL_012_01_to_FR_021 from 'CL-012-01' to 'FR-021';
    requirement 'CL-012-02' {
        doc /* An MCP client observes exactly the browser's station views (profile, receive, selection, radio, transmit, contact, automation, strategy, the #42 alert history and decoded result pages, and the strategy verdicts of POST /strategy/evaluate, read-only) and operates through the same ContactCommand, HaltTransmit and AutomationCommand bodies, receipts, revisions, command_id idempotency and refusal codes as the browser, for FT8 and FT4. Details: WstxMcp::ToolCatalog, ToolResult. */
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
}
