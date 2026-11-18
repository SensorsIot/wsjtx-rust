**Duplicate check**
Considered: #232 (its product facts come here; harness half #233), #231 (held), the model
rewrites #147, #164, #168, #187, #194, #199, #208, #221, #222, #224, the code splits #151 to #169
(not done here), #201 and #198 (separate); #107, #122, #189, #213, #215, #216 keep their code,
this issue their model.

**Problem**
The product contract in `docs/sysml/` does not meet the project's rules
(`harness/project/docs/Finished-Model.md`): facts stand twice, clauses carry prose test
conditions, links run through `dependency`, structure rules are switched off by a pending
list, and model and code disagree in places nobody can see. The rebuilt model on the branch
`sysmlv2-rebuild` meets the rules, but the model tool (`tools/sysml.py`) and its tests encode
the former structure and refuse it. Goal: one model that the definer, the coder and the
reviewer can trust, checked whole by the gate, with every gap to the code visible in the model
itself. The operator gains a contract that says what holds now and what the code does not yet do.

**Functionality**

Already covered:
- The rebuilt model: `docs/sysml/` on `sysmlv2-rebuild` (116 model files), valid for the
  pinned Pilot. The rules: `harness/project/docs/Finished-Model.md`.
- The tool's kept machinery in `tools/sysml.py`: `authority`, `setup`, `validate`
  (`Validate.java`), `canonical_catalog`'s identity patterns, `file_derivations`,
  `file_levels`, `binding_agreement`, `computed_status`, `markers`, `rewrite_paths`,
  `compare_revisions`, `identities`, `architecture_oracle` and `write_architecture_oracle`;
  the readers `server/src/model_values.rs` and `tests/model-values.cjs`.

To do:

*Model (`docs/sysml/`)*
1. `TC-009-002` states `method = "automated"` (its test is code started by hand, as
   `@TestLevel` cost 4 at `station` says); its test carries `// Proves: TC-009-002`.
2. `TC-022-011` is bound to a test that names it. The eight case titles over two lines
   (`TC-022-001` to `-003`, `TC-044-009`, `TC-039-048`, `TC-011-004`, `TC-006-004`,
   `TC-097-007`) take one line.
