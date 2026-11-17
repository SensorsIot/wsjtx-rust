Title: Strategies and contests get one owner in the code: operating holds ranking, Auto and qso and gives each its share
Labels: cr, cr:recorded

**Duplicate check**
Searched: `gh issue list --state all --search` for strategy, strategies, contest, operating, "strategy store", "one owner", ranking; `git log --grep` for strateg and owner on main.
- #144 (open, model conversion of qso with Strategy and Contest) and #187 (open, model rewrite of ranking) convert text of the old model under `docs/sysml`. #144 names the finding "no owner for strategy"; neither changes code.
- #119 (open) changes what a run of Auto does. It keeps the store of the strategies where it is.
- #122 (open) lets an agent select and define strategies. It changes who may command, not who owns.
- #216 (open, built-ins edited in place), #98 (paused, contests as a replaceable file), #107 (open, the Default built-in and the sorting), #124 (open, wanted list) change what a strategy or a contest holds. Each of them edits the owner this issue creates.
- #142 (open, model conversion of the station service), #194, #199: model text only.
- #39, #63, #97 (closed) built the strategies, the contest profiles and the store that this issue moves.
- #53 (closed) recorded "a strategy is data, not a part; the station service is the gate, the profile keeps them". The operator's decision of 2026-11-15 replaces the first half: the strategies have an owning part.

None asks for this change.

**Problem**
The operator decided on 2026-11-15: `operating` is a part. It owns the strategies and contests (what a strategy is, the built-ins, the contest table, defining and selecting) and holds ranking, Auto and qso, to each of which it gives its share: ranking what to prefer, Auto when to act, qso the contest's exchange. The profile stores the definitions; commands come through the station service.

The code has no such owner. The definition of a strategy, the built-ins, the saved strategies with their file, the selection and the Auto switch all stand in ranking's module (`server/src/strategy.rs`); the contest table stands beside the contest counting (`server/src/contest.rs`). Auto and qso reach into that store and read the whole configuration: Auto takes every strategy with all its settings, qso takes the active strategy to find the contest's dupe rule and the station's continent. The contest's exchange is not given to qso at all: the operator sets the special activity by hand, and a contest run of Auto waits with the reason `activity` until he has.

Goal: one function in the code owns the strategies and contests, and ranking, Auto and qso each learn of a strategy only through the share operating gives them.

Value: the operator who selects a contest gets that contest's exchange in his messages without setting the activity a second time (if question 1 is answered as recommended); and each of the waiting changes to strategies and contests (#216, #98, #122, #124) changes one function, not three.

**Functionality**
Already covered: the decision as a rule of the model, by `docs/sysmlV2/Foundation/1-Finished-Model.md` M2.1 (`backend/operating/` with `Operating*`, `Strategies` and the folders ranking, auto, qso) and M2.2, and by `docs/sysmlV2/Foundation/3-Method.md`, "Decided".
Already covered: what a strategy is, the built-ins, the contest table and the selection as data, by `docs/sysmlV2/interfaces/internal/Strategies.sysml`: `Strategy`, `BuiltinStrategies`, `StrategyConfiguration`, `ContestProfile`, `ContestTable`, `ScheduleRule`, `ContestSelection`.
Already covered: ranking's share as a type, by `docs/sysmlV2/interfaces/internal/RankingControl.sysml` `StrategyRules` (name, `RankingKeys`, `ContestInForce`), carried in `RankingRules::active`.
Already covered: the dupe rule of the contest in force for the log, by `docs/sysmlV2/interfaces/internal/LogControl.sysml` `LogContext::contestDupes`.
Already covered: defining, saving, selecting and reading strategies and contests as behaviour, by `server/src/strategy.rs` (`parse_config`, `builtins`, `contest_builtins`, `Owner::put`, `Owner::snapshot`, the upgrades) and `server/src/contest.rs` (`PROFILES`, `next_period`, `parse_selection`), with fifteen named tests (Test cases). This issue changes who holds that behaviour, not the behaviour.
Already covered: what ranking does with its share, by the built ranking part (`docs/sysmlV2/backend/operating/ranking/`, twelve clauses).

