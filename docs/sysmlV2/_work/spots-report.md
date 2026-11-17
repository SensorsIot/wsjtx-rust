# Report: the spots part

2026-11-15. Built by a subagent beside the receive part. Tests 1 to 5 pass. Three lines
wait for the operator (last section but one).

## What was written

| File | Content |
|---|---|
| `backend/spots/Spots.sysml` | the part with two ports, its module, one marker |
| `backend/spots/HearingFeed.sysml` | 2 clauses, 3 rule and data elements, 2 enumerations, 2 test cases |
| `interfaces/internal/Hearing.sysml` | the hearing report: 1 item, 3 data elements, 1 enumeration |
| `interfaces/external/PskReporter.sysml` | the spot, the subscription, the errors, 1 clause, 1 rule element, 1 test case |

## Where the identities were

The ledger had no identity under `backend/spots/`: the old `HearingFeed.sysml` held two
attribute definitions and no clause. The clause and its test cases stood in the old
`backend/operating/qso/QsoData.sysml`, in the ledger as "TO PLACE". They are spots' by
their element (`HearingFeed`) and their code (`pskr.rs`).

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-039-20 | qso/QsoData | HearingFeed | Keeps its core: who hears the station and what the target decodes. Derives from FR-012 only (was FR-007, FR-012). |
| **CL-039-26** | new | HearingFeed | The two switches and the status of the feed, from CL-039-20 and the old `PskrUse`. |
| **CL-039-27** | new | PskReporter | The session with the broker, from CL-039-20. A clause about the exchange stands in the interface file (M6.3). |
| TC-039-020 | qso/QsoData | HearingFeed | Keeps the hearing rules and the first switch; rewritten from its tests. Verifies CL-039-20 and CL-039-26. |
| **TC-039-052** | new | PskReporter | The session conditions of TC-039-020, bound to twelve named tests. |
| TC-039-048 | qso/QsoData | HearingFeed | Keeps its five tests in `pskr_tests.rs`. Verified CL-039-20, CL-039-23 and CL-039-09; verifies CL-039-20 and CL-039-26 now. Its run test in `strategy_tests.rs` is auto's (handed over). |

The three new numbers are the next free ones of their series (CL-039-25 and TC-039-051
were the highest in the old model, the code and the tests; measured by a search).
TC-039-021 (the Settings view) stays "TO PLACE": it is the frontend's.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| CL-039-20 and its cases are spots' | A model file follows the thing; qso's old file holds clauses of many parts | Taken from "TO PLACE" into spots. |
| One old clause became three | M6.4: divided where shown by different tests and changed for different reasons; M6.3: a clause about an exchange stands in the interface file | Hearing (CL-039-20), switches and status (CL-039-26), session (CL-039-27). |
| The numbers of the new identities | Method, "Decided": the next free number of the series | CL-039-26, CL-039-27, TC-039-052. |
| The clauses derive from FR-012 only | A clause derives from the one FR its part serves; `Station.sysml` gives FR-012 to spots | FR-007 dropped as second FR. See line 2 for the operator. |
| The MQTT layouts and the payload of a spot | A followed format is referred to, not copied | The sources are named on `PskReporter` and on `Spot`. The model states which fields the station reads and what it sends. |
| `Spot` has seven typed fields | A field gets a feature only when something in the model names it | The seven that `HearingFeed` uses; the others are the source's. |
| The items had no feature | Structure rule 1 | `HearingReport`, `TargetHearing`, `DecodedOffsets`, `Spot`, `Subscription` typed from the code. |
| Which values stay | The model/code line; values sorted by kind | See the next table. |
| "Never an error for the operator", "never a wildcard", "never the raw feeds" | Negatives with care | See "Negative statements". |
| Routes, the event and the screen texts | M4.7; a part stops at its boundary | Handed over. |

## The values

| Value | Kept as | Why |
|---|---|---|
| 600 s | `HearingFeed::heardWindowSeconds` | ranking, auto and the operator rely on it |
| 32 offsets | the bound of `DecodedOffsets::offsets` | what crosses to auto and qso |
| keep-alive 60 s | `FeedSession::keepAliveSeconds` | the product's choice in the greeting |
| 5 s, 300 s, 60 s | `firstRetrySeconds`, `maxRetrySeconds`, `stableSessionSeconds` | a third party (the broker) is protected by them |
| 4096 bytes | `maxPacketBytes` | how the station tolerates an oversize packet |
| 16 characters | `maxFieldLength` | which payload is a spot, which call forms a filter |
| 256 receivers, 128 spots of the target | dropped | bounds of the memory; nobody outside notices another bound |
| ping after 45 s | dropped | tuning; the rule stays: before the silence reaches the keep-alive |
| silence 90 s | dropped as a value | written as one and a half times the keep-alive |
| 10 s for the greeting, 250 ms poll | dropped | tuning |
| 30 s between pushed spot times | handed over | the pace of the event `pskr.state` (station link); the code keeps it in the feed |
| 23 characters, 4 of the boot identity, port 1884 | sentences | part of the identifier and of the address; no element names them |

