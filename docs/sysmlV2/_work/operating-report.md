# Report: the operating part

2026-11-15. Built by a subagent session; the operator was not asked. What a rule decides is
listed as decided; what no rule decides is listed for the operator at the end and is not
decided here. Every figure is measured by a script (`measure.py`, `foreign.py`, `free.py`
and `run_own_rows.py` in the session's scratchpad folder `operating`; they read only).

**`part_done.py operating` does not pass test 1, and cannot within this session's limits.**
Tests 2 to 5 pass. Test 1 counts 198 identities to the part and fails on 142 of them, none
of which is operating's: the tool gives a part every ledger row whose old file lies under
`backend/<part>/`, and for the part `operating` that is every row of qso's old files (102
"TO PLACE" rows of `qso/QsoData.sysml`, 8 of `QsoTransmit.sysml`, 2 of `QsoWire.sysml`, and
30 rows of `SpecialActivities.sysml` and `StandardQso.sysml` that have a target file and
have not arrived). Those rows are auto's and qso's and stay as they are. With the one
change to test 1 written under "For the main session", the part has 16 identities and all
five tests pass (`run_own_rows.py`, which changes nothing in the tree); ranking, log and
profile count as before under it (29, 25, 20).

## What was written

| File | Content |
|---|---|
| `backend/operating/Operating.sysml` | new: the part `OperatingService` with five ports, its modules, its detail tests; two markers |
| `backend/operating/Strategies.sysml` | new, package `WstxOperatingStrategies`: 6 clauses, 8 rule elements, 10 test cases with 51 lettered lines (one of them planned, no test yet); two markers |
| `interfaces/internal/Strategies.sysml` | the strategy and the contest as data (as ranking wrote them, with `AutoKeys` drawn out of `Strategy`), and new: `ConfigurationKeys`, 8 items (3 commands, 3 answers, 2 shares), 4 port definitions, 4 interfaces; 18 attribute definitions, 7 enumerations; one marker. The marker that waited for this part is gone |
| `interfaces/internal/RankingControl.sysml` | four replacements: `RankingRules` is given by operating and leaves `RankingControlPort`; `config` moved from `RankingRules` to `RankingContext` |
| `backend/operating/ranking/Ranking.sysml` | two replacements: the port `rules : ~RankingSharePort` and its import; the text of `config` |
| `_descriptions/operating.md` | the functional description |
| `_work/parts.json` | the key `operating` (3 files, 20 files to validate with, 22 verdicts); nothing else |
| `_work/ledger.md` | 18 rows changed, 1 row inserted (CL-097-10) |

10 test cases are bound to 17 named tests in 3 files: of the 138 tests of
`strategy_tests.rs` 7, of the 33 of `strategy97_tests.rs` 5, of the 10 of
`contest_tests.rs` 5.

## Identities

The brief named 18 (7 clauses, 11 test cases). 15 arrive, 1 is retired, 2 are handed over,
1 is new. No further "TO PLACE" row was taken.

| Identity | New place | Note |
|---|---|---|
| CL-097-01 | `StrategyForm` | Keeps its core: what a strategy is and that a refusal names its value. Was `partial` for the editor and the run; every line here is built and tested: `implemented`. The built-ins went to CL-039-11, the older files to CL-039-01, the editor to the frontend. |
| CL-039-01 | `SaveRule`, `StrategiesFile`, `OlderFiles` | Keeps its core: the saved strategies, the one active, the file. The routes are the station link's; the continent is one value of the configuration. |
| CL-039-11 | `BuiltinOffer` | The table stands in `WstxStrategies::BuiltinStrategies`. The copy in the editor is the frontend's. |
| CL-063-01 | `ContestOffering` | The table and the schedule stand in the interface. The route is the station link's. |
| CL-063-03 | `SelectionRule` | Keeps the selection of a contest with its period and its strategy. The count of the period is ranking's CL-063-09; the prompt is the frontend's. |
| **CL-097-10** | `Shares` | New: operating gives ranking, Auto and the contact each its share (operator 2026-11-15). Taken from CL-097-01 ("a strategy defines values only"); the next free number of the series (CL-097-09 is the highest in the old model, the new tree, the code and the tests; `free.py`). Status `partial`: ranking and the run work by the active strategy at once, which the tests show; no share is given as an item, and the contact is given nothing. |
| **CL-097-07** | retired | The same promise as CL-097-01: the form of a strategy of class contest is one of the rules of `Strategy` and `StrategyForm`, shown by the same test (TC-097-001 (e)). Its built-ins are CL-039-11's, its selection CL-063-03's, its ranking CL-063-04's, the prompt the frontend's. |
| **CL-097-08** | handed over to auto | Its promise is when CQ is called after the CQ wait; that is Auto's (M5.7). The value (1 to 20, held in every strategy, 2 when a file lacks it) is one line of `AutoKeys::cqWaitPeriods` and of `StrategiesFile`, shown by TC-097-001 (b), (d) and TC-097-002 (g). |
| TC-039-001, TC-039-003, TC-097-002 | with CL-039-01 | TC-039-003 keeps the store; its route conditions (Origin, 401, another profile, another boot, the version) are the station link's, its evaluation is ranking's TC-039-002 (b) and here only condition (f). TC-097-002 also binds the test of the version 1 file, which carries the number TC-039-030. |
| TC-097-001 | with CL-097-01 | Verified CL-097-01 and CL-097-08. The oversized body is the station link's. |
| TC-039-032, TC-097-003 | with CL-039-11 | The run under Casual and the Halt in the test of TC-039-032 are auto's; the browser test is the frontend's. TC-097-003 also verifies CL-063-03 (a contest built-in only with its contest). |
| TC-063-001, TC-063-002, TC-063-003 | with CL-063-01 | Rewritten from their tests. |
| TC-063-007 | with CL-063-03 | Its tally is ranking's TC-063-006 (j). It also binds the selection test that carries the number TC-063-009. |
| **TC-097-015** | handed over to auto and the frontend | Its test is the run of a contest strategy; its other half is the contest prompt in the browser. Its two refusals are TC-063-007 (b) and (d). |

### "TO PLACE": looked through and left

