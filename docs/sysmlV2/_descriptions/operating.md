# Operating

A view of the model, written from `docs/sysmlV2` on 2026-11-16 (working tree, not
committed). It adds no fact and decides nothing. Read: `backend/operating/Operating.sysml`,
`backend/operating/StrategySelection.sysml`, `interfaces/internal/Strategies.sysml`, and of
`Station.sysml`, `interfaces/internal/RankingControl.sysml`, `ProfileAccess.sysml`,
`backend/profile/ProfileDocument.sysml` and `backend/operating/ranking/Ranking.sysml`
only the elements operating uses. Not read: the code, the issues, the old model, the
files of ranking, Auto and the contact beyond those.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Strategy | a named set of rules: the ranking rules, the rules Auto executes, and for class contest the id of its contest | `Strategy` |
| Class | where the ranking rules of a strategy come from: its own (strategy) or a contest's (contest) | `StrategyClass` |
| Rules of a strategy | what a saved strategy must be; operating's, applied by the settings function | `StrategyForm`, `StrategyReading` |
| Saved strategy | a strategy the operator has defined; managed by the settings function (the profile) and read by operating | `SavedStrategies`, `WstxProfileAccess::StrategyDefinitions` |
| Built-in | a strategy the station offers and that cannot be changed | `BuiltinStrategies`, `BuiltinOffer` |
| Configuration | the saved strategies and the selection, as operating holds them | `StrategyConfiguration` |
| Selection | the active strategy and, for class contest, the contest with its period | `SelectionRule` |
| Contest | one entry of the table of contests, with the facts of its official rules | `ContestProfile`, `ContestTable` |
| Contest in force | the contest of the selection, with its period | `ContestSelection` |
| Offered period | the period of the next round of a contest by its schedule | `ScheduleRule`, `OfferedPeriod` |
| Share | what one of ranking, Auto and the contact is given of the active strategy | `Shares` |

"Contest" stands for the entry of the table and, in `Strategy::contest` and
`StrategyConfiguration::contest`, for the id and for the selection of one; the elements
keep them apart. "Period" is the offered one (`OfferedPeriod`) or the one in force
(`ContestSelection`), which need not be equal.

## 2. Place in the system

Position: the model files of operating do not say it. `Station.sysml` has no usage of
`OperatingService` yet; `RankingService`, which operating holds, stands there as
`Station` > `backend` > `stations` > `ranking`. This is a gap (section 10).

| Port of operating | Other end | Interface | What crosses |
|---|---|---|---|
| `control` | station service | `StrategiesControl` | in: `SavedStrategies`, `SelectStrategy`, `ReadStrategies`, `ReadContests`; out: `StrategiesState`, `ContestList`, `StrategiesRefused` |
| `rankingShare` | ranking (`rules`) | `RankingShare` | out: `RankingRules` |
| `autoShare` | Auto | `AutoShare` | out: `AutoRules` |
| `activityShare` | the contact | `ActivityShare` | out: `ContestActivity` |
| `time` | the clock | `StationTimeLink` | in: `StationTime` |

The directions are from operating's side. No connection of these five is written in
`Station.sysml`; the ports of Auto and of the contact that take the shares are not in
the model.

Not connected: the profile, receive, transmit, radio control, audio, the modes part, the
log, spots, udp, web and mcp. Operating takes every command and the saved strategies from
the station service; it keeps no file. The settings function (the profile) creates,
changes and deletes a saved strategy and holds it to operating's rules (`StrategyForm`).

## 3. Purpose and requirements

Operating owns what a strategy is and its rules, offers the built-in strategies, knows the
contests and offers their periods, holds the selection, and gives ranking, Auto and the
contact each its share of the active strategy. It reads the saved strategies. All four
clauses derive from FR-026.

