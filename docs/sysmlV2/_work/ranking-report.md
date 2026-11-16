# Report: the ranking part

2026-11-15. Built by a subagent beside transmit, radioControl and profile; the operator was
not asked. `part_done.py ranking` passes tests 1 to 5. What a rule decides is listed as
decided; what no rule decides is listed for the operator at the end and is not decided
here. Every figure is measured by a script (`measure.py` in the session's scratchpad folder
`ranking`; it reads only).

## What was written

| File | Content |
|---|---|
| `backend/operating/ranking/Ranking.sysml` | the part with six ports, its modules, its detail tests; one marker |
| `backend/operating/ranking/ValueOrder.sysml` | 6 clauses, 14 rule elements, 10 test cases: the verdict, directed CQs, what is new, the band and the filter, the order, the facts of a decoded record |
| `backend/operating/ranking/ContestRanking.sysml` | 3 clauses, 4 rule elements, 3 test cases: the CQ word of the activity, the count of a contest period, the verdict and the order under a contest |
| `backend/operating/ranking/IgnoreLists.sysml` | 1 clause, 1 rule element, 2 test cases |
| `backend/operating/ranking/MostWanted.sysml` | 1 clause, 1 rule element, 1 test case |
| `backend/operating/ranking/Alert.sysml` | 1 clause, 1 rule element, 1 test case; one `@Conflict` |
| `backend/operating/ranking/WantedList.sysml` | new file: one element with one marker and nothing else (no code, no test) |
| `interfaces/internal/RankingControl.sysml` | 14 items (8 from the station service, 6 from ranking), 17 attribute definitions, 11 enumerations, the port and the interface |
| `interfaces/internal/Strategies.sysml` | the strategy as data: 7 attribute definitions, 7 enumerations; no clause; one marker |
| `interfaces/external/ClubLog.sysml` | the query and the download, the port and the interface |
| `interfaces/internal/OperatingChain.sysml` | only `RankedActivityPort` and `RankedActivity` (two doc sentences added); everything else untouched |

In all: 12 clauses, 17 test cases with 100 lettered conditions, bound to 40 named tests in
5 files.

## Identities

29 identities stand in the part: the 17 the ledger named for ranking, 11 taken from "TO
PLACE", 1 new.