135 rows are "TO PLACE" now (153 before). Of the series 039, 042, 055, 063, 097 and 125
none is operating's: ranking's report lists them by owner (what Auto executes, the contact's
Hold Tx and busy partner, the operator's selection of a CQ, what the browser shows, planned
cases without a test), and that sorting holds with operating as a part. Nothing of the
other series (010, 011, 050, 065, 066, 081, 082, 089, 111, 003, 005, 022, 033, 051, 080) is
about a strategy or a contest table.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| Where the containment is written | M3.3 (a part imports no part), M4.3 (`Station.sysml` composes), M2.2 | `Operating.sysml` has the part and its ports only. `Station.sysml` writes `part operating : OperatingService` with the three usages inside it; the lines are under "For the main session". The validator takes that form (scratch model `MiniStation.sysml`). |
| Over which interface ranking gets its share | M5.8 (a connection is typed by an interface and named after what flows), M4.6; operator: operating gives each its share | A connection of its own inside operating, `RankingShare` (`RankingSharePort`, in `Strategies.sysml`), which carries `RankingRules`. The item stays defined in `RankingControl.sysml`, with ranking's types. |
| `RankingConfig` reaches ranking from the station service | the settings rule: the part is given its new value by the station service | `config` moved from `RankingRules` to `RankingContext`. |
| The share is not a command | M5.3, M5.7 | The operator's commands reach operating only through the station service (`StrategiesPort`). What operating gives its three functions goes downward and has no answer. |
| Which FR | decided on the clock: a clause derives from the one FR its part serves; FR-026 reads "Define and select strategies and contests, and order the decoded stations" | All six clauses derive from FR-026. The old clauses named FR-007, FR-016, FR-019, FR-020 and FR-024. |
| One command for defining and selecting | the code decides what is built | `SaveStrategies` carries the whole configuration, as `PUT /strategy` does; a save and a selection share the revision. Line 2 for the operator. |
| The active strategy, the contest | operator: as the code has them | Held while the station runs, not written to the file, none at station start (`SelectionRule`, `StrategiesFile`). Line 1 for the operator. |
| Who writes the strategies file | the settings rule: a definition file is a file of its own that the profile gives the place of; the log's form (`contacts`) | Operating keeps the file itself; its port `definitions` takes `ProfileFolder`. The save keeps its storage refusal: the file is no config value. |
| Is a storing clause needed in the profile | CL-005-01 `ProfileOwnership`: the folder holds the definition files the other functions keep there, and the profile leaves them as they are | None is needed. The profile needs a port for operating (for the main session). |
| The session minutes are not in the strategies file | the settings rule; `RankingConfig` | `StrategyConfiguration` and `StrategiesFile` do not have them. Difference in the code. |
| The Auto switch is not operating's | M5.7: whatever acts at run time belongs to Auto | Not written. In the code it lives in the store and counts its revision. Handed to auto. |
| The refusal as four specialised attribute definitions | authoring rule 7 (a case made impossible by a type), data rule on enumerations (an enumeration holds no attribute) | `InvalidValue` alone has a `field`. An enumeration with an optional field would allow a field on a stale save. It also keeps ranking's test 4 as it is: `Strategies.sysml` is in ranking's `files`, and an enumeration there needs verdicts in ranking's key, which is not this session's. |
| The key names | data rule 5: state external naming once | `ConfigurationKeys`, in the interface, because the file, the refusal and the wire use them. |
| The older file versions | data rule 6 (which versions are read); tests exist | `OlderFiles`, in the present tense. |
| CL-097-07, CL-097-08, TC-097-015 | M6.4, requirements rules 2 and 10, authoring rule 9 | See "Identities". |
| Status | the code decides | CL-097-01 `implemented`; CL-097-10 `partial`. |
| Routes, status codes, body size, events, the MCP principal | M4.7; the brief | Not written; handed to the station link. |
| `counter_exhausted` | the code has it | Kept as `CounterExhausted`, one sentence; no test shows it. |

## Dropped as code or as history

- The decision lists, dates and issue numbers of the old clauses; all `dependency` lines.
- "Written atomically", the lock of the store, "read on first use", the blocking threads.
- The order in which the values of a configuration are checked: the model says one value
  outside its rule is named.
- "A strategy's class is never switched" and "a strategy is new only as a duplicate": the
  code does not hold a save to either; they are the editor's.
- "No built-in is called the default": a property of the names in `BuiltinStrategies`.
- The reading of `GET /strategy/contests` "never on a timer": the browser's.
- The texts of a contest (exchange, score, schedule in words, notes, the address of the
  rules, the Cabrillo name) as features: one sentence in `ContestProfile`; TC-063-001 (d)
  holds the ones its test asserts.

## Renamed or moved

| Old | New | Cited by |
|---|---|---|
| `Strategy::leaveMode`, `leaveCalls`, `leaveCallsHeard`, `goneMinutes`, `txChanges`, `moveEvery*`, `busyPause`, `cqWhenIdle`, `cqWaitPeriods`, `retryMinutes` | `AutoKeys`, as `Strategy::auto` | the handover row to auto; comments in `strategy.rs` name `WstxStrategies::Strategy` |
| `RankingRules::config` | `RankingContext::config` | `_descriptions/ranking.md`; the handover rows 157 and 174 |
| `RankingControlPort::rules` | `RankingSharePort::rules`; ranking's port `rules` | `_descriptions/ranking.md` |
| `StrategyHttp`, `ContestHttp`, `ContestPrompt`, `ProfileTable` (old model) | not written (routes, the browser); `ContestTable` | comments in `strategy.rs`, `contest.rs`; `AutoControl.sysml` |
| the snapshot's `configuration_error`, `configuration_note`, `builtin_strategies` | `StrategiesState::unusable`, `renamed`, `builtins` | wire names: the station link |

## Negative statements

| Old statement | Result |
|---|---|
| "active never survives a station restart" | positive: at station start no strategy is active (`SelectionRule`, `StrategiesFile`) |
| "A strategy never selects, calls, answers, arms or transmits" | dropped: operating has no connection over which it could |
| "cannot be edited through PUT" (a built-in) | positive: a strategy offered under a built-in's name is refused by its name |
| "a saved strategy ... is renamed, never dropped" | positive: it is read under another name |
| "usable everywhere; a limit is a note, not a refusal" | positive: operating offers every contest to every station |
| "selecting a contest sets no activity" | not written; marker on `ContestActivity`, line 3 for the operator |
| "an MCP client can never select a strategy" | not written (the brief); see "Differences from the code" |

## Differences from the code

Each is the input of a code issue. Test 4 shows the first eleven (13 lines with the verdict
"difference in the code").

| Difference | Place in the code |
|---|---|
| There is no unit operating. The store, the built-ins and the routes stand in ranking's module beside the evaluator; the contest table and the schedule stand beside ranking's counting | `server/src/strategy.rs` (`Config`, `parse_config`, `strategy`, `builtins`, `contest_builtins`, `Owner`, `Inner`, `put`, `snapshot`, the upgrades) beside `evaluate`, `classify`, `Station`, `Session`, `AlertLog`; `server/src/contest.rs` (`PROFILES`, `Round`, `next_period`, `parse_selection`) beside `Log`, `classify`, `evaluate` |
| Ranking's constants and names stand in that module (test 4: `ALERT_HISTORY_MAX`, `BANDS_MAX`, `COUNTRIES_MAX`, `CQ_TARGETS_MAX`, `EVALUATE_MAX`, `IGNORE_CALLS_MAX`, `ORDER_MAX`, `SESSION_IGNORE_MAX`, and the wire names `not_confirmed`, `not_worked`, `permanent`, `session`) | `strategy.rs` lines 23 to 31, 133, 218 to 220, `Strategy::json`, `Tier::name` |
| The session minutes are a key of `strategy.json` and of the save (test 4: `SESSION_IGNORE_MINUTES`) | `strategy.rs` `Config::session_ignore_minutes`, `parse_config`, `upgrade`, `Config::json` |
| No share is given. Ranking and Auto read the whole configuration from the store | `strategy.rs` `Owner::evaluate`, `alert_step`, `station`; `server/src/automation.rs` (`contact.strategy.config(state)`, `run_strategy`, `automatic_contest`, `active_strategy`) |
| Auto reads values of ranking's share: `callers_first` and the strategy's `bands` | `automation.rs` (the uses of `chosen.1.callers_first`, `s.bands`) |
| The contact is given nothing. The special activity is the operator's own setting; a contest run waits with the reason `activity` while it is not the contest's | `automation.rs` `strategy_context`; `contact_http.rs` `set_activity` |
| The Auto switch lives in the store, counts its revision and is part of its state | `strategy.rs` `Inner::auto`, `switch_auto`, `auto`, `auto_on`, `auto_off`, `auto_step`, `halt_step`, `auto_request`, `auto_route`, `start_selection` |
| A save starts and ends runs in the store's route | `strategy.rs` `put` (the route), `start_selection` |
| The file is read at the first use of the store, not at station start | `strategy.rs` `Owner::lock` |
| Operating reads the country table, the profile's identity and the file through other units' state | `strategy.rs` `Owner::put` (`state.logbook.dxcc()`), `Owner::lock` (`state.recording.profile`, `store.read_document_file`), `put` (`store.write_document_file` of `profile.rs`) |
| The period of a contest is offered by the clock of the PC | `strategy.rs` `contests_route` (`SystemTime::now`) |
| The state of `GET /strategy` is one object of operating's, ranking's and Auto's values | `strategy.rs` `Owner::snapshot` |
| A draft for an evaluation is checked in ranking's route | `strategy.rs` `Owner::evaluate` (`strategy(s, "strategy", ...)`) |
| An MCP principal: reads `GET /strategy` (`wstx_read strategy`) and asks `POST /strategy/evaluate`; `PUT /strategy`, `POST /strategy/auto`, `POST /strategy/ignore` and `GET /strategy/contests` answer 401. The model writes no rule for it | `server/src/mcp.rs` `VIEWS`, `tool_route`, `principal_guard` |
| Test tags: `tc_039_030_an_old_file_upgrades_...` is bound to TC-097-002; `tc_063_009_a_selection_asks_nothing_...` to TC-063-007; the tests of CL-097-07 and CL-097-08 say those numbers; `tc_097_015_...` is auto's | `strategy_tests.rs`, `strategy97_tests.rs`, `contest_tests.rs` |
| Comments name `WstxStrategies::StrategyHttp`, `ContestHttp`, `ProfileTable`, `WstxStrategy D2`, `WstxContest D11` | `strategy.rs`, `contest.rs` |

