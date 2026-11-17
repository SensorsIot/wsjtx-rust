# Report: mcp

Built 2026-11-17 by the main session. `part_done.py mcp`: tests 1 to 5 pass (8 identities,
3 files, 1 test case). Every other part passes; the whole tree has 5 validator errors, all
from the browser client.

## Decided by the operator

1. **MCP's token goes** (#226 question 1): the browser's routes need no token and MCP's
   tools reach the same routes, so a token keeps nothing out. The client tokens, their
   Settings screen, their record and their revoke go.
2. **MCP's tools by function** (option B): `wstx_read` for every view and read, one command
   tool per function; the argument `command` names the feature.
3. **One agent for the whole shack, one MCP server per station** (option A): each station
   names itself to the agent by its `display_name` and profile id.
4. **MCP and the UI behave the same**: no audit of MCP's requests; `mcp-audit.log` goes.

## Decided by rule

| Question | Rule | Result |
|---|---|---|
| Origin on `POST /mcp` (#175) | the MCP specification's security warning: a server checks a present Origin | a present Origin must be the station's, an absent one passes |
| What an agent may do (handover rows of ranking and operating) | M5.10: an agent has the operator's rights | every feature of the boundary, also clearing alerts, the Most Wanted update, the strategies |
| The JSON-RPC codes, headers and the eras' details | method step 2: values of a source are not written | `McpEndpoint` and `ProtocolVersions` name the source; the supported versions stay (a choice of the station) |
| The answer size cap (65,536) | a limit is code | not written |
| The MCP policy run (`AutomationConfiguration`, `CandidateSelection`) | issue 122: Auto replaces it | CL-012-04, TC-020-003 retired |
| Protocol versions written as dates | they are a source's names, not history | `check.py` M7.4 skips the quoted value of an attribute or a source reference |

## Where the identities stand

| Identity | Where |
|---|---|
| CL-012-01, CL-012-02, TC-020-001 | `backend/mcp/McpEndpoint.sysml`; CL-012-02 partial (the tools of the code are today's six) |
| CL-012-03, TC-020-004 | retired: the token, principal and audit go |
| CL-012-04, TC-020-003 | retired: the MCP policy run goes (#122) |
| TC-020-002 | not carried: its test asserts the token refusals |

## Work for the code

1. The tools by `ToolRule`: `wstx_read` and one command tool per function, exact schemas per
   command, the station's name in the server's title and instructions.
2. The token, its routes (`/authorization/v1/mcp-clients/*`), the principal guard and the
   audit go; a test of the endpoint's checks replaces TC-020-002's.
3. The MCP policy run (`automation.rs`) goes with issue 122.

## Size

Old text: 243 lines (`interfaces/external/Mcp.sysml` 94, `backend/mcp/McpEndpoint.sysml`
139, `backend/mcp/Mcp.sysml` 10). New: 144 lines in three files.
