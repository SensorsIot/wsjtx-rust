**Duplicate check**
Open issues considered: #232 (its product facts of Project-Specifics are taken up here; its
harness half is #233), #231 (user documentation, held until this lands), the model conversions
and rewrites of the former model (#147, #164, #168, #187, #194, #199, #208, #221, #222, #224)
and the code splits (#151 to #169), which this issue does not do; #201 and #198 (model tool),
which stay separate.

**Problem**
The product contract in `docs/sysml/` does not meet the project's rules
(`harness/project/docs/Finished-Model.md`): facts stand twice, clauses carry prose test
conditions, links run through `dependency`, structure rules are switched off by a pending
list, and model and code disagree in places nobody can see. The rebuilt model on the branch
`sysmlv2-rebuild` meets the rules, but the model tool (`tools/sysml.py`) and its tests encode the
former structure and refuse it. Goal: one model that the definer, the coder and the reviewer
can trust, checked whole by the gate, with every gap to the code visible in the model itself.
The operator gains a contract that says what holds now and what the code does not yet do.

**Functionality**

Already covered:
- The rebuilt model: `docs/sysml/` on `sysmlv2-rebuild` (116 model files), valid for the
  pinned Pilot.
- The rules: `harness/project/docs/Finished-Model.md`.
- The tool's kept machinery in `tools/sysml.py`: `authority`, `setup`, `validate`
  (`Validate.java`), `canonical_catalog`'s identity patterns, `file_derivations`,
  `file_levels`, `binding_agreement`, `computed_status`, `markers`, `rewrite_paths`,
  `compare_revisions`, `identities`, `architecture_oracle` and `write_architecture_oracle`;
  the readers `server/src/model_values.rs` and `tests/model-values.cjs`.

To do:

*Model (`docs/sysml/`)*
1. `TC-009-002` carries a method value of `AutomationState`'s set.
2. `TC-022-011` is bound to a test that names it.
3. `ProfileDocument.sysml` names no other part's package (M3.3); `interfaces/external/Udp.sysml`
   imports no control interface (M3.4).
4. `CL-003-01`, `CL-008-08`, `CL-008-11`, `CL-009-06`, `CL-037-06`, `CL-039-25` and `CL-112-01`
   state the status the code and its tests show; an implemented one has a case (M6.5).
5. Code links (M6.6): an `@ImplementedIn` stands on a part definition or on a clause only; the
   ones on `WstxDecode::DecodeWindow`, `WstxMessageEncode::PackMessage`,
   `Ft8WaveformContract`, `Ft4WaveformContract`, `WstxMessagePayload::UnpackPayload` and
   `HashResolution` move to the clauses whose code they name, so
   `CL-009-01`, `CL-011-01`, `CL-007-09` and `CL-024-01` have one module list each; the
   interface clauses of PskReporter (`CL-039-27`) and Udp (`CL-040-01`, `-03`, `-04`, `-06`,
   `-07`, `CL-112-02` to `-06`) carry their own.
6. `shared/ModelBindings.sysml` defines no `RetiredCase` (M1.5, M6.12). The packages of
   `shared/ModelBindings.sysml` and `shared/ModelNotes.sysml` are `WstxModelBindings` and
   `WstxModelNotes` (M7.5), and every citation of them follows (A9).
7. `shared/ModelNotes.sysml` defines `metadata def CodeDiffers { doc /* What the code does today
   where it differs from the element this marks. */ attribute what : String; }`. The markers
   are written as Technical choice 4 says. A part definition whose modules stand outside its
   folder (M2.3) carries one `@CodeDiffers` naming each by its repository path; so does each
   part that names in a clause's `@ImplementedIn` a module another part owns.
8. Module ownership (M2.3): each code module is named by exactly one part definition's
   `@ImplementedIn`. A module several part definitions name today (`server/src/main.rs`,
   `recording.rs`, `radio_setup.rs`, `radio_control/setup.rs`, `strategy.rs`, `contest.rs`,
   `dxcc.rs`, `contact_http.rs`, `most_wanted.rs`) stays with one; the others name it on the
   clauses whose code lies there and carry the `@CodeDiffers` of item 7. A module no part
   names (`authorization.rs`, `authorization_http.rs`, `flex_http.rs`, `logbook_http.rs`,
   `radio_http.rs`, `receive_http.rs`, `transmit/clock_http.rs`, `lib.rs`) is named by the
   part whose function it serves.
9. A joined value meets at a space or `;`, never inside a word, path or test name (M7.6).
10. `docs/sysml/` holds nothing but the model files and `data/` (M2.1): `reference/` and
    `.sysml-viewer/` leave it.
11. The product facts of Project-Specifics' sections "Communication verification model",
    "Recording fixture acquisition" and "Native Windows FFI boundary" stand in the model where
    they are promises, each named at its place in the CR's report; the rest is code.
12. Every clause that prevents something (a refusal, a disabled control, a MUST NOT) has a case
    bound to a negative test (M6.5); one without such a test stands at partial. The report
    lists them (Test cases, P).
13. Text repairs: OperatingScreen names the section `AdvancedSection` names ("Settings >
    Advanced"); QsoPane's `PaneButtons` gives Abort QSO (Esc) the command the client sends
    for it, not `HaltQso`; `BandActivityPane::RowMarks`' tip holds no "(worked on …)";
    `WstxRequirements::BehaviorBaseline` carries no `@Conflict`, and `StandardQso`'s
    `SequenceRule`, which follows WSJT-X v3.3.0-beta6, says so by `@DiffersFromSource`.

*Model tool (`tools/sysml.py`, `tools/sysml/`)*
14. Structure, by the finished model:
    - the tree of M2.1, exactly (the tool's list `MODEL_TREE`); required packages
      `WstxRequirements`, `WstxShack`, `WstxContext`;
    - the layers M3.1 to M3.4 for every file, UseCases taking its actors from Context, and
      `WstxContext` named by Context and UseCases only;
    - M4.1 to M4.3 and M4.9 (what Context, Requirements, Shack and UseCases hold);
    - the fixed rules and roles: one deployment `context : ShackContext`; `shack`;
      `shack.stations[*]` typed `Station`, `0..*`; directly in its `backend` one
      `audioAdapter : AudioDeviceAdapter`, one `catAdapter : CatAdapter` and one
      `profile : PersistedProfile`; `backend.supervisor`; `backend.web`; `frontend.browsers`
      with one port toward the station (StationLink, to `web`) and its operator port the
      context's (M5.5); ranking, auto and qso under `backend.operating`;
    - the context: each outside thing of `ShackContext` a black box of ports, each port joined
      once to a station function through a type of `interfaces/external`, none a subject;
    - connections typed by `interfaces/`, no empty item (M5.8);
    - every clause and case names a subject (M6.9), an FR none (M6.1); a clause derives from one
      FR its part serves (M6.2); a case is a skeleton and a title (M6.5); a use-case step's
      `requirement :>` is a subsetting; every clause carried by a step or `@Debugging` (M6.11);
    - the writing rules of the rebuild's `check.py`: M5.10, M6.4, M6.10, M7.1, M7.3 to M7.6.
15. Catalog and bindings:
    - a value joined by `+` is one value; `paths` reads all its literals;
    - a clause's code link is its own `@ImplementedIn`, else its subject's part definition's
      (M6.6);
    - a clause without a case stands at target or partial; an implemented one has a case;
    - the FR status is computed by M6.1 and no FR states one;
    - a `Proves:` tag holds case identities only, each declared, whose binding holds the test
      (M6.7);
    - an identity the main branch's history declared and its tip does not is refused when
      declared again (M6.12);
    - model and code (M6.13) and code structure (M2.3), as Technical choices 2 and 3 state.
16. Gone: the attribute forms, the `verification def` takeover, the function binding of a
    file, `dependency` ownership and its reciprocity, `RadioAuthority`, `StationProcess`, the
    fixed baseline, `@RetiredCase` and `retired`, the pending-structure list and its gate with
    `CHECK_COMMIT`, the proven removals and `cost-wordings.json`, the context list
    `OutsideThing`, and the rules on control interfaces' commanding end and on the operating
    chain's direction (M5.3 and M5.7 are the reviewer's reading, M8.3).
17. The architecture oracle is regenerated from the rebuilt model by `oracle`.
18. `tools/sysml/README.md` states the tool's contract as built: its rules `TR-01` to `TR-21`
    and its tests `TV-nnn` (Technical choice 1); the tool's docstrings, messages and tests
    hold no history (M7.4): `git grep -n -E "\(#[0-9]+|before #[0-9]" -- tools/sysml.py tools/sysml`
    finds none.
19. The candidate holds no history: `docs/archive/` leaves the main branch (the archived FSD,
    the former harness diagrams and their README) and the rebuild's working folder does not
    land; the tool keeps the refusal of `docs/WSTX Rust FSD.md`. The root `README.md` points to
    no archive and holds no functional prose, only links to the model's existing files (the
    station link to `interfaces/internal/StationLink.sysml` and `backend/web/Listener.sysml`,
    the architecture to `Shack.sysml`); its "Branches" section names no branch `original`: the
    upstream WSJT-X source is master's history up to `967c85a61` (`git show 967c85a61:<path>`).
    Its status paragraph stays for #231.

*Tests and code*
20. `tools/sysml/tests/test_radio_properties.py` and its two `.tsv` files,
    `test_case_retirement.py` and `test_equivalence_proven.py` (with the features they test)
    and `test_stated_once.py` T10 go;
    `test_architecture_context` checks `ShackContext` against an owner table of its own; the
    real-model tests name `Shack.sysml` and `WstxShack`.
21. Every `// Proves:` tag in `server/`, `client/` and `tests/` holds only the test cases its
    test belongs to: no FR, clause, shorthand, issue number or text. A tag naming no declared
    case, or a case whose binding lacks the test, is resolved by binding or untagging. The
    model-value reader tests (`server/tests/model_values.rs`, `tests/model-values.test.cjs`)
    carry no tag and name their tool test.
22. Every comment in `server/`, `client/` and `tests/` that cites a model element names one of
    the rebuilt model, or the citation goes (239 comment lines cite packages the rebuilt
    model does not declare): `git grep -o -h -E "\bWstx[A-Z]\w*" -- server
    client tests` lists only packages of `docs/sysml/` and the folder names `WstxRust` and
    `WstxRustStage426`; every `FR-`, `CL-` or `TC-` identity there is declared;
    `NativeFlexBoundary` has no hit.
23. The test readers name the rebuilt model's elements (`WstxStartup`, `WstxDecode`,
    `WstxModeProcessing`, and those that replace `WstxOperatingReceive`, `WstxHttpContentCoding`,
    `WstxStrategy`, `WstxContest`).
24. Every model value the code holds stands in a constant of its code named as the value's
    feature in upper snake case, with the unit of the name's suffix; an inline number that
    holds a model value becomes such a constant. The code's behaviour does not change.

Not in this issue: the suites' select lists, `test_trace_selection.py`'s probe paths, the harness
documents' links, the removal of the moved sections and of the archive's sentence from
Project-Specifics (the harness change that follows); the code restructuring M2.3 asks for (one
issue per part, after this); the user documentation (#231).

**Technical choices**
1. *Series.* The tool's rules are `TR-nn`, its tests `TV-nnn`, each test naming its rule in
   the README. They are HOW identities: no `Proves:` tag names one; a tool test names its
   `TV` in its docstring or leading comment. `ID`, `source_proves` and the README follow.
2. *Model and code.* The code of an element is the modules of the part whose folder holds its
   file (its part definition's `@ImplementedIn` and the clause links in that part's files);
   for a file under `interfaces/` or `shared/` it is every module. Compared, model to code:
   - each literal of an `enum def` outside `shared/`: found when its code holds it as an
     identifier or a string literal, written as the model writes it, in the snake_case of
     `WstxStationLink::WireNames`, or in UpperCamelCase;
   - each feature name of the definitions that travel on StationLink or Mcp or stand in the
     station's files (StationLink, StationCommands, the control interfaces, Strategies,
     ProfileAccess, Mcp, ProfileDocument): found when its snake_case form is in its code;
   - each `WSTX_*` environment variable the model names: found when its code holds it as a
     string literal;
   - each attribute value: compared with the constants (`const`, `static`) of its code
     named as the value's feature in upper snake case, read in the unit of the name's suffix
     (`Duration::from_secs`/`from_millis` in its unit, `_` separators dropped); a value whose
     code holds no such constant is a difference (item 24).
   A difference stands when a target or partial clause of the same file names the element
   or a definition that owns it, or when the element carries `@CodeDiffers`; otherwise
   `Model and code differ: <element>: <what>: <key>:<line>`. A `@CodeDiffers` on a compared
   element whose code matches: `Code matches its CodeDiffers: <element>: <key>:<line>`. A
   marker on an `enum def` or `attribute def` (what the code holds beyond the model) is
   not compared.
3. *Code structure.* The code modules are every `*.rs` under `server/src/` and every `*.js`
   under `client/`, except test files (`*_tests.rs`, `tests.rs`, and a module declared only
   under `#[cfg(test)]`). A part's folder is that of its model file: `server/src/<folder>/`
   and `client/src/<folder>/`, where `<folder>` is the path below `backend/`
   (`operating/ranking`, …) or `frontend`. Refused: a module named by no part definition and
   not under `server/src/shared/`; a module named by two; a part's module outside its folder
   that its part definition's `@CodeDiffers` does not name; a module path in a part
   definition's `@CodeDiffers` that stands in its folder.
4. *Markers from the archive.* Each verdict of `docs/archive/sysml-rebuild/_work/parts.json` on
   `sysmlv2-rebuild` whose text begins "difference in the code" (136) or "a difference" (12)
   is one marker per distinct element: on the model literal or value it names; for a code
   constant, name or variable, on the model definition the verdict names as its counterpart,
   else on the part definition of the verdict's part. `what` states what the code does today,
   in the present, with no date, issue number, decision or "work for the code" (M7.4). No
   marker where a target or partial clause carries the element. Where the check of choice 2
   finds the element matching, the difference is one of behaviour: the clause carrying it
   stands at partial and no marker is written.
5. *Reuse guard.* The main branch is the ref `master`; its history is that of
   `git merge-base HEAD master`. Used identities are those of declarations added to model
   files in that history (one `git log -p --format= -U0 <base> -- docs/sysml`, its added lines
   read with `IDENTITY_DECLARATION`); present ones those declared in the base's
   `docs/sysml` (`extract`). A working-tree declaration of a used, not present identity:
   `Identity declared again: <ID>: <key>:<line>`, whatever its text. No repository, no
   `master` or a failing git: `Identity history unavailable: <reason>`, exit 2.
6. *Tags.* A tag is `// Proves: TC-ddd-ddd` or several joined by `, `; anything else:
   `Invalid Proves tag: <path>:<line>`.
7. *Pinned tests.* The equivalence tests pinned to history stay. The P5 guard on `f80c243c9`
   goes with the proven removals. The mutation tests on `1df1ba3a5` run on a fixture tree in
   the finished form.

**Test cases**

Test plan (Station: — for all; cost 2, developmentPc, the oracle written by hand in each test).
Each rule's cases: the accepted fixture, then one negative test per way, each refusing a
fixture that breaks it once, with its message, key and line. New tests are red on the parent
(`python3 harness/general/core/tools/red_on_parent.py -- python -m unittest <file>`); kept
rules' tests are guards, red on the parent only where their fixtures change by the renamed
package and composition file, which the commit body names. Tool unit tests are new files
named `test_[!adre]*.py` (sysml-tools); Pilot tests go into the existing `test_architecture_*.py`
or new `test_a_*.py` files (sysml-architecture); real-model tests are `test_real_model_*.py`.

| Rule | Accepted | Negative (one each) |
|---|---|---|
| TR-01 authority | marker, no FSD | no marker; two markers; FSD with and without marker |
| TR-02 validation (kept: TC-DOC-003, -004) | valid tree | syntax error; unresolved name; missing Java, JAR hash, library |
| TR-03 tree | M2.1 tree with `data/` | extra model file; listed file missing; other file in `docs/sysml/` (`reference/README.md`); required package missing; declared twice |
| TR-04 layers | each layer importing earlier ones; UseCases naming Context's actors | function file importing another part's file; interface importing a part; part importing Shack; Shack importing Context; an interface file other than StationLink, Mcp, OperatingChain, StationCommands, Strategies and ProfileAccess importing a control interface; control interface importing StationLink, Mcp, OperatingChain; Requirements importing a part; a file other than Context and UseCases naming `WstxContext` |
| TR-05 file contents | Context, Requirements, Shack, UseCases as M4.1-4.3, M4.9 | FR with subject, `@Status`, `@ImplementedIn`, `#40`; Shack with a clause, an attribute; satisfy of a clause; UseCases with a value; a step naming a clause only in text |
| TR-06 roles | the finished deployment | each role missing; stations `1..1`; second `catAdapter`; `ranking` outside `operating`; second deployment; second browser port toward the station; StationLink port to `receive`; frontend connection to `receive`; a view adding a part |
| TR-07 context | ten boxes, ports only | outside part with a part, an action; port joined twice; joined by an internal interface; joined to nothing; outside thing as subject |
| TR-08 connections, M5.8 | typed connections, typed items; `Halt` whole-message command; abstract item a typed item subsets | untyped connection; typed outside `interfaces/`; untyped item; type with neither doc nor feature; abstract item no typed item subsets |
| TR-09 oracle (kept: TC-DOC-005 on the fixture tree) | `oracle` then `check` | each oracle entry removed; file missing, malformed; unlisted part, port, connection |
| TR-10 catalog (kept: TC-DOC-002, -007) | rebuilt forms | duplicate identity; wrong kind; unreadable form; derivation from a missing FR; clause with no derivation |
| TR-11 clauses and cases | skeleton case; clause at target without case | clause or case without subject; clause whose subject is another part; clause deriving from two FRs, from an FR its part does not serve; case with a doc of two lines, an extra feature; implemented clause without case; clause no step carries, not `@Debugging`; `dependency` |
| TR-12 FR status | (impl, impl) implemented; (impl, partial), (impl, target) partial; (target, target), none target | FR stating a status |
| TR-13 code links | part link inherited; clause's own wins | `@ImplementedIn` on an action definition; two candidates (subject's definition and its supertype); delivered clause without a link |
| TR-14 tags (kept: TC-DOC-011) | `TC-022-004`; two joined by `, ` | tag naming an FR; a clause; `TC-022-004/005`; `#123`; added text; undeclared case; case whose binding lacks the test |
| TR-15 reuse guard (temporary git repository) | kept identity with changed text; new identity | identity of an earlier commit absent from the tip, declared again with other text and with its old text; no `master` |
| TR-16 model and code | equal literal, wire name, variable, constant (`Duration::from_millis`) | literal, wire name, variable absent; constant unequal; each without target/partial clause and without `@CodeDiffers`; `@CodeDiffers` where the code matches (each kind) |
| TR-17 code structure | each module in one part's folder | module of no part; module of two parts; module outside its folder without `@CodeDiffers`; `@CodeDiffers` naming a module inside the folder |
| TR-18 writing rules | the rebuilt model's forms | `user`; clause of two sentences, without MUST/SHOULD/MAY, naming no element of its file; text holding its own identity; a date, `#12`, "formerly"; name with underscore; definition in lowerCamelCase; package not `Wstx<file>`; `//` comment; `/* */` outside `doc`; 101-column line; `"server/src/a" + ".rs"` |
| TR-19 test level (kept: TC-DOC-019 L1, L2) | as today | as today |
| TR-20 values, markers, paths, status (kept: TC-DOC-010, -014, -017, -018) | as today, binding forms `@ImplementedIn`, `@TestedBy`, `@DetailTests`; joined literals | as today |
| TR-21 equivalence, identities (kept: TC-DOC-015) | as today, statuses without retired | as today |