## Dropped as code or as history

- The thread of the feed and its lock; "the station reads a short-held lock".
- The packet identifiers, the read buffer, the byte layout of the packets.
- That fields are folded to capitals and the band to small letters.
- The broker's page, its provider, "no formal terms", the date the chain was checked.
- Why 600 s (the upload delay of reporters).
- The dates, issue numbers and question numbers.
- The dependency links of the old text; `subject` and typed features carry them.

## Renamed or moved

| Old | New | Cited by (measured) |
|---|---|---|
| `WstxHearingFeed::HearingFeed` (one element for everything) | `HearingFeed` keeps the hearing rules; the session is `WstxPskReporter::FeedSession` | 8 citations in 5 code files; they stay valid |
| `WstxHearingFeed::PskrUse` | `FeedSwitches::use` | 13 citations of the qualified name in 4 files, 17 of `PskrUse` in 6 |
| item `HeardSpots` | `Spot` (the code's name) and `Subscription` | none |
| `HearingReport` without features | typed | `ValueOrder.sysml` and `AutoControl.sysml` (taken over) name `HearingFeed` and `PskrUse` in text |

## Negative statements

| Old statement | Result |
|---|---|
| Read-only; sends nothing but handshake, pings, subscriptions | positive: the list of what the station sends, "and nothing else"; a function exists that sends (TC-039-052 f) |
| Never a wildcard from a decoded call | positive: which call forms a filter; every other gets none (TC-039-052 a, f) |
| Exactly two filters, never the raw feeds | positive: the two filters are stated |
| No connection is unknown, never an error for the operator | positive: `HearingState::unknown` and the default "unknown where the feed cannot tell" |
| Receive and the station step never wait on it | positive: "a report is given at once"; no test, written as planned (TC-039-020 i) |
| Nothing else can replace the broker | positive: `WSTX_PSKR` with a loopback address, every other value no connection (TC-039-052 j) |
| No polling (of the browser) | handed over to the station link |

## Settled from the code

- **Status.** The old clause was `implemented`; it stays.
- **The target.** Only the own contact of a strategy or contest run, while it is active.
  The station step tells spots; the model has no connection for it (marker).
- **"No" needs a subscription.** The state is no only while the target's call forms a
  filter; a call with a slash stays unknown.
- **A session attempt counts as stable** from the start of the connection, not from the
  greeting's answer.
- **State off before the first attempt**, also with the switch on, while the profile has
  no call.
- **A file that cannot be opened** gives `storageUnavailable`, an unreadable content
  `invalidPskr`.
- **`heardBy` carries calls only**; time and SNR are given for the target.

## What the comparison with the code found

| Finding | Result |
|---|---|
| `pskr.rs` has no public constant and no public enumeration | 7 values and 14 literals matched by reading, each with a verdict; 4 literals of `FeedState` matched by the tool |
| The feed's code stands in `server/src/operating/qso/` | work for the code |
| `pskr.rs` holds the routes `GET /pskr`, `POST /pskr`, `POST /pskr/use` | the station link's; work for the code |
| The helpers `target_hearing`, `target_reports`, `heard_calls`, `target_offsets` read the station's band, mode and dial inside the feed's module | in the model one report for the station's band and mode; how spots learns them is the marker |

## Edge cases and their homes

| Case | Home |
|---|---|
| spot older than 600 s on arrival; time ahead of the station's | `HearingFeed`, TC-039-020 (c) |
| the border 600 s and 601 s | TC-039-020 (b), (d) |
| payload that is no spot; field of 17 characters | `Spot`, TC-039-020 (a) |
| rp outside -99 to 99 or no number | `Spot::reportedSnrDb`, TC-039-048 (a) |
| spot on a topic of another sender or receiver | `HearingFeed`, TC-039-020 (g) |
| more than 32 offsets | `DecodedOffsets`, TC-039-020 (f) |
| a call with a slash, a wildcard, small letters | `FeedSession`, TC-039-052 (a), (f); TC-039-048 (d) |
| no band, no confirmed dial | `TargetHearing::decoded`, TC-039-048 (e) |
| broker refuses, drops, sends a wrong or oversize packet | `FeedError`, TC-039-052 (d), (g), (i) |
| switch off and on within one look | TC-039-052 (h) |
| file missing, of another profile, not understood, of the earlier form | `FeedSwitches`, TC-039-020 (h), TC-039-048 (c) |
| the save fails | `FeedSwitches`; no test |
| more than 256 receivers | rare and harmless: code |
| the certificate under another root | `FeedError::tlsFailed`, TC-039-052 (k), (l) |

## Not carried over

| What | Why |
|---|---|
| TC-039-020 "GET and POST /pskr with and without a feed, an extra key, a query" | the routes; handed over to the station link |
| TC-039-048 "POST /pskr/use ... 401 for MCP" and the run snapshot | station link and auto |
| The memory bounds 256 and 128 in TC-039-020 | values of the inside |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| `backend/spots/` (2 files) | 8,460 | 14,135 |
| `interfaces/internal/Hearing.sysml` | 418 | 3,502 |
| `interfaces/external/PskReporter.sysml` | 470 | 11,551 |
| CL-039-20, TC-039-020, TC-039-048 in qso's old file | 6,955 | in the files above |
| Total | 16,303 | 29,188 |

The part is 1.8 times its old text. Where the size sits:

| Content | Characters |
|---|---|
| The three test cases, 26 conditions and 1 planned (the two old cases: 5,569) | 10,633 |
| Imports, status and level tags, derivations, test bindings | 4,073 |
| The three clauses | 1,075 |
| Rule elements, typed items and enumerations of the four files | 13,407 |

The growth is the test conditions written one per line with their values, and the two
interface files, whose items had no feature.

## Checks

- `part_done.py spots`: all five tests pass: 6 identities, no finding of the script, no
  validator error, 4 names matched with the code and 21 lines with a verdict, 3 test cases
  with their tests.
- The validator on the whole new tree reports no error in the four files and none on the
  lines of `Station.sysml` that join `spots.hearing` to ranking and auto. The line to
  `qso.hearing` fails on qso's side (not built).
- Read in full before writing: `pskr.rs`, `pskr_tests.rs`, the callers of the feed in
  `main.rs`, `contact_http.rs`, `automation.rs`, `strategy.rs`.

## The functional description

`_descriptions/spots.md`, from the new files alone (12,534 characters). It found five gaps.

| Gap | Settled how |
|---|---|
| No connection brings the switches, the call, the target, the band, the mode and the dial | marker on `SpotsService`; line 1 for the operator |
| `FeedStatus` crosses on no port | the same marker |
| "The range of transmit offsets of the mode" has no element | auto's; handed over |
| Strategy run, contest run, own contact have no element | auto's; handed over |
| `Subscription` does not say whether it is made or removed | left: the source's packets say it |

## Work for the code, when the new tree goes to main

- `pskr.rs` moves out of `operating/qso/`; its routes go to the station link's code.
- 13 comments name `WstxHearingFeed::PskrUse`.
- The tests of TC-039-052 carry the number TC-039-020; `reports_counts_up_to_600_s_and_no_longer`
  carries CL-097-05 and TC-097-010.
- `HEARD_WINDOW_S` and the session's times are read from the model by no test.
- `pskr.rs` reads the band, the mode and the dial of the station itself.

## For the main session

Rows for `_work/handover.md`, in its format:

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station link | `GET /pskr` `{v 1, profile_id, boot_id, enabled, use, state off/connecting/connected/error, error, last_spot_utc_s, storage_error}`, read once on each connection; `POST /pskr {v, profile_id, boot_id, enabled}` and `POST /pskr/use {v, profile_id, boot_id, use}`, exact keys, at most 1024 bytes, operating access from the browser only (an MCP principal: 401); refusals 400 `invalid_request`, 403 `wrong_profile`, 409 `state_conflict`, 503 `storage_unavailable`, 404 without a feed. The event `pskr.state` with the same data on a change; for a new spot at most once per 30 s (the code keeps this pace in the feed, `SPOT_EVENT_S`). The fields are those of `WstxHearingFeed::FeedStatus`. | `HearingFeed`, `PskrUse`, TC-039-020, TC-039-048 | spots |
| station | The station service gives spots the two switches, the profile's call, the target, the station's band and mode and the confirmed dial, and takes `FeedStatus`. `Station.sysml` joins spots to ranking, auto, qso and the broker only (marker on `SpotsService`; line 1 for the operator). In the code the station step calls the feed (`contact_http.rs` `station_tick`) and the routes call it directly. | CL-039-20, `HearingFeed` | spots |
| auto | Auto names the target spots follows: the DX call of the own contact of a strategy or contest run while it is active, not of a pounce, a plain MCP run or a manual contact (`automation.rs` `own_contact`). The run snapshot's `hearing {state, reports, spot_utc_s, snr_db}` and `tx_slot.his_end` are made from `WstxHearing::HearingReport`; LeaveRule and TxMoveRule read `TargetHearing::state` and `reports`. The range of transmit offsets of a mode that bounds `DecodedOffsets` is `freeslot::band` (from 300 Hz). `strategy_tests.rs::tc_039_048_the_run_shows_the_hearing_and_his_end` is auto's; TC-039-048 stands in spots with its five tests of `pskr_tests.rs` and verifies CL-039-23 and CL-039-09 no more. `pskr_tests.rs::reports_counts_up_to_600_s_and_no_longer` is shown by TC-039-020 (d). | CL-039-20, `PskrUse`, CL-097-05, TC-039-048, TC-097-010 | spots |
| ranking | The criterion hears_us reads `HearingReport::heardBy`; with `inUse` false it ties. `ValueOrder.sysml` names `PskrUse` and `HearingFeed` in text: the switch is `WstxHearingFeed::FeedSwitches`, the report `WstxHearing::HearingReport`. | `ValueOrder`, `HearingFeed` | spots |
| qso | The split move away from a busy partner reads the target's decoded offsets of the own transmit parity from `HearingReport`, only while spots follows that partner (`contact_http.rs`, `his_psk`). | `PskrUse` | spots |
| frontend | Settings > Logging: the switch "Listen to PSK Reporter spots", the status line ("Connected · no spot yet", "Connected · last spot n min ago", "Off", "Not connected · code · retrying", the storage error) and the text under it. The PSK toggle next to Auto, disabled with the title "PSK Reporter is off in Settings" while the first switch is off. The two lines of the QSO pane ("Hears us: ...", "Tx ... Hz · open at his end: ..."). | CL-039-20, `PskrUse`, TC-039-021 | spots |
| profile | `pskr.json` lies in the profile's folder (`schema_version 2, profile_id, enabled, use`). Spots has no connection to the profile. | `HearingFeed` | spots |

Test cases handed over, in the table's format:

| Test case | Shows | To |
|---|---|---|
| TC-039-021 Settings shows the PSK Reporter status, pushed | the Settings view and the event (`tests/ui-operating.test.cjs`); verified CL-039-20 | frontend, station link |
| TC-039-048, its run test | the run snapshot's hearing and his end (`strategy_tests.rs`) | auto |

Other files:

- `Station.sysml`: nothing must change for the part to be valid. A connection between the
  station service and spots waits for line 1 for the operator.
- `_work/files.md`: the four files are built; `backend/spots/HearingFeed.sysml` is no
  longer "to build".
- `backend/operating/ranking/ValueOrder.sysml` and `interfaces/internal/AutoControl.sysml`
  (taken over) name `PskrUse` and `HearingFeed` in text.
- The ledger rows of CL-039-20, TC-039-020 and TC-039-048 were "TO PLACE" under qso's old
  file; they now name spots, and three new rows stand beside them.
- From `Decodes.sysml` spots needs nothing.

## For the operator

1. Spots has no connection to the station service: nothing brings it the two switches, the profile's call, the target, the band, the mode and the dial, and nothing takes its status (marker on `SpotsService`). WSJT-X has no such function: it sends reception reports to PSK Reporter and reads none. Recommendation: one control interface for spots in `interfaces/internal/Hearing.sysml`, joined `station.spots` to `spots.control`, as the clock's `ClockStatus` stands in `StationTime.sysml`; M2.1 names no other file for it, and M5.3 asks that commands come from the station service.
2. FR-012 says "the WSJT-X UDP messages and reception reporting". Spots reports no reception; it reads who receives the station. WSJT-X does the opposite half (it reports, `Network/PSKReporter.cpp`). The three clauses derive from FR-012 because `Station.sysml` gives it to spots. Recommendation: reword FR-012 ("... and the PSK Reporter feed of who hears the station") or give spots' clauses to FR-025 and FR-026, which use the report; the first is the smaller change.
3. **Answered (operator 2026-11-16): the feed serves two places. Ranking gets `HeardByReport` (which stations hear us, for `hears_us`) over `HeardByLink`; auto gets `TargetReport` (whether the station being called hears us and how strong, and the frequencies it already decodes in each period) over `TargetHearingLink`, for the automatic choice of the transmit frequency (`FreeTxSlot`). The connection to qso went: the split for a busy partner is a choice of the Tx frequency, auto's. Ranking's marker on the folder went (profile line 2).** The shape of `HearingReport`: one report for the station's band and mode, read by ranking, auto and qso alike. In the code each caller asks the feed with its own arguments (a call, a mode, a band, a parity). WSJT-X has nothing to compare. Recommendation: keep the one report; it needs the station's band, mode and dial from the station service (line 1), and no request items.

## Not sure

- The roots: that the built-in file holds ISRG Root X1 and X2 is taken from the comment in
  `pskr.rs` and the count of two certificates in the file; the certificates were not
  decoded.
- `connectFailed` is also given when a socket option cannot be set after the connection;
  the model says "no address of the broker took the connection".
- WSJT-X was read at the local tree (tag v3.3.0-beta6), not at the behaviour baseline.

## Not done

- Nothing outside `docs/sysmlV2` was touched. `_work/handover.md`, `_work/files.md`,
  `Station.sysml` and `START-HERE.md` are not changed.

## Decided by the operator (2026-11-15)

| Line | Answer | Done |
|---|---|---|
| 1 | a control interface for spots in `Hearing.sysml` | `SpotsControlPort`, `SpotsControl`, `SetFeed`, `SetFeedUse`, `FeedContext`, `FeedReport`, `FeedRefused`; `FeedState`, `StorageError` and `FeedStatus` moved from `HearingFeed.sysml` to the interface; port `control` on `SpotsService`, its marker gone; `stationSpots` in `Station.sysml`. Written by the main session |

Open: line 2 (FR-012), line 3.
| 2 | **FR-027's allocation confirmed (operator 2026-11-16): spots owns PSK Reporter in both directions; reporting gets a connection from receive's decodes and an external interface of its own (IPFIX over UDP, as WSJT-X `Network/PSKReporter.cpp`) with its clause when the code is built.** FR-012 is split in two | FR-012 names the UDP messages and the feed of who hears the station; the new FR-027 names the reception reports to PSK Reporter. It has no clause, code or test, so its status computes as target. `Station.sysml` gives it to spots, which holds the PSK Reporter interface; that allocation is the main session's choice and open to the operator |

## Changed after the report: the settings (operator 2026-11-15)

The operator decided on 2026-11-15 how the settings of a station are sorted and stored:
three stores (the station config, the hidden store of the station, the config of each
frontend), with definition files and data files as files of their own; a setting and a
record are defined by the part that uses them, in that part's control interface; the
profile only stores them, as collections by type (`WstxProfileAccess::StationConfig`,
`StationMemory`); a change takes one way (operator, station service, profile, and back to
the part as its new configuration). The model states this; the code still has a file for
each function, and the difference is work for the code (a later issue). The sections above
are as they were written; where they name a file of the function's own, a set command or a
storage refusal, this section holds.

Measured by `measure.py` in the session's scratchpad, subfolder `settings` (the tree
against a copy made before the change).

