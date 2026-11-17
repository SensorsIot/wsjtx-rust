# Report: the frontend

Built 2026-11-17 by the main session. `part_done.py frontend`: tests 1 to 5 pass (130
identities, 8 files, 58 verdicts, 60 test cases). Every part passes, `top` included; the
whole tree validates with no error and `check.py` has no finding. The ledger is complete:
612 identities, 495 arrived, 63 not carried, 54 retired, none handed over or waiting. Plan
and progress: `_work/frontend-plan.md`.

## Decided by the operator

1. **The frontend states what the operator relies on** (option A): regions and their views,
   controls and their commands, the states the operator tells apart, labels and messages,
   the meaning of the colours, the keys, the differences from WSJT-X; WSJT-X's colour values
   by reference; pixel sizes, fonts and the look of a control are the client's.
2. **An app without browser elements** (#103, #118 Q6 and Q7, #149): the page in its own
   window, installed from web's manifest or opened by a shortcut; on a single PC the station
   opens it (`--app-window`); the full-screen button goes.
3. **The FRs stay in `Requirements.sysml`**, imported where a clause derives from them; the
   numbers stay the names.
4. **Use cases after the frontend**: the list goes to the operator first.

## Decided by rule

| Question | Rule | Result |
|---|---|---|
| Which of two overlapping clauses stays | M1.4 (no duplication) | CL-010-05 into CL-010-16, CL-022-05 into CL-010-07, CL-007-02 into CL-010-09, CL-010-06 into CL-037-04, CL-042-05 into CL-097-12 |
| Clauses that had no home | M6.2: every promise of a part is a clause | CL-006-08 (the display half of CL-006-03), CL-103-01 (the app window), CL-017-01 (FR-017 had no clause), CL-039-31 (Auto and PSK on the screen), CL-037-06 (the pane's buttons), CL-097-12 (the editor's screen), CL-227-01 (the settings drawer) |
| The retry of CQ on a stale contact revision (CL-061-02) | the commands carry no revision | retired with TC-061-003 |
| The authorization's screens, the token form, the full-screen button | #226, #103 | CL-022-01, CL-096-01 and their cases retired |
| Auto's and PSK's toggles | the client has them among the QSO pane's buttons | in `QsoPane`, Auto's line beside the strategy selector |
| PSK Reporter's switches | the two levels (operator 2026-11-16): `ShackSettings::spots` | saved with the shack's settings |
| The display choices | M5.2: the browser is the origin of its presentation preferences | `FrontendConfig` in the part file, kept in the browser for the station's origin |
| Row counts of tests (8 and 6 rows visible) | a test's value stays in its test case | not in the model |
| The Pounce menu item and line | the MCP run goes (#122) | not in the model |
| `shared/Quantities.sysml` | nothing asks for it | left from M2.1 and `files.md` |
| M5.2 "its identity key" | the authorization goes (#226) | the browser is the origin of its presentation preferences only |

## Where the identities stand

In the files: `OperatingScreen` 15 clauses and cases' clauses (the screen, the app window, HALT,
keys, time, link, new start, new client, data not read, health, Tx state, help, Logbook);
`SignalArea` 8; `BandActivityPane` 13; `QsoPane` 7; `LowerPanel` 2; `Settings` 7. Not carried:
planned live cases without a test (TC-051-003, TC-054-003, TC-057-003, TC-061-002, -009,
TC-068-002, TC-073-003, TC-074-004, TC-111-005, -014), and tests that assert what goes
(TC-021-006, TC-022-005, TC-039-046, TC-042-003, TC-044-015, TC-063-012, TC-065-003,
TC-074-002, TC-097-014, TC-125-002).

## Changes outside the frontend's files

- `Listener`: web serves the web app manifest. `Startup`: `--app-window`.
- `Foundation/1-Finished-Model.md`: M5.2; M2.1 without `Quantities`.
- `parts.json`: part `frontend`; `top` loads `BrowserClient`. `settings.csv`: the shack's rows
  and the homes of qso's and the frontend's values corrected.
- `handover.md`: 30 rows taken up.

## Work for the code

1. The app window: the manifest, `--app-window`, the full-screen button goes.
2. The derived wire in the client (routes, events, `clock.time`, the error body's field).
3. The help with version, license, notice and sources (CL-017-01).
4. The Tx state line (CL-111-04); the Now button goes (CL-111-09); the one ignore list on the
   screen (CL-042-06).
5. Settings in the sections of the operator's sorting, the two levels, one member at a time,
   no revision for the station's own values, the PSK switches of the shack.
6. Auto's line from the view auto (no MCP run); no Pounce; Log QSO resends.

## Size

Old text: 3,490 lines, 329,022 bytes (`frontend/*`). New: 1,939 lines, 105,263 bytes in seven
files and `OperatorInteraction`. Left out: pixel geometry, the palette's RGB anchors, the
canvas algorithms, the authorization's screens, the browser's state machines for the old
wire and the copies of other parts' rules.

## For the operator

1. The comparison with the WSJT-X UI (asked 2026-11-17) comes next.
2. Then the list of use cases.