Test 4: 19 lines matched by the tool (1 value, 18 literals), 22 with a verdict: 8 matched by
reading, 13 difference in the code, 1 another part. The tool matched `LeaveMode::contest`
and `StrategyClass::contest` as one name; read: `Class::name` and `Leave::mode` both have
"contest". The four refusals and the keys of `ConfigurationKeys` are no enumeration and no
value, so the tool does not list them; read against `Owner::put`, `parse_config`,
`strategy`, `Strategy::json` and `Config::json`.

## Edge cases and their homes

| Case | Home |
|---|---|
| no strategies file | `StrategiesFile`; TC-039-003 (a) |
| a file of another profile, malformed, of an unknown version, too large | `StrategiesFile`: unusable; TC-097-002 (c), (f), (h); the size has no test |
| a file of an older version | `OlderFiles`; TC-097-002 |
| a saved name that is a built-in's | `StrategiesFile`: read under another name; TC-097-002 (a), TC-039-032 (g) |
| the 17th strategy; a name twice | `SaveRule`; TC-039-001 (c), (d) |
| every bound of a strategy | the features; TC-097-001 (a) to (d) |
| a key more or missing | `ConfigurationKeys`; TC-039-001 (b), TC-097-001 (d), (e) |
| two saves from one revision | `SaveRule`: `StaleRevision`; TC-039-003 (c) |
| the file cannot be written | `SaveRule`: `StorageUnavailable`; no test |
| the revision at its end | `CounterExhausted`; cannot occur in operation; no test |
| a built-in's name in another letter case | `BuiltinOffer`; TC-039-032 (a), TC-097-003 (b) |
| a contest without a contest strategy, and the reverse | `SelectionRule`; TC-063-007 (d), TC-097-003 (c) |
| a period of no length, backward, over 31 days | `SelectionRule`; TC-063-007 (b) |
| a selection across a restart | `SelectionRule`: none active; TC-039-032 (e), TC-097-003 (d), TC-063-007 (c) |
| a contest whose day is asked; a round that is running; the year's end | `ContestOffering`, `ScheduleRule`; TC-063-002 |
| a save while the file is unusable | `StrategiesFile`: from revision 0; no test of its own |
| removing the active strategy in a save | `SaveRule`: `active` must name a strategy of the same save; covered by the rule, no test |
| two commands at once | serialised by the code; rare and harmless, not written |

## Not carried over

| What | Why |
|---|---|
| CL-097-07 | retired (above) |
| CL-097-08, TC-097-015 | handed over (above) |
| The route conditions of TC-039-003, TC-063-003 and TC-097-001 (Origin, credentials, the version, another profile or boot, a query, another method, the oversized body) | station link |
| The run, the Halt and the browser steps of TC-039-032; the property of the mapped goals "gives the verdicts TC-039-030 expects" as an evaluation | auto, frontend, ranking |
| The condition of the version 1 file with only one of its two ignore keys | it is about the session minutes, which are not in the file in the model |

## Size

Measured in characters.

| | Old | New |
|---|---|---|
| the 7 clauses in `qso/QsoData.sysml` | 7,909 | 2,163 (6 clauses) |
| the 11 test cases in `qso/QsoData.sysml` | 18,446 | 20,312 (10 cases) |
| rule elements, imports and markers of the function file | | 13,711 |
| `backend/operating/Operating.sysml` | | 2,207 |
| `interfaces/internal/Strategies.sysml` | 25,203 in the old model; 13,267 as ranking left it | 23,523 |
| `interfaces/internal/RankingControl.sysml` | 21,314 | 21,336 |
| `backend/operating/ranking/Ranking.sysml` | 2,001 | 2,096 |

The function file has 592 lines and 36,186 characters. The part is larger than its old
text (51,558 against 61,916 characters, counting the old interface file and the 18 old
identities against the three files of the part). The growth is in the interface: the
commands, answers, shares, ports and `ConfigurationKeys` (10,256 characters more than
ranking left) take the place of `StrategyHttp`, `ContestHttp`, `ContestPrompt` and the
upgrade text of the old file, which ranking had taken out; and in the function file the
eight rule elements, which the old model held inside the clauses and the old interface.
`_descriptions/operating.md` has 19,321 characters. The ledger has 572 rows: 242 arrived,
38 handed over, 17 not carried, 5 retired, 135 "TO PLACE".

## Checks

- `python docs/sysmlV2/_work/part_done.py operating`: test 1 FAIL (142, see the top); tests
  2 to 5 pass: no finding in 3 files, no validator error in them, 19 names matched and 22
  lines with a verdict, 10 test cases with their tests.
- `run_own_rows.py operating` (test 1 by the folder of the old file): 16 identities, all
  five tests pass.
- `part_done.py ranking`, `log`, `spots`, `profile`: all five tests pass (29, 25, 6 and 20
  identities; ranking 37 matched and 47 with a verdict, as before).
- The validator on the whole new tree: 59 errors, as before this part: 48 in
  `Station.sysml`, 2 in `Context.sysml`, 7 in `StationLink.sysml`, 2 in
  `OperatingChain.sysml`; none in the files of operating or ranking.
- A scratch model outside the tree (`MiniStation.sysml`) with `operating` holding `ranking`,
  the connection `operating.rankingShare` to `operating.ranking.rules`, the connection of
  `definitions` to a port of the profile and both `satisfy` lines of FR-026: no error.
- `check.py` on `backend/operating`, `Strategies.sysml` and `RankingControl.sysml`: no
  finding.
- `git status`: `docs/sysmlV2/` is the only change.

## The functional description