| File | Lines | Characters |
|---|---|---|
| `interfaces/internal/Hearing.sysml` | 160 to 149 | 7,443 to 7,215 |
| `backend/spots/Spots.sysml` | 18 to 21 | 785 to 954 |
| `backend/spots/HearingFeed.sysml` | 179 to 166 | 11,268 to 10,249 |
| `_descriptions/spots.md` | 208 to 207 | 12,534 to 12,572 |

Moved in (spots defines it now, in its control interface):

| Element | What |
|---|---|
| `SpotsConfig` (new, in `WstxHearing`) | the configuration: `enabled` = true and `'use'` = true, each with what it does; the two features came from `FeedSwitches` of the function file |
| `SpotsConfiguration` (new) | the item that carries it, at station start and whenever the station config changes |
| `SpotsService` | one attribute: `config : SpotsConfig` |
| `FeedSwitches` | stays in the function file as the rule: what the two switches do (the session, the forgetting, the report, the subscription of the target) |

Left:

| Element | What left |
|---|---|
| `SetFeed`, `SetFeedUse` | the two commands and their places on the port |
| `FeedRefused`, `StorageError` | the refusal of a switch that could not be saved, and its two reasons (`invalidPskr`, `storageUnavailable`) |
| `FeedStatus` | `storageError` |
| `FeedReport` | "the answer to an accepted SetFeed or SetFeedUse" |
| `FeedSwitches` | the file `pskr.json`, what a missing, an older and a broken file mean, and the refusal of a change that cannot be saved |
| CL-039-26 | "keep the operator's two switches of the feed across restarts": the profile keeps them (CL-005-02). The clause stays with what spots does: "read the feed and let runs use it only as the two switches of its configuration say, and report the state of the feed" |
| TC-039-020 (h) | "Enabled switched off and the station started again: enabled off. Started for another profile, and with a file that holds one brace: enabled on, with invalidPskr". Kept: a configuration never set is on, and the state is off where no connection is allowed. 9 lettered lines and the one test file as before |
| TC-039-048 (c) | whole: a file without the second switch, the file after a change, five broken files. Its test `tc_039_048_the_use_setting_is_kept_in_schema_2` showed (c) only and left `@TestedBy` (5 to 4 lettered lines, 5 to 4 tests). The letter (c) is not used again |

