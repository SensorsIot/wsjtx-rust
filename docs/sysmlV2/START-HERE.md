# Start here

The rebuild of the SysML model of wsjtx-rust. Read this file first, then the three
foundation documents, then continue with the next part.

## What this is

The model under `docs/sysml` (103 files, 24,600 lines) is rebuilt new under `docs/sysmlV2`,
in the structure and by the rules of the foundation. The old model is a source that is read;
it is never changed. The work is done by the operator and one assistant session, outside
the factory: no implementer session, no agents, no issues, no gate.

## Limits of the work

- **Changes only inside `docs/sysmlV2`.** Everything else in the repository is read only:
  the old model, the code, the tests, the tools. Nothing is committed or pushed.
- Nothing is posted on GitHub and nothing is said to the implementer session until the
  operator says so.
- `git status` must show `docs/sysmlV2/` as the only change.

## How the operator wants to work

- **No shortcuts.** Every rule sentence and every lettered test condition is written from
  the code and the bound test, read in full; the old text is a pointer. A passing
  done-test is not proof. Every figure in a report is measured by a script.
- **Check WSJT-X before a design question** (`D:\Github\wsjtx`), and say what it does.

- **Rules decide.** A question that a rule of the foundation answers is decided and listed
  in the part's report under "Decided by rule". Only what no rule decides is asked, one
  question at a time, with a founded recommendation.
- **The code decides what is built.** The old model has errors and duplications.
- **No evidence, no statement.** What has no evidence in the code or its tests is dropped.
- **Negatives with care.** "Never does X" only where a function exists that could do X.
- **A model file follows the thing, not the code's modules.**
- **Values are sorted like sentences.** A protocol value belongs to the source, a test
  value (sample size, fixture count, comparison tolerance) to its test case, and only a
  value of the promise to the model. Evidence in the code is needed for a value; it is not
  a reason to keep it. A count "36 of 40" is written as a share.
- Answers are short, lead with the result, plain words, tables where they carry structure.

## Read in this order

1. `Foundation/README.md`: the first rule and the three documents.
2. `Foundation/1-Finished-Model.md`: where everything stands (rules M0 to M8, the tree).
3. `Foundation/3-Method.md`: the nine steps for a part, the seven tests, everything decided.
4. `Foundation/Authoring/SKILL.md` and, for the kind of content at hand, its
   `references/`: how each element is written. `fsd-from-model.md` for the description.
5. `backend/clock/StationClock.sysml` with `_work/clock-report.md` and
   `_descriptions/clock.md`: the finished example of a part. `backend/modes/` with
   `_work/modes-report.md` is the example of a part with several function files and an
   interface of its own. `backend/audio/` with `_work/audio-report.md` is the example of a
   part with two outside connections (sound device and Flex) and clauses moved in from
   other parts.
6. `_work/handover.md`: what the next part must take up.

## State at the end of 2026-11-16

Measured: thirteen parts pass `part_done.py` (tests 1 to 5). The ledger has 580 rows
(counted by its last two columns): 246 arrived, 42 handed over, 13 not carried, 9 retired,
135 "TO PLACE" and 135 waiting for a part not yet built. The validator on the model tree
(without `Foundation/` and `_work/`, whose example files define a second `ModelBindings`)
gives 61 errors, all in `Station.sysml` (50), `Context.sysml` (4) and `StationLink.sysml`
(7), on lines that name parts not built yet.

| Part | State |
|---|---|
| clock | done by all seven tests; interfaces `StationTime`, `TimeSource`; port `heard` (the stations receive hears) |
| modes | tests pass; interface `ModeProcessing` |
| audio | tests pass; interfaces `AudioStreams`, `AudioControl`, `SoundDevice`; one line waits (thread priority) |
| receive | tests pass; interfaces `ReceiveControl`, `Decodes`, `DisplayData`; part type `ReceiveService` |
| log | subagent; tests pass; `LogControl`, the log's ends of `OperatingChain` |
| spots | subagent; tests pass; `Hearing` (with `SpotsControl`), `PskReporter` |
| udp | subagent; tests pass; its clauses stand in `interfaces/external/Udp.sysml` |
| flexAdapter | subagent; tests pass; **parked** (not developed for the moment) |
| transmit | subagent; tests pass; `TransmitControl`; port `control : Keying` |
| radioControl | subagent; tests pass; `RadioControl`, `Keying`, `Cat`, `RadioProperties` |
| profile | subagent; tests pass; `ProfileAccess` (`StationConfig`, `StationMemory`), `RecordingTransfer` |
| operating | subagent; tests pass; `Operating.sysml`, `Strategies.sysml`, interface `Strategies`; holds ranking, auto and qso in `Station.sysml` |
| ranking | subagent; tests pass; `RankingControl`, `ClubLog`; inside operating |

