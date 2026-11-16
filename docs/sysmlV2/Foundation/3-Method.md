# Method of the rebuild

2026-11-15. Entry point for a new session: `../START-HERE.md`. This page says how the new model under `docs/sysmlV2` is built from the
model under `docs/sysml`. The old model is read and never changed.

## What is given

- The target tree stands, with 47 files taken over from the old model because they are
  already off the pending list.
- `_work/ledger.md` lists the 549 identities of the old model (26 FRs, 211 clauses, 312
  test cases), each with its old file and its target file.
- `_work/files.md` lists every target file with its state.

## The old model is a source, not an authority

The old model has errors and duplications. Where it is unclear, contradicts itself or
seems wrong, the code decides what is built: its values, its states, its tests. What the
code shows is written; what cannot be settled from the code is marked, not guessed.

## Rules decide; the operator is asked only where none does

A question is decided by the rules of the foundation wherever one applies. The part's
report lists it under "Decided by rule", with the rule. Only what no rule decides is put to
the operator, one question at a time (operator 2026-11-15).

## One unit of work is one part

A part is built completely before the next one starts: its own file, its function files,
and what it puts into its interfaces.

## The steps for a part

1. **Read the slice in the old model:** every element the ledger assigns to the part, the
   interfaces it uses, and the code and tests its elements name.
2. **Sort each statement** by the one question: could two correct implementations differ
   on it without anyone outside the part noticing? If so, it is code and is not carried
   over. Each test case is sorted the same way: one that shows something at a part
   boundary stays; one of the inside retires into the part's detail tests.
   **Each value is sorted too,** into one of three kinds. A value of the protocol or of
   another source is not written: the source reference covers it. A value of a test (a
   sample size, a count that describes a fixture, a tolerance of a comparison) stands in
   its test case only. A value of the promise (a limit, a share, a range that someone
   outside the part relies on) stands in the clause's element. That a test reads a value
   from the model, or that the code holds it, does not make it a promise (operator
   2026-11-15, on modes).
3. **Place what remains** in the highest level that can hold it: skeleton, then prose.
4. **Write the function files** by the authoring rules.
5. **Write the handover list:** every statement in the part's old text that is another
   part's promise goes to `_work/handover.md`, with the part it belongs to and the old
   clause it came from. That part takes it up when it is built.
6. **Fill the ledger:** every identity of the part has arrived, or is listed as retired
   with its reason.
7. **Write the part's functional description** by `Authoring/fsd-from-model.md`, from the
   new files alone. Every gap it lists is repaired in the model or becomes a marker.
8. **Write the part's report:** what was dropped as code, which test cases retire, which
   elements were renamed, every marker (`@NotStated`, `@Conflict`, `@LeftOpen`) added, and
   the size before and after.
9. **The operator reads the part,** its description and its report, and decides the open
   lines.

## What must hold for a finished part

Seven tests. The first five are run by `_work/part_done.py <part>`; a part is offered to
the operator for reading only when all five pass.

| # | Test | How |
|---|---|---|
| 1 | **Nothing is lost.** Every identity of the part is accounted for: arrived, handed over, retired or not carried, each with its reason. | the ledger |
| 2 | **The writing rules hold.** | `check.py`: no finding |
| 3 | **It is valid SysML.** | the pinned validator: no error in the part's files |
| 4 | **The model matches the code, both ways.** Model to code: every value, enumeration literal and name the model states exists in the part's modules; what does not is stale and is dropped. Code to model: every constant, enumeration, wire name and environment variable of those modules is in the model, or is the inside of the part. A number that differs fails. Every line on one side only needs a verdict in `_work/parts.json`: matched by reading, inside, or a difference with what is done about it. | the program lists; the verdicts are written and the operator sees the differences |
| 5 | **Every test case has its test.** A named test (`path::name`) is defined in the file it names. A whole file exists and carries the case's number. | the program |
| 6 | **The description has no gap** that is not a marker (M0.3). | reading |
| 7 | **The cut is right:** what was dropped as code, what was handed over, what was renamed. A part is larger than its old text only where it needs to be; the report then says, measured, what the growth consists of. | the operator's reading of the report |