No identity is retired or not carried.

Planned, no test yet: the profile keeps the two switches across a restart; the line stands
in the profile's TC-022-002 (k).

Verdicts in `parts.json` (test 4: 4 matched, 19 with a verdict; before 4 and 21): two taken
out, model literals `StorageError::invalidPskr` and `::storageUnavailable`. Test 4 shows no
new line.

Differences in the code that test 4 does not show (work for the code):
`operating/qso/pskr.rs` keeps `pskr.json` (`Feed::start`, `set_enabled`, `set_use`,
`storage_error` in the view); the routes that switch the feed
(`http_routes_read_and_switch_the_feed`, `tc_039_048_post_pskr_use_saves_and_refuses`).

Not decided, for the operator: nothing of spots' own.

Not verified: of `pskr_tests.rs` the tests `the_setting_defaults_on_and_survives` and
`tc_039_048_the_use_setting_is_kept_in_schema_2` were read in full; that the other four
tests of TC-039-048 show (a), (b), (d) and (e) rests on their names and on the report
above.

## Changed after the report: the addresses and the reception reports (operator 2026-11-16)

The official PSK Reporter is the default for production; a test profile may name a
simulator, for the feed and for the reports alike. FR-027 is spots'.

| File | Element | What |
|---|---|---|
| `Hearing.sysml` | `SpotsConfig` | `feedBroker` (mqtts or mqtt, host and port; default `mqtts://mqtt.pskreporter.info:1884`), `report` (off by default, as WSJT-X), `reportCollector` (udp or tcp, host and port; default `udp://report.pskreporter.info:4739`) |
| `Hearing.sysml` | `FeedContext` | `locator`, for the reports |
| `PskReporter.sysml` | `FeedSession` | the broker is `feedBroker`; TLS with the built-in roots for mqtts, none for mqtt; a changed broker ends the session and forgets every Spot; `WSTX_PSKR` gone; TC-039-052 (j) planned |
| `PskReporter.sysml` | new | `ReportedStation`, `ReceptionReport`, `ReportCollectorPort`, `ReportCollector` |
| `SpotsReporting.sysml` (new, M2.1 `Spots*`) | CL-039-28 (new, FR-027, status target) | `ReceptionReports`: what is reported and when, after WSJT-X (`PSKReporter.cpp`, `pskPost`): decoded, a CQ or a grid, not our own call, not a recording; 300 s before a call again (every record above 49 MHz); sent every 120 s; at most 2048 waiting |
| `Spots.sysml` | ports | `decodes` (from receive), `collector` |
| `Station.sysml`, `Context.sysml` | connections | `decodesSpots`; `reportCollectorLink` to PSK Reporter's new port `collector` |

No test case: no test exists. The code: issue #195, revised to this model.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-039-020 (`HearingFeed.sysml`): a report is given at once while the feed waits on the network.
- TC-039-048 (`HearingFeed.sysml`): a contact the operator starts with K1ABC makes K1ABC the target, as Auto's contact does, and the station service is given the same TargetReport as auto.
- TC-039-052 (`PskReporter.sysml`): the default broker is mqtts://mqtt.pskreporter.info:1884; mqtt://127.0.0.1:1883 speaks to that peer without TLS; a changed broker ends the session and forgets every Spot; mqtt://name@host:1883, ftp://host:1883, a port 0 and a path are not admitted.
