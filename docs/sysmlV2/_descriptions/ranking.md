# Ranking

A view of the model, written from `docs/sysmlV2` on 2026-11-15 (working tree, not
committed). It adds no fact and decides nothing. Read: the seven files of
`backend/operating/ranking/`, `interfaces/internal/RankingControl.sysml`,
`interfaces/internal/Strategies.sysml`, `interfaces/external/ClubLog.sysml`, and of
`Station.sysml`, `Context.sysml`, `interfaces/internal/OperatingChain.sysml`,
`Decodes.sysml`, `Hearing.sysml` and `LogControl.sysml` only the elements ranking uses.
Not read: the code, the issues, the old model.

## 1. Terms

| Term | Meaning | Element |
|---|---|---|
| Strategy | a named set of rules: ranking rules, the rules Auto executes, and for a contest the facts of its official rules | `Strategy` |
| Active strategy | the one strategy ranking works by, or none | `RankingRules::active` |
| Verdict | what ranking says about one decoded record: rank or none, grey or not, why | `Verdict` |
| Rank | the place among the ranked records of one evaluation, from 0 | `Verdict::rank` |
| Grey | the record is a CQ whose directive leaves the station out | `Verdict::grey`, `DirectedCqRule` |
| Directive | what stands between CQ and the sender's call | `DirectedCqRule` |
| Caller | a record whose message goes to the profile's call and is no RR73 and no 73 | `CallerOfMyCall` |
| Candidate | a record that passes every line of the strategy's filter | `Candidate` |
| New | not worked, or not worked or not confirmed, in a scope | `NewNeeded`, `Needed`, `NewPer` |
| Station's band | the band of the dial radio control confirms, else that of the operating selection | `RankingContext::band` |
| Evaluation | one set of records judged together | `Evaluation` |
| Count | the QSOs of a contest's period counted by the contest's rules | `ContestCount` |
| Ignore list | the one list of calls and patterns ranking holds for the session | `IgnoreListsRule` |
| CQ words | the words after CQ that make a CQ one for the station: the station's own, the strategy's, the contest's | `DirectedCqRule`, `RankingContext::cqWords`, `CqTargetList::included`, `ContestProfile::cqWords` |
| Most Wanted list | the ranks of DXCC entities from Club Log | `MostWantedListRule` |
| Alert | a record of a newly decoded candidate | `AlertRule`, `AlertEntry` |
| Decoded facts | entity, new-flags and worked status of the sender of a decoded record | `DecodedEntity`, `DecodedFacts` |
| Wanted list | the calls and patterns the operator wants worked first; kept by the settings function for the operator's stations | `WantedEntry`, `WantedRule` |