| Clause | Promise | Element | Status (the model's declaration) |
|---|---|---|---|
| CL-039-11 | offer the built-in strategies beside the saved ones, each selectable, none changeable | `BuiltinOffer` | implemented |
| CL-063-01 | know each contest by the facts of its rules and offer the period of its next round | `ContestOffering` | partial |
| CL-063-03 | take the selection of the active strategy, put a contest in force only with its period and an active strategy of class contest for it, and hold the selection until the next one or the stop of the station | `SelectionRule` | implemented |
| CL-097-10 | give ranking, Auto and the contact each its share, at station start and at every change | `Shares` | partial |

The saving of strategies (CL-039-01) and the check of a strategy (CL-097-01) are the
profile's clauses; they apply the rules below.

## 4. Data and rules

### A strategy (`Strategy`, `AutoKeys`, `StrategyClass`, `LeaveMode`)

| Feature | Type | Rule |
|---|---|---|
| `name` | text | 1 to 32 printable ASCII characters, no space at either end; once among the saved ones without regard to letter case; not a built-in's name |
| `strategyClass` | strategy or contest | |
| `ranking` | `RankingKeys` (ranking's interface) | class contest uses of it the bands, the three lists and `callersFirst` |
| `contest` | id of a contest | present for class contest, absent for class strategy |
| `auto` | `AutoKeys` | every strategy of either class has every value |

| `AutoKeys` | Rule |
|---|---|
| `leaveMode` | calls, until_logged or contest |
| `leaveCalls`, `leaveCallsHeard` | with calls: 1 to 20, and from `leaveCalls` to 40 |
| `goneMinutes` | with until_logged: 1 to 60 |
| `txChanges` | with contest: 1 to 20 |
| `moveEveryHeard`, `moveEveryNotHeard`, `moveEveryNoReports` | 0 never, 1 at every call, n at every n-th call, up to 20 |
| `busyPause`, `cqWhenIdle` | on or off |
| `cqWaitPeriods` | 1 to 20; held also while `cqWhenIdle` is off |
| `retryMinutes` | 1 to 120 |

### The rules of a saved strategy (`StrategyForm`, `StrategyReading`)

| Rule | |
|---|---|
| form | each value within the rule of its feature in `Strategy`, `AutoKeys` and `RankingKeys` |
| class strategy | names no contest |
| class contest | names a contest of the table, has an empty order and only the bands, the three lists and `callersFirst` of the ranking rules |
| country entry | of the kind country, names an entity of the country file without regard to letter case, held as the country file writes it |
| count | at most 16 saved strategies (`strategiesMax`) |
| refusal | one value outside its rule is named, as `ConfigurationKeys` says |

`StrategyReading` says how the strategies file is read: a strategy without
`cq_wait_periods` with a CQ wait of 2; the keys `continent`, `ignore_calls` and
`session_ignore_minutes` read without their values; a saved strategy named like a
built-in read under the name with "copy" after it, then "copy 2", "copy 3", the first
free one, cut to 32 characters. A version 3 strategy (class award, with goals, needed,
value, window, repetitions, quiet_minutes, cq_when_no_target) becomes one of class
strategy for every band; its goals give what is new and the one scope (band_mode before
band before ever); it is left after `repetitions` calls and twice as many while heard. A
version 2 strategy has `calls_per_station` and is read as one of version 3 with the order
most_wanted, 4 repetitions and 10 quiet minutes. Of a version 1 file the strategies are
not taken over. A file of another version, or with a strategy outside its form, cannot be
used.

### The built-ins (`BuiltinStrategies`)

Five of class strategy, in this order, then one of class contest for each contest of the
table under the contest's name.

| Built-in | What differs from the common values |
|---|---|
| common, class strategy | every band; region all; no minimum SNR; worked since all; Treat 73 as CQ on; empty lists; calling stations answered; leaving after 4 calls and 8 while heard; frequency moved never, at every call, at every 2nd call; busy pause on; no CQ when idle; CQ wait 2; retry pause 10 minutes |
| DXCC all | new dxcc per band_mode, not_confirmed; order most_wanted, snr; leaving until_logged after 10 minutes |
| New DXCC on band | as DXCC all, per band |
| New DXCC | as DXCC all, per ever |
| Casual | new call per band, not_worked; order snr_bucket, distance; CQ when idle |
| POTA/SOTA | as Casual, worked since today, CQ targets POTA and SOTA included, no CQ when idle |
| each contest | every band; empty lists; no order; calling stations answered; leaving in the mode contest after 2 Tx changes; frequency moved never, at every 2nd, at every 2nd call; busy pause off; CQ when idle with a CQ wait of 2; retry pause 10 minutes |

### The configuration (`StrategyConfiguration`, `ConfigurationKeys`)

| Feature | Rule | Kept by the settings |
|---|---|---|
| `strategies` | at most 16 (`strategiesMax`), ordered | yes |
| `active` | the exact name of a saved strategy or a built-in, or absent | no |
| `contest` | present exactly while the active strategy is of class contest | no |

`ConfigurationKeys` gives the names under which the values are written in the strategies
file and named in a refusal: a path of keys joined by full stops with list places in
square brackets from 0 (`strategies[0].leave.calls`), `configuration` for the whole. An
object with a key missing or a key more is named as a whole, except a strategy without
`cq_wait_periods` and a contest selection with `automation_confirmed`, `operation`,
`repetitions` or `quiet_minutes`, which are named by that key. A list of the wrong length
is named as a whole, a wrong or repeated member by its place.

### The contests (`ContestTable`, `ContestProfile`, `ScheduleRule`)

Nine contests, in the order offered: ww_digi, arrl_digi, arrl_field_day, arrl_vhf_jan,
arrl_vhf_jun, arrl_vhf_sep, iaru_50_mgm, iaru_70_mgm, ft8_activity. Each has an id, a
name, a special activity or none, its CQ words (the word of its activity: WW, TEST or FD;
none without an activity), its bands, a dupe rule, a points rule, a multiplier rule, the
modes it counts, its automation clause (forbidden or silent) and its schedule; the table
gives the values of each. A schedule is one or more rounds on the n-th or last
full weekend of a month, the n-th Saturday of a month or the n-th weekday of every month,
or its day is asked (arrl_vhf_jan).

### Commands and answers (`StrategiesPort`)

| Item | Carries | Answer |
|---|---|---|
| `SavedStrategies` (from the station service) | the saved strategies, at station start and after every change | none |
| `SelectStrategy` | `active` (a name, or none), `contest` (for class contest) | `StrategiesState`, or `StrategiesRefused` with the field |
| `ReadStrategies` | nothing | `StrategiesState` |
| `ReadContests` | nothing | `ContestList` |

`StrategiesState` has the `configuration` and the `builtins` in their order.
`ContestList` has one `ContestOffer` for each contest: the id and the `OfferedPeriod`
(start, end, and the band of a round that has one), absent for a contest whose day is
asked.

### The shares

| To | Item | Content |
|---|---|---|
| ranking | `RankingRules` | `active`: name, `Strategy::ranking`, and for class contest the contest with the two instants of its period |
| Auto | `AutoRules` | `active`: name, `Strategy::auto`, and for class contest the `ContestSelection` |
| the contact | `ContestActivity` | `inForce` and the special activity of the contest in force, or none; while a contest is in force the contact uses it (no special activity for a contest without one) in the place of the operator's own setting, which holds again when no contest is in force; the exchange text of Field Day and RTTY Roundup stays the operator's |

## 5. Behaviour

### The selection (`SelectionRule`)

| Selected | Taken when |
|---|---|
| no strategy | no contest is given; a contest in force ends |
| a strategy of class strategy | no contest is given |
| a strategy of class contest | the contest it names is given with a period: start and end to the minute, end after start and at most 31 days (`periodDaysMax`) after it |

`active` is absent or exactly the name of a saved strategy or a built-in. Every other
combination is refused by the contest; a wrong value of the selection by its own name
(`StrategiesRefused` with the field), and a refused selection changes nothing. A selection carried out is
answered with `StrategiesState` and gives the shares anew; it writes no file. The period
need not be one the schedule offers. The selection holds while the station runs and is
not kept by the settings: at station start nothing is active. When a change of the saved
strategies leaves out the active saved strategy by its name, the selection ends.

### The built-ins (`BuiltinOffer`)

They are listed in every state of operating and selected by their exact name; no saved
strategy has a built-in's name, without regard to letter case.

### The contests (`ContestOffering`)

The list names every contest in the order of the table. The period of each is that of
the round that has not ended and starts first, at the station time of the question (in
UTC, taken over the port `time`); a running
round is offered until its end. A limit that depends on the place of the station or the
class of the entry is a note; every contest is offered to every station.

### The shares (`Shares`)

Operating gives the three shares at station start and gives a share anew whenever the
saved strategies or the selection change a value of it. While no strategy is active, the
active strategy is absent in both rule items and the activity is absent. A function is
given its own share and no other value of a strategy.

## 6. Implemented in and tested by

`OperatingService`: `server/src/strategy.rs`, `server/src/contest.rs`. Detail tests:
`server/src/strategy_tests.rs`, `server/src/strategy97_tests.rs`,
`server/src/contest_tests.rs`, which also cover the evaluator of ranking and the runs of
Auto.

## 7. What it relies on from outside

| Element | Needed for |
|---|---|
| `WstxRankingControl::RankingKeys`, `RankingRules`, `StrategyRules`, `ContestInForce` | the ranking rules of a strategy, ranking's share |
| `WstxProfileAccess::StrategyDefinitions` | where the saved strategies are kept (named in text) |
| `WstxStationTime::StationTimePort` | station time, the moment of a `ReadContests` |
| `FR-026` | the requirement the clauses derive from |

Named in text without an element: the country file and its entity names; the special
activities (`ContestProfile::activity` is a text); "the contact" and "Auto" as parts.

## 8. Differences from a named reference

None is recorded. The model names no reference for the strategies; `ContestTable` follows
the official rules of each contest.

## 9. Verification

All six cases declare cost 2, the development PC, automated.

| Case | Verifies | Shows |
|---|---|---|
| TC-039-032 | CL-039-11 | a built-in is selected by its exact name and is not kept |
| TC-097-003 | CL-039-11, CL-063-03 | the list of the built-ins; a contest built-in only with its contest |
| TC-063-001 | CL-063-01 | the facts of the nine contests |
| TC-063-002 | CL-063-01 | the offered period of each contest, the full weekend, the rounds of ft8_activity |
| TC-063-003 | CL-063-01 | the list of the contests |
| TC-063-007 | CL-063-03, CL-097-10 | the selection of a contest, its refusals, that it is not kept; ranking under it and under a selected strategy |

Every clause has a case. Of CL-097-10 the cases show the share of ranking only; the
model says so in TC-063-007 (g) ("Planned, no test yet").

## 10. Open points, gaps and disagreements

Marked by the model:

- `Shares` (`NotStated`): by which rules a draft strategy offered for an evaluation is
  checked; the code holds it to `StrategyForm`, and no command carries a draft.

Gaps:

- `Station.sysml` has no usage of `OperatingService`, no connection of its five ports and
  no `satisfy` of FR-026 by it. Missing from the files read, not from the part.
- Auto and the contact have no port that takes `AutoRules` and `ContestActivity`.

Disagreements and observations:

- `ConfigurationKeys` says a value written as absent is null, and that `contest` may also
  be left out: one value has two absent forms.
- `ContestProfile::activity` and `ContestActivity::activity` are texts, not a type of the
  contact's activities (weak link).
- `StrategyForm` names the country file only in text; the settings function takes the
  entity names from `RuleFacts`, which the station service gives it.
