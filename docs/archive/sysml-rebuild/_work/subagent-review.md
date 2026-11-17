# Reading the subagent parts against their reports

Item 1 of "Next" in `START-HERE.md`: the main session reads the model files of each part a
subagent built against the part's report, and the code where a sentence is in doubt. What a
rule decides is repaired and listed; what no rule decides goes to the operator.

## log

Read whole: `Log.sysml`, `Logbook.sysml`, `CountryFile.sysml`, `LogControl.sysml`, the log's
ends in `OperatingChain.sysml`. The files match the report's tables (identities, markers,
limits, renamed elements). `Station.sysml` and `backend/udp/Udp.sysml` carry the change of
`LoggedContactPort` the report asked for.

| # | Found | Done |
|---|---|---|
| 1 | The marker on `LogService` (port `contacts`) said the port's items have no content. `ProfileAccess` now carries `ProfileFolder`; the handover row of the profile says the marker is answered. | Marker and its import removed. |
| 2 | The marker on `PeriodQsos` asked who holds the counting rules; the operator answered (ranking, `ContestCount`). | Marker and its import removed. |
| 3 | The udp row "the activity of a record is the log's" was not taken up: the log was built before udp. The code compares two records of one contact by the fields call to state only (`first_difference`), so a save that differs in the activity only is `alreadySaved`; the model said "the same fields", which includes `activity`. | One sentence in `LogRecord`: which features are compared. No new identity (M6.4). Handover row marked. |
| 4 | TC-011-001 (h) "a profile without a locator" is short for a record that carries a locator while the profile has none (`validate_record`: `my_gridsquare` must equal the profile's locator). `LogRecord::myGridsquare` says so. | Left. |
| 5 | The log's port `contacts` is typed by the whole `ProfileAccess`, which also carries the save of the station config and of the hidden store; the log uses only `folder`. | For the profile part (a narrower port); listed, not changed. **Answered 2026-11-15: the connections went; the folder comes with each part's context.** |

`part_done.py log` passes after the changes. Open for the operator: report lines 4 to 7
(line 4 is already carried out in `Station.sysml` and in udp's port).

## spots

Read whole: `Spots.sysml`, `HearingFeed.sysml`, `Hearing.sysml`, `PskReporter.sysml`, and
the tests of `pskr_tests.rs` that TC-039-020 rests on. The files match the report as
changed by its two later sections (the control interface, the settings): `FeedSwitches`
holds the rule, `SpotsConfig` the two switches, no file of spots' own and no refusal.

| # | Found | Done |
|---|---|---|
| 1 | TC-039-020 was bound to the whole of `pskr_tests.rs`, which also holds the tests of TC-039-052, TC-039-048 and the routes handed over to the station link. | Bound to the seven tests that show (a) to (h), each read. |
| 2 | TC-039-048 has the letters (a), (b), (d), (e): (c) went with the settings. | Left; the report says so. |

`part_done.py spots` passes. Open for the operator: report line 3 (one `HearingReport`
for all three readers); the allocation of FR-027 to spots.

## udp

Read whole: `backend/udp/Udp.sysml`, `interfaces/external/Udp.sysml`. The files match the
report as changed by its later sections (the T/R period follows WSJT-X, `PeriodView::job`,
the settings: `UdpConfiguration` is the configuration, no file, no revision, no refusal).

| # | Found | Done |
|---|---|---|
| 1 | `OutboundRules` and `LoggedFields` said again when the log gives a record ("stored for the first time; a record stored already and records from an ADIF file send none"). That is the log's fact (`LoggedContact`, `DirectLog`, `SaveContact`, `UpdateLogbook`); M1.4. | Both say "for each LoggedContact" now. |
| 2 | Eleven of the twelve test cases are bound to the whole of `server/src/log/udp_tests.rs`, which also holds the log's two tests of TC-011-001 and TC-011-002. The method allows a whole file that carries the case's number. | Left; listed. |

`part_done.py udp` passes. Open for the operator: report lines 1, 2, 4, 5.

## transmit

Read whole: `Transmit.sysml`, `Schedule.sysml`, `TransmitState.sysml`, `TxLevel.sysml`,
`TransmitControl.sysml`, and the transmit ends of `OperatingChain.sysml`. The part's own
files match the report as changed by its two later sections (no radio authorization; the
settings: `TransmitConfig`, `LevelFound`, no `SetWatchdogs`, no `ManualLevel`, no file).
`port control : Keying` is written, as the report's first item for the main session asked.

| # | Found | Done |
|---|---|---|
| 1 | Report item 3 for the main session was not carried out. `TransmitControl` says the connection from qso carries the contact's commands "with the same items", but `MessageToSendPort` carried the request only (M1.3: a sentence without its skeleton). | `MessageToSendPort` carries `Arm`, `Disarm`, `Abort`, `SetTune`, `WatchdogStop`, `SendCount`, `StepBegins` and takes `CommandAnswer`, `TransmitOutcome`, `TransmitStatus`, imported by name from `TransmitControl` (M3.4 allows it). |
| 2 | `OperatingChain` held a second `TransmitRefusal`, with `notAuthorized`, which the operator removed from the product; `StartAnswer` named `notAuthorized`. | The enumeration is gone; `StartAnswer` uses `WstxTransmitControl::TransmitRefusal`; `notAuthorized` left its text (M1.4). |
| 3 | The text of `TransmitRequest` restated `Admission` and named `TransmitAuthority`, `PackMessage`, `PlanTransmitStart`, `TransmitTiming` (all gone) and an issue number. | One sentence that names `Admission` and `Transmission` as the rules (M1.4, M7.4). |
| 4 | The import `WstxRequirements::ImplementationState` (for CL-085-02, qso's) did not resolve; the log's report found it. | `ModelBindings::ImplementationState`. The validator reports no error in `OperatingChain.sysml` now; `check.py` 17 findings, all on qso's and auto's old elements (`CL-085-02`, `BusyPartner`). |

`part_done.py` passes for all thirteen parts after the change. Open for the operator:
report lines 2 to 12 (line 1 is answered; line 2 is the chain carrying the contact's
commands, which item 1 above now writes as the rule M5.7 says).

## radioControl

Read whole: the part file, `CatControl.sysml`, `RadioFacts.sysml`, `CatLifecycle.sysml`,
`RadioSetup.sysml`, `RadioControl.sysml` (interface), `Keying.sysml`, `Cat.sysml`,
`RadioProperties.sysml`. The files match the report as changed by its two later sections
(no permission, grant or safety revision; the settings: `RadioConfig`, `RadioRecords`,
`RadioMemory`, no file of its own). The lines the report gave for `Station.sysml` and for
the transmit and Flex ports are carried out.

| # | Found | Done |
|---|---|---|
| 1 | The port `RadioControl` had two items named `kept`: the `RadioMemory` the station service gives and the `RadioKept` answer to `DiscoverRadio` (the validator warned "Duplicate of other owned member name"). | The answer is `radioKept`; `kept` and `keep` stay the pair of `RadioMemory`, as in `AudioControl`. |
| 2 | Most cases are bound to whole files that several cases share (`server/tests/radio_control.rs`, `radio_setup_tests.rs`, `setup_tests.rs`, `cat_lifecycle_tests.rs`), and TC-022-009 to `auth_tests.rs`, the file of the radio authorization the operator removed. | Left; listed. |
| 3 | TC-044-002 (d) states which endpoints are at the radio's place, a rule of audio's `RadioPlace`; the test stands in radio control's `setup_tests.rs`. The report proposed that audio's TC-044-006 take it up. | Left for the operator's reading of audio; listed. |
| 4 | `MeterReadings` (`poPct`, `swrTimesTen`) and transmit's `MeterView` (`po_pct`, `swr_x10`) name the same values twice; the second carries the code's wire names in transmit's status. | **Repaired 2026-11-17 (M1.4):** `MeterView` removed; `TxLevelStatus::meters` is a `MeterReadings`. |

`part_done.py radioControl` passes. Open for the operator: report lines 1, 2, 4, 5, 6, 8,
9, 10, 11, 12 (the reconnect on a renamed station), 13, and whether radio control waits for
the undo record to come back before it writes.

## profile

Read whole: `Profile.sysml`, `Recordings.sysml`, `ProfileAccess.sysml`,
`RecordingTransfer.sysml`. The files match the report as changed by its later sections
(the settings: `StationConfig`, `StationMemory`, `KeepMemory` with CL-005-06; the
continent and the CQ words in `ProfileConfig`, `RankingConfig` gone).

| # | Found | Done |
|---|---|---|
| 1 | The marker on `PersistedProfile` said only the station service and the log are joined to the profile; operating is joined too (port `definitions`, the strategies file). | The marker names the three. |
| 2 | The ports `contacts` and `definitions` are typed by the whole `ProfileAccess`; their text says only `ProfileFolder` crosses (see log, item 5). | Left: report line 2 asks whether these connections stay at all. **Answered 2026-11-15: the connections went; the folder comes with each part's context.** |
| 3 | `ImportChunk::bytes : Integer[1..2048]` writes the value of `RecordingLimits::rawChunkBytes` a second time, as a multiplicity. | **Repaired 2026-11-17 (M1.4):** `Integer[1..*]`, the limit in its doc. |
| 4 | `StationConfig` has no member yet for qso's configuration and the station service's own (Monitor off at startup); the handover rows to qso and station say they come with those parts. | Left. |

`part_done.py profile` passes. Open for the operator: report lines 1 to 8, the four
questions of its settings section (the revision of a save the station makes itself; the
file and form of the hidden store; the keys of the new configurations; whether a part waits
for its record to be kept).

## operating

Read whole: `Operating.sysml`, `backend/operating/Strategies.sysml`,
`interfaces/internal/Strategies.sysml`. The files match the report as changed by its last
section (the six decisions of issue 228 and the operator's answers a to h). The lines the
report gave for `Station.sysml` (the composition, the shares, `timeOperating`, the
allocation), for the profile's port `definitions` and for test 1 of `part_done.py` are
carried out.

| # | Found | Done |
|---|---|---|
| 1 | `@DetailTests` on `OperatingService` says the three test files cover "the evaluator of ranking and the runs of Auto": those are other parts' insides, not operating's detail tests (authoring rule 11). | **Repaired 2026-11-17:** covers names operating's own insides. |
| 2 | TC-039-003 (f) shows ranking's verdicts after a save; it stands here as the proof that the share reaches ranking (CL-097-10), as the report says. | Left. |

`part_done.py operating` passes. Open for the operator: report lines 2, 6, 7, 9, 10, and
answer a of the decisions section (the CQ word of an activity set by hand).

## ranking

Read whole: `Ranking.sysml`, `ValueOrder.sysml`, `ContestRanking.sysml`,
`IgnoreLists.sysml`, `MostWanted.sysml`, `Alert.sysml`, `WantedList.sysml`,
`RankingControl.sysml`, `ClubLog.sysml`, and the ranking ends of `OperatingChain.sysml`.
The files match the report as changed by its two later sections (the one ignore list of
20 entries, the three parts of a directed CQ, the continent and the CQ words in the station
config; `RankingConfig` gone; `RankingRules` from operating).

| # | Found | Done |
|---|---|---|
| 1 | `DecodedFacts` had no feature for the worked status: its type `WorkedStatus` stood in `OperatingChain.sysml`, which a control interface may not import (M3.4), so the item carried less than `DecodedEntity` says (M1.3). The report proposed the move. | `WorkedStatus` moved to `WstxLogControl` (the log makes it, beside `Continent` and `CallEntity`); `OperatingChain`, `ValueOrder` and `RankingControl` import it from there; `DecodedFacts::worked : WorkedStatus[0..1]`; the marker is gone. The log needed one verdict (`workedThisBandAndMode`, a text the tool does not read). Handover row marked. |
| 2 | `@DetailTests` on `RankingService` says the three test files cover "the saved strategies, their routes and the runs of Auto": operating's and auto's insides (as operating, item 1). | **Repaired 2026-11-17:** covers names ranking's own insides. |
| 3 | TC-063-006 (j) runs the count through the station with a logbook, so it also shows the log's `PeriodQsos`; the log's TC-011-003 (i) still says "Planned, no test yet" for the QSOs of a period. | Left; for the operator's reading. |
| 4 | `WantedList` is an element with only a marker: no code, no test. | Left: report line 2. |

`part_done.py` passes for all thirteen parts after the change. Open for the operator:
report lines 1 (answered by the operating part), 2, 3, 4, 5, 6, 7.

## Summary

Eight parts read. Repaired by rule: 12 points in 10 model files (log 3, spots 1, udp 1,
transmit 4, radioControl 1, profile 1, ranking 1), with one verdict in `parts.json` and two
handover rows marked. Listed and left: 15. No question to the operator came from the reading itself;
the open lines of the reports stand as they were, with the notes above.