"Rank" has two meanings: the place in a ranked list (`Verdict::rank`) and the place of an
entity on the Most Wanted list (`MostWantedRow::rank`). The wanted list (the operator's
calls) and the Most Wanted list (Club Log's entities, downloaded, not editable) are two
different things.

## 2. Place in the system

Position: `Station` > `backend` > `stations` (one per profile) > `ranking : RankingService`.

| Port of ranking | Other end | Interface | What crosses |
|---|---|---|---|
| `control` | station service | `RankingControl` | in: `RankingContext`, `EvaluateRequest`, `IgnoreCommand`, `ClearIgnoreList`, `ReadRankingState`, `ReadAlerts`, `ClearAlerts`, `UpdateMostWanted`; out: `RankedList`, `EvaluateReply`, `RankingState`, `Alert`, `DecodedFacts`, `RankingRefused` |
| `rules` | operating | `RankingShare` | in: `RankingRules` |
| `decodes` | receive | `Decodes` | in: `ResultRecord`, `PeriodView` |
| `ranked` | auto | `RankedActivity` | out: `RankedList` |
| `workedBefore` | log | `WorkedBefore` | out: `WorkedWindow`, `EntityRequest`, `ContestPeriod`; in: `WorkedSet`, `EntityAnswer`, `PeriodQsos` |
| `hearing` | spots | `Hearing` | in: `HearingReport` |
| `clubLog` | the Club Log service of the context | `ClubLog` | out: `MostWantedQuery`; in: `MostWantedDownload` |

Not connected: transmit, qso, radio control, audio, the clock, the modes part, udp, the
profile, web and mcp. Ranking can therefore start no contact and transmit nothing, and it
takes every command and every profile value from the station service. It has no port
toward the profile although it keeps a file there (marker, section 10).

## 3. Purpose and requirements

Ranking orders the decoded stations by the rules of the active strategy and gives a verdict
for each; it says what is new about each decoded sender, keeps the ignore list and the
Most Wanted list, ranks the wanted stations first, counts the QSOs of a contest and
records alerts. All fourteen clauses derive from FR-026, which `Station.sysml` gives to
ranking.

| Clause | Promise | Element | Status (declared) |
|---|---|---|---|
| CL-039-02 | one verdict for each decoded standard message of a sender with a call, for the decodes of each period and on request | `VerdictRule`, `Evaluation` | partial |
| CL-039-03 | a CQ whose directive leaves the station out is grey and has no rank | `DirectedCqRule`, `MyContinent` | partial |
| CL-042-01 | what is new is judged from what the log says is worked and confirmed; nothing is claimed that cannot be checked | `NewNeeded` | implemented |
| CL-097-02 | rank only on the strategy's bands and only what passes every filter line; name the failing line | `StrategyBandsRule`, `Candidate`, `CallerOfMyCall`, `CountryListRule`, `UsStateFilterRule`, `CqTargetListRule` | implemented |
| CL-097-03 | order by the strategy's criteria, never by decode order; the wanted records first | `ValueOrder`, `StationDistance` | partial |
| CL-055-02 | entity, what is new and worked status for each decoded record whose sender can be named; again for the current period after a change of the logbook, the country file or the band | `DecodedEntity` | partial |
| CL-042-02 | no rank, in every ranking, for a station an entry of the ignore list matches; the list held for the session as the operator makes it | `IgnoreListsRule` | partial |
| CL-039-10 | fetch the Most Wanted list on request, keep the last good one, rank entities by it | `MostWantedListRule` | implemented |
| CL-124-02 | rank first, in every ranking, a wanted station not worked since its entry was added, whenever it can be called | `WantedRule` | target |
| CL-124-03 | report an exact wanted entry once a QSO with its call is logged after it was added | `WantedRemoval` | target |
| CL-042-04 | one alert per newly decoded station worth calling (under a contest: a new multiplier or a wanted station), once per call and band in the dedupe time, with a history | `AlertRule` | partial |
| CL-063-02 | a CQ word of the contest ranked by makes a CQ one for the station | `ContestDirective` | partial |
| CL-063-09 | count the QSOs of the contest's period by the contest's rules; tell QSOs, multipliers, points, score | `ContestCount` | implemented |
| CL-063-04 | under a contest strategy rank only what can be called and is no dupe, by its worth in the contest | `ContestVerdictRule`, `ContestValueOrder` | implemented |

## 4. Data and rules

### What the station service gives (`RankingControl`)

| Item | Carries | Answer |
|---|---|---|
| `RankingContext` | call, locator, station's band, operating mode, the continent the operator set and the CQ words (both of `OperatorConfig`), the wanted list; each may be absent but the mode | none |
| `RankingRules` (from operating, on `rules`) | the active strategy (`StrategyRules`: name, `RankingKeys`, `ContestInForce` for class contest) or none | none |
| `EvaluateRequest` | job, first and next sequence (at most 2048 apart), an optional draft, explain | `EvaluateReply` or `RankingRefused` |
| `IgnoreCommand` | an entry (1 to 13 characters of A to Z, 0 to 9, "/", "*" and "?", with at least one letter), ignore or not | `RankingState`, or `RankingRefused` (`ignoreListFull`) |
| `ClearIgnoreList` | - | `RankingState` |
| `ReadRankingState` | - | `RankingState` |
| `ReadAlerts`, `ClearAlerts` | - | `Alert` |
| `UpdateMostWanted` | - | `RankingState` or `RankingRefused` |

`RankingKeys`: bands (absent: every band); newWhat (`dxcc`, `call`, `grid`, `cq_zone`,
`itu_zone`, `continent`, `prefix`); newPer (`ever`, `band`, `band_mode`); newMeans
(`not_worked`, `not_confirmed`); region (`all`, `dx`, `selected` with continents); minSnrDb
(-50 to 49); workedSince (`all`, `today`, `from_to` with two dates); treat73AsCq; the
country list (64 entries each side, kind `prefix` or `country`, optional bands); the US
state lists (the 50 states and DC); the CQ target lists (32 words each side); order (up to
16 `ValueCriterion`, each once); callersFirst. A strategy of class contest gives bands, the
three lists and callersFirst only.

Refusals (`RankingRefusal`): `notConfigured`, `staleRequest`, `downloadFailed` (with a
reason), `storageUnavailable`, `ignoreListFull`. A refused command changes nothing.

### What ranking gives

| Item | Content |
|---|---|
| `RankedList` | the period view evaluated; the verdicts: ranked records by rank, then the others |
| `Verdict` | sequence, rank (absent: not ranked), kind (`caller`, `candidate`), grey, why, and under a contest `ContestVerdict` (dupe, newMultiplier, points) |
| `EvaluateReply` | strategy name (the contest's name under a contest), the station's continent, the verdicts (without explain only ranked, grey and dupes), the `ContestTally` under a contest while the logbook is available |
| `RankingState` | the ignore list (its entries in the order put on), `MostWantedStatus` (date, entries, unmapped), unreadable flag, the attribution text, the station's continent and the one derived from the call |
| `Alert` | revision; up to 100 `AlertEntry` (id, utc, call, message text, strategy name, band, mode, SNR, entity name) |
| `DecodedFacts` | job, sequence, `EntityView` (shown name, continent, CQ zone, ITU zone, km), the `NewFlag`s that hold (twelve: call, grid, entity, continent, CQ zone, ITU zone, each ever and on the band); the worked status has no feature (marker) |

### The strategy as data (`Strategies`)

`Strategy`: name (1 to 32 printable ASCII, no space at an end, once among the saved ones
without regard to case, not a built-in's), class (`strategy`, `contest`), `RankingKeys`,
the contest id for class contest, and the settings Auto executes: leave mode (`calls` with
1 to 20 calls and up to 40 while heard; `until_logged` with 1 to 60 minutes; `contest` with
1 to 20 Tx changes), three move counts 0 to 20, busy pause, CQ when idle, CQ wait 1 to 20
periods, retry pause 1 to 120 minutes.

`BuiltinStrategies`: DXCC all, New DXCC on band, New DXCC, Casual, POTA/SOTA, and one
built-in of class contest per contest, each with the values the element lists.

`StrategyConfiguration`: up to 16 saved strategies, the active name and the
`ContestSelection` (profile, start, end; at most 31 days), present exactly while the
active strategy is of class contest.

`ContestTable`: nine `ContestProfile`s (ww_digi, arrl_digi, arrl_field_day, arrl_vhf_jan,
arrl_vhf_jun, arrl_vhf_sep, iaru_50_mgm, iaru_70_mgm, ft8_activity), each with activity,
its CQ words (the word of its activity: WW, TEST or FD, or none), bands, `DupeRule` (`band`, `band_mode_class`, `band_grid`, `call`), `PointsRule` (seven),
`MultiplierRule` (`none`, `field_per_band`, `grid_per_band`), `CountedModes` (`ft8Ft4`,
`digital`, `digitalNoRtty`, `any`), `AutomationClause` (`forbidden`, `silent`) and schedule
(`ScheduleRule`).

### The exchange with Club Log (`ClubLog`)

One `MostWantedQuery` (a GET over HTTPS for the fixed address, the station naming itself,
JSON accepted, the certificate checked against the roots of the operating system) is
answered by one `MostWantedDownload`: a JSON object of 1 to 1000 rows, rank to ADIF number
(below 10000, text or number), no number twice. Only status 200 is a list.

## 5. Behaviour

**Default: a record that no rule gives a rank has none, and nothing is new that ranking
cannot check.**

### The verdict under class strategy (`VerdictRule`, `Candidate`, `CallerOfMyCall`)

A record has a verdict when it is decoded, a standard message, and its sender is a call (a
hashed sender has none, also filled in). The first test that holds decides:

| # | Test | Verdict |
|---|---|---|
| 1 | sender ignored | no rank, not grey, why names the list and for a pattern the entry |
| 2 | CQ left to others by `DirectedCqRule` | no rank, grey, "CQ <directive> — not for <continent>" or "not for this station" |
| 3 | sender is the profile's call | "my own message" |
| 4 | off the strategy's bands | "band not in the strategy" / "band unknown" |
| 5 | caller or candidate | a rank when every filter line holds, else the first failing line as why |

Filter lines in order, with their why: callsign guard (three characters, a digit and a
letter, not ending /R); "not a CQ" (a CQ, or with treat73AsCq an RR73 or 73 to another
call); "region"; "below min SNR" (unknown SNR fails a minimum); "not new" (one NewWhat at
least must be new); "country list"; "state list"; "CQ target". A caller is not asked the
guard, the CQ line and the CQ target line; its failing line is written after "calls my
call · "; with callersFirst off a caller that passes has no rank and "calls my call · not
answered". A candidate's why is "new: " with the new things and the band or band and mode.

### What is new (`NewNeeded`)

Ranking asks the log for the `WorkedSet` of the strategy's window. Keys by
`WorkedCategory`; entity keys from the `EntityAnswer`; grid from the first four characters
of a locator in the message. Scopes: every QSO; the station's band; that band in the
operating mode. Nothing is new: entity keys without an entity; band scopes with an unknown
band; grid without a locator in the message or when a QSO with the sender has no grid;
everything without a `WorkedSet`.

### Directed CQs and the continent (`DirectedCqRule`, `MyContinent`, `ContestDirective`)

For the station: a CQ without a directive; CQ DX when both continents are known and differ;
a CQ with one of the station's CQ words; under a strategy, one of its included CQ targets
(either class); under a contest, one of the contest's CQ words, whatever the continents.
Everything else leaves the station out; the special activity the operator sets adds no
word. The station's continent:
set by the operator, else that of the call's entity, else that of the entity nearest to the
locator, else unknown.

### The lists (`CountryListRule`, `UsStateFilterRule`, `CqTargetListRule`)

Country: a prefix entry matches the beginning of the call, a country entry the entity's
name without regard to case; an entry with bands only on those; excluded wins; a non-empty
included list must match. US state: known only for the United States, Alaska and Hawaii,
from an RTTY Roundup exchange among the records evaluated, else from the `WorkedSet`;
excluded fails when known and listed; a non-empty included list needs a known, listed
state. CQ target: asked of non-callers; an excluded directive fails; a non-empty included
list passes only a CQ with a listed directive; the included words are also the strategy's
CQ words.

### The order (`ValueOrder`, `StationDistance`)

Callers first (with callersFirst on); then the criteria in the strategy's order
(most_wanted by list rank; the eleven new_ criteria, new first; snr_bucket above 0 dB,
-10 to 0, below, unknown; snr; distance, farther first; hears_us by
`HearingReport::heardBy`, equal while `inUse` is false); then always SNR, then the lower
audio frequency, then the call. Distance: great circle (6371 km) from the centre of the
profile's locator to the centre of the four-character grid of the message, else to the
entity's position; whole kilometres, cut off; unknown without a locator or without both.

### When ranking evaluates (`Evaluation`)

For each `PeriodView` while a strategy is active, also one published again: one
`RankedList`, given without being asked to Auto and the station service; it names its view
(`periodView`, with `complete`). On an `EvaluateRequest`: under the draft, else the active strategy, else
refused `notConfigured`; another job than the current one `staleRequest`. A contest draft
is counted over the contest in force when it is its contest, else over every QSO. A request
waits for the `WorkedSet` that holds the latest logbook change; a period view takes the set
at hand.

### Under a contest (`ContestCount`, `ContestVerdictRule`, `ContestValueOrder`)

Count: the `PeriodQsos` of the period whose mode is counted and whose band is the
contest's, in order of start, without dupes. Dupes by `DupeRule`; under `band_grid` a QSO
without a grid dupes every grid of that call on the band and is itself a dupe when the
call is counted there at all. Tally: QSOs, multipliers (distinct keys), points (0 where a
needed grid is unknown), score (points times multipliers, or points alone).

Verdict tests in order, each without a rank: ignored; grey by `DirectedCqRule`; "my own
message"; "band unknown"; "band not in the contest"; "log unreadable"; "dupe" (also for a
caller); "callsign guard" (non-callers; without an ending /R under `band_grid`); "not a
CQ". Every other record is a caller or candidate with newMultiplier and points. The
strategy then removes the rank: off its bands, on a failing list, or for a caller with
callersFirst off. Order: callers, new multiplier, more points, stronger SNR, lower
frequency, call.

### The ignore list (`IgnoreListsRule`)

An entry matches the whole call; "*" is any run, "?" one character. The list is held for
the session: not stored, empty at station start, on every band; an entry is put at the
end (a listed one moves last) and stays until the operator takes it off or empties the
list (`ClearIgnoreList`); with 20 entries (`ignoreListMax`) a further one is refused
(`ignoreListFull`). In every ranking, under any strategy or contest, an ignored
sender has no rank and is not grey; without a rank Auto does not answer it, and a reply
by hand is not refused. The why is "<call> is ignored (ignore list)", with the entry for a
pattern; the call itself before a pattern, the first pattern in character order.

### The wanted list (`WantedRule`, `WantedRemoval`, `WantedEntry`)

An entry is a call or a pattern of the ignore list's form, with the moment it was added;
at most 100 (`wantedListMax`), each call once, kept by the settings function in
`wanted.json` of the operator's folder. A sender is wanted while an entry names it and the
logbook holds no QSO with it that started at or after the entry was added.

| A wanted record | |
|---|---|
| can be called on | a CQ, an RR73, RRR or 73 to another call, a message to my call; whatever `treat73AsCq`, `callersFirst`, the filter lines and a contest's verdict say |
| cannot be called | ignored; off the strategy's or the contest's bands; failing the callsign guard; a CQ `DirectedCqRule` leaves to others |
| verdict | a rank, `VerdictKind::wanted`, why "wanted (<entry>)"; it alerts |
| order | first, before the callers and the candidates, ordered among themselves by the strategy's or contest's order |
| without a selection | ranks nothing |

An exact entry leaves the list at its first QSO after it was added: ranking gives
`WantedWorked`, and the station service removes it. A pattern stays until the operator
removes it; each station it names stops being wanted once worked after it was added.

### Most Wanted list (`MostWantedListRule`)

`UpdateMostWanted` sends one query; a download that is a list is written to
`most_wanted.json` in the profile's folder with the UTC date and is in use from then;
anything else is refused with a reason and the list in use stays. After a station start
the file is read when first needed; a file that cannot be used gives no list and the
unreadable flag. The rank of an entity is that of its ADIF number in a table ranking
holds; unmapped counts entries without a name in that table.

### Alerts (`AlertRule`)

Each record of the current job is judged once, also without an active strategy. A
candidate of the active strategy alerts, unless the same call alerted on the same station
band less than 10 minutes of period start earlier. The history keeps 100; `ClearAlerts`
empties it and keeps the dedupe memory and the ids. Both are empty at station start.

### Decoded facts (`DecodedEntity`)

Sender: of a standard message its sender; of a nonstandard-call message the sending call;
of a DXpedition message the DXpedition's call; a filled-in hash counts; an unfilled hash,
free text and telemetry have none. Entity with km to the entity's position, rounded. Flags
from the `WorkedSet` of every QSO; band flags only with a known band, grid flags only with
a locator, entity flags only with an entity; none for a DXpedition message or without a
set. Worked status only for a standard message from a call, with a known band, for the
mode of the job.

## 6. Implemented in and tested by

`RankingService`: `server/src/strategy.rs`, `server/src/contest.rs`,
`server/src/most_wanted.rs`. CL-055-02 names `server/src/dxcc.rs`. Detail tests:
`server/src/strategy_tests.rs`, `server/src/strategy97_tests.rs`,
`server/src/contest_tests.rs` (they also cover the saved strategies, their routes and the
runs of Auto).

## 7. What it relies on from outside

| Element | Needed from it |
|---|---|
| `WstxDecodes::ResultRecord`, `PeriodView` | the decoded message: its kind, sender, addressee, CQ and directive, grid, exchange, SNR, audio frequency, period start, sequence |
| `WstxOperatingChain::WorkedSet`, `WorkedCategory`, `Standing`, `WorkedStatus`, `DateWindow`, `ContestPeriod`, `PeriodQsos` | what is worked and confirmed, the US state of a call, the gridless mark, the QSOs of a period |
| `WstxLogControl::EntityRequest`, `EntityAnswer`, `CallEntity`, `Continent` | the entity of a call |
| `WstxHearing::HearingReport` | `heardBy`, `inUse` |

Named in text without an element: "standard message", "RTTY Roundup message", "Field Day
exchange", "DXpedition message", "nonstandard call", "free text", "telemetry" (kinds of
message of the modes part); "special activity"; `most_wanted.json`; the table from entity
names to ADIF numbers.

## 8. Differences from a named reference

Reference: WSJT-X at the behaviour baseline.

| Topic | Reference | This product | Recorded as |
|---|---|---|---|
| Callers of the own CQ | with the CQ response None it answers none by itself | callersFirst off gives a caller no rank | follows the source |
| New-flags | `LogBook::match`, six categories for logbook and band, highlighting by mode off | the same twelve flags | follows the source |
| Where a decode is looked up | when it is printed, coloured at once | ranking gives the facts, the browser colours | deliberate |
| Contest QSOs | a log of their own, dupes by call and band | the QSOs of the logbook that start in the period, by the contest's dupe rule | deliberate |
| Whom to answer in a contest | the first decoded caller | every callable station, ranked | deliberate |

## 9. Verification

Every case declares cost level 2, the development PC, automated.

| Case | Verifies | Shows |
|---|---|---|
| TC-039-002 | CL-039-03, CL-039-02 | the directive table, the verdict list with reasons, Treat 73 as CQ, the station's continent |
| TC-042-001 | CL-042-01 | new entity and zone against a logbook, both meanings, unknown band, no set |
| TC-097-005 | CL-042-01, CL-097-02 | every NewWhat in every scope; the why of a candidate |
| TC-097-004 | CL-097-02 | the strategy's bands |
| TC-039-030 | CL-097-02, CL-042-01 | grid, region, minimum SNR, the window |
| TC-097-006 | CL-097-02 | the three lists |
| TC-097-007 | CL-097-02, CL-097-03 | callers pass the filter; callersFirst off |
| TC-039-040 | CL-097-03, CL-039-02 | filter and order together, the exact tie |
| TC-097-008 | CL-097-03 | SNR bucket, hears us, new continent, a contest strategy with callers off |
| TC-055-002 | CL-055-02 | entity, flags and worked status of decoded records |
| TC-042-002 | CL-042-02 | the list, its order, empty at start; band change, clear and restart planned |
| TC-125-001 | CL-042-02 | patterns |
| TC-039-031 | CL-039-10 | what is a list, the entity numbers, the update |
| TC-042-006 | CL-042-04 | alerts, dedupe, history, clear |
| TC-063-004 | CL-063-02 | the CQ words of the contest; the operator's activity planned |
| TC-063-005 | CL-063-09 | points and multipliers by hand |
| TC-063-006 | CL-063-04, CL-063-09 | the count, the dupes, the verdicts and the tally |

Every clause has a case.

## 10. Open points, gaps and disagreements

Marked by the model:

- `RankingService` (`NotStated`): the connection over which ranking keeps the Most Wanted
  list in the profile's folder; it has no port toward the profile.
- `MyContinent` (`NotStated`): how ranking learns the entity nearest to a locator; an
  `EntityRequest` asks by a call.
- `DecodedFacts` (`NotStated`): the feature that carries the worked status; its type stands
  in the operating chain's file, which a control interface does not import.

Gaps:

- How a `WorkedWindow` request is matched to its `WorkedSet`, and an `EntityRequest` to its
  answer, is the log's port; not read further.
- `ContestProfile::activity` is a text; the element that defines the special activities was
  not in the files read.

Disagreements and observations:

- `Strategies.sysml` holds data and no clause; the clauses of the saved strategies are not
  in the files read (marker above).
- The texts of the why are sentences in the rule elements, not data elements.
- `ContestInForce::profile` and `ContestSelection::profile` both name a contest by a text
  id of `ContestTable`.
- Weak links (by name in text): `WstxValueOrder::ValueOrder` from `ValueCriterion`;
  `WstxStrategies::ContestTable` from `ContestInForce`; `WstxIgnoreLists::IgnoreListsRule`
  and `WstxContestRanking::ContestVerdictRule` from `VerdictRule`.
