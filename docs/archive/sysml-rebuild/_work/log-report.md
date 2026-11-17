# Report: the log part

2026-11-15. Built by a subagent beside the receive part; the operator was not asked.
`part_done.py log` passes tests 1 to 5. What a rule decides is listed as decided; what no
rule decides is listed for the operator at the end and is not decided here. Every figure
is measured by a script (`measure.py` in the session's scratchpad; it reads only).

## What was written

| File | Content |
|---|---|
| `backend/log/Log.sysml` | the log part with five ports; one marker |
| `backend/log/Logbook.sysml` | 4 clauses, 8 rule elements, 6 test cases: logging a finished contact, the same station again, the exchange with other logging programs, what has been worked |
| `backend/log/CountryFile.sysml` | 2 clauses, 3 rule elements, 2 test cases: the entity of a call, the operator's country file |
| `interfaces/internal/LogControl.sysml` | the record, the limits, 10 commands of the station service and 8 answers and reports; 18 items, 6 attribute definitions, 7 enumerations |
| `interfaces/internal/OperatingChain.sysml` | only the log's ends: `LogAnswer` rewritten; `LoggedContactPort`, `LoggedContact`, `LoggedContactLink` added; `WorkedBeforePort` with `WorkedSet`, `WorkedCategory`, `Standing`, `WorkedStatus`, `WorkedWindow`, `DateWindow`, `ContestPeriod`, `PeriodQso`, `PeriodQsos` written. Everything else in the file is untouched |

`interfaces/external/ClubLog.sysml` is not the log's: its ends are ranking and the Club Log
service (`Context.sysml` joins `ranking.clubLog`). Not touched.

## Identities

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-010-04 | log/Logbook | Logbook | Keeps its core: every finished contact is stored once. Its second half is CL-010-18. Its UDP half is udp's. |
| **CL-010-18** | new | Logbook | The update from another program's file, the export and the history, split from CL-010-04: another test case (TC-011-002) and another reason of change. The next free number of the series. |
| CL-085-01 | log/Logbook | Logbook | Rewritten from `same_station_again` and `collect_logs`. |
| CL-010-13 | qso/QsoData (TO PLACE) | Logbook | Its core is the log's: what has been worked, from the logbook. The display half is handed over. Derives from FR-011 only (was FR-010, FR-011). |
| CL-055-01 | qso/QsoData (TO PLACE) | CountryFile | The tree puts `CountryFile` in the log. |
| CL-055-03 | qso/QsoData (TO PLACE) | CountryFile | Keeps its core: the operator's file in the place of the bundled one. The Settings view is handed over. Derives from FR-011 (was FR-016). |
| TC-011-001, TC-011-002 | log/Logbook | Logbook | Rewritten from their tests; TC-011-002 verifies CL-010-18 now. |
| TC-085-001, -002, -003 | log/Logbook | Logbook | Rewritten from their tests. TC-085-001 verifies CL-085-01 only (was also CL-085-02, which is qso's). The contest condition of TC-085-004 that is the log's rule is TC-085-002 (e). |
| TC-011-003 | qso/QsoData (TO PLACE) | Logbook | Keeps the conditions shown at the log; its browser and route conditions are handed over. Was `partial`; every condition written here has a test, one is planned. |
| TC-055-001, TC-055-003 | qso/QsoData (TO PLACE) | CountryFile | Rewritten from their tests. |
| CL-011-03, TC-007-008 | log/Logbook | handed over: qso | The FT4 contact through the contact engine. The log's two facts (MFSK with FT4; the effective mode) stand in `LogRecord`. |
| CL-110-01, TC-110-001 to -004 | log/Logbook | handed over: qso | The saved Auto Seq and Call 1st (`qso-settings.json`, written by the contact command path). |
| TC-110-005, TC-085-005 | log/Logbook | handed over: frontend | Browser tests. The one condition of TC-085-005 at the log is TC-085-001 (a). |
| TC-085-006, TC-110-006 | log/Logbook | not carried | Planned live cases without a test. |

25 identities are accounted for in the ledger: 14 arrived, 9 handed over, 2 not carried.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| The country file and its two clauses are the log's | M2.1 names `CountryFile` under `log/`; a clause stands in the function file of its part (M6.2) | CL-055-01 and CL-055-03 arrive here from qso's old file. The handover row "ranking: `cty.dat`" of the top files is taken up by the log. |
| What has been worked is the log's clause | A model file follows the thing; FR-011 is the log's; the port `workedBefore` needs its clause | CL-010-13 arrives here. |
| CL-010-04 is divided | M6.4: members shown by different tests and changing for different reasons | CL-010-18; the method's rule for a new number. |
| Each clause derives from FR-011 only | Decided on the clock | Three second FRs dropped. |
| How the log learns callsign, locator, dial and the contest's dupe rule | M5.3; the method, decided on audio: a function learns what the profile says from the station service | `LogContext` on `LogControl`. In the code the contact step reads all four itself. |
| The pending records and the refusal belong to the log although they stand in `contact_http.rs` | A model file follows the thing, not the code's modules | `DirectLog`, `SameStationAgain`; the two clauses name the module. |
| The routes, their status codes, keys and body sizes | M4.7: a transport file holds them | Not written; handed over to the station link. `LogControl` holds the commands and what they carry. |
| The record crosses three connections | Data that crosses a connection belongs to the interface (authoring rule 3) | `LogRecord` stands in `LogControl`; `LoggedContact` refers to it by type. |
| What the log gives udp is not what qso gives the log | A connection is typed by what flows (M5.8); a port names its items | `LoggedContactPort`. `Station.sysml` must follow (below). |
| The items of `WorkedBeforePort` | An item on a connection has features (structure rule 1) | Typed from the code. The entity of a call is asked for on the same port, because ranking has no other connection to the log. |
| ADIF, cty.dat, the WPX prefix, the band limits, the shortening of names | A followed source is referred to, not copied | Named once each; the 33 bands and the 26 name replacements are not written. |
| The check of the request's authority while writing | M5.3: the station service is the gate | Not written; handed over. |
| Limits kept as values | Values are sorted; a limit someone outside relies on is a promise | 13 values. `REASON_GROUPS` (16) is the size of two lists of `ImportView`. `RECEIPTS`, `WORKED_WINDOWS` and the body sizes are not written. |
| Promises without a test | Decided on audio | One line "Planned, no test yet": TC-011-003 (i). |

## Dropped as code or as history

- The decision list D1 to D11 of `Contest.sysml`, all 13 `dependency` lines, all dates,
  issue numbers and names of reviews.
- The worked-before index and the caches of worked sets (at most four windows), the
  build thread; the model says that a set follows the logbook and that the last one is
  given at once.
- The receipts of `SaveContact` (16 kept), which make a repeated command harmless: a rule
  of the command transport.
- Blocking threads, locks, "off the async runtime", "never delays Halt".
- The comparison of two records field by field (letter case, trailing zeros, times
  without seconds); the model says "the same fields".
- The 27,000-QSO workload as a promise; it is a condition of TC-011-002 with its test's
  values.
- The temporary file names, the day-count arithmetic, the lower case of a contact id.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| `LogCommand`, `LogState` (empty items) | the ten commands, `LogAttempt` | `Station.sysml` uses the interface only |
| `WstxLogbook::LogRecord`, `AdiError` | `WstxLogControl::LogRecord`, `AdiError` | header of `server/src/logbook.rs`; old `Udp.sysml`, `QsoControl.sysml` |
| `AdiLimits` | `WstxLogControl::LogLimits` | header of `logbook.rs` |
| enumeration `LogOutcome` (saved, alreadySaved, invalidField, conflict, storageFailed) | `SaveOutcome` (the code's three), `LogRefusal`, `LogError` | none found |
| `WstxLogbook::WorkedStatus` with `unknown` | `WstxOperatingChain::WorkedStatus`, three literals as the code | old `LogControl::DecodedEntity` |
| `calc def EntityOfCall` returning a text | `action def EntityOfCall` returning `CallEntity` | old `ValueOrder.sysml`, `RankingControl.sysml` (by name in text) |
| `CountryFile::bytesMax` | `LogLimits::countryFileBytesMax` | none |
| `DirectLog`, `SaveContact`, `UpdateLogbook`, `ExportAdi`, `ContactHistory`, `WorkedBeforeQuery` (actions) | the same names, attribute definitions holding the rules | `logbook.rs`, `contact_http.rs`, `contact.rs`, `udp.rs`, old `Udp.sysml` and `Mcp.sysml`: names unchanged |
| `LogRecord::contestFields[0..8]`, `confirmationFields[0..7]` | fifteen named features | none |
| `pending` limit, unnamed | `DirectLog::logPendingMax` | the code's `LOG_PENDING_MAX` |

## Negative statements

| Old statement | Result |
|---|---|
| "without a review step"; the retired review queue | dropped: history |
| An update sends nothing to the UDP targets or elsewhere | kept, positive where it can be: "No record of an update is given as `LoggedContact`"; a function exists that gives one (a saved record), and TC-011-002 (l) shows it |
| A confirmation is only added, never removed | "is not taken away or lowered"; the upgrade is the function that could; TC-011-002 (i) |
| An unreadable file is never overwritten | positive: "leaves the file as it is" |
| "No time is involved" in the same-station rule | one sentence kept: the update's rule next to it does use time |
| SaveContact has no dupe refusal | positive: "stored as they are" |
| Nothing is downloaded automatically (country file) | dropped: no such function |
| History is read-only, no edit or delete | dropped: no such function |
| The browser never substitutes its clock | dropped: no such function in the log |
| LoTW highlighting is not adopted | dropped |
| Name, operator, propagation and satellite fields are not adopted | a `@DiffersFromSource` on `LogRecord`, checked in WSJT-X `AdifQso.cpp` |

## Settled from the code

- **Three outcomes of a save, not five.** `invalidField` and `storageFailed` are refusals.
- **`tooLarge` is not a fault of a file.** The size is refused at the reservation.
- **An update that stalls.** A receiving update whose last part is 60 s old no longer
  blocks the next reservation. The old text had "one update at a time" only.
- **The same station under a contest.** Only `band_grid` changes the answer; under the
  other three dupe rules the result is the same as without a contest.
- **The contact's own record.** When the record that waits last is the contact's own, no
  record is compared at all, also not the last stored one.
- **Reading the stored file is not reading an update.** The stored file's contest fields
  are taken as they are; an update drops those a save would refuse.
- **Zones.** A CQ or ITU zone 0 is taken.
- **The export's header** also carries the program's version, and the time of the export.
- **The saved record's grid** is 4 or 6 characters; an update takes 2, 4, 6 or 8.
- **`FREQ`** of a saved record must lie in its `BAND`.

## What the comparison with the code found

| Finding | Result |
|---|---|
| The pending records, the retry and the same-station check stand in `contact_http.rs` (qso) | Work for the code. Two clauses name the module; 7 verdicts for its other names. |
| Six refusals of the model are decided in `logbook_http.rs`, the module of the routes: the sizes, the ranges of the history, a profile without callsign, the words `invalid_cty`, `bundled`, `uploaded` | Work for the code. 6 verdicts "difference in the code". |
| Three values are private constants (`LOG_RETRY`, `CONSOLIDATION_SECONDS`, `IMPORT_IDLE`) | Matched by reading. |
| The codes of `AdiError`, `LogError` and most of `LogRefusal` are strings, not an enumeration | 16 literals matched by reading. |
| The tool does not read `OperatingChain.sysml` for this part (it holds another part's clause) | `WorkedStatus` (3 literals) and `WorkedCategory` (7) compared by reading: `not_worked`, `worked_other_band_or_mode`, `worked_this_band_and_mode` in `logbook.rs`; `Category` has `Dxcc`, `Continent`, `CqZone`, `ItuZone`; call, grid and prefix are the indexes 0, 1 and 6 of `dxcc.rs`. |
| The tool keys a literal by its name | `SaveOutcome::saved` and `alreadySaved` matched `LogOutcome` of the code; read: `SaveOutcome` of the code has exactly the model's three. |

Test 4: 17 lines matched by the tool (10 of the 13 values, 7 literals), 50 with a verdict:
35 matched by reading, 8 another part, 6 difference in the code, 1 inside.

## Edge cases and their homes

| Case | Home |
|---|---|
| missing, unreadable, malformed `contacts.adi`; two records with one id | `Logbook`, TC-011-001 (k), (l) |
| a write that fails at each of its three steps | `Logbook`, TC-011-001 (g) |
| the same contact handed over twice; Log QSO after completion | `DirectLog`, TC-011-001 (b) |
| the file cannot be written for long | `logPendingMax`, TC-011-001 (d), (e) |
| the station stops while records wait | `DirectLog` (they are lost); no test |
| a profile without callsign | `logInvalidField` for a finished contact, TC-085-002 (g); `profileIncomplete` for a save, no test at the log |
| no confirmed dial | `DirectLog`, TC-011-001 (a) |
| band known on one side only | `SameStationAgain`, TC-085-002 (d) |
| a restart between two QSOs with one station | TC-085-003 (a) |
| a field at and over each limit of an update | TC-011-002 (e) |
| an update given twice, cut off, out of order, with a wrong checksum | TC-011-002 (f) |
| two starts 120 and 121 s apart | TC-011-002 (b) |
| a record without date in a dated window | `WorkedBeforeQuery`; covered by the rule, no condition |
| a call without an entity; a call outside ASCII | `WorkedCategory`, `EntityOfCall`, TC-055-001 (b), TC-011-003 (c) |
| a stored country file that cannot be used | `ProfileCountryFile`, TC-055-003 (f) |
| a history page whose records are large | `ContactHistory`, TC-011-002 (m) |
| the log changes while an export runs | `ExportAdi`, TC-011-002 (k) |
| two commands at once | serialised by the code; rare and harmless, not written |

## Not carried over

| What | Why |
|---|---|
| TC-085-006, TC-110-006 | planned live cases, no test |
| `Contest.sysml`: the decision list and the dependencies (4,579 characters) | history and a construct the model does not use |
| `Contest.sysml`: `ContestLog` (1,525 characters) | waits for the operator, first line below |
| `LogControl::DecodedEntity` (2,274 characters) | another part's: handed over |
| `LogControl::CountryFileHttp` (1,033 characters) | the route: handed over to the station link |
| the conditions of the old test cases on status codes, Origin, grants and the browser | handed over |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| `backend/log/Logbook.sysml`, what stays of it | 45,178 (of 65,011; 19,833 leave for qso and the frontend) | 42,294 |
| `backend/log/CountryFile.sysml` | 3,104 | 10,567 |
| `backend/log/Log.sysml` | 613 | 1,294 |
| `interfaces/internal/LogControl.sysml` | 3,820 | 20,113 |
| the six identities that come in from `qso/QsoData.sysml` | 7,083 | in the files above |
| the log's elements in `OperatingChain.sysml` | 133 | 5,307 |
| Total | 59,931 | 79,575 |

The part is a third larger than its old text. Where the size sits:

| Content | Characters | Old |
|---|---|---|
| The 8 test cases, 62 lettered conditions | 28,797 | 16,510 |
| The 6 clauses | 2,313 | 5,135 for five |
| Definitions: rule elements, the record, items, enumerations, ports, the part | 38,682 | |
| Imports | 2,730 | |
| The log's elements in `OperatingChain.sysml` | 5,307 | 133 |

The growth is in two places. The test cases carry one set of values for each condition,
written from 42 named tests. The two interface files had four empty items
(`LogCommand`, `LogState`, `WorkedSet`, `FinishedContact`); three of them are now typed.
The rule elements are shorter than before: `UpdateLogbook` had 8,471 characters,
`LogRecord` 4,965.

## Checks

- `python docs/sysmlV2/_work/part_done.py log`: all five tests pass: 25 identities, no
  finding in 4 files, no validator error in them, 17 names matched and 50 lines with a
  verdict, 8 test cases with their tests. `part_done.py clock`, `modes` and `audio` still
  pass.
- `check.py` on `OperatingChain.sysml` reports 19 findings; all stand on lines of other
  parts' elements (CL-085-02, `BusyPartner`, `TransmitRequest`), none on the log's.
- The validator on `OperatingChain.sysml` reports two errors, both on the old import
  `WstxRequirements::ImplementationState` that CL-085-02 uses; none on the log's elements.
- Tests bound: 42 named tests in five files. Of the 27 tests of `logbook_tests.rs` 26 are
  bound (the other is a timing measurement); of the 11 of `dxcc_tests.rs` 7 (the other four
  go through the route `/receive/results`); of the 10 of `logbook_http_tests.rs` 2 (the
  other eight show the routes).
- `git status`: `docs/sysmlV2/` is the only change.

## The functional description

`_descriptions/log.md`, from the new files alone, 24,447 characters. It found five gaps.

| Gap | Settled how |
|---|---|
| The order of the parts of an export | One sentence on `ExportChunk`. |
| How an answer is matched to its command | One sentence on `LogControlPort`. |
| The source of the prefix rule was named in text only | `@FollowsSource` on `WorkedCategory`. |
| "The first field" refused by a save, without an order | The promise was more than the code keeps; now "a field that is outside". |
| What crosses the connection to the profile | A marker on `LogService`. |

## Markers

| Where | Marker | Says |
|---|---|---|
| `DirectLog` | `@NotStated` | `FinishedContact` has no feature; what the record needs from it |
| `PeriodQsos` | `@NotStated` | which part holds the rules by which a contest counts these QSOs |
| `LogService` | `@NotStated` | what crosses the port `contacts` |
| `Logbook`, `SameStationAgain`, `LogRecord` | `@DiffersFromSource`, five | empty GRIDSQUARE; the whole file written anew; the same station again; six fields of WSJT-X not kept; a value refused where WSJT-X changes it |
| `Logbook`, `UpdateLogbook`, `WorkedBeforeQuery`, `EntityOfCall`, `CountryFile`, `LogRecord`, `WorkedCategory` | `@FollowsSource`, seven | ADIF 3.1.8, WSJT-X at the behaviour baseline, AD1C cty.dat, the CQ WPX rules |

## Checked in WSJT-X (`D:\Github\wsjtx`)

| Question | WSJT-X does |
|---|---|
| Is a QSO compared with the one before when it is logged? | No: `LogBook::add` passes every QSO to `WorkedBefore::add` (`logbook/logbook.cpp`). |
| Which fields does it write? | `AdifQso.cpp`: `gridsquare` also when empty; `name`, `operator`, `prop_mode`, `sat_name`, `sat_mode`, `freq_rx` when set; `<` and `>` taken out of a value, other characters outside printable ASCII written as `?`. |
| How is "worked before" asked? | `LogBook::match`: the mode is left out when highlighting by mode is off, which is its default (`Configuration.cpp`); an unknown entity is not flagged. |
| Where does it keep the contest's QSOs, dupes and multipliers? | With the logbook: `LogBook::contest_log()` holds a `CabrilloLog` (its own table, `dupe` by call and band) and a `Multiplier`; the main window asks them. |

## Work for the code, when the new tree goes to main

- The pending records, the retry and the same-station check move from `contact_http.rs`
  to the log.
- The log takes callsign, locator, dial and the dupe rule from the station service; the
  contact step reads them itself today.
- Six checks stand in the routes (`logbook_http.rs`) and belong to the log.
- `LOG_RETRY`, `CONSOLIDATION_SECONDS` and `IMPORT_IDLE` are private; no test reads a
  value from the model.
- The test tags: `invalid_stored_log_is_unavailable_and_never_rewritten`,
  `adi_parser_*` and the history test say TC-011-002 or TC-011-001 where the other case
  holds their condition now; the tests of CL-010-18 say CL-010-04; `tc_039_030_*` of
  `dxcc_tests.rs` and two tests of `logbook_tests.rs` are bound to TC-011-003.
- Comments in `logbook.rs`, `dxcc.rs`, `contact.rs`, `contest.rs` and `udp.rs` name
  `WstxLogbook::LogRecord`, `AdiLimits`, `WstxContest::ContestLog`, `WstxDxcc` and
  `WstxLogControl::DecodedEntity`.
- No test shows the US state of a call, the QSOs of a contest period, or
  `profileIncomplete` at the log.

## For the main session

### Handover rows (for `_work/handover.md`)

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| log | `contacts.adi`, in ADIF 3.1.8 ADI. **Taken up:** `WstxLogbook::Logbook`, CL-010-04. | old `Context.sysml`, `log/Logbook` | top files |
| log | `cty.dat` (AD1C). **Taken up by the log, not by ranking** (M2.1 names `CountryFile` under `log/`): `WstxCountryFile::CountryFile`, `EntityOfCall`, CL-055-01, CL-055-03. The most-wanted list stays ranking's. | old `Context.sysml`, `ranking/ValueOrder` | log |
| qso | `FinishedContact` has no feature. The log's record needs from it: the identity of the contact, whether it is handed over at completion or by Log QSO, the partner's call and grid, the mode, the two reports as logged, start and end, the contest fields, the activity and the Tx offset (`contact.rs` `log_fields`, `LogKind`; `contact_http.rs` `record_of`). The marker on `WstxLogbook::DirectLog` is answered by it. | CL-010-04, `LogRecord`, `DirectLog` | log |
| qso | The times of a logged QSO: the start is the period of the first transmitted Tx2, or one period before the first transmitted Tx3, otherwise the period of the first transmitted message, otherwise the preparation; the end is the end of the last period with a counted message. The reports as logged: the last transmitted and the last counted report; for RTTY Roundup and EU VHF the RST or RS of the exchange. The contest fields from the exchange (`contest_fields`). | `LogRecord` | log |
| qso | When a contact is handed to the log: once at its completion, and by Log QSO in any state with a DX call; Log QSO of an unfinished contact closes it (completed, Tx6, transmission off with cause contactCompleted); a contact completed without a received report is logged without RST_RCVD; a contact without a partner is not handed over. CL-011-03 and TC-007-008 (the FT4 contact) are qso's; the log's part of them is `LogRecord::mode`, `submode`. | `DirectLog`, CL-011-03 | log |
| qso | CL-110-01 with TC-110-001 to -004: Auto Seq and Call 1st saved for each profile in `qso-settings.json` (`QsoSettingsFile`, at most 256 bytes), written by the contact command path before the receipt; a failed write refuses the command with `storage_unavailable`. TC-110-005 is the browser's. The clause derived from FR-007 and FR-016. | CL-110-01, `QsoSettingsFile` | log |
| qso | CL-085-02 and CL-085-03 stay qso's. TC-085-001 verifies CL-085-01 only now; TC-085-004 keeps the serial, and its condition (d), the log's rule under `band_grid`, is also TC-085-002 (e). | TC-085-001, TC-085-004 | log |
| station | The station service gives the log `LogContext`: the profile's callsign and locator in upper case, the dial that radio control has confirmed, and the dupe rule of the contest in force (the active strategy of class contest), at station start and whenever one changes. It passes the operator's log commands (`SaveRecord`, the update, the export, the history, the country file, `EntityRequest`) and reports `LogAttempt` in the contact snapshot (`log`). In the code the contact step and the routes read these themselves. | CL-010-04, CL-085-01, `contact_http.rs`, `logbook_http.rs` | log |
| station | A change of the logbook or of the country file is written only while the request's authority is still current; a grant revoked between admission and writing wins (`Gate`, `StoreError::Unauthorized`; `revocation_between_admission_and_publication_wins_the_atomic_replace`). A finished contact is stored without a request's grant. A repeated `SaveRecord` with the same command id gets the same receipt; with another body `state_conflict` (16 receipts kept). | CL-010-04, `DirectLog`, `SaveContact` | log |
| station link | The log's routes: `POST` and `GET /contacts`, `GET /contacts/export.adi`, `POST /contacts/imports`, `GET` and `PUT /contacts/imports/{id}`, `GET` and `PUT /dxcc`. Per route the keys, status codes and sizes: save body at most 8192 bytes; the record's keys with `record.<field>` in a refusal; history reply `{v, profile_id, total, cursor, next, more, records}`, limit default 10, page at most 16384 bytes, never content-coded; export as `application/octet-stream`, attachment `contacts.adi`, chunked without Content-Length; import chunks with exact Content-Range, 201 for the completing chunk, 422 `import_failed`; `/dxcc` view `{v, profile_id, boot_id, source, version, entities, upload_unreadable}`, `?call=` of 1 to 13 characters, body at most 2 MiB, 400 `invalid_cty` with `line`; 404 in environment-only mode; wrong Origin 403, stale boot 409. The contact snapshot's `log` is `{contact_id, call, outcome, error}`. | `CountryFileHttp`, `ContactHistory`, `ExportAdi`, `UpdateLogbook`, TC-011-001, TC-011-002, TC-055-003, TC-085-005 | log |
| station link, ranking | CL-055-02 and TC-055-002: each decoded record of a resolved sender carries `dxcc` (`{name, cont, cq, itu, km}`), `flags` (the twelve `new_*` names, only the true ones) and `worked_status`. Which call is the sender (also a filled-in hash; none for a hash nobody heard, a free text; the entity only for a DXpedition message), the band used (the CAT dial band, else the selection band; without one no `_band` flag and no status), and the distance from the profile's locator. The log's part is `WorkedSet`, `WorkedStatus` and `EntityOfCall`. Which part puts them on a record is for the operator (below). The four route tests of `dxcc_tests.rs` belong to it. TC-055-005 is a planned live case without a test. | `LogControl::DecodedEntity`, CL-055-02, TC-055-002, TC-011-003 | log |
| ranking | Ranking asks the log on `WorkedBeforePort`: a `WorkedSet` for a window (`WorkedWindowRule`), the entity of a call (`EntityRequest`), and the QSOs of a contest period (`ContestPeriod`). `ContinentOfCall`, `UsStateOf`, `NewNeeded`, the nearest continent of a locator and the rules of `ContestLog` read these. `WstxRankingControl::Continent` and `WstxLogControl::Continent` are the same seven; one should refer to the other. `ValueOrder.sysml` and `RankingControl.sysml` name `WstxCountryFile::EntityOfCall` (unchanged name) and `WstxLogControl::DecodedEntity` (gone). | `WorkedBeforeQuery`, `ValueOrder` | log |
| udp | The log gives each newly stored QSO once as `WstxOperatingChain::LoggedContact` (a `LogRecord`), on `LoggedContactPort`: for a finished contact's first store and for a saved record; not for a replaced record and not for an update. That udp sends it as QSO Logged and then Logged ADIF is udp's. `Udp.sysml` names `WstxLogbook::DirectLog` and `SaveContact` (names unchanged) and has two `dependency` lines to them. | CL-010-04, `DirectLog`, TC-011-001 | log |
| frontend | The QSO pane's "Not logged <call> · same station as the last log entry" and "Logged" notices (TC-085-005); Settings > Logging & Reporting "Update logbook from ADIF" with its result line "Logbook updated: N added, M already present (C confirmations updated), K skipped" and "Logbook not updated"; the Logbook page; Settings > General: the country file line and its upload; the worked-before text and colours of TC-011-003; TC-110-005. | CL-010-04, CL-085-01, CL-010-13, CL-055-03 | log |
| profile | The logbook (`contacts.adi`) and the operator's country file (`cty.dat`) lie in the profile's folder; the log reads and writes them itself in the code. `ProfileAccess` carries two empty items on `contactStorage`; the marker on `WstxLogPart::LogService` waits for what crosses. | `Logbook`, `ProfileCountryFile` | log |

### Test cases handed over

| Test case | Shows | To |
|---|---|---|
| TC-007-008 FT4 contact, logging and mixed-mode isolation | the FT4 contact through the contact engine | qso |
| TC-110-001 to TC-110-004 Saved Auto Seq and Call 1st | the saved settings | qso |
| TC-110-005 The browser after a restart | the two checkboxes | frontend |
| TC-085-005 What the operator sees | the QSO pane's notice | frontend |
| TC-085-006, TC-110-006 | planned live cases, no test: not carried by the method | - |
| TC-055-002 Decoded records carry entity and new-* flags (not in the log's ledger rows) | the route `/receive/results`; its condition at the log is TC-011-003 (c) | station link, ranking |

### Changes needed outside the log's files

`Station.sysml`, word for word:

- add `private import WstxOperatingChain::LoggedContactLink;`
- replace `interface loggedContact : CompletedContact connect log.logged to udp.logged;`
  by `interface loggedContact : LoggedContactLink connect log.logged to udp.logged;`

`backend/udp/Udp.sysml` (the udp part): `port logged : ~CompletedContactPort;` becomes
`port logged : ~LoggedContactPort;`, with the import `WstxOperatingChain::LoggedContactPort`.

`interfaces/internal/OperatingChain.sysml`, not the log's and left as it is: the import
`WstxRequirements::ImplementationState` does not resolve (it is
`ModelBindings::ImplementationState`); CL-085-02 names `WstxLogbook::SameStationAgain`
and `WstxOperatingChain::LogAnswer`, both still there.

`_work/files.md`: `LogControl.sysml`, `Log.sysml`, `Logbook.sysml` and `CountryFile.sysml`
are built; `backend/log/Contest.sysml` stays an old file without a target.

`START-HERE.md`: the ledger count and the state table (log: tests 1 to 5 pass; one new
identity CL-010-18; six identities placed from "TO PLACE").

### Dependencies on interfaces built at the same time

None of `Decodes`, `DisplayData`, `ReceiveControl`, `Udp`, `PskReporter`, `Hearing` and
`FlexApi` is imported by the log's files. The log imports `Strategies` (for `DupeRule`),
`ProfileAccess` and `OperatingChain`, all taken over; the validator needs
`ModeProcessing`, `RankingControl`, `QsoControl` and `RadioControl` with them.

## For the operator

One line each; none is decided here.

1. **Where the contest text of old `log/Contest.sysml` goes** (open point 2 of the
   finished model). What is left after history is `ContestLog`: which QSOs of the period a
   contest counts, the dupes, and the tally of QSOs, multipliers, points and score.
   WSJT-X keeps this with its logbook (`LogBook::contest_log()`, a `CabrilloLog` with its
   own dupe query, and `Multiplier`). The code here keeps it in `contest.rs`, called from
   `strategy.rs`, and takes from the log only the QSOs of the period.
   Recommendation: `backend/operating/ranking/ContestRanking.sysml`, with CL-063-03's
   tally; the log gives the QSOs of a period (`PeriodQsos`, written, with a marker). The
   reason: the rules come from the contest profile, which the strategies own, and their
   only use is the verdict and the score that ranking makes; the log would need the
   contest profiles to hold them.
2. **Which part puts the entity and the new-flags on a decoded record** (CL-055-02). WSJT-X
   does it in the main window when it prints a decode (`m_logBook.match`). The code does
   it in the route `/receive/results`. Recommendation: ranking, the only part joined to
   both the decodes and the log; the wire names go to the station link.
3. **The log learns the dial and the contest's dupe rule from the station service**
   (`LogContext`). Written so by the rule decided on audio for the profile's values; the
   dial and the dupe rule are radio control's and the strategies' facts, for which the
   same reasoning (M5.3) was applied and not confirmed by you. The other way is that qso
   puts them into `FinishedContact`. Recommendation: as written.
4. **Decided by rule (M5.8) and carried out.** `LoggedContactPort`, a port of its own for what the log gives udp, with a change of
   one line in `Station.sysml`. Recommendation: yes; the connection was typed by qso's
   hand-over, whose answer (`LogAnswer`) udp never gives.
5. **Decided by rule (a case is divided where its tests differ; the next free number).** CL-010-18, the one new identity. Recommendation: keep the split; TC-011-001 and
   TC-011-002 then verify one clause each.
6. **Decided by precedent (a size stays, as the profile's `profileHttpMaxBytes`).** `historyPageBytesMax` (16,384) stands in the log's limits although it is a size on
   the wire: the log cuts the page by it. Recommendation: keep it here and let the
   station link refer to it.
7. **Answered (operator 2026-11-16): no extra keeping. A record is tried again a few times within a short time (a short blockage of the file) and then given up; `logPendingMax`, `retrySeconds` and `logQueueFull` left; TC-011-001 (e) left, (m) planned. Work for the code: `LOG_PENDING_MAX`, the queue and `LOG_RETRY` in `contact_http.rs`.** A waiting record is lost when the station stops. Stated as the code does it. A
   finished contact whose record could not be written is then gone without a trace in the
   logbook. Recommendation: keep the sentence, and take it up as a product question when
   the tree is on main.

## Not done, and what is not sure

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted.
- `FinishedContact`, CL-085-02 and the rest of `OperatingChain.sysml` are other parts' and
  were left.
- Read in full: `logbook.rs`, `logbook_http.rs`, `dxcc.rs`, `logbook_tests.rs`,
  `logbook_http_tests.rs`, `dxcc_tests.rs`, the old `Logbook.sysml`, `CountryFile.sysml`,
  `Contest.sysml`. Read in the parts that concern the log: `contact_http.rs` (the
  settings file, the log step, the snapshot), `contact.rs` (`log_fields`, `hand_over`,
  `OpenLog`, `complete`), `contact_http_tests.rs` (the record test and the five tests of
  the same-station rule), `log/udp_tests.rs` (the two log tests). Not read:
  `client/logbook.js`, `tests/*.cjs`, `contest.rs` beyond its `Qso` record, `strategy.rs`
  beyond its calls into the log.
- TC-011-001 (e) and (d) were written from `udp_tests.rs` lines read in two pieces; the
  lines between were read.
- The sentence "Ranking is given the set made last at once" describes `worked_latest`;
  `strategy.rs` also calls the waiting form `worked_set`. Which call ranking uses where
  was not read.
- The validator accepts the files; it does not show that `Station.sysml` still fits. It
  does not until the one line above is changed.

## Decided by the operator (2026-11-15)

| Line | Answer | Done |
|---|---|---|
| 1 | the contest counting goes to ranking, `ContestRanking.sysml` | handover row to ranking; open point 2 of the finished model is answered |
| 2 | ranking puts the entity, the new-flags and the worked status on a decoded record | handover row to ranking |
| 3 | the log learns callsign, locator, dial and dupe rule from the station service | `LogContext` stays |

Open: lines 4 to 7.

## Decided by the operator (2026-11-16): the logbook is immutable

The logbook is appended to and read; a stored record is not changed (WSJT-X appends to
`wsjtx_log.adi` and changes no record, `WorkedBefore::add`). Log QSO stays (as WSJT-X): it
logs a running QSO once and closes it.

| Point | Model | Difference in the code |
|---|---|---|
| A contact handed over again with other fields | `DirectLog`: a contactId the logbook holds changes nothing; the replacement in place left; TC-010-018 (i) lost its last sentence; CL-010-04 `partial` | `logbook.rs` `put` (`LogOutcome::Replaced`) replaces the record; `logbook_tests.rs` 1359 to 1373 asserts it; `QsoControl.sysml` (taken over) still names "replaced" in the contact's log outcome |
| Confirmations from an ADIF file on present records | unchanged so far | open: the second conflict with an immutable logbook (`Logbook.sysml` CL-010-18, 409 to 422) |

### Log QSO resends the last QSO (operator 2026-11-16)

Log QSO is the operator's button to send the last QSO record again to the logging program
outside, for a logger that was not running when the QSO was logged. It writes nothing to
the logbook. Logging happens only automatically, when a QSO completes; an unfinished QSO is
not logged.

| Model | Difference in the code |
|---|---|
| New CL-010-19 with `ResendRule` (status `target`); `ResendLast` and `Resent` on `LogControlPort`; `LoggedContact` (in `OperatingChain.sysml`) is also the newest QSO again on Log QSO; TC-011-001 verifies CL-010-19 by the planned line (n); `Udp.sysml` TC-112-005 (h) shortened, planned (j) | the button `contact-log` (Alt+Q, `client/contact.js` 34, 227, 700) sends `open_log`, which hands a running QSO to the log and closes it (`contact.rs` `LogKind::LogQso`, `contact_http.rs` 719 to 754); no resend exists |
| `DirectLog`: the sentence on a Log QSO after completion left; the marker on `FinishedContact` no longer asks whether a contact came by Log QSO | `contact_http.rs` 722 to 726 |
| TC-011-001 (c) (W1AW closed by Log QSO) left, (b) without the Log QSO, (d) two records; TC-085-001 (d) left; TC-085-002 (g) without the QSO closed by Log QSO | the bound tests still assert the old behaviour: `udp_tests.rs::tc_011_001_...`, `contact_http_tests.rs::tc_085_001_log_qso_pending_records_and_restart` and `tc_085_001_the_same_station_in_a_row_is_not_logged` |

Handover: qso loses the Log QSO hand-over (handover row "When a contact is handed to the
log": only at completion); the station service passes the operator's Log QSO to the log as
`ResendLast`; the frontend's button keeps its name and key.

### Confirmations accrue (operator 2026-11-16)

The one exception to the immutable logbook: a confirmation from an ADIF file (LoTW, QSL
card, eQSL) is added to a stored record, never removed or lowered; QSO fields never change.
As the code does (`UpdateLogbook`); stated once in `Logbook`. WSJT-X has no confirmations.

### One logbook for the operator's stations (operator 2026-11-16)

`contacts.adi` and `cty.dat` lie in the operator's folder; up to six stations append to
the logbook under the file's lock and take in the others' records before they use it
(`Logbook`, `ProfileCountryFile`, `LogContext::folder`). The `@DiffersFromSource` "the
logbook writes the whole file anew" left: a record is appended, as WSJT-X does.
Difference in the code: the logbook lies in each profile's folder, every change writes
it whole, no lock between stations.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-011-001 (`Logbook.sysml`): a fault of the file that lasts beyond the tries again: the contact is given up, the logbook does not hold it, and it is not given.
- TC-011-001 (`Logbook.sysml`): after (a), a ResendLast: the record of K1ABC is given once more, Resent names its contact, contacts.adi is byte for byte as before. On an empty logbook: nothing is given, Resent has no contactId.
- TC-011-003 (`Logbook.sysml`): the US state of a call, and the QSOs of a ContestPeriod.


## Done: cty.dat is downloaded by the settings function (operator 2026-11-16, "Download, as WSJT-X")

| Element | What changed |
|---|---|
| `interfaces/external/CountryFiles.sysml` (new; M2.1 and `Context.sysml` name it) | `CtyQuery` (the source of WSJT-X), `CtyDownload` (`bytesMax` 1048576), `CountryFilesPort`, `CountryFiles` |
| CL-055-06 (new, `ProfileDocument.sysml`) | `CountryFileFetch`, `CountryFileStore` (cty.dat in the operator's folder, read by `CountryFile`); target, no test |
| `ProfileAccess` | `UpdateCountryFile`, `DefinitionsSnapshot::countryFile` and `countryFileUnusable`, `SaveRefusal::invalid_country_file` |
| CL-055-03 (`CountryFile.sysml`, log) | uses the file the settings function keeps; `ProfileCountryFile` says only which file is in use; partial |
| `LogControl` | `ReplaceCountryFile` carries the profile's file; `invalidCty`, `LogRefused::line`, `countryFileBytesMax`, `uploadUnreadable` gone; `CountryFileSource` bundled, downloaded |
| TC-055-003 | not carried: its test uploads a file |

Work for the code: no download (dxcc.rs takes an upload over the logbook routes); the check and the
file are the log's in the code.