`_descriptions/operating.md`, from the new files alone. It found these gaps:

| Gap | Settled how |
|---|---|
| Operating has no item that gives it the identity of the profile | marker on `StrategiesFile` |
| The keys by which a refusal names a value stood nowhere | `ConfigurationKeys` |
| `StrategiesState` did not say what its revision is at station start | one sentence on `revision` |
| What holds while the file is unusable for the shares | one sentence in `Shares` |
| `Station.sysml` does not compose operating | for the main session |
| Auto and the contact have no port for their share | handover rows |
| The set continent has no item from operating to the station service but the state | left; line 4 for the operator |
| `contest` has two absent forms (left out, null) | left: both stand in `ConfigurationKeys`, as the code reads them |

## Markers

| Where | Marker | Says |
|---|---|---|
| `OperatingService` | `@NotStated` | how operating learns the entity names of the country file |
| `OperatingService` | `@NotStated` | by which clock a `ReadContests` is answered |
| `StrategiesFile` | `@NotStated` | from which item operating learns the identity of the profile |
| `Shares` | `@NotStated` | by which rules a draft for an evaluation is checked |
| `ContestActivity` | `@NotStated` | what the contact does with the activity of the contest in force |
| `ContestTable` | `@FollowsSource` | the official rules of each contest (as ranking wrote it) |

## Checked in WSJT-X (`D:\Github\wsjtx`, tag v3.3.0-beta6)

WSJT-X has no strategies, no table of contests and no schedule. The operator sets one
special operating activity in the settings (`Configuration.cpp`, `SelectedActivity_`,
`special_op_id`), which is kept in the settings file across restarts, and it keeps whole
configurations (`MultiSettings`). Every question below is therefore the product's own.

## For the main session

### `part_done.py`, test 1

In `test_ledger`, a row belongs to a part by its old file only when the file lies directly
in the part's folder. Replace

```
        in_part = any(target.startswith(f) for f in files) or old.startswith("backend/%s/" % part) \
            or old.startswith("backend/operating/%s/" % part) or old.startswith(part + "/")
```

by

```
        in_part = any(target.startswith(f) for f in files) or os.path.dirname(old) in (
            "backend/%s" % part, "backend/operating/%s" % part, part)
```

Measured with it: operating 16, ranking 29, log 25, profile 20 identities.

### `Station.sysml`

Imports to add:

```
    private import WstxOperatingPart::OperatingService;
    private import WstxStrategies::StrategiesControl;
    private import WstxStrategies::RankingShare;
    private import WstxStrategies::AutoShare;
    private import WstxStrategies::ActivityShare;
```

In `StationProcess`, in the place of the three lines `part ranking : RankingService;`,
`part auto : AutoService;`, `part qso : QsoService;`:

```
        part operating : OperatingService {
            part ranking : RankingService;
            part auto : AutoService;
            part qso : QsoService;
        }
```

Every end that names one of the three gets `operating.` before it (15 connections:
`qsoOperations`, `stationRanking`, `stationAuto`, `timeQso`, `decodesRanking`, `decodesQso`,
`displayAuto`, `rankedActivity`, `targetChoice`, `contactTransmit`, `completedContact`,
`workedBefore`, `hearingRanking`, `hearingAuto`, `hearingQso`), for example
`connect station.ranking to operating.ranking.control`.

Connections to add:

```
        interface stationStrategies : StrategiesControl
            connect station.strategies to operating.control;
        interface strategyDefinitions : ProfileAccessLink
            connect operating.definitions to profile.definitions;

        // Inside operating: the share of each function.
        interface rankingRules : RankingShare
            connect operating.rankingShare to operating.ranking.rules;
        interface autoRules : AutoShare connect operating.autoShare to operating.auto.rules;
        interface contestActivity : ActivityShare
            connect operating.activityShare to operating.qso.activity;
```

`station.strategies` (`StrategiesPort`), `profile.definitions` (`~ProfileAccess`),
`auto.rules` (`~AutoSharePort`) and `qso.activity` (`~ActivitySharePort`) are ports of parts
that are not built or not this session's.

The allocation, in the place of the four lines of FR-007, FR-024, FR-025 and FR-026:

```
        satisfy 'FR-007' by operating.qso;
        satisfy 'FR-024' by operating.qso;
        satisfy 'FR-025' by operating.auto;
        satisfy 'FR-026' by operating;
        satisfy 'FR-026' by operating.ranking;
```

The line the part needs is `satisfy 'FR-026' by operating;`.

### The profile (`backend/profile/Profile.sysml`)

No storing clause is missing: CL-005-01 with `ProfileOwnership` carries the folder and the
files the other functions keep in it. Needed: one port,

```
        port definitions : ~ProfileAccess {
            doc /* Operating. Of ProfileAccess only ProfileFolder crosses here:
                 operating keeps the strategies file in the folder by itself. */
        }
```

and the marker on `PersistedProfile` can leave operating out as it stands. Operating also
needs the identity of the profile (marker on `StrategiesFile`); `ProfileFolder` has the
path only.

### `_work/files.md`

`backend/operating/Operating.sysml` and `backend/operating/Strategies.sysml`: built.
`interfaces/internal/Strategies.sysml` stays built.

### `_work/parts.json`

`interfaces/internal/Strategies.sysml` stands in ranking's `files` and in operating's. It is
operating's file now; when it leaves ranking's `files`, ranking needs it in `validate_with`
and verdicts for the 18 wire names of `strategy.rs` and `contest.rs` that its literals
match today.

### `_work/settings.csv`, column "Model home"

| Row | New text |
|---|---|
| The defined strategies | `WstxStrategies::StrategyConfiguration::strategies`, kept by operating in its definition file (`WstxOperatingStrategies::StrategiesFile`; CL-039-01, CL-097-01) |
| Permanent ignore list | `WstxStrategies::StrategyConfiguration::ignoreCalls`, kept by operating in `StrategiesFile` and given to ranking as `WstxRankingControl::RankingRules::permanentIgnore` (`WstxOperatingStrategies::Shares`) |
| Active strategy | `WstxStrategies::StrategyConfiguration::active`, held by operating (`WstxOperatingStrategies::SelectionRule`; CL-039-01); not stored |
| Selected contest | `WstxStrategies::ContestSelection`, held by operating (`SelectionRule`; CL-063-03); not stored |

The column "Model today" of the same rows: "operating: Strategies" in the place of
"interface Strategies (not placed)".

### Handover rows (for `_work/handover.md`)