**Model impact**

| Element | Today | Change | Why |
|---|---|---|---|
| `backend/operating/Operating.sysml` | the file does not exist | add: the part definition of operating with its ports; it holds ranking, auto and qso | M2.1, M2.2, M4.4 |
| `backend/operating/Strategies.sysml` | the file does not exist; its seven clauses and eleven test cases are "TO PLACE" in `_work/ledger.md` (old text: `docs/sysml/backend/operating/qso/QsoData.sysml`) | add: the function file with CL-039-01, CL-039-11, CL-097-01, CL-097-07, CL-097-08, CL-063-01, CL-063-03 and their test cases, subject operating, derived from FR-026 | M4.5, M6.2: a clause stands in the function file of its part |
| `interfaces/internal/Strategies.sysml`, metadata `definitionClauses` about `Strategy`, `StrategyConfiguration` | a `NotStated` marker: no file is named for the promises about defining, saving, selecting and reading | remove; the function file above answers it, nothing replaces it | the home exists |
| `interfaces/internal/Strategies.sysml`, the package | data only: no command and no state of defining and selecting | add: the commands and the state operating takes and gives (open question 2) | M4.6; M5.3 |
| `Station.sysml` `ranking : RankingService`, `auto : AutoService`, `qso : QsoService` and their connections | three parts of the station process, each joined to the station service by its own control connection | change: one part operating that holds the three; which connections cross its border is open question 2 | M2.2 |
| `Station.sysml` `satisfy 'FR-026' by ranking` | ranking alone carries "define and select strategies and contests" | change: by operating | M6.1: the FR goes to the part that carries it |
| `interfaces/internal/RankingControl.sysml` `RankingRules` | doc: "the station service gives them"; it carries `config`, `active` and `permanentIgnore` | change: `active` is the share operating gives (open questions 2 and 3) | the decision: operating gives each its share |
| `interfaces/internal/AutoControl.sysml` `AutoCommand`, `StrategyRun`, `ContestRun` | taken-over text of the old model: Auto's rules of a strategy are told in prose with routes and history; no element holds Auto's share | add, when auto is built: one typed element for Auto's share (the leave rule, the three Tx moves, the busy pause, CQ when idle with its wait, the retry pause, and for a contest its bands, period and `AutomationClause`) | a part defines what it needs in its control interface, as ranking did |
| `interfaces/internal/AutoControl.sysml` `AutoToggle` | Auto on and off, described with the route `POST /strategy/auto` | stays Auto's; no change in the model | M5.7: whatever decides or acts at run time belongs to Auto. The code keeps it in the strategy store (Model and code, 4) |
| `interfaces/internal/QsoControl.sysml` `QsoCommand` | taken-over text: "the contest exchange" as a word in a doc; the activity is one of the operator's commands | add, when qso is built: the element for qso's share (open question 1) | the decision: qso the contest's exchange |
| `interfaces/internal/Strategies.sysml` `ContestProfile::activity` | a `String`: the special activity that goes with the contest | change, when qso is built: typed by qso's activity | M6.10: refer by type, not by a name in a text |
| `backend/operating/ranking/Ranking.sysml` `RankingService`, `@ImplementedIn` and `@DetailTests` | names `strategy.rs` and `contest.rs` whole; "covers the saved strategies, their routes and the runs of Auto, which stand in the same modules" | change: names ranking's modules only, once the code is divided | M6.7 |