No test shows that a rewritten sentence promises the same as the old one. Tests 4 and 6
catch a wrong value, a wrong name and a missing fact; the operator's reading guards the rest.

## When the rebuild is finished

- Every identity of the ledger is accounted for.
- Every target file exists and no other model file does.
- Every rule of the finished model holds.
- The model tools and the tests that read values from the model pass on the new tree.

## The order of the parts

modes, audio, receive, transmit, radioControl (with the CAT adapter and `Keying`),
flexAdapter, profile, log, spots and udp, ranking, auto, qso, the station service, web and
the station link, mcp, frontend. An interface file is rebuilt with the part that owns it.
The clock and the top files are done.

## Not decided

1. How and when the new tree replaces the old one on main.

## Decided

- Nothing satisfies a clause formally; its subject names its owner (M6.2, M6.10).
- A clause is written with MUST, SHOULD or MAY (M6.4).
- There is no `dependency` (M7.1).
- A clause derives from the one FR its part serves. That it uses another function's
  output, or is shown on a screen, adds no second FR (operator 2026-11-15, on the clock).
- `backend/clock/` holds `Clock` and `StationClock`: the clock is one thing that holds
  station time, is corrected from the air, is checked against a time server and publishes
  time. A model file follows the thing, not the code's modules.
- A package is named `Wstx` followed by its file's name. A part's own file adds `Part`
  (`WstxClockPart`), because four parts share their file name with an interface: Station,
  Udp, Mcp and RadioControl.
- A name that no longer says what the thing is, is renamed; the report lists what cites
  it (the clock: package `WstxStationClock`, element `TimeServerCheck`).
- A test case is written only when a test for it exists in the code. A planned case
  without a test is not carried over; the ledger and the report list it, so the gap
  stays visible (operator 2026-11-15).
- A clause's status follows the code: built and tested is `implemented`.
- **No evidence, no statement.** What has no evidence in the code or its tests is dropped,
  not marked (operator 2026-11-15).
- **A negative statement is handled with care.** "Never does X" is written only where a
  function exists that could do X. Where no such function exists, nothing is written.
  Where one exists, the case is made impossible by a type if it can be, and otherwise the
  rule is stated in the positive (what the result is used for, what stays).
- A test case is classed when its part is built (step 2); the report lists each
  retirement.
- A new identity takes the next free number of the series the clause or case was split
  from (operator 2026-11-15, on audio).
- A part may be larger than its old text if it needs to be (operator 2026-11-15, on
  audio).
- A promise that no test shows is noted in the model for the implementer: one line in
  its test case, marked "Planned, no test yet" (operator 2026-11-15, on audio).
- A function learns what the profile says from the station service, over its control
  interface. A stream is opened and closed by the function that takes it, on the
  stream's own connection (operator 2026-11-15, on audio; M5.3, M5.4).
- The capture clock belongs to audio alone (operator 2026-11-15).
- `operating` is a part. It owns the strategies and contests (what a strategy is, the
  built-ins, the contest table, defining and selecting) and holds ranking, auto and qso,
  to each of which it gives its share: ranking what to prefer, auto when to act, qso the
  contest's exchange. The profile stores the definitions; commands come through the
  station service (operator 2026-11-15; M2.1 and M2.2 changed).
- The settings: a setting is defined as configuration of the part that uses it; the
  profile stores the station config and the station's hidden store as collections of
  the parts' types; a frontend has its own config; definition files and data files are
  files of their own (operator 2026-11-15).
