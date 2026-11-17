# Plan: web and the station link (main session, from 2026-11-17)

Decided by the operator (START-HERE "Decided on 2026-11-17"): TLS stays and the token goes;
environment mode goes; the wire is derived from the model (option A).

## Steps

1. **The station boundary list** in `StationCommands`: the port `StationOperations` names
   every command web and mcp give (`out item`) and every view and answer the station gives
   back (`in item`), each typed by the function's own item (M3.4: the one set of commands
   that web and mcp both give). The wire and the MCP catalogue are its two projections.
2. **One item per command** where a function has a catch-all: `QsoCommand` (kind
   `QsoAction`, about 25 kinds) splits into one item per command with exactly its values
   (needed by "one route per command item"). `SwitchAuto` stays (one command, one value).
   Radio control's `OperationRequest` stays (the supervisor's, not at the boundary).
3. **StationLink** rewritten: the derivation rule (read, command, event, settings and
   collection members, keys in snake_case), the envelope, the command id and its receipt,
   the error body, the refusal-to-status table, the validation order, the limits, the
   WebSocket (one socket per browser, heartbeat, subscription Detailed/Thin/Off, events),
   the exceptions (WAV import, ADIF export and import, the page files, the client build,
   the source commit header). No field of a function is copied (M4.7).
4. **Web's files**: `backend/web/Web.sysml` (the part, its ports), `Listener.sysml` (the
   listener's start with TLS, the origin, serving the client, the socket bounds, liveness,
   the link byte log), `ContentCoding.sysml` (gzip by RFC 9110, which GETs, caps before
   coding). Identities: CL-003-01..03, -05..08, CL-005-03, CL-022-02, CL-022-05, CL-033-01,
   CL-051-01 and their cases; the handed-over CL-010-14, -15, CL-044-13 and cases.
5. **Ledger, handover** (36 rows to web and the station link), `parts.json` (part `web`
   with verdicts; routes of the code differ by A: work for the code), report.

## Done (2026-11-17)

- Step 1: `StationOperations` lists the boundary; features subset `commands`, `reads`,
  `answers`, `views`. Alerts, `RankedList` and `DecodedFacts` are views.
- Step 2: `QsoCommand` split into 18 items (`CancelContact`, `HaltQso` named to avoid
  clashes); qso and supervisor texts reworded; qso verdicts updated.
- Also: `StationRequest::commandId` for every command, `ReceiptRule` at the gate (transmit's
  Halt receipts and `keptReceipts` left); the selection's `generation` left (receive has
  none, operator 2026-11-15).
- Step 3: `StationLink.sysml` rewritten (WireNames, JsonValues, WireRule, WireRefusal,
  ErrorBody, StatusRule, RequestOrder, Limits, Transfers, SocketProtocol, DisplayRows,
  ThinLinkBudget). #174 decided by rule: the error body names the field.

## Notes for the build

- The authorization goes (#226): CL-022-02, the `/authorization/*` routes, the grants, the
  MCP-client routes of the browser (MCP's credential is #226 question 1, for the mcp part).
- Content coding stays by rule: it serves the 32 kbit/s target of #80.
- `station.status` carries `radio: "unconfigured"`, a constant: no job (M5.8), it goes.