- **Tree:** none beyond M2.1 for the two new files. M2.1 names no control interface of operating and no interface for the shares: open question 2.
- **Identities:** the seven clauses and eleven test cases (TC-039-001, TC-039-003, TC-039-032, TC-097-001, TC-097-002, TC-097-003, TC-097-015, TC-063-001, TC-063-002, TC-063-003, TC-063-007) keep their numbers and move from "TO PLACE" to `backend/operating/Strategies.sysml`. The promise about the shares (Functionality 2 to 4) and its test cases are new; each takes the next free number of the series it is split from (the highest known are CL-063-09 and TC-063-012; measure again at the build). None is retired.
- **Other parts:** the profile stores the saved strategies and gives them at station start (`ProfileAccess`: definition files are files of their own). The station service passes the commands to define and to select. The log keeps receiving `LogContext::contestDupes`. The station link's routes and wire keys (`StationLink.sysml`, taken over) and the MCP tool catalogue (`Mcp.sysml`) do not change.
- **Model and code:** the rules of the model state the change; the part itself is not built in the model (the first four rows). The differences in the code are the work:
  1. The definition (the type of a strategy, its validation, the built-ins, the upgrade of older files) stands in ranking's module: `server/src/strategy.rs` `Strategy`, `Config`, `parse_config`, `builtins`, `contest_builtins`, `upgrade`, `upgrade_2`, `upgrade_3`, `rename_builtin_names`.
  2. The contest table, its schedule and the selection stand with the contest counting: `server/src/contest.rs` `Profile`, `PROFILES`, `Round`, `Profile::next_period`, `profiles_json`, `Selection`, `parse_selection`. The counting in the same file (`Qso`, `Log`, `Points::of`, `classify`, `evaluate`, `order`) is ranking's and stays.
  3. The store (the loaded configuration, its revision, its error, the rename notes, the read and the write of `strategy.json`) is one object with ranking's session ignore list, alert history, Most Wanted list and contest count: `server/src/strategy.rs` `Owner`, `Inner`, `Owner::lock`, `Owner::config`, `Owner::put`, `Owner::snapshot`. It is a field of qso's station object: `server/src/contact_http.rs` `Station::strategy`.
  4. The Auto switch stands in the same store: `Inner::auto`, `Owner::switch_auto`, `auto_on`, `auto_off`, `auto_step`, `halt_step`, `auto_request`, and the functions `start_selection` and `auto_route`.
  5. Auto reads the whole configuration: `server/src/automation.rs` calls `contact.strategy.config(state)` (in `selected`, `tick` and the leave step) and passes `(strategy::Config, strategy::Strategy)` to its own functions.
  6. qso reads the store: `server/src/contact_http.rs` `contest_dupes`, and `strategy::selection_warning` and `strategy::run_admits`, which read the configuration for the continent and the CQ targets.
  7. qso is not given the contest's exchange: `server/src/automation.rs` `strategy_context` compares the station's activity with `Profile::activity` and waits with `activity`; `client/contact.js` shows the hint "This contest uses the activity ...".
  8. The routes `/strategy` (GET, PUT) and `/strategy/contests` call ranking's module: `server/src/main.rs`, the route table.

Promises:
1. Operating MUST be the one function that holds what a strategy is, the built-in strategies, the contest table, the saved strategies of the profile and the selection (the active strategy and the contest in force with its period).
2. Operating MUST give ranking what ranking needs of the active strategy and nothing else (`StrategyRules`: its name, its ranking keys, and for class contest the contest in force with its period), at station start and whenever the selection or the definition of the active strategy changes.
3. Operating MUST give Auto the rules Auto executes of the active strategy and nothing else: the leave rule, the three Tx moves, the busy pause, CQ when idle with its wait, the retry pause, and for a contest its bands, its period and its automation clause.
4. Operating MUST give qso the exchange of the contest in force (what that is: open question 1).
5. Ranking, Auto and qso MUST learn of a strategy only through their share: none of them reads the saved strategies, the selection or the contest table of another function.
6. A command to define or to select MUST enter through the station service and reach operating; the profile MUST store the saved strategies.
7. The Auto switch MUST be held by Auto.
8. With no strategy active, each share MUST be absent: ranking gives no ranked list and Auto starts nothing.

What stays as it is: every route, body, refusal and event of `/strategy`, `/strategy/contests`, `/strategy/auto`, `/strategy/evaluate`, `/strategy/ignore` and `/strategy/alerts`; `strategy.json` in its schema 4 with the upgrade of the older schemas; that the active strategy and the contest are not saved; the five built-ins and the nine contest built-ins with their values; the evaluator, the ignore lists, the alerts, the Most Wanted list and the contest count in ranking; the browser's strategy bar, editor and contest prompt. Not part of this issue: whether Auto asks the evaluator or is given a ranked list (line 4 of `_work/ranking-report.md`), and where the session minutes are stored (the settings issue).