| Identity | Old place | New place | Note |
|---|---|---|---|
| CL-039-02 | ranking/ValueOrder | ValueOrder | Keeps its core: one verdict for each decoded message. The route and "the browser never evaluates" are handed over. |
| CL-039-03 | ranking/ValueOrder | ValueOrder | The directive rule. The operator's selection warning is qso's. |
| CL-042-01 | ranking/ValueOrder | ValueOrder | What is new, from the log. |
| CL-097-02 | ranking/ValueOrder | ValueOrder | Band and filter. Was `partial`; every line is built and tested: `implemented`. |
| CL-097-03 | ranking/ValueOrder | ValueOrder | The order. Was `partial`: `implemented`. |
| TC-039-040, TC-097-004, -005, -007, -008 | ranking/ValueOrder | ValueOrder | Rewritten from their tests. TC-097-004 keeps the evaluator's condition; the run test is auto's. TC-097-005 and -008 were `partial`; every condition written has a test. |
| CL-042-02, TC-125-001 | ranking/IgnoreLists | IgnoreLists | Rewritten. The run and pounce tests of TC-125-001 are auto's. |
| CL-039-10, TC-039-031 | ranking/MostWanted | MostWanted | Rewritten. |
| CL-042-04 | ranking/Alert | Alert | Rewritten from `alert_step`. |
| CL-063-02, CL-063-04 | ranking/ContestRanking | ContestRanking | Derive from FR-026 only (were FR-026 and FR-024). |
| **CL-063-09** | new | ContestRanking | The count and the tally of a contest period, from CL-063-03 and old `ContestLog` (operator 2026-11-15). The next free number of the series (CL-063-08 and TC-063-012 were the highest in the old model, the code and the tests; measured by a search). |
| CL-055-02, TC-055-002 | qso/QsoData (TO PLACE) | ValueOrder | Operator 2026-11-15: ranking puts entity, new-flags and worked status on a decoded record. Derives from FR-026. |
| TC-039-002 | qso/QsoData (TO PLACE) | ValueOrder | Verified CL-039-02, -03, -24; its three evaluator tests show ranking's two clauses. The selection-warning test is qso's. |
| TC-039-030 | qso/QsoData (TO PLACE) | ValueOrder | Verified CL-039-01, -02, -05; its six evaluator tests in `strategy_tests.rs` show the filter. The log bound the two `dxcc_tests.rs` tests of this number to TC-011-003. The upgrade test of this number is the strategy store's. |
| TC-042-001 | qso/QsoData (TO PLACE) | ValueOrder | Verified CL-042-01 (ranking's) and CL-042-05 (the editor). |
| TC-097-006 | qso/QsoData (TO PLACE) | ValueOrder | Verified CL-097-02 (ranking's) and CL-097-09. The two run tests of this number are auto's. |
| TC-042-002 | qso/QsoData (TO PLACE) | IgnoreLists | Verified CL-042-02 (ranking's) and CL-042-06. The two run tests and the configuration test are not bound here. |
| TC-042-006 | qso/QsoData (TO PLACE) | Alert | Verified CL-042-04 (ranking's) and CL-042-07. |
| TC-063-004 | qso/QsoData (TO PLACE) | ContestRanking | Verified CL-063-02 (ranking's) and CL-063-07. The selection test is qso's. |
| TC-063-005, TC-063-006 | qso/QsoData (TO PLACE) | ContestRanking | The points, the count, the dupes and the verdicts: the counting the operator gave to ranking. |

### "TO PLACE": looked through and left

164 identities were "TO PLACE"; 153 are left. Those of the series 039, 042, 055, 063, 097
and 125 that I read and did not take, with the reason:

| Identities | Not ranking's because |
|---|---|
| CL-039-01, CL-039-11, CL-097-01, CL-097-07, CL-097-08, CL-063-01, CL-063-03; TC-039-001, TC-039-003, TC-039-032, TC-097-001, -002, -003, -015, TC-063-001, -002, -003, -007 | They promise defining, saving, selecting and reading strategies and contest profiles. The record on #53 says the station service is the gate for that and the profile keeps them; ranking is handed only its group. Line 1 for the operator. Their data stands in `Strategies.sysml`. |
| CL-039-05, -21, -22, -23, CL-097-04, -05, -06, CL-063-05, -06, CL-042-03, CL-039-08, -09 and their cases (TC-039-004, -009, -010, -022, -033, -042 to -051, TC-042-004, TC-063-009 to -011, TC-097-009 to -013, -017, -018) | what Auto executes (M5.7), or qso's Hold Tx and busy partner |
| CL-039-24, CL-063-07, CL-097-09 | the operator's selection of a CQ that is not for the station: qso and the frontend |
| CL-039-25, CL-042-05, CL-042-06, CL-042-07, CL-063-08; TC-039-006, TC-042-003, -005, -007, TC-125-002, TC-063-008, -012, TC-097-014, -019, TC-055-004 | what the browser shows |
| CL-039-07, TC-039-008 | `target`, no code |
| TC-039-007, TC-039-047, TC-055-005, TC-097-016 | planned live cases without a test |

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Old `auto/Strategy.sysml` | M5.7: a strategy defines, ranking orders, Auto executes | Nothing of it arrives in ranking. Its 13 elements (`PskCase`, `Pounce`, `ManualIntervention`, `StrategyWatchdog`, `TxMoveRule`, `BusyPause`, `LeaveCountLabel`, `StartedQso`, `LeaveRule`, `QuietTime`, `CqWhenNoTarget`, `FreeTxSlot`, `WatchdogFromOperator`) are handed to auto. What a strategy defines for them (ranges and built-in values) stands in `WstxStrategies::Strategy`. Its package text is a decision list: history. |
| `Strategies.sysml` holds data and no clause | #53 (consolidated target): "a strategy is data, not a part"; M6.2 and M2.1 name no function file for its promises | The definition clauses stay "TO PLACE"; line 1 for the operator. |
| The contest counting is a clause of its own | M6.4: shown by other tests (TC-063-005) and changed for another reason (the contest's rules) than the verdict | CL-063-09. |
| Each clause derives from FR-026 only | decided on the clock; `Station.sysml` gives FR-026 to ranking | FR-024 dropped from CL-063-02 and CL-063-04; FR-010 and FR-011 from CL-055-02. |
| How ranking learns call, locator, band, mode, the set continent and the activity's CQ word | M5.3; decided on audio | `RankingContext`. In the code `strategy::station` reads them itself. |
| The active strategy reaches ranking as its ranking group | #53: the station service hands each group to its reader | `RankingRules`, `StrategyRules`. In the code the store lives in ranking's module. |
| `Continent` | operator 2026-11-15 | `RankingControl` and `Strategies` import `WstxLogControl::Continent`. |
| The WPX prefix, the entity of a call, the continent of a call | the log's (built): `WorkedCategory::prefix`, `EntityOfCall` | `WpxPrefix` and `ContinentOfCall` are not written in ranking. |
| The CQ word of a special activity | the activity is qso's; a part does not import a part | `RankingContext::activityCqWord`; the old enumeration `ActivityWord` is not written. |
| Routes, status codes, wire keys, body sizes, the two events | M4.7 | Not written; handed to the station link. |
| The texts of the why | a displayed text is a promise when a test asserts it | Written once, in the rule sentence of the test that gives it. |
| Bounds | values are sorted; one fact, one place | 15 values stay (the nine of `RankingLimits`, `sessionIgnoreMinutes`, the two SNR bounds, `strategiesMax`, `periodDaysMax`, `entriesMax`); the multiplicities refer to them. `BODY_MAX` is the station link's; the size of `most_wanted.json` is inside. The 340 entity numbers are a value of TC-039-031. |
| Status | the code decides | CL-097-02 and CL-097-03 are `implemented`. |
| `WantedList.sysml` | no evidence, no statement; M2.1 names the file | One element, one marker. Line 2 for the operator. |
| The modes handover row on hashed calls | the code decides | A hashed sender has no verdict and no worked status; a filled-in hash has an entity and flags (`tc_055_002_every_decoded_sender_call_resolves`). The row said "no call" for both. |

## Dropped as code or as history

- The decision lists of old `Strategy.sysml` and `Contest.sysml`, all `satisfy` and
  `dependency` lines, dates, issue and question numbers.
- The caches of worked sets and of the contest count, the build threads, "off the station
  step", "on a blocking thread", the 50 ms step.
- The upgrade of saved files (schema 1 to 3) and the renaming of names that collide with a
  built-in: the store's, handed over.
- The fetch's timeout of 20 s and its read limit; the request line of the fetch.
- The lock order and the test seam of the fetch.
- `Maidenhead` arithmetic, the haversine formula as code; the model says "great circle on a
  sphere of 6371 km".
- The table from entity names to ADIF numbers (340 entries): the sources are named.
- "Evaluation never keys", "ignore lists never key", "alerts never select, arm or key":
  ranking has no connection over which it could.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| `WstxRankingControl::WorkedWindow` | `WorkedSince` (the operating chain has the log's `WorkedWindow`) | comment in `strategy.rs` |
| `RankingKeys::contest` | `StrategyRules::contest : ContestInForce` | none |
| `RankingRules` with `keys`, `ignore`, `mostWanted`, `evaluate`, `ignoreCommand`, two Booleans | `RankingRules` (active, permanent list, minutes) and one item for each command | `StationLink.sysml` (taken over) |
| `IgnoreLists` (attribute definition) | gone: `RankingRules::permanentIgnore`, `RankingState::sessionIgnore`, `RankingLimits` | `StationLink.sysml` line 365; comment in `strategy.rs` |
| `MostWantedList`, `MostWantedEntry` | gone: `WstxClubLog::MostWantedDownload`, `MostWantedRow`; `entriesMax` there | comments in `strategy.rs`, `most_wanted.rs`; `StationLink.sysml` (text) |
| `Alert`, `EvaluateRequest`, `EvaluateReply`, `IgnoreCommand`, `RankingState` (attribute definitions) | items | `StationLink.sysml` types attributes by them |
| `Alert::historyMax`, `dedupeMinutes`; `EvaluateRequest::recordsMax`; `IgnoreLists::sessionEntriesMax`; `CountryList::entriesMax`; `CqTargetList::entriesMax` | `RankingLimits::alertHistoryMax`, `alertDedupeMinutes`, `evaluateMax`, `sessionIgnoreMax`, `countriesMax`, `cqTargetsMax` (the code's names) | none |
| `calc def NewNeeded`, `StationDistance`, `MyContinent`, `DirectedCqRule` | attribute definitions of the same names | comments in `strategy.rs`, `dxcc.rs`, `contact_http.rs` |
| `calc def WpxPrefix`, `ContinentOfCall`, `UsStateOf`, `SaneCall`; `enum ActivityWord`; `WorkedWindowRule` | not written: the log's, or a sentence in `UsStateFilterRule`, `Candidate`, `NewNeeded`, `Evaluation` | comments in `strategy.rs`, `dxcc.rs` |
| `WstxLogControl::DecodedEntity` (gone with the log) | `WstxValueOrder::DecodedEntity`, `WstxRankingControl::DecodedFacts` | comment in `dxcc.rs` |
| `WstxContest::ContestLog` | `WstxContestRanking::ContestCount` | comments in `contest.rs`, `strategy.rs` |
| `WstxStrategies::StrategyHttp`, `ContestHttp`, `ContestPrompt`, `ProfileTable` | not written (routes, the browser); `ContestTable` | `AutoControl.sysml` names `ContestPrompt`; comments in `strategy.rs`, `contest.rs` |
| `Strategy::leaveCalls = 4` and the other defaults | no default on the feature; the values stand in `BuiltinStrategies` | none |

## Negative statements

| Old statement | Result |
|---|---|
| "Decode order is never a ranking" | kept in the clause as "never by the order in which they were decoded": a function exists that orders, and TC-039-040 (i) and TC-097-008 (d) show it |
| "The browser never evaluates a strategy itself" | dropped: the frontend's |
| "It never switches bands" (a strategy) | dropped: no such function in ranking |
| "An alert never transmits, selects, arms or changes a contact" | dropped: ranking has no such connection |
| "A dupe never has a rank" | positive: the dupe test of `ContestVerdictRule` |
| "An ignored sender is never a candidate or a caller" | positive: no rank, not grey, also as a caller |
| "No automatic refresh, nothing bundled, no upload" (Most Wanted) | dropped: no such function |
| "The licence data and the grid are not used" (US state) | dropped: the rule says what is used |
| "No alert is recorded for a contest" | `@Conflict`: the code records them (line 3) |
| "A manual Reply of an ignored station is not refused" | handed to qso |

## Settled from the code

- **A caller is not asked the callsign guard.** The old text listed the guard for callers.
- **The why of a caller off the bands** has no "calls my call" before it.
- **The included CQ target list does not lift the grey under a contest strategy**; there
  only the list's own line is applied afterwards.
- **`snr_bucket`**: 0 dB is in the middle group, -10 dB too.
- **A draft of class contest without its contest in force** is counted over every QSO of
  the logbook, not "from now".
- **The Most Wanted suffix** is given only while `most_wanted` is a criterion.
- **Unranked records** follow in the order of the records under class strategy and in the
  order of their numbers under a contest.
- **The km of the shown entity** is rounded; the distance of the order criterion is cut
  off, and uses the message's grid first.
- **Worked status**: only a standard message from a call that is no hash; with the mode of
  the receive job, not the operating mode.
- **Flags**: none for a DXpedition message, although it gets an entity.
- **Alert without a period start**: the time of judging is taken.
- **The session list's remaining time** is given in whole seconds, rounded up.
- **Of several patterns that match**, the first in character order is named.
- **Field Day points** of a decoded sender are those of a digital mode.

## What the comparison with the code found

| Finding | Result |
|---|---|
| The strategy store, its routes and the Auto toggle stand in `strategy.rs`, ranking's module | work for the code; the names concerned have no model element here (`BODY_MAX`: verdict "another part") |
| `dxcc::annotate` and the route `/receive/results` make the decoded facts | work for the code (operator 2026-11-15); CL-055-02 names `dxcc.rs` |
| Ranking reads profile, band, mode, activity, the logbook and the feed itself (`strategy::station`) | work for the code |
| All enumerations of the three modules are `pub(crate)`; the tool reads none | 26 literals matched by wire names or by `dxcc::Category`, 41 by reading |
| The tool keys a literal by its name | `ValueCriterion::new_call` and ten more fall together with `NewFlag`; `RegionKind::all` with `WindowKind::all`; `NewPer::band` and `NewWhat::call` with `DupeRule`; each compared by reading (`CRITERIA`, `FLAGS`, `PERS`, `WHATS`) and said in its verdict |
| `ALERT_DEDUPE_MS` is a product, `PERIOD_MAX_MS` private, the SNR bounds are literals in a `match` | 4 values matched by reading |
| Two constants `FILE_BYTES_MAX` (dxcc.rs, most_wanted.rs) | one verdict, which names both |

Test 4: 37 lines matched by the tool (11 values, 26 literals), 47 with a verdict: 45
matched by reading, 1 another part, 1 inside.

## Edge cases and their homes

| Case | Home |
|---|---|
| no entity; unknown band; no worked set; no grid; a gridless QSO | `NewNeeded`; TC-042-001 (d), (e), TC-039-030 (a) |
| unknown SNR against a minimum | `Candidate`; TC-039-030 (c) |
| unknown continent of the station or the sender | `DirectedCqRule`; TC-039-002 (a), (d) |
| a call without an entity and a locator | `MyContinent`; TC-039-002 (f) |
| exact tie of SNR and frequency | `ValueOrder`; TC-039-040 (i) |
| empty order | TC-039-040 (f) |
| a caller that fails each line | `CallerOfMyCall`; TC-097-007 (c) |
| the 65th session entry; an entry at its end; unknown band to unknown band | `IgnoreListsRule`; TC-042-002 (b) to (d) |
| a pattern of stars only; a call on both lists | TC-125-001 (a), (c) |
| a list with 1001 entries, a number twice, a failed fetch, an unreadable file | `MostWantedListRule`; TC-039-031 (a), (e), (f) |
| the list cannot be written | `MostWantedListRule`; no test |
| the 101st alert; exactly 10 minutes; another band; clear | `AlertRule`; TC-042-006 (c) to (f) |
| a QSO at the start and at the end of the period; a QSO without a band or grid | `ContestCount`; TC-063-006 (a), (b) |
| logbook unavailable under a contest | `ContestVerdictRule`; TC-063-006 (g) |
| a request for another job; without a strategy | `Evaluation`; no condition here (the route test TC-039-003 shows both) |
| more than 2048 records in a request | `EvaluateRequest`; the refusal is the route's |
| two commands at once | serialised by the code; rare and harmless, not written |

## Not carried over

| What | Why |
|---|---|
| The 13 elements of old `auto/Strategy.sysml` (49,034 characters with the package text) | auto's |
| `StrategyHttp`, `ContestHttp`, `ContestPrompt` and the upgrade text of `StrategyConfiguration` | station link, frontend, the store |
| Old conditions on status codes, Origin, the MCP principal, the former upload route | station link |
| TC-097-005 (d) "an undated record counts only for any time" | the log's rule (`WorkedBeforeQuery`: a set of a window counts the records whose date lies in it) |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| `backend/operating/ranking/` (6 files, now 7) | 54,126 | 75,143 |
| `interfaces/internal/RankingControl.sysml` | 11,435 | 20,913 |
| `interfaces/internal/Strategies.sysml` | 25,203 | 13,383 |
| `interfaces/external/ClubLog.sysml` | 1,328 | 2,088 |
| the 11 identities that come in from `qso/QsoData.sysml` | 19,066 | in the files above |
| `ContestLog` of old `log/Contest.sysml` | 1,520 | in `ContestRanking.sysml` |
| ranking's elements in `OperatingChain.sysml` | 246 | 349 |
| Total | 112,924 | 111,876 |

The part is as large as its old text. Where the size sits:

| Content | Characters | Old |
|---|---|---|
| The 17 test cases, 100 lettered conditions | 35,931 | 30,044 for the same 17 |
| The 12 clauses | 4,596 | 10,784 for eleven |
| Imports | 5,487 | |
| Everything else: rule elements, items, enumerations, ports | 65,862 | |

`RankingControl.sysml` grew because the old file had two general items and one attribute;
it now has one item for each command and each answer, with the context and the decoded
facts that were not in it. `Strategies.sysml` shrank by the routes, the prompt, the upgrade
text and the history.

## Checks

- `python docs/sysmlV2/_work/part_done.py ranking`: all five tests pass: 29 identities, no
  finding in 10 files, no validator error in them, 37 names matched and 47 lines with a
  verdict, 17 test cases with their tests. `part_done.py log` and `spots` still pass.
- The validator on the whole new tree reports 63 errors, none in ranking's ten files: 52
  in `Station.sysml` and 2 in `Context.sysml` (parts not built), 2 in `OperatingChain.sysml`
  (the old import of CL-085-02, as the log reported), 7 in `StationLink.sysml`. The 7 are
  new and come from this part: see "Changes needed outside".
- `check.py` on `OperatingChain.sysml`: 19 findings as before, none on ranking's lines.
- Tests bound: 40 named tests. Of the 138 tests of `strategy_tests.rs` 23 are bound, of the
  33 of `strategy97_tests.rs` 5, of the 10 of `contest_tests.rs` 5, of the 11 of
  `dxcc_tests.rs` 4, of the 3 of `most_wanted.rs` 3. The others show the store, the routes
  and the runs of Auto.
- `git status`: `docs/sysmlV2/` is the only change.

## The functional description

`_descriptions/ranking.md`, from the new files alone, 23,939 characters. It found these gaps:

| Gap | Settled how |
|---|---|
| `RankingState` had no command that asks for it, and the alert history none | `ReadRankingState`, `ReadAlerts` |
| The bounds stood twice, as a value and as a multiplicity | the multiplicities are open and name `RankingLimits` |
| When the facts of a record are given again | marker on `DecodedEntity` |
| The worked status has no feature in `DecodedFacts` | marker; a line for the main session |
| How ranking learns the entity nearest to a locator | marker on `MyContinent`; handover row to the log |
| The connection to the profile's folder | marker on `RankingService` |
| The special activity is a text in `ContestProfile` | left: qso's element is not built; handover row |
| The kinds of message ("standard", "Field Day exchange", ...) are named in text | left: they are the modes part's, reached through `ResultRecord` |

## Markers

| Where | Marker | Says |
|---|---|---|
| `RankingService` | `@NotStated` | the connection to the profile's folder |
| `Evaluation` | `@NotStated` | a ranked list for each period view, or when auto asks |
| `MyContinent` | `@NotStated` | the entity nearest to a locator |
| `DecodedEntity` | `@NotStated` | when the facts are given again |
| `DecodedFacts` | `@NotStated` | the feature for the worked status |
| `Strategy`, `StrategyConfiguration` | `NotStated` about both | which element holds the promises about the saved strategies |
| `WantedList` | `@NotStated` | the whole list |
| `AlertRule` | `@Conflict` | alerts under a strategy of class contest |
| `ContestCount`, `ContestValueOrder`, `DecodedEntity` | `@DiffersFromSource`, three | the contest's own log; the first decoded caller; where a decode is looked up |
| `CallerOfMyCall`, `DecodedEntity`, `ContestCount`, `MostWantedListRule`, `ContestTable`, `MostWantedDownload` | `@FollowsSource`, six | WSJT-X at the behaviour baseline; the contests' rules; ADIF and the country file; the Club Log service |

## Checked in WSJT-X (`D:\Github\wsjtx`, tag v3.3.0-beta6)

| Question | WSJT-X does |
|---|---|
| What is flagged as new on a decode? | `LogBook::match` (`logbook/logbook.cpp`): call, grid, country, continent, CQ zone, ITU zone; with highlighting by mode off the mode is left out; an unknown entity is not flagged. Called from the main window when a decode is printed (`widgets/mainwindow.cpp`). |
| Does it keep strategies? | No. It keeps whole configurations (`MultiSettings`). |
| Does it keep a list of wanted calls? | No. Its "Wanted" alert is one of the alert categories (`Configuration.cpp`, `alert_Wanted_`); Wait and Call watches one call. |
| Are alerts tied to a contest? | No. `alert_CQ_`, `alert_MyCall_`, `alert_DXCC_` and the others are settings of the configuration, whatever the activity. |
| Contest QSOs, dupes | with the logbook: `LogBook::contest_log()` (from the log's report; not read again). |

## Work for the code, when the new tree goes to main

- The store of the strategies, its routes and the Auto toggle leave ranking's module.
- Ranking takes call, locator, band, mode, the set continent and the activity's CQ word
  from the station service, and the active strategy as its ranking group.
- `dxcc::annotate` moves to ranking; the route only carries what ranking gives.
- The entity nearest to a locator is asked of the log.
- Whether auto asks the evaluator or is given a list for each period view (marker).
- Alerts under a contest strategy (`@Conflict`).
- Test tags: the tests of CL-063-09 say CL-063-03; `tc_039_030_each_goal_...` is bound to
  TC-042-001; the dxcc route tests `tc_011_003_receive_results_...` and `tc_055_006_...` are
  bound to TC-055-002; `tc_063_007_...` also to TC-063-006.
- Comments name `WstxRankingControl::IgnoreLists`, `MostWantedList`, `WorkedWindow`,
  `WstxContest::ContestLog`, `WstxValueOrder::WpxPrefix`, `UsStateOf`, `WorkedWindowRule`,
  `WstxLogControl::DecodedEntity`, `WstxStrategies::ProfileTable`, `ContestHttp`.
- No test reads a value from the model. No test shows a list that cannot be written.

## For the main session

### Handover rows (for `_work/handover.md`)

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| ranking | `cty.dat` (AD1C) and the most-wanted list. **Taken up:** the list is `WstxMostWanted::MostWantedListRule`, CL-039-10; `cty.dat` is the log's. | old `Context.sysml`, `ranking/ValueOrder`, `ranking/MostWanted` | top files |
| ranking | DXCC and worked-before treat a filled-in hash as no call; a frame whose sending call is a hash has no strategy facts. **Taken up, as the code does it:** a hashed sender has no verdict (`VerdictRule`) and no worked status; a filled-in hash has an entity and flags (`DecodedEntity`, TC-055-002 (e)). | CL-024-01, TC-024-002 | modes |
| ranking | CL-055-02 and TC-055-002. **Taken up:** `WstxValueOrder::DecodedEntity`, `WstxRankingControl::DecodedFacts`. | `LogControl::DecodedEntity` | log |
| ranking | Ranking asks the log on `WorkedBeforePort`. **Taken up:** `NewNeeded`, `UsStateFilterRule`, `ContestCount`; `Continent` is the log's. | `WorkedBeforeQuery`, `ValueOrder` | log |
| ranking | The criterion hears_us reads `HearingReport::heardBy`. **Taken up:** `ValueOrder`. | `ValueOrder`, `HearingFeed` | spots |
| ranking | The contest counting. **Taken up:** CL-063-09, `WstxContestRanking::ContestCount`, TC-063-005, TC-063-006. | old `log/Contest.sysml` `ContestLog` | log |
| station | The saved strategies: `strategy.json` beside `profile.json` (`{schema_version 4, profile_id, revision, configuration}`, at most 262144 bytes; a missing file is the default at revision 0; a foreign or malformed one gives no configuration and `invalid_configuration` until the next save); at most 16 strategies; one active or none; active and the contest selection are never saved, so none is active after a station start; a contest goes with an active strategy of class contest of the same contest; a built-in can be selected and not changed; a saved name that equals a built-in's reads renamed ("<name> copy", "copy 2", ...), listed once; files of schema 1, 2 and 3 are read by the upgrade and written as schema 4 by the next save; each refusal names its field path; the nine contest profiles and their period from the schedule rule. Clauses CL-039-01, CL-039-11, CL-097-01, CL-097-07, CL-097-08 (the value), CL-063-01, CL-063-03 with TC-039-001, TC-039-003, TC-039-032, TC-097-001 to -003, TC-097-015, TC-063-001 to -003, TC-063-007. The data stands in `WstxStrategies` (`Strategy`, `StrategyConfiguration`, `BuiltinStrategies`, `ContestTable`, `ContestProfile`, `ScheduleRule`, `ContestSelection`); the marker there waits for the home of these clauses (line 1 for the operator). | CL-039-01, CL-097-01, CL-063-01, `StrategyConfiguration`, `BuiltinStrategies` | ranking |
| station | The station service gives ranking `RankingContext` (the profile's call and locator, the station's band, the operating mode, the continent the operator set, the CQ word of the special activity) and `RankingRules` (the ranking group of the active strategy with its contest and period, the permanent ignore list, the session minutes), at station start and whenever one changes; it passes `EvaluateRequest`, `IgnoreCommand`, `ReadRankingState`, `ReadAlerts`, `ClearAlerts` and `UpdateMostWanted` and takes `RankedList`, `DecodedFacts`, `RankingState` and `Alert`. A session ignore change advances no revision of the strategy store. In the code ranking reads all of this itself (`strategy::station`, `Owner`). | CL-039-02, CL-042-02, `strategy.rs` | ranking |
| station link | Ranking's routes: `GET` and `PUT /strategy`, `POST /strategy/evaluate` (`{v, profile_id, boot_id, source_id, job_id, generation, first_sequence, next_sequence, strategy, explain}`; reply `{v, profile_id, boot_id, strategy, my_continent, verdicts, contest}`), `POST /strategy/ignore` (`{..., call, ignore}`), `GET /strategy/alerts`, `POST /strategy/alerts/clear`, `POST /strategy/most-wanted/download`, `GET /strategy/contests`; bodies at most 32768 bytes; the verdict's keys `sequence, rank, grey, why, dupe, new_multiplier, points`; the snapshot's `my_continent, derived_continent, session_ignore [{call, band, remaining_s}], most_wanted {date, entries, unmapped}, most_wanted_unreadable, most_wanted_attribution, builtin_strategies, configuration_note`; the alert's keys `id, utc, call, message, rule, band, mode, snr_db, dxcc`; refusals 409 `not_configured` (field `strategy` or `configuration`), 409 `stale_request` (`job_id`), 400 `invalid_request` `next_sequence` for more than 2048 records, 502 `download_failed` with `reason`, 503 `storage_unavailable`; an MCP principal is refused 401 for the download and the clear; the events `strategy.state` and `alert.state`. On a decoded record: `dxcc {name, cont, cq, itu, km}`, `flags` (the twelve `new_*` names, only the true ones), `worked_status`. | `StrategyHttp`, `ContestHttp`, CL-039-02, CL-042-02, CL-042-04, CL-039-10, CL-055-02 | ranking |
| auto | The 13 elements of old `auto/Strategy.sysml` are auto's: `PskCase`, `Pounce`, `ManualIntervention`, `StrategyWatchdog`, `TxMoveRule`, `BusyPause`, `LeaveCountLabel`, `StartedQso`, `LeaveRule`, `QuietTime`, `CqWhenNoTarget`, `FreeTxSlot`, `WatchdogFromOperator`. The values a strategy holds for them stand in `WstxStrategies::Strategy` and `BuiltinStrategies`. Auto reads `WstxRankingControl::RankedList` on `RankedActivity`: the verdicts with a rank, their `kind` and under a contest `ContestVerdict`. That a run selects no ignored station, answers no ignored caller, waits off the strategy's bands, and selects a CQ whose directive is on the strategy's included CQ targets (`run_admits`) follows from the verdict and is auto's to state; the tests `tc_042_002_a_run_never_*`, `tc_125_001_a_run_never_*`, `tc_125_001_a_pounce_*`, `tc_097_004_the_run_waits_*`, `tc_097_006_the_pota_sota_run_*`, `tc_097_006_only_the_runs_own_select_row_*` and `tc_097_007_the_run_answers_*` are auto's. Auto on under a contest whose `AutomationClause` is forbidden needs the operator's confirmation (`auto_request`). `AutoControl.sysml` names `ValueOrder`, `ContestValueOrder` (names unchanged) and `WstxStrategies::ContestPrompt` (gone). | old `auto/Strategy.sysml`, CL-042-02, CL-097-02 | ranking |
| qso | The CQ word of a special activity (TEST for na_vhf, eu_vhf and arrl_digi, WW for ww_digi, FD for field_day, RU for rtty; `Activity::cq`) is qso's; the station service gives it to ranking as `RankingContext::activityCqWord`. `ContestProfile::activity` names a special activity by a text. The operator's selection of a CQ that is not for the station warns with the text of `WstxValueOrder::DirectedCqRule` ("CQ NA — not for EU") and needs no confirmation for the activity's own word (`selection_warning`; CL-039-24, CL-063-07, CL-097-09; `tc_039_002_a_selection_of_a_cq_not_for_me_*`, `tc_063_004_a_selection_of_the_activitys_cq_*`). A manual reply to an ignored station is not refused. | CL-039-03, CL-063-02, CL-042-02 | ranking |
| log | Ranking needs the continent of the entity nearest to a locator (`dxcc::Table::nearest_continent`); `EntityRequest` asks by a call only (marker on `WstxValueOrder::MyContinent`). The marker on `PeriodQsos` is answered: `WstxContestRanking::ContestCount`. `DecodedFacts` cannot name `WorkedStatus` (below). | `MyContinent`, `ContestLog` | ranking |
| profile | `most_wanted.json` (`{schema_version 1, profile_id, date, list}`, at most 262144 bytes) and `strategy.json` lie in the profile's folder. Ranking has no connection to the profile (marker on `RankingService`). | `MostWantedListRule`, `StrategyConfiguration` | ranking |
| frontend | The strategy selector and editor with its nine decisions, the contest prompt, the marks and the order of Band Activity (rank, grey, dupe, new multiplier, Show all), the why in the preview, Settings: the ignore lists, "List from <date>" with Update Most Wanted and the attribution, the alert history with sound and notification, the "Renamed <from> to <to>" notes. | CL-039-25, CL-042-05, -06, -07, CL-063-08, CL-097-09, `ContestPrompt` | ranking |
| mcp | An agent reads the alert history (`wstx_read alerts`) and cannot clear it or update the Most Wanted list. | CL-042-07, TC-042-006, TC-039-031 | ranking |

### Test cases handed over

| Test case | Shows | To |
|---|---|---|
| TC-039-003 Strategy store, routes and evaluation | the store and the routes; its evaluate conditions are also TC-039-002 (b) | station, station link |
| TC-063-007 The contest selection on the store and the evaluate route | the selection; its tally is TC-063-006 (j) | station, station link |
| TC-039-001, TC-039-032, TC-097-001 to -003, TC-097-015, TC-063-001 to -003 | defining and saving strategies and contest profiles | station (line 1 for the operator) |

### Changes needed outside ranking's files

`interfaces/internal/StationLink.sysml` (taken over), 7 validator errors since this part:
line 365 names `WstxRankingControl::IgnoreLists`, which is gone; lines 328, 365, 366, 377,
378 and 388 type attributes by `Alert`, `IgnoreCommand`, `EvaluateRequest`, `EvaluateReply`
and `RankingState`, which are items now. They go when the station link is rebuilt.

`interfaces/internal/OperatingChain.sysml` or `LogControl.sysml` (the log's):
`WstxRankingControl::DecodedFacts` needs `WorkedStatus`, which stands in the operating
chain's file; a control interface does not import that file (M3.4). Moving `WorkedStatus`
to `WstxLogControl` would let `DecodedFacts` carry
`attribute worked : WorkedStatus[0..1];`. The marker on `DecodedFacts` waits for it. The
marker on `PeriodQsos` ("which part holds the rules by which a contest counts these QSOs")
can go: `WstxContestRanking::ContestCount`.

`Station.sysml`: nothing must change for the part to be valid. A connection between
ranking and the profile (as `contactStorage` for the log) waits for the profile part.
`satisfy 'FR-026' by ranking` stands alone; if the strategy clauses go to the station
service (line 1), FR-026 needs a second `satisfy`.

`_work/files.md`: `Ranking.sysml`, `ValueOrder.sysml`, `ContestRanking.sysml`,
`IgnoreLists.sysml`, `WantedList.sysml`, `MostWanted.sysml`, `Alert.sysml`,
`RankingControl.sysml`, `Strategies.sysml` and `ClubLog.sysml` are built;
`backend/operating/auto/Strategy.sysml` and `backend/log/Contest.sysml` stay old files
without a target.

`START-HERE.md`: the state table (ranking: tests 1 to 5 pass; one new identity CL-063-09;
eleven identities placed from "TO PLACE"; `ReadRankingState`, `ReadAlerts`, `DecodedFacts`
and `RankingContext` added to `RankingControl`); the traps: "`*/` inside a doc text ends
the comment: a pattern such as star-slash is written another way"; "`entry` and `end` are
keywords too".

### Dependencies on interfaces built at the same time

Ranking imports nothing of transmit, radioControl or profile. It imports `Decodes`,
`LogControl`, `OperatingChain` and `Hearing` (built) and `ModeProcessing` through them.
`Strategies` and `LogControl` import each other (`Continent`, `DupeRule`); the validator
takes it.

## For the operator

One line each; none is decided here.

1. **Where the promises about defining, saving and selecting strategies stand** (CL-039-01,
   CL-039-11, CL-097-01, CL-097-07, CL-097-08, CL-063-01, CL-063-03 and eleven test cases).
   The record on #53 makes the station service the gate and the profile the keeper;
   `Station.sysml` gives FR-026 to ranking alone; M2.1 names no function file for them. In
   the code they live in ranking's module. WSJT-X has no strategies; it keeps whole
   configurations. Recommendation: a function file of the station service (it needs a
   name in M2.1, for example `Strategies` under `backend/station/`), with the data staying
   in `interfaces/internal/Strategies.sysml` as written, and FR-026 satisfied by the
   station service too. The reason: ranking is to read its group only; the store also holds
   Auto's group and the selection that starts and ends runs.
2. **`WantedList.sysml` has no content.** #124 is recorded and not built; the file holds one
   element with a marker. WSJT-X has no list of wanted calls. Recommendation: keep the file
   as it is until #124 is built, since M2.1 names it; the other way is to take it out of
   M2.1 until then.
3. **Alerts under a contest strategy.** The old model says none is recorded; the code
   records them, judging by the filter of class strategy with the values every built-in
   starts from (new entity per band and mode, not confirmed), which no operator chose.
   WSJT-X's alerts do not depend on the activity. Recommendation: no alert under a contest
   strategy, as the old model says, and a change of the code; the model has a `@Conflict`
   until then.
4. **When ranking makes a ranked list.** Written as "for each `PeriodView`", which
   `Station.sysml` suggests (decodes to ranking, ranked list to auto). In the code the run
   of auto calls the evaluator for the newest publication. WSJT-X judges each decode as it
   prints it. Recommendation: as written, a list for each period view; it is work for the
   code and keeps M5.7's direction.
5. **When the facts of a decoded record are given again.** The code makes entity, flags and
   worked status each time the records are read, so a QSO logged later changes them.
   WSJT-X colours a decode once, when it prints it. Recommendation: ranking gives the facts
   once for each record and again for the records of the current period when the logbook or
   the station's band changes; that keeps the browser's rows true without a read.
6. **CL-063-09**, the one new identity. Recommendation: keep it; TC-063-005 shows the count
   alone.
7. **CL-097-02 and CL-097-03 are `implemented`** (were `partial`). Every filter line and
   criterion is built and has a test; what was open in #97 is the run, which is auto's.
   Recommendation: keep.

## Not done, and what is not sure

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted. Issue #53
  and #124 were read on GitHub.
- Read in full: `strategy.rs`, `contest.rs`; of `most_wanted.rs` everything but the 340
  rows of the table; `dxcc.rs` in the parts ranking uses (`annotate`, `flags`, `compact`,
  `sender`, `nearest_continent`, the constants); the old ranking files, `RankingControl`,
  `Strategies`, `ClubLog`, `Contest.sysml`; of old `auto/Strategy.sysml` the package text
  and the list of its elements, not their bodies (they are auto's).
- Tests read in full: the 40 bound tests; their helper functions as far as a condition
  uses them. Two long lines of `dxcc_tests.rs` that build hand-made records were read cut
  off at 200 characters. Not read: the other 115 tests of `strategy_tests.rs`, the other 28
  of `strategy97_tests.rs` (store, routes, runs), `automation.rs` beyond its three calls
  into the evaluator, `client/contact.js`, `tests/*.cjs`.
- "For each `PeriodView` one `RankedList`" has no test and no code as written (marker).
- The sentence on reading `most_wanted.json` "when ranking first needs it" stands for three
  places in the code (reading the state, an evaluation, Auto on); a station that only
  receives does not read it.
- The validator accepts the files; it does not show that `StationLink.sysml` still fits.
  It does not (7 errors, above).
- WSJT-X was read at the local tree (tag v3.3.0-beta6), not at the behaviour baseline.

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
| `interfaces/internal/RankingControl.sysml` | 447 to 455 | 20,913 to 21,314 |
| `backend/operating/ranking/Ranking.sysml` | 40 to 43 | 1,827 to 2,001 |
| `backend/operating/ranking/IgnoreLists.sysml` | 132 to 132 | 8,162 to 8,163 |
| `interfaces/internal/Strategies.sysml` | 252 to 250 | 13,383 to 13,267 |
| `_descriptions/ranking.md` | 368 to 369 | 23,939 to 24,213 |

One setting is ranking's: the session minutes of the session ignore list.

| Element | What |
|---|---|
| `RankingConfig` (new, in `WstxRankingControl`) | the configuration: `sessionIgnoreMinutes` = 30, with what it does and its range (1 to 720) |
| `RankingRules` | carries `config : RankingConfig` in place of its own `sessionIgnoreMinutes` |
| `RankingService` | one attribute: `config : RankingConfig` |
| `IgnoreListsRule` | names `RankingConfig::sessionIgnoreMinutes` |
| `WstxStrategies::StrategyConfiguration` | `sessionIgnoreMinutes` left: the value is a config value and is defined once, with ranking. Nothing else of the file changed |

Not changed, as the brief says: the strategy definitions, the permanent ignore list, the
Most Wanted list (`most_wanted.json`, a definition file of ranking's own, with its marker
on `RankingService`) and the wanted list. The active strategy, the selected contest and the
session ignore list are not stored; their elements are as they were. No test condition
left a case: TC-042-002 (e) shows what the minutes do ("with 5 minutes set ... W1AW with
300 s"). No identity is retired or not carried.

Test 4 is unchanged (37 matched, 47 with a verdict): `sessionIgnoreMinutes` = 30 still
matches `SESSION_IGNORE_MINUTES`.

Planned, no test yet: the profile keeps the session minutes across a restart; the line
stands in the profile's TC-022-002 (k).

Differences in the code that test 4 does not show (work for the code): `strategy.rs` keeps
`session_ignore_minutes` in `strategy.json`, beside the strategies and the permanent
ignore list (`Configuration`, its validation and its migration of an older file).

Found and not decided, for the operator: `StrategyConfiguration::continent` (the station's
continent as the operator sets it; `RankingContext::continent`) is a value the operator
sets and is not among the 53 settings of `settings.csv`. It was left where it is.

Not verified: `strategy_tests.rs` was not read again.

## Changed after the report: the operator's decisions on ignoring and directed CQs (2026-11-15)

The operator decided six points on 2026-11-15 (issue 228). The operating report's section
of the same name lists all six, where each stands and by which rule. This section holds
ranking's part: the one ignore list (decision 3), the three parts of a directed CQ
(decision 4) and the continent as a value of the station (decision 5). The sections above
are as they were written; where they differ, this section holds. Measured by `measure.py`
in the session's scratchpad folder `decisions`.

### Elements changed

| File | Element | What |
|---|---|---|
| `IgnoreLists.sysml` | `CL-042-02` | reworded: no rank in every ranking for a station an entry of the ignore list matches; the list held for the session as the operator makes it. Status `partial` |
| | `IgnoreListsRule` | one list; "*" any run, "?" one character; held for the session, not stored, empty at station start, on every band; an entry stays until an `IgnoreCommand` or `ClearIgnoreList` takes it off; ignored in every ranking whatever strategy, contest, filter or order; without a rank not answered by Auto, a reply by hand not refused; the why "<call> is ignored (ignore list)", with the entry for a pattern; a marker on how many entries the list holds |
| | `TC-042-002` | conditions rewritten for the one list from the three bound tests; (d) planned: the band change, `ClearIgnoreList`, a restart |
| | `TC-125-001` | conditions rewritten; (a) from the session test; (f) planned: the "?"; the test of the permanent list's entries (`tc_125_001_permanent_list_entries_validate`) is no longer bound: it shows the form only on the saved list, which goes |
| `ValueOrder.sysml` | `VerdictRule` | the ignore test names the rule without repeating it; the grey test names `DirectedCqRule` alone |
| | `CL-039-03` | status `partial` |
| | `DirectedCqRule` | the three parts: DX by the continents; the station's CQ words (`RankingContext::cqWords`); the CQ words of the strategy evaluated (its included CQ targets, either class) or of its contest (`ContestDirective`) |
| | `CqTargetListRule` | the included words are the strategy's CQ words of `DirectedCqRule` (the sentence on the grey moved there) |
| | `TC-039-002` | setup with the CQ word EU; (a), (d) with the CQ words; (g) planned: CQ CH, and a contest strategy's included words |
| `ContestRanking.sysml` | `CL-063-02` | reworded: a CQ word of the contest ranking ranks by. Status `partial` |
| | `ContestDirective` | the words of `ContestProfile::cqWords` of the contest `StrategyRules::contest` names; none under class strategy; the operator's activity adds none |
| | `TC-063-004` | setup with the contest's words; (c) without an activity; (d) planned: the operator's activity ww_digi and rtty |
| `Alert.sysml` | `TC-042-006` | setup: "G4ABC on the ignore list" |
| `Ranking.sysml` | `RankingService` | `config : RankingConfig` gone; "the ignore list" |
| `RankingControl.sysml` | package text | no configuration of ranking |
| | `RankingConfig` | gone: its one value, the session minutes, goes |
| | `CqTargetList` | the included words are the strategy's CQ words, also words for the station's own CQ |
| | `RankingLimits` | `ignoreCallsMax` and `sessionIgnoreMax` gone |
| | `RankingContext` | `config` and `activityCqWord` gone; `cqWords` new; `continent` names `ProfileConfig::continent` |
| | `RankingRules` | `permanentIgnore` gone |
| | `IgnoreCommand` | the one list; the form of an entry with "?" and at least one character that is neither "*" nor "?" |
| | `ClearIgnoreList` | new item, answered by `RankingState` |
| | `IgnoreTier`, `SessionIgnoreEntry` | gone |
| | `RankingState` | `ignoreList` in the place of `sessionIgnore` |
| | `RankingControlPort` | `out item clearIgnore : ClearIgnoreList` |
| `_descriptions/ranking.md` | sections 1 to 5, 9, 10 | as the model now says; the port table also shows `rules` from operating |
| `_work/parts.json` | ranking | five verdicts added |

Sizes (characters): `IgnoreLists.sysml` 8,163 to 8,103; `ValueOrder.sysml` 39,835 to
40,047; `ContestRanking.sysml` 14,760 to 15,033; `Alert.sysml` 4,381 to 4,373;
`Ranking.sysml` 2,096 to 1,919; `RankingControl.sysml` 21,336 to 20,373;
`_descriptions/ranking.md` 24,213 to 24,430.

### Decided by rule

| Point | Rule | Result |
|---|---|---|
| Where the ignore list lives | session state with the function that holds it; M5.3 | ranking holds it; `IgnoreCommand` and `ClearIgnoreList` come from the station service |
| The universal effect | M1.4, one fact one place; the brief | stated once in `IgnoreListsRule`; `VerdictRule` and `ContestVerdictRule` name the rule |
| An entry that would match every call ("?+", "+?", "?") | authoring rule 7: a harmful edge case is a promise; the code's reason for refusing stars only | refused: an entry needs one character that is neither "*" nor "?" (line 3 below) |
| `RankingConfig` | M5.8 and M0.2: no empty item; nothing left in it | removed, with `StationConfig::ranking`, `RankingContext::config`, `RankingService::config` |
| The station's CQ words and continent | the station's own values in `ProfileConfig`; a change reaches ranking from the station service | `RankingContext::cqWords`, `RankingContext::continent` |
| A strategy's CQ words | the code decides: the included CQ targets already admit a CQ (`included_target`) | `CqTargetList::included`, no new feature |
| A contest's CQ words | a definition with the thing it belongs to | `ContestProfile::cqWords` in the contest table; ranking finds them by `StrategyRules::contest` |
| Status | a clause's status follows the code | CL-042-02, CL-039-03, CL-063-02 `partial` |

### Identities

None is new, retired or not carried; the ledger is unchanged. Reworded: CL-042-02,
CL-063-02, TC-042-002, TC-125-001, TC-039-002, TC-063-004, TC-042-006 (setup). A test
case that still has a test for a kept condition keeps it bound; a promise without a test
has its line "Planned, no test yet": TC-042-002 (d), TC-125-001 (f), TC-039-002 (g),
TC-063-004 (d). An ignored station under a contest is shown by
`tc_125_001_a_contest_strategy_skips_a_sender_matched_by_a_pattern` (TC-125-001 (e)).

### The pattern forms

The old text and test conditions write the star of a pattern as "+" (a star before a slash
would end the doc comment), and the old case named "BY+"; the code and its tests use "*"
(`entry_matches`, the tables of `tc_125_001_*`). The rule writes the operator's form, "*"
and "?"; the test cases keep "+" for the star, said in their setup. Every difference:

| Form | Code | Model |
|---|---|---|
| "*" any run, also none, anywhere, any number | yes (`entry_matches`) | yes |
| "?" one character | refused: "K1?BC" is no entry (`ignore_entry`, both tests of TC-125-001 (a)) | yes |
| an entry of stars only | refused | refused, and so is one of "*" and "?" only |
| a pattern in the why text | an entry with "*" (`ignore_why`) | an entry with "*" or "?" |
| the list named in the why | "session list" or "permanent list" (`Tier::name`) | "ignore list" |

### Under a contest

The code applies the ignore lists under a contest as under a strategy: `contest.rs`
`classify` asks `Station::ignored_by` first, as `strategy.rs` `classify` does, and
`strategy::station` merges both lists into `Station::ignored` for either evaluator. A test
shows it (above). No difference there.

### Differences from the code (for the code issue)

| Difference | Place in the code |
|---|---|
| Two lists: a saved permanent list in the strategies file, and a session list | `strategy.rs` `Config::ignore_calls`, `parse_config`, `upgrade`; `Session`, `Tier`, `station` |
| A session entry ends after the session minutes, carries the band, and every change of the band empties the list; the 65th entry drops the oldest | `strategy.rs` `Session::add`, `Session::observe_band`, `Session::entries`, `Owner::ignore`, `SESSION_IGNORE_MINUTES`, `SESSION_IGNORE_MAX` |
| No "?" in an entry | `strategy.rs` `ignore_entry`, `entry_matches`, `ignore_why` |
| No command that empties the list | `strategy.rs` `ignore_route`, `Owner::ignore` |
| The why names the tier | `strategy.rs` `ignore_why`, `Tier::name` |
| The state shows the session list with band and remaining seconds | `strategy.rs` `Owner::snapshot` (`session_ignore`) |
| A directive that is the code of the station's continent is for it; no CQ words of the station | `strategy.rs` `answerable` |
| The special activity's word is for the station, with or without a contest; no CQ words of a contest | `strategy.rs` `answerable_in`; `contact.rs` `Activity::cq`; `contest.rs` `PROFILES` |
| A strategy's included CQ targets lift the grey only under class strategy | `strategy.rs` `classify` (`included_target`); `contest.rs` `classify` (`greyed` alone) |
| The operator's selection warns by the same computed rule | `strategy.rs` `selection_warning` |
| The run's own selection passes a CQ only by the strategy's included list | `strategy.rs` `run_admits` |
| The continent the operator sets is a value of the strategies file | `strategy.rs` `Config::continent`, `parse_config`, `my_continent` |

Test 4 of ranking: 32 matched (37 before: `RankingConfig::sessionIgnoreMinutes`,
`RankingLimits::ignoreCallsMax`, `sessionIgnoreMax` and the two literals of `IgnoreTier`
are gone), 52 with a verdict (47 before): `IGNORE_CALLS_MAX`, `SESSION_IGNORE_MAX`,
`SESSION_IGNORE_MINUTES`, `"permanent"` and `"session"` with "difference in the code: ...
(operator 2026-11-15), issue 228".

### Edge cases and their homes

| Case | Home |
|---|---|
| an entry that matches every call | `IgnoreCommand::call`: refused; TC-125-001 (a), (f) |
| an entry put on twice; one taken off that is not listed | `IgnoreListsRule`; TC-042-002 (b), TC-125-001 (d) |
| a change of the band, also to or from an unknown band | `IgnoreListsRule`: the list stays; TC-042-002 (d) planned |
| a station restart | `IgnoreListsRule`: empty; TC-042-002 (c), (d) |
| the list at its largest | marker on `IgnoreListsRule` |
| an ignored caller of the profile's call; an ignored station under a contest | `IgnoreListsRule`; TC-042-002 (a), TC-125-001 (e) |
| CQ DX with an unknown continent | `DirectedCqRule`: not for the station; TC-039-002 (a), (d) |
| the station's CQ words empty | `DirectedCqRule`: only plain CQs, DX and the strategy's and contest's words; TC-039-002 (d) |
| the continent unknown, with CQ words | `DirectedCqRule`: the words count; TC-039-002 (g) planned |
| a word on two of the three lists | `DirectedCqRule`: for the station; covered by the rule |
| a contest without CQ words | `ContestDirective`: no word; TC-063-001 (e) planned |

### For the operator

1. **How many entries the ignore list holds**, and what a command beyond gets (marker).
   The code keeps 64 on the session list and drops the oldest, which "an entry stays until
   the operator takes it off" excludes, and refuses more than 100 on the saved list.
   WSJT-X has no ignore list. Recommendation: 100, and an `IgnoreCommand` beyond refused.
2. **The why text of an ignored station.** Written as "<call> is ignored (ignore list)"
   and "<call> is ignored (ignore list: <entry>)", the smallest change from the code's
   texts. Recommendation: keep.
3. **An entry of "*" and "?" only** ("?", "?*") is refused, by the reason the code gives
   for stars only (it would ignore every station). Recommendation: keep.
4. **The CQ word of the special activity set by hand** and **a contest without an
   activity**: lines 1 and 2 of the operating report's section.

### Verified and not verified

- `part_done.py ranking`: tests 1 to 5 pass. `check.py` on `backend/operating`: no
  finding. The validator: no new error on the whole tree.
- Read in full: the bound tests of TC-042-002 and TC-125-001
  (`tc_042_002_ignored_senders_never_match`,
  `tc_042_002_session_list_expiry_renewal_capacity_and_band_change`,
  `tc_042_002_ignore_route_store_and_band_change`,
  `tc_125_001_permanent_list_entries_validate`, `tc_125_001_entries_match_the_whole_call`,
  `tc_125_001_session_patterns_and_the_station_skip_matches`,
  `tc_125_001_a_contest_strategy_skips_a_sender_matched_by_a_pattern`), the tests of
  TC-039-002 `tc_039_002_continent_and_directed_cq_rule` and
  `tc_039_002_verdicts_grey_reasons_and_treat_73`, and of TC-063-004
  `tc_063_004_the_directive_table_in_a_contest_activity`; in the code `ignore_entry`,
  `entry_matches`, `ignore_why`, `Station`, `Tier`, `Session`, `answerable`,
  `answerable_in`, `selection_warning`, `run_admits`, `ignored_by`, `greyed`, `classify`,
  `evaluate`, `evaluate_contest`, `my_continent`, `station` of `strategy.rs`, `classify`
  of `contest.rs`, `Activity::cq` of `contact.rs`.
- Not read: `tc_039_002_my_continent_from_config_call_and_locator` and the bound test of
  TC-042-006 again (their conditions keep their text but for the setup); the browser.

### Answered by the operator (2026-11-15)

The answers to the lines above are in the operating report's section of the same name. For
ranking: the ignore list holds `RankingLimits::ignoreListMax` = 20 entries and refuses a
further one with `RankingRefusal::ignoreListFull` (the marker is gone); an entry needs at
least one letter; the why text stays. Open: whether a contest's CQ words count only within
its period, and the CQ word of an activity set by hand (line 1 there).

## Answered by the operator (2026-11-16): line 2, the wanted list

Not left empty: modelled from issue 124 (recorded) and the day's decisions ("no shortcuts,
we do the right thing"). Q1 was decided on 124 (2026-11-12) as WSJT-X's Wait and Call;
Q2 answered (a). The list is ranking's data, kept by the settings function.

| Element | What |
|---|---|
| `WantedList.sysml` | CL-124-02 with `WantedRule` (wanted while not worked since added; can be called on a CQ, an RR73, RRR or 73 to another call, or a call to me, whatever the filter, `treat73AsCq`, `callersFirst` and a contest's verdict say; never ignored, off the bands, failing the callsign guard, or a CQ left to others; first in the order; why "wanted (<entry>)"; only with a selection); CL-124-03 with `WantedRemoval` (an exact entry leaves at its first QSO after it was added; a pattern stays). Both `target`; no test exists, so no test case |
| `RankingControl` | `WantedEntry` (call of the ignore list's form, `addedUtcMs`), `RankingLimits::wantedListMax` 100 (124's listed default L2), `RankingContext::wanted`, `VerdictKind::wanted`, `WantedWorked` |
| `ValueOrder`, `ContestRanking`, `Alert` | `VerdictRule` and `ContestVerdictRule` take the wanted test after the band tests; `ValueOrder` and `ContestValueOrder` put the wanted first; a wanted record alerts |
| the profile | `SettingsCollection::wantedList`, `CreateEntry::wanted`, `DefinitionsSnapshot::wanted` and `wantedRevision`, `WantedFile` (`wanted.json` in the operator's folder) |

124's CL-124-01 (the list, its route and editor) is covered by the profile's CL-039-01
(the collection), the station link and the frontend; its number is not used. Most Wanted:
one list, downloaded, not editable (operator 2026-11-16).

## Answered by the operator (2026-11-16): line 3, alerts under a contest

The alerts stay (asked first: the operator had not known of them; WSJT-X has sound alerts
for its categories). Under a contest strategy a record alerts when it is wanted or brings a
new multiplier (`ContestVerdict::newMultiplier`); nothing else. `AlertRule` says so, the
`@Conflict` is gone, CL-042-04 is `partial`, TC-042-006 (g) is planned. Difference in the
code: `alert_step` (`strategy.rs`) judges every record by `evaluate`, the class-strategy
evaluator, also under a contest strategy, with the filter values a contest strategy falls
back on.

Correction found while reading WSJT-X (tree v3.3.0-beta6): it has hand-kept call lists,
"highlight orange/blue callsigns" with prefix and directed-CQ matching, a colour and the
"Wanted" alert (`mainwindow.cpp` 3156 to 3199). They do not rank or call. Issue 124's
"WSJT-X has no wanted-callsign list" is out of date for this tree.

## Decided by rule (2026-11-16): line 4, when ranking makes a ranked list

M5.7: the operating chain commands only downward (ranking, auto, qso, transmit). Ranking
gives a `RankedList` for each `PeriodView`, also for a view published again, without being
asked, to Auto and to the station service (`Evaluation`; the marker is gone). The list now
names its view (`RankedList::periodView`, in the place of `job`), so Auto sees whether the
period is complete. CL-039-02 is `partial`. WSJT-X judges each decode as it prints it.
Difference in the code: Auto's step asks the evaluator for the newest complete publication
(`automation.rs` `verdicts`, `strategy::evaluate`), and the browser asks by
`POST /strategy/evaluate`.

## Answered by the operator (2026-11-16): line 5, when the facts are given again

Once for each record, and again for the records of the current period view whenever the
logbook (also by another station's QSO), the country file or the station's band changes;
older periods stay as given (`DecodedEntity`; the marker is gone; CL-055-02 `partial`).
WSJT-X colours a decode once. Difference in the code: the facts are worked out at every
read of `GET /receive/results` (`receive_http.rs`, `dxcc::annotate`), and nothing is
given after a change.

## Decided by rule (2026-11-16): lines 6 and 7

Line 6, answered by the operator: CL-063-09 is kept (the old CL-063-03 held the selection,
operating's, and the count of the period, ranking's since 2026-11-15; M6.4; the next free
number; shown by `tc_063_005_the_points_rules_by_hand` and
`tc_063_006_only_the_period_counts_and_each_dupe_rule`).

Line 7, by the rule "a clause's status follows the code" after reading the bound tests in
full: CL-097-02 stays `implemented` (every filter line and the bands have a test).
CL-097-03 is `partial`: new_cq_zone, new_itu_zone and new_prefix have no test as order
criteria, nor has the tie by the lower audio frequency (`exact_tie`), and the wanted
records first is not built; TC-097-008 (f) is planned for them. TC-039-040 (k) is
completed from its test (new_dxcc_band, new_call, new_grid_band with the band unknown).
