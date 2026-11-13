package WstxMcpInterface {
    private import ScalarValues::*;

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
    attribute def McpCredential {
        attribute tokenPrefix : String = "wstx_mcp_";
        attribute refusedAttemptsPerMinute : Integer = 10;
        attribute auditFile : String = "mcp-audit.log";
        attribute auditRecentShown : Integer = 32;
        doc /* (#58) Exactly one Authorization field "Bearer " plus an MCP client token of
             this station (WstxStationLink::McpClientCredential): "wstx_mcp_" and 43 base64url
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
             WstxRankingControl::Alert, read-only; clearing stays in the browser). wstx_results {source_id, job_id: UUID; generation, cursor: safe
             integer; limit optional 1..16} -> GET /receive/results. wstx_contact_command
             {command: WstxQsoControl::ContactCommand} -> POST /contact/command; its description
             states that open_log (WstxLogbook::DirectLog) closes an unfinished contact
             (completed, Enable Tx off, nothing queued, #37).
             wstx_transmit_halt {halt: HaltTransmit body} -> POST /transmit/halt.
             wstx_automation_command {command: AutomationCommand} -> POST
             /automation/command; its description names every AutomationConfiguration
             wire key (max_run_minutes, strategy and pounce included).
             wstx_strategy_evaluate {request: the StrategyEvaluate body of
             WstxStrategies::StrategyHttp} -> POST /strategy/evaluate (readOnlyHint; it never
             changes station state; the browser's refusals, e.g. 409 not_configured
             strategy, are its tool errors). Missing, extra or mistyped arguments, an unknown view or a
             non-UUID id are a tool error {status 400, error invalid_request with the field}
             without a station call. */
    }
}