**Test cases**
1. The tests of the store and the definition pass with unchanged assertions after the move: `tc_039_001_configuration_is_exact`, `tc_039_003_store_routes_and_evaluate`, `tc_039_032_the_builtin_table_and_what_a_configuration_may_say`, `tc_039_032_a_builtin_is_selected_like_any_strategy_and_never_stored`, `tc_097_001_schema_4_every_key_at_its_bounds_and_one_refusal_per_field`, `tc_097_001_a_put_is_read_back_and_an_oversized_body_is_refused`, `tc_097_002_a_schema_3_file_upgrades_key_by_key_and_renames_built_in_names`, `tc_097_002_schema_2_and_4_files_and_the_cq_wait_default`, `tc_097_003_the_five_built_ins_the_contest_built_ins_and_active`, `tc_097_015_the_contest_built_in_and_a_saved_contest_strategy_run`, `tc_063_001_the_profile_table_holds_the_rule_facts`, `tc_063_002_the_period_comes_from_the_rule`, `tc_063_003_the_list_names_each_profile_with_its_period`, `tc_063_003_the_contests_route`, `tc_063_007_a_selection_is_parsed_exactly`, `tc_063_007_a_contest_selection_store_and_evaluation`. (Promises 1, 6, and "what stays".)
2. The forty tests bound to ranking's seventeen test cases and the tests of `automation_tests.rs` pass with unchanged assertions. ("What stays".)
3. The built-in Casual is selected. Ranking's share names Casual with new call per band, not worked, and the order `snr_bucket`, `distance`. Auto's share holds: leave after 4 calls and after 8 while heard; Tx moves never, at every call, at every 2nd call; busy pause on; CQ when idle on with a wait of 2 periods; retry pause 10 minutes. qso's share is absent. (Promises 2, 3, 4.)
4. The contest built-in WW Digi is selected with a period. Ranking's share holds the contest `ww_digi` and that period. Auto's share holds: leave in the mode contest after 2 Tx changes; Tx moves never, at every 2nd call, at every 2nd call; busy pause off; CQ when idle with a wait of 2 periods; retry pause 10 minutes; the bands 160m, 80m, 40m, 20m, 15m, 10m; the period; the automation clause forbidden. qso's share holds the exchange of WW Digi (by question 1: the activity `ww_digi`). (Promises 2, 3, 4.)
5. None is selected after test 4: all three shares are absent, Auto is off, and an evaluation without a draft is refused `not_configured` as today. (Promise 8.)
6. A saved strategy that is active is saved again with `leave` changed from 4 to 6 calls: Auto's share holds 6 before the reply of the PUT is given, the revision is one higher, ranking's share is unchanged in its keys. (Promises 2, 3.)
7. After a station restart with two saved strategies in `strategy.json`: both are listed, none is active, all three shares are absent. (Promises 1, 6, 8.)
8. A source check: the modules of ranking, Auto and qso name neither the store nor the configuration type of operating; they name their share types. It fails on the parent at the places of Model and code 5 and 6. (Promise 5.)
9. Auto on, Auto off and a Halt with a strategy selected behave as `automation_tests.rs` and the tests of `tc_039_003` state today, with the switch read from Auto. (Promise 7.)