R, on the candidate: `python tools/sysml.py check`, `traces`, `status`, `markers` and
`fingerprints` exit 0; `status` prints FR-016 and FR-017 partial; the suites
`sysml-documentation`, `sysml-tools`, `sysml-architecture`, `sysml-architecture-context`,
`model-values` and every suite that reads model values pass; the full gate passes.

P, preventing clauses: the report holds a table clause, what it prevents, case, negative test
(`path::name`), or "partial: no negative test". Its candidates are the clauses that `git grep
-n -E "MUST NOT|refus|reject|disabl|never" -- docs/sysml` finds in a clause's `doc`, each read;
the reviewer reads M6.5 against it. A negative test already present is a guard.

L, live (cost 3, Station yes): the station built from the candidate starts its profile and
decodes FT8 on the operating screen.

**Reading list**
- `harness/project/docs/Finished-Model.md` (the rules).
- `docs/sysml/` on `sysmlv2-rebuild`, in particular `Shack.sysml`, `Context.sysml`,
  `UseCases.sysml`, `shared/ModelBindings.sysml`, `shared/ModelNotes.sysml`,
  `interfaces/internal/StationLink.sysml` (`WireNames`).
- On `sysmlv2-rebuild` only: `docs/archive/sysml-rebuild/_work/harness-adaptation.md` (the
  inventory of the tool and its tests), `check.py` (the writing rules), `parts.json` (the code
  differences), `issue-sweep.md` (comments and modules).
