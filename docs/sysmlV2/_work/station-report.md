# Report: the station service

Built 2026-11-17 by the main session. `part_done.py station`: tests 1 to 5 pass (20
identities in the ledger, 5 files, 17 names matched by the tool, 71 with a verdict, 6 test
cases).

## Decided by the operator

1. **Monitor off goes** (2026-11-17): "We do not create shortcuts. Monitor off can go. We do
   not need it." The station always takes up the last receive at start, as WSJT-X does by
   default (`MonitorOFF` false). `settings.csv` row 28: gone. The browser's checkbox and the
   `POST /receive/startup` route go (handover rows to the frontend and the station link).
2. **Where the station service's own data stands** (asked 2026-11-17; the answer was the
   point above and "We do not create shortcuts"): done as recommended. `StationCommands` is
   the station service's control interface, the one set of commands that web and mcp both
   give, with the station's own state and records; M3.4 names StationLink and Mcp as the
   transport files. `ProfileAccess` collects `StartupRecords` from it in
   `StationMemory::station`. Line 1 below asks the operator to confirm this reading.

## Decided by rule

| Question | Rule | Result |
|---|---|---|
| Which FR the station's clauses derive from | M6.2 (one FR per part); FR-021 says "with the station holding the authoritative state", which M5.1 and M5.3 give the station service | `Station.sysml`: `satisfy 'FR-021' by station`; all fourteen clauses derive from FR-021 |
| The frequencies of the bands | method step 2: a value of another source is not written | `BandFrequency` names WSJT-X's default frequency list; the twelve bands stay (`OperatingBand`), they are what the station offers |
| The wait for radio control (3 s) and the resume's wait (20 s) | method: a limit of time is code unless something outside waits on the number | not written; `LeaseRule` and `ResumeRule` say the waits are bounded |
| CL-045-03 "never arms, keys or tunes" | the rule on negatives | in the positive: `ResumeAtRest` (the resume gives commands to receive and radio control only) |
| The remembered receive | settings decision (rows 27, 28 of `settings.csv`) | a record of the hidden store (`StartupRecords::lastReceive`); `receive-startup.json` goes |
| `StartupOutcome` | handover row of the profile (operator 2026-11-15) | moved to `Startup.sysml` with `LaunchRule`; the profile answers `OpenRequest` and `CreateRequest` with `OpenRefused` (`OpenRefusal`, six reasons, `invalid_runtime_configuration` for a native intent outside its rules, as the code) |
| The profile's own `wrong_profile` on a save | M1.4, M5.3: the gate refuses another profile before a command reaches a function | `SaveProfile::profileId` and `SaveRefusal::wrong_profile` left `ProfileAccess`; `SaveSettings` lost its two lines; `GateRule` says "a function checks nothing of this again" |
| The station's band, written in five interfaces | M1.4 | stated once in `StationBandRule` (CL-008-11); `Hearing`, `RankingControl`, `QsoControl`, `AutoControl`, `TransmitControl` refer to it |
| `StationMode` "absent until the station has one" | contradiction with the code (FT8 from the start) | `StationMode::mode` always present, `OperatingModeRule` |
| The `auto_on` refusal of issue 119 (CL-119-06's list) | it is a refusal of the gate; no model text held it | `AutoOnRule`, CL-119-09 (target), on today's commands; Log QSO resends now and touches no contact, so it is not refused |
| Process end toward udp | handover row of udp; the item was missing | `ProcessEnds` on `UdpControlPort` (imported from `TransmitControl`), `LaunchRule` |
| `SelectionStateEvent`, the snapshot of `GET /receive/selection` | M4.7: wire views belong to the transport file | handover to the station link; `StationCommands` holds `SelectionState` only |
| `AuthStatusRequest` | the authorization goes (#226) | dropped |
| The hold of a transmission refusing a reservation at once (`a_transmit_hold_refuses_the_lease_at_once`) | the test shows radio control's `ControlExchange` | bound to TC-009-001 (radio control) |
| JavaScript tests named by title | START-HERE trap: extend the tool when a part needs it | `part_done.py` test 5 reads `test('title'` for `.cjs` and `.js` |

## Where the identities stand

| Identity | File | Note |
|---|---|---|
| CL-008-07 | OperatingSelection | `SelectionRule`, implemented |
| CL-008-10 (new) | OperatingSelection | `CancelRule`, implemented |
| CL-044-16 | OperatingSelection | `LeaseRule`, implemented |
| CL-011-02 | OperatingSelection | `OperatingModeRule`, implemented (from qso) |
| CL-008-11 (new) | OperatingSelection | `StationBandRule`, implemented (`strategy::station_band`); no test |
| CL-008-12 (new) | OperatingSelection | `ReadbackRule`, implemented |
| TC-009-005 | OperatingSelection | selection and cancel, 7 tests of `recording_tests.rs`; its other clauses are web's, radio control's and the frontend's |
| TC-044-023 | OperatingSelection | 2 tests of `radio_level_tests.rs` |
| TC-011-004 (new) | OperatingSelection | 3 tests of `contact_http_tests.rs` |
| TC-009-008 (new) | OperatingSelection | 2 tests of `cat_lifecycle_tests.rs` |
| CL-006-07 (new) | StationAuthority | `GateRule`, implemented (each route checks itself) |
| CL-119-09 (new) | StationAuthority | `AutoOnRule`, target |
| CL-044-17 (new) | StationAuthority | `SwrBarrier`, partial |
| CL-005-08 (new) | StationAuthority | `ContextRule`, partial (the code's functions read the profile themselves) |
| TC-006-004 (new) | StationAuthority | 2 tests |
| CL-005-09 (new) | Startup | `LaunchRule`, `StartupOutcome`, partial (the code takes no `--operator`; the operator's folder is CL-005-07's, partial) |
| CL-045-01 | Startup | `ResumeRecord`, partial (kept in `receive-startup.json`, not in the hidden store) |
| CL-045-02 | Startup | `ResumeRule`, implemented |
| CL-045-03 | Startup | `ResumeAtRest`, implemented |
| TC-045-001 | Startup | 4 tests of `receive_startup_tests.rs` and the native resume of `native-flex.test.cjs` |
| TC-045-002 | not carried | planned, live on the radio, no test |

## The tests read and not bound

| Test | Why not bound |
|---|---|
| `receive_startup_tests.rs::startup_choice_round_trips_and_stop_clears` | asserts the whole content of `receive-startup.json` (schema, profile id, Monitor off) |
| `receive_startup_tests.rs::startup_file_invalid_or_foreign_is_ignored` | the file and its refusal `invalid_startup` go; an unreadable hidden store is the profile's |
| `receive_startup_tests.rs::startup_http_view_and_monitor_off_update` | the `POST` of Monitor off and the file go |
| `receive_startup_tests.rs::startup_resume_off_or_stopped_stays_off` | asserts the state `off` of Monitor off |
| `recording_tests.rs::canonical_preferred_table_*`, `selection_preferred_entries_match_*` | read the old model's table (handover row to the tools) |
| `contact_http_tests.rs` (the command identity table) | asserts `set_watchdogs` with `tune_seconds`, which left qso's commands |
| `radio_level_tests.rs::a_clear_swr_fault_stops_transmitting_and_keeps_automation_off` | asserts `watchdog_spent` (`operator_seen`), the mechanism the model removes; bound to transmit's TC-044-017 for the halt |

## Changes outside the station's files

- `ProfileAccess`: `OpenRequest`, `CreateRequest`, `ProfileCreated`, `OpenRefusal`,
  `OpenRefused` and their port items; `StationMemory::station`; `SaveProfile::profileId` and
  `SaveRefusal::wrong_profile` gone. `ProfileDocument`: `StartupOutcome` gone, the open and
  the creation answer the requests, `memory.json` has the key `station`.
- `UdpControl`: `ProcessEnds`. `TransmitControl`: `StationMode`, `StationBand` refer to the
  station's rules. `Hearing`, `RankingControl`, `QsoControl`, `AutoControl`: the band refers
  to `StationBandRule`.
- `CatControl`: TC-009-001 gains the test of the transmit hold.
- `Station.sysml`: `satisfy 'FR-021' by station`, `targetHearingStation`.
- `Foundation/1-Finished-Model.md`: M3.4.
- `parts.json`: the part `station`; every part that validates with `ProfileAccess` or
  `UdpControl` also loads `StationCommands` and its imports; `top` loads the station files.
  Test 3 of `top`: 21 errors, all from web, mcp and the browser client (41 before).

## Work for the code

1. One gate: each route checks profile and boot itself today (`GateRule`).
2. The SWR barrier with the code `swr_fault` and an operator's command as its end, in the
   station service, in place of `operator_seen` and `tx_watchdog` (`SwrBarrier`).
3. The refusal `auto_on` while Auto is on (`AutoOnRule`, issue 119).
4. The functions take their configuration and context from the station service instead of
   reading the profile (`ContextRule`).
5. The remembered receive in `memory.json` (`station`); `receive-startup.json`, its route
   `POST /receive/startup` and Monitor off go.
6. The pairing of a detection with the endpoints at the radio's place moves from
   `radio_setup.rs` to the station service; the requester (operator or agent) travels with
   each command.
7. The two tests that read the old preferred table (handover row to the tools).

## Size

Old text: 923 lines, 67,375 bytes (`station/Station`, `StationAuthority`,
`OperatingSelection`, `receive/Startup`, `StationCommands`). New: 957 lines, 49,788 bytes in
five files. The bytes fell by a quarter (the 12.8.1 wire text went to the station link, the
preferred table to the source); the lines grew by 34 for what the old text did not hold: the
gate, the SWR barrier, `auto_on`, the contexts, the launch with its outcomes and the
detection's answer.

## For the operator

1. **`StationCommands` as the station service's control interface** (done as recommended,
   after your answer "We do not create shortcuts"). Please confirm, or say otherwise.
2. A start without arguments (environment mode) still runs in the code; `LaunchRule`
   refuses it as the profile's rules already did. Whether it stays is to be asked when web
   is built (handover row "web, station").
3. `OperatingBand` has the twelve bands of the code (160 m to 4 m). A rig of Hamlib's list
   with 2 m or 70 cm gets no band there; widening it waits for such a rig.