| To | Statement | From (old model) | Found while building |
|---|---|---|---|
| station | The saved strategies. **Taken up by operating:** CL-039-01, CL-039-11, CL-097-01, CL-063-01, CL-063-03, CL-097-10 with ten test cases, in `backend/operating/Strategies.sysml`; CL-097-07 is retired, CL-097-08 and TC-097-015 are auto's. | CL-039-01, CL-097-01, CL-063-01 | operating |
| station | The station service passes `SaveStrategies`, `ReadStrategies` and `ReadContests` to operating over `StrategiesControl` (its port `strategies : StrategiesPort`) and takes `StrategiesState`, `ContestList` and `StrategiesRefused`. It refuses a command for another profile with `wrong_profile` and for another boot with `state_conflict` before the command reaches operating; in the code `Owner::put` checks both after the configuration. It tells every browser of a new revision (`strategy.state`). It no longer gives ranking `RankingRules`: operating does. It gives ranking `RankingContext`, which now carries `config : RankingConfig` (rows "The station service gives ranking ..." and "The one way for a change of a setting": read `RankingContext` for `RankingRules`). The continent the operator sets reaches the station service only as `StrategiesState::configuration.continent`. A draft strategy for an evaluation is checked by `WstxOperatingStrategies::StrategyForm` in the code's evaluate route; no command carries it to operating (marker on `Shares`). | CL-039-01, `StrategyHttp`; `strategy.rs` `put`, `evaluate` | operating |
| station link | Operating's routes. `GET /strategy`: of operating `revision`, `configuration` (null while unusable), `configuration_error` (`invalid_configuration`), `builtin_strategies` (each strategy with `builtin` true), `configuration_note` (`[{from, to}]`); the same object carries ranking's and Auto's values. `PUT /strategy` `{v, profile_id, boot_id, expected_revision, configuration}`, at most 32768 bytes (413 above): 400 `invalid_request` with the field of `InvalidValue`, or with the missing key of the body, or without a field for a key more; 400 `unsupported_version` `v`; 403 `wrong_profile` `profile_id`; 409 `state_conflict` `boot_id`; 409 `stale_revision` `expected_revision`; 409 `counter_exhausted`; 503 `storage_unavailable`; 200 with the state. The configuration on the wire has `session_ignore_minutes`, which is ranking's configuration in the model. `GET /strategy/contests` `{v 1, profile_id, boot_id, profiles}`, each profile with `id, name, cabrillo, cabrillo_confirmed, activity, bands, modes, exchange, dupes, points, multipliers, score, automation, automation_text, schedule, notes, source, period {start, end, band}`; a query 400, no credentials 401, another method 405. The event `strategy.state` `{profile_id, boot_id, strategy_revision}`. An MCP principal reads `GET /strategy` and asks `/strategy/evaluate`; every other strategy route answers it 401 (`mcp.rs` `principal_guard`). The route conditions of TC-039-003, TC-063-003 and TC-097-001 go with it. | `StrategyHttp`, `ContestHttp`, TC-039-003, TC-063-003 | operating |
| auto | CL-097-08 (when CQ is called after the CQ wait: every period counts, the count starts again at Auto on, after a QSO and after a leaving) and TC-097-015 (the run of a contest strategy) are auto's. Auto takes `WstxStrategies::AutoRules` on a port `rules : ~AutoSharePort`: the name, `AutoKeys` and for class contest the `ContestSelection`; the facts of the contest (`bands`, `activity`, `automation`) it reads in `ContestTable`. The Auto switch is auto's: in the code it lives in the strategy store (`Inner::auto`), counts its revision, is off at station start, goes off with a selection of none, at a Halt and at every end of a run, and a changed selection ends a run and starts the new one while Auto is on (`start_selection`). Auto on needs a selection, and under a contest whose `AutomationClause` is forbidden the operator's confirmation. A contest run waits while the station's activity is not the contest's (`activity`), off the contest's bands (`band`) and outside the period (`outside_period`); a run of class strategy waits while a special activity is set. The code's run reads `callers_first` and the strategy's `bands`, which are ranking's share. The tests of the run in `tc_039_032_a_builtin_is_selected_...` (Casual calls DL1XYZ; Halt turns Auto off and keeps the selection) and `tc_097_003_...` (Auto off after a restart) are auto's. | CL-097-08, CL-097-07, CL-063-03, TC-097-015; `strategy.rs`, `automation.rs` | operating |
| qso | Operating gives the contact `WstxStrategies::ContestActivity` on a port `activity : ~ActivitySharePort`: the special activity of the contest in force (ww_digi, arrl_digi, field_day, na_vhf, or none). What the contact does with it is not stated (marker; line 3 for the operator): in the code the activity is the operator's own setting, a contest sets none, and an activity sets no strategy (`tc_063_009_search_and_pounce_...` shows the last). `ContestProfile::activity` and `ContestActivity::activity` are texts until the contact's activities have a type. | CL-063-03, `ContestProfile` | operating |
| profile | Operating keeps `strategy.json` in the profile's folder by itself and needs a port of the profile for `ProfileFolder` (`definitions`), and the identity of the profile. In the code the store reads and writes the file through `Store::read_document_file` and `write_document_file` of `profile.rs`. The row "`most_wanted.json` ... and `strategy.json` lie in the profile's folder" is taken up for `strategy.json`. | `StrategyConfiguration`; `strategy.rs` `Owner::lock`, `put` | operating |
| log | Operating needs the names of the entities of the country file: a saved country entry must name one, without regard to letter case, and is held as the file writes it (`countries_of`; marker on `OperatingService`). It has no connection to the log. | CL-097-01, TC-097-001; `strategy.rs` | operating |
| ranking | `RankingRules` comes from operating over `RankingShare` (ranking's port `rules`); `RankingContext` carries `config`. `_descriptions/ranking.md` still shows `RankingRules` on `control` (its lines 43 and 84) and the marker on `Strategy` and `StrategyConfiguration`, which is gone (line 347). `Strategy`'s Auto values are `AutoKeys`. | `RankingControl` | operating |
| frontend | The strategy editor: a strategy's class is not switched and a strategy is made only as a copy; the nine numbered decisions; "Renamed <from> to <to>" for each `RenamedStrategy`, shown once; the contest prompt with the offered period, the strategies of the contest and no operation choice; the browser tests `TC-039-032 Built-in strategies are read-only ...` and `TC-097-015 the contest prompt ...` in `tests/ui-operating.test.cjs`. | CL-097-01, CL-039-11, CL-097-07, TC-039-032, TC-097-015 | operating |
| mcp | An agent reads the strategies (`wstx_read strategy`) and asks for verdicts (`wstx_strategy_evaluate`); it can neither save nor select a strategy or a contest, nor read the contests. No rule is written for it: MCP's credential is not decided. | `StrategyHttp`; `mcp.rs` | operating |

### Test cases handed over

| Test case | Shows | To |
|---|---|---|
| TC-097-015 | the run of a contest strategy; the contest prompt | auto, frontend |
| TC-039-003, TC-063-003, TC-097-001, their route steps | Origin, credentials, version, profile, boot, query, method, body size | station link |
| TC-039-032, its run, Halt and browser steps | the run under a built-in; the editor | auto, frontend |

### `START-HERE.md`, `_work/issue-operating-draft.md`

The state table: part operating, built by a subagent session; tests 2 to 5 pass and test 1
with the changed folder rule; with `Strategies` as its control interface; one new identity
(CL-097-10), CL-097-07 retired, CL-097-08 and TC-097-015 handed to auto; five markers; ten
lines wait for the operator. The trap: "`part_done.py` gives a part every ledger row under
`backend/<part>/`; a part that holds other parts gets their rows".

The issue draft's bracket "[The element names are added when the part is built.]":
`WstxOperatingPart::OperatingService`; `WstxOperatingStrategies` (CL-097-10, `Shares`);
`WstxStrategies::RankingSharePort`, `AutoSharePort`, `ActivitySharePort`, `AutoRules`,
`AutoKeys`, `ContestActivity`. The table "Differences from the code" above is its input.

## For the operator

One line each; none is decided here.

1. **Should the selection be kept across a restart?** The active strategy and the contest
   in force are not stored; after a station start nothing is active. WSJT-X keeps its one
   special activity in the settings file. Recommendation: keep both in the hidden store and
   leave Auto off at station start, so that Band Activity is ordered at once and nothing
   transmits without the operator; a contest whose period has ended is not taken up again.
   **Answered (operator 2026-11-15, issue 228):** not kept, as the code has it. The model
   stood so already; nothing changed.
2. **One command for defining and selecting, or two.** The model has one (`SaveStrategies`),
   as the code: a selection writes the strategies file and counts its revision. WSJT-X has
   nothing to compare. Recommendation: two commands once line 1 is decided, a save of the
   definitions (the file, the revision) and a selection (no file); one until then.
   **Answered (operator 2026-11-16):** two, both in operating: the save is the strategies'
   CRUD, the selection is made where it is selected. `SaveStrategies` carries
   `expectedRevision` and `strategies`; the new `SelectStrategy` carries `active` and
   `contest`, writes no file, leaves the revision and is refused with `InvalidValue`
   only (`StrategiesPort::selection`). A save that leaves out the active saved strategy
   ends the selection (as the editor does, `client/contact.js` 1837). CL-039-01 lost "the
   choice of the active one"; CL-063-03 takes the selection of the active strategy;
   `SaveRule`, `SelectionRule`, `BuiltinOffer`, `Shares` and the conditions of TC-039-001
   (a), TC-039-003 (b), (f), new planned (h), TC-039-032 (a), (e), (f), TC-097-003 (b),
   (c), TC-063-007 (c) to (e) follow. Difference in the code: `PUT /strategy`
   (`strategy.rs` `put`) takes the whole configuration, a selection rewrites
   `strategy.json` and raises the revision, and can be refused `stale_revision` or
   `storage_unavailable`; the client selects by a whole save (`client/contact.js` 1374,
   1377, 1643).
3. **What the contact does with the contest's special activity.** Operating gives it
   (`ContestActivity`); in the code the activity stays the operator's own setting and a
   contest run waits until it fits. WSJT-X has only the setting. Recommendation: while a
   contest is in force the contact takes the contest's activity, and returns to the
   operator's setting when it ends; one selection instead of two.
   **Answered (operator 2026-11-15, issue 228):** as recommended; the exchange text of Field
   Day and RTTY Roundup stays the operator's. See the last section.
4. **The continent the operator sets.** It is a value of the strategies file
   (`StrategyConfiguration::continent`) and is used by ranking alone; it is not among the 53
   settings. WSJT-X has no such setting. Recommendation: a value of ranking's configuration
   (`RankingConfig`), stored in the station config, out of the strategies file.
   **Answered (operator 2026-11-15, issue 228):** a setting of the station, in the station
   config (`ProfileConfig::continent`), out of the strategies file. See the last section.
5. **The permanent ignore list.** Kept by operating in the strategies file and given to
   ranking, as `settings.csv` proposes. Recommendation: keep it so; it is a list the
   operator defines, like the strategies, and ranking only reads it.
   **Answered (operator 2026-11-15, issue 228), otherwise:** one ignore list for the session,
   held by ranking; the permanent list goes. See the last section.
6. **The identities.** CL-097-10 is new; CL-097-07 is retired into CL-097-01; CL-097-08 and
   TC-097-015 go to auto. Recommendation: keep all four.
   **Answered (operator 2026-11-16), after reading the old texts, the code and the tests in
   full:** keep all four. CL-097-07 is not only CL-097-01's promise: it has four pieces,
   each with a home (`StrategyForm` with CL-097-01; `BuiltinStrategies` with CL-039-11;
   `SelectionRule` and `ConfigurationKeys` with CL-063-03, the prompt the frontend's;
   ranking's CL-063-04); the ledger row names them. CL-097-08's run is tested by
   `tc_097_018_cq_after_exactly_the_cq_wait` and `tc_097_018_the_cq_wait_starts_again`
   (TC-097-018, still TO PLACE, for Auto). TC-097-015's server test is the contest run
   and two refusals (TC-063-007 (b), (d)); its browser test is the prompt.
7. **The package of the function file** is `WstxOperatingStrategies`, because
   `WstxStrategies` is the interface. Recommendation: keep; the other way is to rename the
   function file (for example `StrategyStore`), which M2.1 would have to name.
   **Answered (operator 2026-11-16):** after the settings move the file holds one function,
   offering the built-ins and contests, holding the selection and giving the shares; it is
   renamed `backend/operating/StrategySelection.sysml`, package `WstxStrategySelection`
   (the package rule needs no special case); M2.1 changed (`Foundation/README.md`). The
   sections of this report above name the old file and package as they were written.
8. **The clock of a contest's period.** The code offers the period by the clock of the PC.
   Recommendation: station time, by a port `time` of operating like those of receive and
   transmit.
   **Answered (operator 2026-11-15, issue 228):** station time, in UTC; the port `time` is
   written. See the last section.
9. **The names of the entities of the country file.** Operating checks a saved country
   entry against them and has no connection to the log. Recommendation: a connection from
   operating to the log for `EntityRequest`, as ranking has one.
   **Decided by rule (2026-11-16):** the method's entry "data, management and use are
   divided" says a rule that needs other data stays with the data and the profile is given
   those facts; M5.3 gives the way, through the station service. `WstxProfileAccess::
   RuleFacts` (the entity names, from the new `CountryFileState::entityNames`, and the
   names of the built-ins, from `StrategiesState::builtins`); `CollectionRule` takes them;
   the marker is gone. Code: `strategy.rs` reads the log's table itself
   (`state.logbook.dxcc()`, `countries_of`).
10. **The refusal of a save** is written as four specialised attribute definitions, not as
    an enumeration with an optional field. Recommendation: keep; the other interfaces use
    an enumeration, and the main session may prefer one form for all.
    **No longer applies (2026-11-16, the settings move):** the save went to the profile,
    whose refusals are the enumeration `SaveRefusal`; a selection has one refusal,
    `StrategiesRefused` with its field.

## Not done, and what is not sure

- Nothing outside `docs/sysmlV2` was touched; nothing was committed or posted; no agent
  was started. `Station.sysml`, `Requirements.sysml`, `START-HERE.md`, `handover.md`,
  `files.md`, `settings.csv`, the Foundation and the profile's files are unchanged.
- `part_done.py operating` fails test 1 for the reason at the top.
- Read in full: `contest.rs`; of `strategy.rs` lines 1 to 1235 (the data, the parser, the
  upgrades, the built-ins), 2076 to 2300 (the alert log, `Inner`, `Owner`, `lock`), 2360 to
  2490 and 2590 to 3231 (the envelope, the Auto switch, the snapshot, `put`, `evaluate`,
  the routes). Not read: lines 1236 to 2075 (geography, the evaluator, the session list:
  ranking's) and 2300 to 2360, 2490 to 2590 (the Most Wanted list, the alert step).
  `automation.rs` was read only at the lines that use the store; `mcp.rs` at the guard.
- Tests read in full: the 17 bound tests and the helpers they call in the same files
  (`config`, `strategy_json`, `contest_json`, `configuration`, `put`, `select`,
  `builtin_table`, `schema_3`, `mine_v4`). Of `tc_097_015_...` (not bound) the whole body.
  Not read: `tests/ui-operating.test.cjs`, `client/contact.js`, the helpers `station`,
  `publish`, `at_even`, `contest_leaving` of other files.
- The old model: the seven clauses and eleven cases in full; of old
  `interfaces/internal/Strategies.sysml` the texts of `StrategyConfiguration`,
  `StrategyHttp`, `ContestHttp`, `ContestSelection`, `ContestPrompt` and the list of its
  elements; old `auto/Strategy.sysml` was not read (auto's, as ranking decided).
- The texts of `BuiltinStrategies`, `ContestTable` and `ScheduleRule` were written by the
  ranking session; they were compared here line by line with `builtins`,
  `contest_builtins` and `PROFILES` and left unchanged.
- No test shows a strategies file that cannot be written, one over 262144 bytes, or a share
  given to Auto or the contact.
- The size of `interfaces/internal/Strategies.sysml` before this session (13,267
  characters) is the figure of ranking's report; the file was overwritten before a copy
  was taken.
- WSJT-X was read at the local tree (tag v3.3.0-beta6), not at the behaviour baseline.

## Changed after the report: the operator's decisions on ignoring and directed CQs (2026-11-15)

The operator decided six points on 2026-11-15 (issue 228, the decision comment and its two
corrections). The model states them since; the sections above are as they were written,
and where they differ this section holds. This section covers all six decisions; the
ranking report and the profile report hold the same section for their own elements.
Figures are measured by `measure.py` in the session's scratchpad folder `decisions`,
against a copy of the files taken before the change.

### Where each decision stands

| # | Decision | Element | Rule that put it there |
|---|---|---|---|
| 1 | A contest brings its exchange into the QSO | `WstxStrategies::ContestActivity` (new feature `inForce`; text for the contact; the marker is gone); `Shares` | M5.7 and the operating decision: operating gives the contact its share; what the contact does with it is the contact's (not built), stated in the item's text for qso to take up |
| 2 | Selection not kept across a restart | `SelectionRule`, `StrategiesFile` (unchanged) | the code decides; the model stood so |
| 3 | One ignore list, universal in ranking | `WstxIgnoreLists::IgnoreListsRule` (CL-042-02); `IgnoreCommand`, new `ClearIgnoreList`, `RankingState::ignoreList` in `RankingControl` | session state with the function that holds it (ranking holds the list, as it held the session list); the commands reach ranking from the station service over its control interface (M5.3); the universal effect stated once in the ignore rule, which `VerdictRule` and `ContestVerdictRule` name |
| 4 | Directed CQs in three parts | `WstxValueOrder::DirectedCqRule` (CL-039-03); (a) built in there; (b) `WstxProfileAccess::ProfileConfig::cq_words`, given to ranking as `RankingContext::cqWords`; (c) `CqTargetList::included` of a strategy and new `ContestProfile::cqWords` of a contest, used by `ContestDirective` (CL-063-02) | (b) the station's own values in `ProfileConfig`, a change reaches ranking from the station service; (c) a definition with the thing it belongs to: a strategy's words in the strategy (the included CQ targets the code has), a contest's in the contest table |
| 5 | The continent a setting of the station | `ProfileConfig::continent`, given to ranking as `RankingContext::continent`; `StrategyConfiguration::continent` gone | the station's own values in `ProfileConfig`; ranking is given it by the station service (M5.3) |
| 6 | The period by station time, in UTC | port `time : ~StationTimePort` on `OperatingService` (the clock marker is gone); `ContestOffering` | `StationTimeLink`: the clock gives station time to a function that keeps time (M5.4, M5.8), as receive, transmit and qso take it |

### Elements of operating changed

| File | Element | What |
|---|---|---|
| `Operating.sysml` | `OperatingService` | port `time : ~StationTimePort`; the marker on the clock removed; import of `StationTimePort` |
| `Strategies.sysml` (function) | `CL-039-01` | status `partial` (the code keeps the continent and the ignore list in the file) |
| | `SaveRule` | the continent and the ignore list are no rules of a save |
| | `StrategiesFile` | without a file: no saved strategy at revision 0; a configuration with the keys `continent`, `ignore_calls`, `session_ignore_minutes` is read without them (data rule 8, how a reader tolerates old names) |
| | `OlderFiles` | version 1: only "the strategies are not taken over" |
| | `TC-039-001` (a), `TC-039-003` (a), (e) | the continent and the ignore list left out of the setup; (e) a second save |
| | `TC-097-002` (h), new line (i) | (h) keeps what stays; (i) planned: the continent and the ignore list not taken over |
| | `CL-063-01` | status `partial` (the code reads the clock of the PC) |
| | `ContestOffering` | the moment is the station time over the port `time`, in UTC |
| | `TC-063-001` (e), `TC-063-003` (c) | planned: the CQ words of the contests; the station time |
| | `Shares` | `permanentIgnore` gone; the contact is given whether a contest is in force and its activity |
| | imports | `RankingLimits` no longer needed |
| `interfaces/internal/Strategies.sysml` | `StrategyConfiguration` | `continent` and `ignoreCalls` gone; its text |
| | `ConfigurationKeys` | the configuration has the keys active, strategies and contest |
| | `SaveStrategies` | its text: no ignore list, no continent |
| | `ContestProfile` | new feature `cqWords` |
| | `ContestTable` | one sentence: the CQ words of each contest (the word of its activity, from `Activity::cq` in `contact.rs` and the activity of each profile in `contest.rs`) |
| | `ContestActivity` | the text for the contact, new feature `inForce`, the marker gone |
| | imports | `WstxLogControl::Continent` and `ModelNotes::NotStated` gone |
| `_descriptions/operating.md` | sections 1, 2, 3, 4, 5, 7, 10 | as the model now says |
| `_work/parts.json` | operating | `StationTime.sysml` in `validate_with`; five verdicts rewritten (`IGNORE_CALLS_MAX`, `SESSION_IGNORE_MAX`, `SESSION_IGNORE_MINUTES`, `"permanent"`, `"session"`) |
| `_work/settings.csv` | rows | "Permanent ignore list" and "Session ignore list" one row "Ignore list (callsigns with * and ?)"; "Session minutes of the session ignore list" deleted; three rows added: "Continent of the station", "CQ words for this station (allow list)", "CQ words of a strategy or contest" |

In the merged settings row the cells not named in the brief come from the row "Session
ignore list" (menu, WSJT-X, how checked, model today), and "Stored today" names both lists
("strategy.json (permanent list) and not saved (session list)").

Sizes (characters): `Operating.sysml` 2,207 to 2,158; the function file 36,186 to 36,558;
the interface `Strategies.sysml` 23,523 to 23,897; `_descriptions/operating.md` 19,321 to
18,945. The function file grew by four planned lines and the tolerant reading of the file.

### Identities

None is new, retired or not carried; the ledger is unchanged. Reworded (conditions or
setup changed, the identity kept): TC-039-001, TC-039-003, TC-097-002, TC-063-001,
TC-063-003. Status changed to `partial`: CL-039-01, CL-063-01.

### Differences from the code (for the code issue)

| Difference | Place in the code |
|---|---|
| The contact's special activity is the operator's setting alone; a contest sets none, and a contest run waits with the reason `activity` until the setting is the contest's | `server/src/automation.rs` `strategy_context`; `server/src/contact_http.rs` `command` (`set_activity`) |
| The contest prompt shows a hint that the station is on another activity | `client/contact.js` (`cp-activity`) |
| The strategies file and the save carry `continent`, `ignore_calls` and `session_ignore_minutes`, check them and refuse a save by them; a file of version 1 takes them over and is unusable with a wrong continent | `server/src/strategy.rs` `Config`, `parse_config`, `upgrade`, `Config::json`, `Owner::put` |
| The period of a contest is offered by the clock of the PC | `server/src/strategy.rs` `contests_route` (`SystemTime::now`) |
| No CQ words of a contest: the word comes from the station's special activity | `server/src/contest.rs` `PROFILES` (no such field); `server/src/contact.rs` `Activity::cq` |

Test 4 of operating: 19 matched, 22 with a verdict, as before; five verdicts now read
"difference in the code: ... (operator 2026-11-15), issue 228".

### For `Station.sysml` and `handover.md` (for the main session)

`Station.sysml`, after `interface timeQso`:

```
        interface timeOperating : StationTimeLink connect clock.time to operating.time;
```

`StationTimeLink` is imported there already. A scratch copy of the tree with this line
has the same 64 validator errors as without it (line numbers shifted by one).

Handover rows: listed in the final report of this session to the main session (qso: the
activity and the CQ words of its own CQ; auto: no answer to an unranked or not-for-me CQ,
its CQ words; frontend: the one ignore list, the CQ words in Settings, the contest prompt
without its hint; station service: the continent and CQ words in `RankingContext`, the
commands of the ignore list; station link: the routes of the ignore list and of the
strategies without the continent and the ignore keys).

### For the operator

1. **The CQ word of a special activity set by hand.** The three parts leave no place for it:
   under the activity rtty (RTTY Roundup, no contest of the table) CQ RU is not for the
   station unless RU is among its CQ words or a strategy's. The code takes the activity's
   word (`answerable_in`). WSJT-X uses the activity's word for the station's own CQ.
   Recommendation: keep the three parts; the operator adds RU to the station's words.
2. **A contest without an activity** (IARU 50 and 70 MHz MGM, FT8 Activity): the model
   says the contact then uses no special activity, not the operator's setting (from
   "uses the special activity of that contest in place of the operator's own").
   Recommendation: keep.
3. **The continent derived "from the locator".** The brief says so; the model and the code
   derive it from the entity of the profile's call first and from the locator only after
   (`MyContinent`, `my_continent`). Not changed. Recommendation: keep the call first.
4. **An older strategies file's continent.** The model reads a file with `continent`
   without taking it over. Whether the station service moves it into the station config
   once is not decided. Recommendation: move it once, at the first start after the code
   change, and only when the station config has none.

### Verified and not verified

- `part_done.py` passes for operating, ranking, profile, log and spots.
- `check.py` on `backend/operating`, `backend/profile` and the three interfaces: no
  finding. The history grep of the changed model files finds only test names and "today"
  of the worked window.
- The validator on the whole tree: 64 errors before and after, the same lines.
- Read in full for this change: `strategy.rs` lines 430 to 490, 1340 to 1500, 1735 to 2035;
  `contest.rs` lines 755 to 795; `automation.rs` lines 1000 to 1016, 1335 to 1350, 1905 to
  1954; the bound tests `tc_039_001_configuration_is_exact`,
  `tc_039_030_an_old_file_upgrades_and_active_never_survives_a_restart`, and of
  `tc_039_003_store_routes_and_evaluate` the lines up to the evaluation. Not read again: the
  other bound tests of operating.

### Answered by the operator (2026-11-15), and what it changed

The operator answered the eight questions of this section and of the ranking and profile
sections in one message (a to h, in the order of the session's final report).

| Question | Answer | Model |
|---|---|---|
| a. The CQ word of an activity set by hand outside a contest (RU) | "yes, if it was according to the rules, and in the correct time" | not changed: open, line 1 below |
| b. A contest without an activity: no special activity | yes | as written |
| c. The continent from the call first, then the locator | ok; the operator can change it anyway | as written |
| d. Move an old file's continent into the station config | no; an empty continent must give an error message | not moved (the file's continent is not taken over, as written); `ProfileConfig::continent`: while the station has no continent, neither set nor derived, the operator is shown an error message that asks him to set it |
| e. The size of the ignore list | 20 is enough | `RankingLimits::ignoreListMax = 20`; a further entry refused with the new `RankingRefusal::ignoreListFull`; the marker on `IgnoreListsRule` is gone; TC-042-002 (d) planned line extended |
| f. The why text | yes | as written |
| g. Entries of "*" and "?" only refused | no: an entry needs at least one letter | `IgnoreCommand::call`: "with at least one letter"; TC-125-001 (f) planned line extended ("1+", "+/1") |
| h. The country word | find a ham radio country abbreviation list | the primary prefix of the entity of the profile's call in the country file (`cty.dat`, AD1C, bundled in `server/third-party/cty/`; `WstxLogControl::CallEntity::primaryPrefix`): HB for Switzerland, DL for Germany, JA for Japan; it is the form of directed CQs on the air (CQ JA, CQ DL). The marker on `cq_words` keeps only the number of words |

New differences from the code: the code has no bound of 20 and no refusal of a full list
(`strategy.rs` `Owner::ignore`, `Session::add`); it takes an entry without a letter such as
"1*" (`ignore_entry`); it shows no error message for an unknown continent (`my_continent`
gives none and every directed CQ is grey); it proposes no CQ words. Test 4 of ranking: two
verdicts added (`RankingLimits::ignoreListMax`, `RankingRefusal::ignoreListFull`), two
rewritten.

Open for the operator:

1. **Answer a.** Two readings: (i) the CQ word of a special activity counts again, as a
   fourth source, while the activity is set according to the rules of its contest and
   within that contest's time; (ii) a contest's CQ words count only within the period of
   the contest in force. The model can state (ii) at once (`ContestInForce` has the
   period). For (i) the model has no time for an activity without an entry in the
   contest table (RTTY Roundup, EU VHF). Recommendation: (ii), and RTTY Roundup added to
   the contest table later if its word is wanted.
   **Answered (operator 2026-11-15, issue 228, last comment):** (ii). A contest's CQ words
   count only while it is in force and station time lies in its period; an activity set by
   hand gives no word, the operator adds it to the station's CQ words. The model stood so
   already (`WstxContestRanking::ContestDirective`, `ContestProfile::cqWords`); nothing
   changed (found 2026-11-16).

## Changed after the report: the strategies are managed by settings (operator 2026-11-16)

Operating keeps the data of a strategy (`Strategy`, `StrategyForm`, `StrategyReading`,
`ConfigurationKeys`, the built-ins, the contests) and the selection; the profile manages
the saved strategies (create, update, delete by name, the file `strategy.json` in the
operator's folder, the rules applied). Operating reads them as `SavedStrategies`.

| Moved or changed | Where now |
|---|---|
| CL-039-01 (`SaveRule`, `StrategiesFile`, `OlderFiles`), TC-039-001, TC-039-003 (a), (b), (d), TC-097-002 | the profile (`CollectionRule`, `StrategiesFile`, `WstxStrategies::StrategyReading`) |
| CL-097-01 (`StrategyForm`), TC-097-001 | the profile's `StrategyCheck`; `StrategyForm` itself in the interface |
| TC-039-003 (f), (g) | TC-063-007 (f), (g), with its test bound there too |
| TC-039-032 (b), (c), (f), (g) | TC-097-001 (g), TC-097-002 (g) |
| `SaveStrategies`, `StrategiesState::revision`, `unusable`, `renamed`, the four refusals, `OperatingContext` | gone; `StrategiesRefused` has a field only (a selection); `SavedStrategies` new |
| the marker on the country file's names | the profile's `CollectionRule` |

Differences in the code: operating's module (`strategy.rs`) keeps, checks and writes the
strategies with the whole configuration (`put`); the bound tests of the moved cases
assert that form.