- `tools/sysml.py`, `tools/sysml/README.md`, `tools/sysml/architecture-oracle.json`,
  `tools/sysml/pending-structure.json`, `tools/sysml/tests/`.
- `harness/project/suites.yaml` (read only: the model suites and their run patterns).

**Open questions**

**Sequence**
After #233 and #234 (landed). Before the harness change for the paths, #232's closing, #231 and
the code restructuring per part.

**Acceptance** (checked after the deploy)
- [ ] 1. On the main branch, `python tools/sysml.py check` and `status` exit 0; `status` shows
      FR-016 partial.
- [ ] 2. The station built from the landed commit starts its profile and decodes FT8 on the
      operating screen as before; observed on the live page.

**Scope:** writes `docs/sysml/` (whole, from `sysmlv2-rebuild`, without `reference/` and
`.sysml-viewer/`), removes `docs/archive/`, writes `tools/sysml.py`, `tools/sysml/README.md`,
`tools/sysml/Validate.java`, `tools/sysml/architecture-oracle.json`, `tools/sysml/tests/`,
removes `tools/sysml/pending-structure.json` and `tools/sysml/cost-wordings.json`; writes
`server/`, `client/` and `tests/` (tags, readers, comments, the fixtures' comments under
`tests/fixtures/model-values/`) and the root `README.md`. Nothing under `harness/`, `.harness/`,
`.claude/` or `.github/`.

**Decisions:** https://github.com/SensorsIot/wsjtx-rust/issues/235#issuecomment-6963451141

**Approval**
The operator's go: phase 1 of the plan from the rebuild to production (decision comment).

**Blast:** high: it replaces the product contract, removes `docs/archive/`, rewrites the model
tool and its tests, and changes tags, readers and comments in about 80 code and test files;
product behaviour does not change.

The candidate is cut from the main branch and takes `docs/sysml/` from `sysmlv2-rebuild`; the
coordinator writes model text, the coder the tool, the tests, the tags and the comments.