**Reading list**
- The decision: `docs/sysmlV2/Foundation/3-Method.md` ("Decided", the line on `operating`); `docs/sysmlV2/Foundation/1-Finished-Model.md` M2.1, M2.2, M4.4 to M4.6, M5.3, M5.7, M6.2; `docs/sysmlV2/START-HERE.md` ("Open points that wait").
- Model: `docs/sysmlV2/interfaces/internal/Strategies.sysml` (whole); `docs/sysmlV2/interfaces/internal/RankingControl.sysml` `StrategyRules`, `ContestInForce`, `RankingRules`, `RankingContext`; `docs/sysmlV2/interfaces/internal/AutoControl.sysml` `AutoCommand`, `StrategyRun`, `AutoToggle`, `ContestRun`; `docs/sysmlV2/interfaces/internal/QsoControl.sysml` `QsoCommand`; `docs/sysmlV2/interfaces/internal/LogControl.sysml` `LogContext`; `docs/sysmlV2/backend/operating/ranking/Ranking.sysml` `RankingService`; `docs/sysmlV2/Station.sysml` (the parts ranking, auto, qso, their connections, the `satisfy` lines of FR-024 to FR-026); `docs/sysmlV2/Requirements.sysml` FR-026.
- Records: `docs/sysmlV2/_work/ranking-report.md` (the identities left "TO PLACE", the handover rows to station, auto and qso, line 1 for the operator, "Work for the code"); `docs/sysmlV2/_work/ledger.md` (the seven clauses); `docs/sysmlV2/_work/settings.csv` rows 31 and 33 to 40.
- Old model, as a pointer only and not carried forward: `docs/sysml/backend/operating/qso/QsoData.sysml` (the seven clauses), `docs/sysml/backend/operating/auto/Strategy.sysml`, `docs/sysml/backend/log/Contest.sysml`.
- Code: `server/src/strategy.rs`; `server/src/contest.rs`; `server/src/automation.rs` `selected`, `strategy_context`, `tick`; `server/src/contact_http.rs` `Station`, `contest_dupes`, and the call of `selection_warning`; `server/src/main.rs` (the `/strategy` routes, the events `strategy.state` and `alert.state`); `server/src/mcp.rs` (the read of `strategy`); `client/contact.js` (the strategy bar, the contest prompt, `set_activity`).
- Tests: `server/src/strategy_tests.rs`, `server/src/strategy97_tests.rs`, `server/src/contest_tests.rs`, `server/src/automation_tests.rs`, `tests/ui-operating.test.cjs`.

**Open questions**
1. **What qso is given as "the contest's exchange".** Today the operator sets the special activity himself (`set_activity`, with the exchange text for Field Day and RTTY Roundup); a contest only names its activity (`Profile::activity`), the prompt shows a hint, and a contest run waits with `activity` until the two agree. `_work/settings.csv` row 31 lists the special activity as a value of qso's configuration that the operator sets. WSJT-X has no contest selection: the special operating activity is one setting (`Configuration::special_op_id`, Settings, Advanced) with the Field Day and RTTY exchange beside it. Recommendation: while a contest is in force, operating gives qso the activity of that contest (none for the three contests that have none), and qso uses it in place of the operator's setting; the exchange text of Field Day and RTTY Roundup stays the operator's value in qso's configuration; when the contest ends, the operator's own setting holds again; the waiting reason `activity` and the hint go. The other reading changes nothing the operator sees: qso is only told which contest is in force, and the activity stays the operator's.
2. **Over which connections the commands and the shares cross.** M2.1 names `interfaces/internal/Strategies` and no control interface of operating; ranking, auto and qso are each joined to the station service by their own control connection today, and M5.3 lets a command reach a function only from the station service. WSJT-X has no strategies (it keeps whole configurations, `MultiSettings`), so it does not answer this. Recommendation: no new file. `Strategies.sysml` becomes operating's control interface (the commands to define and to select, and the state), joined to the station service; each share stays defined in the control interface of the part that receives it, as `StrategyRules` is, and operating gives it inside the part; the station service keeps giving each of the three its own configuration, context and the operator's commands.
3. **The permanent ignore list and the station's continent** stand in `StrategyConfiguration` and in `strategy.json`, and only ranking uses them. The decision names neither. WSJT-X has neither (the ignore list follows WSJT-Z, #125). Recommendation: they are no part of a strategy and not operating's; this issue leaves them stored where they are and handed to ranking as today, and the settings issue decides their file.

