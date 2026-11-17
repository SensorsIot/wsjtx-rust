# Report: web and the station link

Built 2026-11-17 by the main session. `part_done.py web`: tests 1 to 5 pass (30 identities,
5 files, 47 verdicts, 11 test cases). Every other part passes; `top` test 3 has 10 errors,
all from mcp and the browser client, which are not built.

## Decided by the operator

1. **TLS stays, the token goes** (#226 question 2). A listener beyond loopback needs TLS,
   because the browser offers notifications, the clipboard and `crypto.subtle` only in a
   secure context. `WSTX_TOKEN`, `POST /session`, the session cookie and the login rate go.
2. **Environment mode goes.** Every station starts with its profile; `WSTX_BIND` and
   `WSTX_ORIGIN` go; the tests start a disposable profile.
3. **The wire is derived from the model** (option A, after an investigation of who uses
   the wire, how today's routes fit the rebuilt parts and what changes anyway). Route names
   follow the parts (`/qso`, not `/contact`).
4. **Each station has its own profile** (wording of M5.1 and `Shack`).

## Decided by rule

| Question | Rule | Result |
|---|---|---|
| Which features cross the station boundary | M3.4: StationCommands is the one set of commands web and mcp give | `StationOperations` lists every command, read, answer and view, typed by the function's item; four abstract features mark the kind |
| `QsoCommand` with a kind and optional values | option A: one route per command item | 18 items in `QsoControl` (`CancelContact`, `HaltQso` named so as not to clash with `ModeProcessing::Cancel` and `TransmitControl::Abort`); texts of qso and the supervisor name them |
| A command sent again | #53 (MCP and browser carry the same messages) | `StationRequest::commandId` on every command; `ReceiptRule` at the gate; transmit's own Halt receipts (`keptReceipts`) left |
| The selection's `generation` | contradiction: receive has none (operator 2026-11-15) | left from `SelectionRequest`, `SelectionState`, `SelectionRule` |
| How the supervisor starts web's listener | M4.6, M5.8: every connection typed by an interface; the handover row said no item carries it | `WebControl` (`WebContext`, `Listen`, `Listening`, `ListenRefused`); M2.1 names it |
| The upload of a recording through its own port | M1.4: `recordingChunk` already crosses the boundary | the web-to-supervisor upload port and its connection left |
| The station time on the screen | M5.4: a stream goes from producer to consumer | `timeWeb` from the clock to web; the event `clock.time` once a second |
| The error body's `field` (#174) | M5.8 and the answers' `field` attributes | `ErrorBody` names the field, or null; the same for MCP |
| The authorization's files in the profile's folder (#226 question 3) | nothing reads them | left untouched; no function names them |
| Content coding | it serves the 32 kbit/s target (#80) | `CodingRule`: gzip on every GET of a view, a read or a client file when the request selects it, identity otherwise (no 406); the caps before coding and the 49 vectors are code and test values |
| The sizes of the views, the pace of each event, the socket count, the stale-pong time | method: a limit is code unless something outside waits on it | not written; `BoundsRule` says they are bounded; `eventDelayMs` (the operator sees a change within it) and `heartbeatMs` (the browser's silence watch) stay |
| `station.status` `radio: "unconfigured"` | M5.8: no item without a job | left; `station.status` carries version and build |
| The link byte log's clients | the grants go | browser or mcp and the remote address |
| TC-092-004 | the rule on negatives | not carried |

## Where the identities stand

| Identity | Where |
|---|---|
| CL-003-01, -02, -03, -05, -06, -07, -08, CL-033-01, CL-051-01 | `Listener.sysml`; -07 partial (the token), -02, -03, -05, -08 partial (the derived wire) |
| CL-003-09 (new) | `ContentCoding.sysml`, partial |
| TC-021-005, -008, TC-033-001, TC-051-001, TC-080-001 | `Listener.sysml` |
| TC-007-005, TC-082-003, TC-092-009, TC-111-007, TC-010-002, TC-010-005 | `Listener.sysml` (handed over by qso, receive, transmit, clock) |
| CL-010-15, CL-044-13 | retired: merged into CL-003-08 |
| CL-005-03, CL-022-02, TC-022-004, TC-022-008 | retired: the sessions and the authorization go |
| CL-022-05, TC-021-006, TC-051-003, CL-010-14, TC-010-009, TC-043-003, TC-022-005 | handed over to the frontend |
| TC-021-009, TC-092-004 | not carried |

## The tests read and not bound

| Test | Why not bound |
|---|---|
| `communication.test.cjs` TC-021-009 | asserts the token login, which goes |
| `profiles.test.cjs` TC-022-004, TC-022-008 | the cookies and the authorization's status route |
| `http_compression_tests.rs`, `radio-selection.test.cjs` H1 | the six-route allowlist, the caps and 406, which `CodingRule` replaces |

## Changes outside web's files

- `StationCommands`: the boundary list; `StationRequest::commandId`; the selection's own
  `commandId` and `generation` left. `QsoControl`: one item per command. `TransmitControl`:
  `Halt::commandId` left. `TransmitState`: the receipts left. `StationAuthority`:
  `ReceiptRule`, `AutoOnRule` and `SwrBarrier` name qso's items. `Startup`: the line WSTX
  profile, `Listen`, `ProcessEnds` to web. `Supervisor`: port `web`, the upload port left.
  `Shack`: `webControl`, `timeWeb`, the upload connection left.
- `parts.json`: part `web`; verdicts of qso (the 18 items), transmit (`HALT_RECEIPTS`),
  supervisor (`WSTX_BIND`, `WSTX_ORIGIN`). M2.1 names `WebControl`; `files.md`.
- `handover.md`: 36 rows taken up; new rows for the frontend and mcp.

## Work for the code

1. The routes, bodies and events of the derived wire (`WireRule`, `SocketProtocol`), with
   the client, MCP's dispatch and the tests; `station.tick` becomes `clock.time`.
2. The token, `/session`, the cookie, the login rate and `/authorization/*` go; a test of
   TLS and the origin replaces TC-021-009's.
3. Environment mode goes; the tests start a disposable profile.
4. One receipt store at the gate for every command; transmit's goes.
5. Content coding by `CodingRule`.
6. The routes that go: `/transmit/command`, `/radio/tx-level`, `/radio/settings/undo`,
   `/radio/connect`, `/radio/disconnect`, `/radio/operation`, `POST /receive/startup`,
   `/audio/devices`, the whole-list `PUT /strategy` and `PUT /udp`, `/automation/command`.
7. `station.status` without `radio`.

## Size

Old text: 2,089 lines, 154,245 bytes (`web/StationProtocol`, `ContentCoding`, `Web`, the old
`StationLink`). New: 642 lines, 34,200 bytes in `Web`, `Listener`, `ContentCoding`,
`StationLink` and `WebControl`, plus about 150 lines of the boundary list in
`StationCommands`. The authorization, the per-route field lists and the negotiation vectors
were most of the old text.

## For the operator

1. **Two naming conventions in the model.** Decided 2026-11-17 (option A): every model name
   is camelCase (M7.5, checked by check.py); `WireNames` gives the snake_case names of the
   wire and the station's files, with three named exceptions for numbers.
2. **#174 and #226 question 3** are decided by rule in the model; the issues on GitHub are
   not updated (nothing posted).
3. **MCP's credential** (#226 question 1) and **Origin on POST /mcp** (#175) come with mcp,
   the next part.