Not built: auto, qso (inside operating), the station service (with `Startup`), web and the
station link, mcp, the frontend. Every other model file is a copy of the old one ("taken
over"), rebuilt with its part.

The main session has read the model files of the eight subagent parts against their
reports (`_work/subagent-review.md`): 12 points repaired by rule, 15 listed for the
operator's reading. `WorkedStatus` stands in `LogControl` now; `MessageToSendPort`
carries the contact's commands to transmit.

## Decided on 2026-11-15 (recorded in the method's "Decided" list and on the issues)

- **The radio authorization goes** (issue #226): no grant, no setup confirmation, no
  safety revision. Each station works only with its own UI. Kept: the Tx watchdog, Halt,
  the release at start, the keying-inhibit confirmation of the radio setup check.
- **Settings in three stores** (issue #227): one config per station, one hidden store,
  one config per frontend; definition and data files stay files of their own; a setting
  is defined with the part that uses it, the profile only stores; what the software
  manages is not shown; a menu Advanced with Diagnostics. `_work/settings.csv` names the
  model home of every setting.
- **`operating` owns the strategies and contests** (issue #228) and holds ranking, auto
  and qso, giving each its share. A contest brings its exchange into the QSO; the
  selection is not kept across a restart; a contest's period is offered by station time
  in UTC.
- **One ignore list** (issue #228): comma-separated callsigns with `*` and `?`, at most
  20, at least one letter per entry; session state, not saved; acts universally in
  ranking (an ignored station has no value); a button erases it.
- **Directed CQs in three parts** (issue #228): CQ DX calculated from the continent; the
  station's CQ words (proposed: continent code plus the primary prefix from `cty.dat`,
  for example HB); a strategy's or contest's CQ words, a contest's only within its
  period. They are also the words of the station's own CQ.
- **The continent is a setting of the station**; without one an error message asks the
  operator to set it.
- **The contact's commands reach transmit only over the chain** (transmit line 2): Arm,
  Disarm, Abort, Tune, the repetition limit and the step come from qso; the operator's
  starts (Enable Tx is retired, #111/#121) and Tune go station service → qso →
  transmit. The station service gives transmit Halt and the station's facts. The raw
  route `POST /transmit/command` is work for the code.
- **`runEnded` and `DisarmCause::operator` left the model** (transmit line 9; #121): no
  code gives either; a run that ends cancels its contact.
- **The Tx level, manual or automatic** (transmit line 3): the ALC is a radio-control
  reading in percent of the ALC zone; one level per band for transmit and Tune; manual
  shows the slider (WSJT-X's Pwr), automatic (the default) hides it, finds the level when
  Tune is switched on (the tone goes on at it) and corrects by one step per transmission;
  no Set level button; meters, warnings and the SWR fault in both.
- FR-008 names the transmit drive level (transmit line 4).
- **Scope: the rigs Hamlib supports** (radio control lines 6, 9): FR-009 says so; the
  rig is the operator's choice (`ControlSelection::rig`, `RigModel` with Hamlib's
  number); the IC-7300 is the first rig built (CL-008-04); no identity query at every
  connection; the old property catalogue stays out.
- **A profile save does not reconnect the radio** (radio control line 12, as WSJT-X):
  only a change of the rig, the endpoint or the PTT method does; `profileRevision` left
  radio control.
- **No Undo of the recommended menu items** (radio control): the check and Apply stay.
- **FR-027 (reception reports) is spots'** (confirmed): one part for PSK Reporter in both
  directions; CL-039-28 (target). Broker and collector are `SpotsConfig` values, the
  official PSK Reporter by default, a simulator for tests; `WSTX_PSKR` gone. Code: #195.
- **Spots feeds two places** (spots line 3): ranking gets which stations hear us
  (`HeardByReport`), auto gets what the station being called hears (`TargetReport`) for
  the automatic Tx frequency; no connection to qso.
- **Udp has its control interface `UdpControl`** (udp line 1): configuration, the
  station's state for Status and the targets' snapshot; its own clauses (targets,
  instance name) stand in `backend/udp/UdpSender.sysml`; the wire file keeps the exchange.
  `Keying` and `UdpControl` are in M2.1's tree.
- **A contact the logbook cannot take is tried again briefly, then given up** (log line
  7): no queue, no extra file; "complexity only where it has value".
- **The hidden store is `memory.json`** beside `profile.json` (profile settings question):
  one key per part; unreadable means defaults and `MemorySnapshot::unreadable`.
- **No conversion of audio device names at start** (profile line 7; code: issue #229):
  devices are saved by endpoint id only, because identical radios have identical names.
- **The station's name** (2026-11-16): chosen when the radio is defined (offered: rig
  name, FLEX-6600 A to F, No radio), unique on the PC, kept until changed; it is
  `display_name` and the UDP instance `WSTX-Rust - <name>`. Changes #112's answer.
- **No generation** (profile line 3): one job or import at a time is `busy`; old jobs and
  recordings are `not_found` by their id. The count left receive and the profile.
- **The folder comes with each part's context** (profile line 2): the log's and
  operating's connections to the profile went; `Profile.sysml` holds only the part, its
  rules stand in `ProfileDocument.sysml` (line 1).
- **No radio authority part** (radio control line 2): the two lock files of the code are
  two rules of the CAT adapter (a port held by one station process; a discovered radio
  reserved until the process ends).
- **The Tx watchdog is qso's and only the repetition limit** (transmit line 10):
  transmit lost the limit, the count, `WatchdogStop`, `OperatorSeen`, `spent`,
  `tx_expired`, `WatchdogView` and CL-039-06 with TC-039-005 (to qso). The SWR fault
  barrier is the station service's, code `swr_fault` (#122 Q3 now (b)). The Tune limit
  stays with transmit.
- **Saving and selecting strategies are two commands** (2026-11-16, operating line 2):
  `SaveStrategies` is the strategies' CRUD (file, revision); `SelectStrategy` selects the
  active strategy and the contest (no file, no revision). Both are operating's. Issue
  #228's answer a was already decided there ((ii)).
- **CRUD only for collections whose members the operator adds, copies or deletes**
  (2026-11-16): strategies, UDP targets, the wanted list, the ignore list (already add,
  remove, erase). No CRUD for things of stable structure (station config, frontend
  config, radio settings, Tx level per band): one save, one read. Replaced whole: the
  country file, the Most Wanted list, the recording. Written by the software: the hidden
  store, alerts, decodes. Read only: built-ins, contest table, rig list. No list of
  stations: one server is one station, its rig chosen from Hamlib's list. The logbook is
  immutable, append and read only (WSJT-X appends to `wsjtx_log.adi` and changes no
  record): the replacement in place left (`DirectLog`); the one exception is a
  confirmation an ADIF file adds (never removed or lowered).
- **Data, management and use divided; two levels of settings** (2026-11-16): see the
  method's "Decided" list (two new entries). Six stations share one logbook and the
  operator-level settings in one shared folder per PC, including the UDP targets and
  the PSK Reporter configuration.
- **One Most Wanted list** (2026-11-16): Club Log's, downloaded on request, used as the
  criterion `most_wanted`; not editable. WSJT-X has none.
- **The wanted list (#124) is modelled** (2026-11-16): CL-124-02 (ranks first when it can
  be called, as WSJT-X's Wait and Call), CL-124-03 (an exact entry leaves once worked, a
  pattern stays; Q2 (a)); ranking's `WantedEntry`, the profile's collection `wantedList` in
  `wanted.json` of the operator's folder; target, no code.
- **Log QSO resends** (2026-11-16): the button sends the newest logbook record again to
  the logging program (`ResendLast`, CL-010-19); logging is only automatic at
  completion, an unfinished QSO is not logged.
- FR-012 is split: FR-027 (reception reports to PSK Reporter) is new, without a clause,
  given to spots in `Station.sysml` (allocation not confirmed by the operator).
- Subagents may build parts (not the frontend); each writes only its own files and its
  own rows, and the main session merges.

## Next

1. **Done:** the subagent parts read against their reports (`_work/subagent-review.md`).
2. **The operator's open lines**, one at a time, each with the model, the code, WSJT-X
   and a recommendation. Each report ends with its list "For the operator" and a section
   "Decided by the operator"; the lines not marked answered are open. **Done:**
   transmit (all 12 and its settings questions), radioControl (all 13 and the undo
   question), profile (all 8 and its settings questions), receive (2, 4, 7, 9), log (4 to
   7), udp (1, 2, 4, 5), spots (3 and FR-027; issue #195 revised to the model).
   operating (line 2, answer a), the CRUD sorting, the logbook (immutable, Log QSO
   resends, confirmations accrue), the division of data, management and use, the two
   levels of settings, operating (all lines: 6 verified in full, 7 the file renamed
   `StrategySelection.sysml`, 9 decided by rule with `RuleFacts`, 10 no longer applies).
   Ranking (lines 2 to 7: the wanted list modelled from #124; alerts kept, under a contest
   for a new multiplier and a wanted station; a ranked list for each period view, by
   M5.7; the facts given again for the current period; CL-063-09 kept; CL-097-03
   partial). **Open, next:** the remaining parts (step 3 below).

   **The settings move, state at the end of 2026-11-16.** Written, all thirteen parts
   pass: the profile is the settings function (strategies' CRUD, `CL-039-01`,
   `CL-097-01` and their cases moved there); the operator level (`OperatorFolder`,
   `OperatorConfig`, `OperatorSettings`, `operator.json`, `SaveOperator`, CL-005-07,
   TC-022-011; the logbook, `cty.dat`, `most_wanted.json`, `strategy.json`, the UDP
   targets and `SpotsConfig` in the operator's folder); the station config without
   revision; the revision on shared files and member commands; M5.1 reworded. The
   reports of profile, operating and log have a section on it; handover rows for the
   station service, station link, frontend and log; the descriptions of profile,
   operating and log are rewritten; TC-012-004 (f) is planned for the UDP targets' member
   commands. Left for the parts not built: the station service, the station link and the
   frontend take up their handover rows (Settings split by level). When a part's lines come up,
   its limits of time are checked by the rule of the method (a limit is code unless
   something outside waits on the number or it bounds the transmitter's switch).
   How the operator answers (2026-11-15/16): prefers simplification ("complexity only
   where it has value"; ask whether each variable has a job); no shortcuts (read every
   bound test, do the structure properly, check the model before asking); look to the
   future (six stations, all Hamlib rigs), not only today's code.
   Issues created or revised this session: #229 (no device-name conversion), #195 (PSK
   Reporter addresses and reports). Many other decisions of 2026-11-15/16 leave "work
   for the code" (see the reports' sections and `_work/handover.md`); the operator may
   ask for issues for them.
3. **The remaining parts:** auto and qso (inside operating), then the station service,
   web and the station link, mcp, the frontend (main session; not for a subagent). They
   take up the rows of `_work/handover.md` addressed to them and the "TO PLACE" rows of
   the ledger.
4. **The issue-writing skill:** a draft is in `_work/skill-draft/issue-writing/`
   (SKILL.md, a reference, a helper script), improved once from two real issues. It goes
   into the harness as a harness change, in a separate checkout of the harness repository,
   when the operator says so.

## The tools

All run from the repository root and read only.

| Command | Does |
|---|---|
| `python docs/sysmlV2/_work/part_done.py <part> [-v]` | the five program tests of a part; its files and verdicts are in `_work/parts.json`. A test case names a test as `path::name` (the file defines it) or a whole file (the file carries the case's number). |
| `python docs/sysmlV2/_work/check.py [-v] [path ...]` | the writing rules on the new tree or a folder |
| `python tools/sysml.py validate <files>` | the pinned validator on a list of files; give the files a part imports as well |
| `python docs/sysmlV2/_work/show.py <old file> <name,name> <chars>` | prints elements of the old model |
| `python docs/sysmlV2/_work/fr_homes.py` | which parts hold the clauses of each FR in the old model |
| `python docs/sysmlV2/_work/find_time.py` | example of a search across the old model for one theme |

Working files: `_work/ledger.md` (every identity), `_work/handover.md` (statements for
other parts), `_work/files.md` (the target files), one report per part, and
`_descriptions/` with one functional description per part.

## For a new part

1. Add the part to `_work/parts.json` with its files and what the validator needs with them.
2. Follow the nine steps of the method.
3. Run `part_done.py` until the five tests pass; write a verdict for every line of test 4
   that stands on one side only.
4. Write the description and the report, then offer the part to the operator.

## Traps met so far

- The language refuses `state`, `action`, `item` as feature names, and `standard`, `empty`,
  `state` as enumeration literals. Where the code's name is such a word, write it in quotes
  (`enum 'standard';`).
- `part_done.py` reads an enumeration only when each literal has its own line.
- A source reference names "WSJT-X at the behaviour baseline", not a release: the release
  stands once, in `Requirements.sysml`.
- What a part returns over its interface is defined in its interface file, also when another
  interface passes it on (`ResultRecord` is `ProcessingResult` plus `sequence`).
- A Python script given to the shell inline loses its backslashes; write it to a file.
- An attribute is typed by an attribute definition, not by an item definition.
- A rule is a sentence in its element; an attribute fixed to `true` is not a rule.
- A value's name ends in a unit suffix of `shared/Units` (`Ms`, `Seconds`, `Db`, `Hz`,
  `Pct`).
- A rename is checked against the code first: the code's names win (test 4 finds it).
- In this shell, a command with two heredocs fails; write a script file and run it.
- `part_done.py` keys an enumeration literal by its name alone: a literal that two
  enumerations share is matched once. Compare such enumerations by reading.
- `part_done.py` reads public constants only; a private one needs a verdict.
- `render` is a keyword of the language too; it cannot name a port's item.
- An item on a port is typed by an item definition, not by an attribute definition.
- A clause whose code stands in another part's modules names them (`@ImplementedIn` on the
  clause); every name of those modules then needs a verdict.
- A test condition is written from the test, read in full, not from the old case's text:
  the old texts differ from the tests (audio: the render channels, the endpoint cases).
- `frame` and `view` are keywords too; they cannot name an attribute or a port's item.
- Inside an item definition, a member typed by an item definition is written `item x : T`,
  not `attribute x : T`.
- The verdict for a text the tool found as `=> "x"` has the key
  `code name wire name "x"`.
- Search the tests by the clause's number across the whole `server/` tree before writing:
  receive's tests of the transmit periods stand in `server/src/transmit/`.
- While several sessions work, a script must not rewrite `parts.json` or the ledger as a
  whole: it loses another session's edit. Change single rows.
- A star followed by a slash inside a doc text ends the comment; write such a pattern
  another way. `entry` and `end` are keywords too.
- `part_done.py` compares Rust modules only. It has no comparison yet for routes, event
  types, reply fields or JavaScript; extend it when the first part needs it.

## Open points that wait

- `interfaces/internal/Keying.sysml` is written and used; whether M2.1 names it is line 1
  of `_work/radioControl-report.md`. Until then `check.py` on the whole tree lists it.

- The behaviour baseline says WSJT-X v3.3.0-beta4; many old texts cite beta5 (marked in
  `Requirements.sysml`).
- Issue #225 on GitHub (product change request, recorded): the station service gives audio
  its devices; receive and transmit name none. It waits until the new tree is on main.
- **The priority of the audio threads** (from CL-057-02): the code raises the priority of
  the capture and the playback thread. Audio did not write it (sorted as code). The
  operator keeps it as an issue to discuss.
- How and when the new tree replaces the old one on main. Work for the tools and the code
  is collected in the reports.
- `docs/harness/Finished-Model.md` on main is the older copy of the finished model; the
  working copy is `Foundation/1-Finished-Model.md`.
- `_work/files.md` still shows the clock's files as "taken over" and lists `PeriodTiming`;
  the states of the modes files are right.
- Issue #120 on GitHub was written new on 2026-11-15 as a first pilot, before the authoring
  rules were found. It does not follow them (too many clauses, no MUST) and waits.