**Sequence**
- First: the part operating is built in the rebuilt model (`backend/operating/Operating.sysml`, `backend/operating/Strategies.sysml`, the rows of the model impact), and the rebuilt tree under `docs/sysmlV2` is on main. Until then this issue waits, as #225 and #226 do.
- The rows marked "when auto is built" and "when qso is built" need those two parts in the rebuilt model.
- #119 and #122 change the same functions of `server/src/automation.rs` and the `/strategy` routes; Check orders them against this issue.
- #216, #98, #107 and #124 build on the owner this issue creates.
- The settings issue (three stores; drafted, not posted) moves the session minutes out of `strategy.json`; the two name each other once it has a number.
- Related: #144, #187, #142, #53.

**Acceptance** (checked live after the deploy; each item names what is observed and how; at least one observes the value)
- [ ] 1. On the station page, the strategy Casual is selected in the strategy bar: Band Activity shows ranks and grey rows, and the preview of a row names its reason, as before the deploy.
- [ ] 2. A strategy is duplicated, renamed and saved in the editor; after a station restart the strategy bar lists it and shows None as active.
- [ ] 3. The contest WW Digi is selected through the prompt with its period: the tally line shows, and the QSO pane shows the activity WW Digi without the operator having set it (the value; applies if question 1 is answered as recommended, otherwise the hint and the wait are as before).
- [ ] 4. Auto is switched on with Casual selected and a decoded station callable: the status line shows the run calling it; Auto off ends the run; the strategy stays selected.
- [ ] 5. `wstx_read strategy` over MCP returns the same snapshot keys as before the deploy.

**Decisions:** `docs/sysmlV2/Foundation/3-Method.md`, "Decided" (operator, 2026-11-15); no decision comment on GitHub yet.

**Approval**
The operator's decision of 2026-11-15, given while the model was rebuilt. The go for the code change is asked at Decide, with the three open questions.

**Blast:** high, because the change touches the selection of a strategy and a contest, the runs of Auto that start transmissions, and what qso sends in a contest.

Proposed class: product CR (the model impact holds "add" and "change" rows, and the readers get new share types). The move of the definition, the contest table and the store into a module of their own is a pure move by itself; the coordinator may cut it off as a restructuring that lands first.

<details><summary>Technical details</summary>

- Sizes today: `server/src/strategy.rs` 3,231 lines, `server/src/contest.rs` 924, `server/src/automation.rs` 2,726; tests `strategy_tests.rs` 9,330, `strategy97_tests.rs` 2,245, `contest_tests.rs` 764, `automation_tests.rs` 1,148.
- A folder `server/src/operating/` exists and holds only `qso/` today. Where the new module stands is the coder's choice.
- The store writes `strategy.json` through the profile's store (`state.store`, `read_document_file`, `write_document_file` with `FILE_NAME`): the profile already stores; no change is needed there.
- `Owner` also carries `revision_seen`, `halts_seen` and `auto_epoch` (atomics read without the lock) and a lock order stated in comments (alerts before `inner` and `session`; the automation lock before the strategy lock). Dividing the object divides that order.
- `start_selection` joins three things: it loads ranking's Most Wanted list and worked sets, builds the contest count, and starts Auto's run. After the change the selection is operating's and each of the three steps follows from the share its function receives.
- `contact_http.rs` `contest_dupes` serves the rule "never the same station twice" (CL-085-01); in the model that value is the log's `LogContext::contestDupes`.
- Test tags found wrong by the ranking part and corrected when the tests move: the tests of the contest count carry CL-063-03 and belong to CL-063-09.
- Not read in full for this issue: `automation.rs` (read: `selected`, `strategy_context`, the start of `tick`, and every line that names `strategy::` or `contest::`), the test files (their test names were listed by number, their bodies not read), `client/contact.js` (searched for the routes and the activity). The promises' values in test cases 3 and 4 are those of `BuiltinStrategies` and `ContestTable` in the model, not re-read from `builtins()` and `PROFILES`.
- WSJT-X was read at the local tree `D:\Github\wsjtx` (the ranking report names its tag v3.3.0-beta6), for `Configuration::special_op_id` only; that it keeps no strategies is taken from `_work/ranking-report.md`.

</details>