3. Layers: `ProfileDocument.sysml` names no other part's package (M3.3); `Udp.sysml` imports
   no control interface; `RadioPlace` moves from `WstxAudioControl` to `WstxRadioControl`
   and `ProcessEnds` from `WstxTransmitControl` to `WstxStationCommands` (M3.4: a type stands
   in its owner's control interface).
4. FR allocation (M6.2): `CL-039-04`, `CL-042-06`, `CL-097-12`, `CL-039-31` and `CL-001-02`
   derive from FR-019; `CL-063-08` and `CL-039-25` from FR-010; `CL-042-07` and `CL-042-08`
   from FR-017; `CL-085-02` from FR-007; Shack gives FR-001 to `supervisor` too (for
   `CL-001-01`). An interface clause derives from an FR a part at one of its ends serves.
5. `CL-003-01`, `CL-008-08`, `CL-008-11`, `CL-009-06`, `CL-037-06`, `CL-039-25` and
   `CL-112-01` state the status the code and its tests show; an implemented one has a case.
6. Code links (M6.6) stand on part definitions and clauses only: the ones on
   `WstxDecode::DecodeWindow`, `WstxMessageEncode::PackMessage`, `Ft8WaveformContract`,
   `Ft4WaveformContract`, `WstxMessagePayload::UnpackPayload` and `HashResolution` move to
   their clauses and `ModeFunctions` names the modes modules; the interface clauses of
   PskReporter (`CL-039-27`) and Udp (`CL-040-01`, `-03`, `-04`, `-06`, `-07`, `CL-112-02`
   to `-06`) carry their own.
7. `shared/ModelBindings.sysml` defines no `RetiredCase`. Its package and that of
   `shared/ModelNotes.sysml` are `WstxModelBindings` and `WstxModelNotes` (M7.5); every
   citation follows (A9).
8. `WstxModelNotes` defines `metadata def CodeDiffers { doc /* What the code does today where
   it differs from the element this marks. */ attribute what : String; }`.
9. Module ownership (M2.3): each code module is named by exactly one part definition's
   `@ImplementedIn`. A module several name (`main.rs`, `recording.rs`, `radio_setup.rs`,
   `radio_control/setup.rs`, `strategy.rs`, `contest.rs`, `dxcc.rs`, `contact_http.rs`,
   `most_wanted.rs`) stays with one; the others name it on their clauses. A module none
   names (`authorization.rs`, `authorization_http.rs`, `flex_http.rs`, `logbook_http.rs`,
   `radio_http.rs`, `receive_http.rs`, `transmit/clock_http.rs`, `lib.rs`) is named by the
   part whose function it serves. A part with a module outside its folder, or with code in
   another part's module, carries one `@CodeDiffers` naming each by its path.
10. Values (M6.8, M6.13; inventory in `docs/archive/sysml-rebuild/_work/model-values.md` on
    `sysmlv2-rebuild`), each verified as Technical choice 2 says:
    - leave the model (A4, A5): `WstxModeProcessing::Period`, the safe JSON integer (each of
      its three places), `checkpointMaxMs`; `WstxRadioProperties::DialRange` becomes a
      property of `RigModel` from the catalogue; each keeps its `@FollowsSource`;
    - corrected: a new station's display name is "New station"; the ignore list is one list
      of 100 (its code carries `@CodeDiffers`); Band Activity sorts descending;
    - `WstxStationLink` gets a clause at target: the link to a browser MUST stay within
      `ThinLinkBudget`; its case is manual, judged from the link log;
    - colliding features of one code are renamed (A9): `AirClock` and `TimeServerCheck`
      `maxAgeSeconds`, the FT8 and FT4 tone limits, `sourceUrl`, `schemaVersion` and `split`
      of the interfaces, `stepHz` against `STEP_HZ`, `mode` against `MODE`;
    - `alcLimit`, `alcHigh`, `ShackDocument`, `region`, `levelMode` and the other values the
      code holds otherwise carry `@CodeDiffers`, or their clause stands at partial
      (choice 2); `ft4PublishedByMs` has its test, or `CL-007-05` stands at partial.
11. Decided behaviour (`docs/archive/sysml-rebuild/_work/restart-plan.md`, "Sweep
    decisions"), each clause at the status the code shows:
    - `WstxStrategies::BuiltinStrategies` holds a built-in "Default", first: every station
      shown, no ranking order, no filter, no alert, no CQ when idle. After every start
      "Default" is active and nothing is restored (StrategySelection's start and
      end-of-selection rules); `active` is always present;
    - "Default" cannot be changed; every other built-in is changed in place; Factory reset
      puts the selected built-in back to its shipped state; a created strategy has none
      (`BuiltinOffer`, `StrategyEditor`);
    - M5.10: `WstxStationCommands::AgentRefusal`, an `enum def` of the commands an agent may
      not give, holds `saveConfig` (profile, rig, CAT/PTT, connection, audio devices, receive
      settings) and `saveShack` (call sign, locator, strategies file, UDP and PSK Reporter
      targets); applying radio settings to the rig is operating. mcp's port toward the
      supervisor is typed `AgentOperations`: `StationOperations` with those commands
      redefined to `[0]`. `GateRule` and `ToolUse` name `AgentRefusal`; their clauses stand
      at target until the code refuses them;
    - qso's rules: a contact whose transmit stops with `deviceLost` is kept, shows the cause,
      and the operator resumes or cancels it;
    - `WstxRadioSetup::RecommendedSettings`: the station holds the menu items of the last
      completed Apply (one record in its memory) and sets back and shows a changed item;
      VOX is held off, split held at the station's split setting and set back when changed.
12. Joined values meet at a space or `;`, never inside a word, path or test name (M7.6).
13. `docs/sysml/` holds the model files and `data/` only: `reference/` and `.sysml-viewer/` go.
14. The product facts of Project-Specifics' "Communication verification model", "Recording
    fixture acquisition" and "Native Windows FFI boundary" stand in the model where they are
    promises, each named in the CR's report; the rest is code.
15. A clause that prevents something has a case bound to a negative test (M6.5), or stands
    at partial; the report lists them (Test cases, P).
16. Text: OperatingScreen names "Settings > Advanced" (`AdvancedSection`); `PaneButtons`
    gives Abort QSO (Esc) the command the client sends, not `HaltQso`; `RowMarks`' tip holds
    no "(worked on …)"; `BehaviorBaseline` carries no `@Conflict`, and `StandardQso`'s
    `SequenceRule`, which follows v3.3.0-beta6, says so by `@DiffersFromSource`.

*Model tool (`tools/sysml.py`, `tools/sysml/`)*
17. Structure: the M2.1 tree exactly (`MODEL_TREE`), packages `WstxRequirements`,
    `WstxShack`, `WstxContext`; layers M3.1 to M3.4, the control interfaces being those of the
    packages `WstxStationLink::WireNames`' doc names, none importing StationLink, Mcp or
    OperatingChain; `WstxContext` named by Context and UseCases only; M4.1 to M4.3, M4.9; the
    fixed rules and roles: one deployment `context : ShackContext`, `shack`,
    `shack.stations[*] : Station` (`0..*`), in its `backend` one `audioAdapter`, `catAdapter`
    (`CatAdapter`), `profile`, `supervisor`, `web`, ranking, auto and qso under `operating`;
    `frontend.browsers` with one port toward the station (StationLink to `web`) (M5.5);
    each outside thing of `ShackContext` a black box of ports, each port joined once to a
    function through a type of `interfaces/external`, none a subject; connections typed by
    `interfaces/`, no empty item (M5.8); M5.10: mcp's command items are web's minus those
    `AgentRefusal` names, each literal naming a command, and no text holds "user";
    subjects (M6.9), an FR none (M6.1); a clause derives from one FR its part serves, an
    interface clause from one a part at its ends serves (M6.2, M6.3); a case is a skeleton
    and a one-line title (M6.5); steps' `requirement :>` are subsettings; every clause
    carried by a step or `@Debugging` (M6.11); the writing rules of the rebuild's `check.py`
    (M6.4, M6.10, M7.1, M7.3 to M7.6).
18. Catalog and bindings: a value joined by `+` is one value, also for `paths`; a clause's
    code link is its own `@ImplementedIn`, else its subject's part definition's; a clause
    without a case stands at target or partial, an implemented one has a case; FR status is
    computed (M6.1), none stated; a `Proves:` tag holds declared case identities only, whose
    binding holds the test (M6.7); the reuse guard (M6.12), the values and names (M6.8,
    M6.13) and the code structure (M2.3) as Technical choices 2 to 5 state.
19. Gone: the attribute forms, the `verification def` takeover, a file's function binding,
    `dependency` ownership and reciprocity, `RadioAuthority`, `StationProcess`, the fixed
    baseline, `@RetiredCase` and `retired`, the pending-structure list and `CHECK_COMMIT`,
    the proven removals and `cost-wordings.json`, `OutsideThing`, the pinned-reader kind of
    `equivalence`, and the rules on control interfaces' commanding end and the chain's
    direction (M5.3, M5.7: the reviewer's, M8.3).
20. `oracle` regenerates the architecture oracle from the rebuilt model.
21. `tools/sysml/README.md` states the contract as built (`TR-01` to `TR-21`, `TV-nnn`). The
    tool, its README and tests hold no history: `git grep -n -E
    "\(#[0-9]+|before #[0-9]" -- tools/sysml.py tools/sysml` finds none.
22. No history lands: `docs/archive/` leaves the main branch and the rebuild's working folder
    stays on its branch; the tool keeps refusing `docs/WSTX Rust FSD.md`. The root
    `README.md` links only existing model files (`interfaces/internal/StationLink.sysml`,
    `backend/web/Listener.sysml`, `Shack.sysml`), names no branch `original` (the upstream
    source is master's history up to `967c85a61`: `git show 967c85a61:<path>`), holds no
    functional prose, and its status paragraph states the present from the model's statuses.

*Tests and code*
23. `test_radio_properties.py` and its two `.tsv` files, `test_case_retirement.py`,
    `test_equivalence_proven.py` and `test_stated_once.py` T10 go. The mutation tests of
    `test_architecture_integrity.py` run on a fixture tree in the finished form;
    `test_equivalence.py`'s `test_r_real_readers_of_this_repository` checks the fixture readers
    of this repository (that tree's file and `test_architecture_oracle.py`) and that
    `server/src/main.rs` is none; E15's pinned cases go. `test_architecture_context` checks
    `ShackContext` against an owner table of its own; real-model tests name `Shack.sysml`.
24. Every `// Proves:` tag in `server/`, `client/` and `tests/` holds only its test's cases.
    A tag naming no declared case, or one whose binding lacks the test, is bound or removed.
    The model-value reader tests carry no tag and name their tool test.
25. Every code comment that cites a model element names one of the rebuilt model, or the
    citation goes (239 lines): `git grep -o -h -E "\bWstx[A-Z]\w*" -- server client tests`
    lists only packages of `docs/sysml/` and the folders `WstxRust`, `WstxRustStage426`; every
    `FR-`, `CL-` or `TC-` identity there is declared.
26. The test readers name the rebuilt model's elements (`WstxStartup`, `WstxDecode`,
    `WstxModeProcessing`, and those replacing `WstxOperatingReceive`, `WstxHttpContentCoding`,
    `WstxStrategy`, `WstxContest`).
27. Code constants (V1): every model value the code holds stands in one constant of its code
    named as the feature in upper snake case; an inline number, an array element, a struct
    field or a setting's default holding one becomes such a constant. Values the code does not
    hold are read by the contract test bound to the clause's case (V2): the values only tests
    hold, the `PaneLayout` rows (the browser test counts the visible rows), the fixture SNR
    levels. Behaviour does not change.

Not here: the suites' select lists, `test_trace_selection.py`'s probes, the harness links and
Project-Specifics' moved sections (the next harness change); the restructuring per part (M2.3);
the code of #107, #122, #189, #213, #215, #216; #231.

**Technical choices**
1. *Series.* The tool's rules are `TR-nn`, its tests `TV-nnn`; HOW identities that no
   `Proves:` tag names; a tool test names its `TV` in its docstring. `ID` and
   `source_proves` follow.
2. *Values, names, variables.* The code of an element is its part's modules (part
   definition's and clauses' `@ImplementedIn` in that part's files); for `interfaces/` and
   `shared/`, every module. `Requirements.sysml` and `shared/` enumerations are not compared.
   An element is covered by, in order:
   - V3, not built: a clause in any file names it or reaches it through typed features, and
     every such clause is target or partial;
   - V4: it carries `@CodeDiffers`; refused (`Code matches its CodeDiffers: <element>`) where
     its code matches;
   - V1, values: the one constant of its code named as its feature in upper snake case equals
     it (constant arithmetic evaluated on both sides, `200.` read as 200.0, a Real equal when
     it rounds to the model's decimals, `Duration::from_secs`/`from_millis` in the name's
     unit, an enumeration value as its wire name); literals and wire names (the features of
     StationLink, StationCommands, the control interfaces, Mcp and ProfileDocument, and the
     `'type'` values): found as a string literal or identifier in the model's, the
     snake_case (`WireNames`) or the UpperCamelCase form; `WSTX_*` variables: found as a
     string literal;
   - V2, values: a test file bound to a case of a clause that names or reaches it holds its
     qualified name, or its definition's qualified name and the feature's name.
   Otherwise refused: `Model and code differ: <element>: <what>: <key>:<line>` (a found
   counterpart unequal) or `Value not verified: <element>: <key>:<line>`. Two constants of one
   name in one code, or two compared values of one name there: `Name twice in one code:
   <name>`. A marker on an `enum def` or `attribute def` is not compared.
3. *Code structure.* Modules: every `*.rs` under `server/src/` and `*.js` under `client/`,
   except `*_tests.rs`, `tests.rs` and modules declared only under `#[cfg(test)]`. A part's
   folder: `server/src/<folder>/` and `client/src/<folder>/`, `<folder>` its model file's path
   below `backend/` or `frontend`. Refused: a module of no part outside `server/src/shared/`;
   of two parts; outside its folder and not named by its part's `@CodeDiffers`; a path in that
   marker standing in the folder.
4. *Markers.* The verdicts of `_work/parts.json` beginning "difference in the code" (136) or "a
   difference" (12) give one marker per distinct element (for a code-side item, on the
   definition named as its counterpart, else on its part definition), `what` in the present
   without date, issue or decision; none where V3 holds; where choice 2 finds a match, the
   carrying clause stands at partial instead. Every other difference the check finds is
   settled the same way, from the code.
5. *Reuse guard.* History: `git merge-base HEAD master`. Used identities: declarations added to
   model files there (`git log -p --format= -U0 <base> -- docs/sysml`, read with
   `IDENTITY_DECLARATION`); present: those of the base's `docs/sysml`. A used, not present
   identity declared: `Identity declared again: <ID>: <key>:<line>`, whatever its text. No
   repository, `master` or git: `Identity history unavailable: <reason>`, exit 2.
6. *Tags.* `// Proves: TC-ddd-ddd`, several joined by `, `; else `Invalid Proves tag: <path>:<line>`.

**Test cases**

Test plan (Station —, cost 2, developmentPc; expected results written by hand). Per rule: the
accepted fixture, then one negative test per way, each breaking it once and refused with its
message, key and line. New tests are red on the parent (`red_on_parent.py -- python -m unittest
<file>`); kept rules' tests are guards, red on the parent only by the renamed package and
composition file, as the commit body says. New unit test files are `test_[!adre]*.py` (sysml-tools); Pilot
tests go into `test_architecture_*.py` or new `test_a_*.py` (sysml-architecture); real-model
tests are `test_real_model_*.py`.

| Rule | Accepted | Negative (one each) |
|---|---|---|
| TR-01 authority | marker, no FSD | no marker; two; FSD with and without marker |
| TR-02 validation (TC-DOC-003, -004) | valid tree | syntax error; unresolved name; missing Java, JAR hash, library |
| TR-03 tree | M2.1 tree, `data/` | extra model file; listed file missing; `reference/README.md`; required package missing, twice |
| TR-04 layers | earlier layers; UseCases naming Context's actors; QsoControl importing TransmitControl | part importing another part, Shack; interface importing a part; Shack importing Context; external interface importing a control interface; control interface importing StationLink, Mcp, OperatingChain; Requirements importing a part; another file naming `WstxContext` |
| TR-05 file contents | as M4.1-4.3, M4.9 | FR with subject, `@Status`, `@ImplementedIn`, `#40`; Shack with a clause, an attribute, satisfy of a clause; UseCases with a value; a step naming a clause in text only |
| TR-06 roles | the finished deployment | each role missing; stations `1..1`; second `catAdapter`; `ranking` outside `operating`; second deployment; second browser port to the station; StationLink port, frontend connection to `receive`; view adding a part; mcp offering a refused command, lacking another; `AgentRefusal` literal naming no command |
| TR-07 context | ten boxes, ports only | outside part with a part, an action; port joined twice, by an internal interface, to nothing; outside thing as subject |
| TR-08 M5.8 | typed connections, items; `Halt`; abstract item a typed item subsets | untyped connection; typed outside `interfaces/`; untyped item; type with neither doc nor feature; abstract item no typed item subsets |
| TR-09 oracle (TC-DOC-005, fixture tree) | `oracle` then `check` | each entry removed; file missing, malformed; unlisted part, port, connection |
| TR-10 catalog (TC-DOC-002, -007) | rebuilt forms | duplicate identity; wrong kind; unreadable form; derivation from a missing FR; clause without derivation |
| TR-11 clauses, cases | skeleton case; target clause without case; interface clause from an end's FR | clause or case without subject; subject another part; two FRs; FR its part does not serve; interface clause from an FR no end serves; two-line title; extra feature; implemented clause without case; no step, not `@Debugging`; `dependency` |
| TR-12 FR status | all implemented; mixed partial; all target, none target | FR stating a status |
| TR-13 code links | inherited; own wins | on an action definition; two candidates (definition and supertype); delivered clause without |
| TR-14 tags (TC-DOC-011) | `TC-022-004`; two | FR; clause; `TC-022-004/005`; `#123`; added text; undeclared case; binding lacking the test |
| TR-15 reuse guard (temporary git repository) | kept identity, changed text; new identity | earlier identity absent from the tip declared again, other and same text; no `master` |
| TR-16 values, names | V1 constant (expression, `200.`, Real, `from_millis`); V2 bound test; V3 target clause in another file; V4 marker; literal, wire name, variable found | unequal constant; value none verifies; implemented clause reaching a target-covered value; literal, wire name, variable absent; marker where the code matches; constant twice; feature twice |
| TR-17 code structure | each module in one part's folder | module of no part; of two; outside its folder unmarked; marker naming a module inside |
| TR-18 writing rules | the rebuilt model's forms | `user`; clause of two sentences, without MUST/SHOULD/MAY, naming no element of its file; own identity in text; a date, `#12`, "formerly"; underscore; definition in lowerCamelCase; package not `Wstx<file>`; `//`; `/* */` outside `doc`; 101 columns; `"server/src/a" + ".rs"` |
| TR-19 test level (TC-DOC-019) | as today | as today |
| TR-20 values read, markers, paths, status (TC-DOC-010, -014, -017, -018) | as today; `@ImplementedIn`, `@TestedBy`, `@DetailTests`; joined literals | as today |
| TR-21 equivalence, identities (TC-DOC-015) | as today, fixture readers only, no retired status | as today |

R, on the candidate: `python tools/sysml.py check`, `traces`, `status`, `markers` and
`fingerprints` exit 0; `status` prints FR-016 and FR-017 partial; the suites
`sysml-documentation`, `sysml-tools`, `sysml-architecture`, `sysml-architecture-context`,
`model-values` and the full gate pass.

P, preventing clauses: the report's table gives clause, what it prevents, case and negative test
(`path::name`), or "partial: no negative test"; candidates are the clause docs `git grep -n -E
"MUST NOT|refus|reject|disabl|never" -- docs/sysml` finds, each read. Present negative tests are
guards.

L, live (cost 3, Station yes): the station built from the candidate starts its profile and
decodes FT8 on the operating screen.

**Reading list**
- `harness/project/docs/Finished-Model.md`, `Project-Specifics.md` (item 14), `README.md`.
- `docs/sysml/` on `sysmlv2-rebuild`: `Shack.sysml`, `Context.sysml`, `UseCases.sysml`,
  `shared/`, `interfaces/internal/StationLink.sysml` (`WireNames`).
- On `sysmlv2-rebuild`, `docs/archive/sysml-rebuild/_work/`: `harness-adaptation.md`,
  `check.py`, `parts.json`, `model-values.md`, `restart-plan.md`, `issue-sweep.md`.
- `tools/sysml.py`, `tools/sysml/` (README, oracle, pending list, tests);
  `harness/project/suites.yaml` (read only).

**Open questions**

**Sequence**
After: #233, #234 (both closed). Related, in work against the former model: #108, #132 and #166
(ready, PASS on f629f2934) and #107 (defining); once this lands, their renewal or definition
reads the rebuilt model. Before: the harness change for the paths, the closing of #232, #231, and
the code splits #135, #151, #153, #154, #156, #157, #159 to #163 and #169.

**Acceptance** (checked after the deploy)
- [ ] 1. On the main branch, `python tools/sysml.py check` and `status` exit 0; `status` shows
      FR-016 partial.
- [ ] 2. The station built from the landed commit starts its profile and decodes FT8 on the
      operating screen as before; observed on the live page.

**Scope:** writes `docs/sysml/` (from `sysmlv2-rebuild`, without `reference/` and
`.sysml-viewer/`), removes `docs/archive/`, `tools/sysml/pending-structure.json` and
`tools/sysml/cost-wordings.json`; writes `tools/sysml.py`, `tools/sysml/`, `server/`, `client/`,
`tests/` and the root `README.md`. Nothing under `harness/`, `.harness/`, `.claude/`, `.github/`.

**Decisions:** https://github.com/SensorsIot/wsjtx-rust/issues/235#issuecomment-6963451141

**Approval**
The operator's go: phase 1 of the plan from the rebuild to production (decision comment).

**Blast:** high: it replaces the product contract, removes `docs/archive/`, rewrites the model
tool and its tests, and changes tags, readers, comments and constants in about 100 code and test
files; product behaviour does not change.

The candidate is cut from the main branch and takes `docs/sysml/` from `sysmlv2-rebuild`.