- The radio authorization is not part of the model: no grant, no confirmation of the
  setup, no safety revision; a station works only with its own UI by its address, the
  Origin check and the profile id (operator 2026-11-15; the code change is issue #226).
- The resume of receive at station start belongs to the station service, whole: the
  stored choice, the Monitor-off setting and the resume. `Startup` stands in
  `backend/station/` (operator 2026-11-15, on receive; M2.1 changed).
- The contact's commands to transmit (Arm, Disarm, Abort, the tone, the repetition
  limit's stop and count, the step) come only from qso over the operating chain; the
  operator's starts and Tune enter through the station service to qso. The station
  service gives transmit Halt and the station's facts (operator
  2026-11-15, on transmit; M5.3 for what enters, M5.7 inside the chain).
- The Tx level (operator 2026-11-15, on transmit): the ALC is a reading of radio control
  like the output power, in percent of the radio's ALC zone. The level is kept per band,
  for transmissions and Tune alike, and is set manual or automatic, automatic by default.
  Manual: the operator's slider, as WSJT-X's Pwr. Automatic: no slider; Tune, a toggle in
  both, finds the level and the tone goes on at it; each transmission corrects it by one
  step at most. There is no Set level button. The meter reading, the warnings and the SWR
  fault hold in both.
- "Tx watchdog" names the repetition limit only, and it is qso's: the limit, the count, the
  calls left and "expired"; at the limit qso gives Disarm with txWatchdog. There is no
  barrier for starts after it or at boot (#119: Auto goes off; #122: an agent is the
  operator). The one barrier is the SWR fault's, held by the station service, refusal
  code `swr_fault`. Transmit keeps only the Tune limit (operator 2026-11-15, on
  transmit).
- The product's scope is the rigs Hamlib supports, the rig chosen by the operator as in
  WSJT-X (FR-009); the IC-7300 is the first one built. The model accommodates several
  rig configurations: the rig is a value of radio control's configuration
  (`ControlSelection::rig`), each rig's rules of connection stand in their own element
  and clause, written when the rig's code exists. Hamlib's list stays data
  (`hamlib-models.json`), not model text (operator 2026-11-15, on radio control).
- **Data, management and use are divided** (operator 2026-11-16). The data of a setting
  (its type and its rules) is with the part that uses it; one used by several parts is
  with the part it is about. Every setting of kind config value or definition in
  `_work/settings.csv` is managed by the settings function, the profile: create, read,
  update and delete, the file, and the application of the rules the data's part states,
  with no code of its own for a type. A rule that needs other data when it is applied
  stays with the data, and the profile is given those facts. A browser preference is
  managed by the frontend's settings. Records, session state, data files and the
  downloaded Most Wanted list stay with their parts. Create, update and delete one
  member exist only for collections whose members the operator adds, copies or deletes
  (strategies, UDP targets, the wanted list); a thing of stable structure has one save
  and one read. The parts that use a setting read it; the station service gives it.
  This replaces "operating defines the strategies" of 2026-11-15: operating offers the
  built-ins and the contests and selects.
- **Two levels of settings, one logbook** (operator 2026-11-16): up to six station
  processes (for example six FlexRadio slices) share one logbook. The settings have an
  operator level, one shared folder per PC (callsign, locator, continent, CQ words,
  strategies, wanted list, country file, Most Wanted list, and the logbook), and a
  station level, the profile folder (name, rig or slice, connection, audio, CAT and PTT,
  Tx level per band, receive settings, listener address, hidden store). Session state
  (active strategy, contest, ignore list) is held by each process. The shared files are
  written under a file lock by whichever station writes; the logbook is appended so, and
  every station reads the QSOs the others append. The UDP targets and the PSK Reporter
  configuration (`SpotsConfig`) are of the operator level too; each station still sends
  its own datagrams and its own reception reports. A revision guards by level: a
  station's own settings have one maintainer (its browser) and no revision, the later
  save stands; each shared file has a revision, and a save or a member command made
  from an older one is refused with `revision_conflict`. M5.1 says so.
- A limit of time is a value of the code, not of the model, unless something outside the
  part waits on the number or it bounds the transmitter's switch; the model says that the
  thing ends in time. A cadence (how often something happens) is no limit (operator
  2026-11-15, on radio control).
