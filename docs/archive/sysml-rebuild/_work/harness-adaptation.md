# Adapting the harness to the rebuilt model

State 2026-11-17, branch `sysmlv2-rebuild`, after commit ab597af89 (the rebuilt model is
`docs/sysml`). Operator: "We want to do the right thing. If we have a new SysML
documentation, maybe we have also to adapt the harness to it. No shortcuts."

Three read-only inventories, each reading its files in full: the model tool
(`tools/sysml.py`, 3082 lines, its README and data files), the tool tests that read the real
model, and the harness texts (project harness, generated agents and skills, the general
harness). Nothing was changed by them.

## What fails today

- `tools/sysml.py check`, `traces`, `status`, `retired`, `fingerprints`: stop at the first
  rule ("Model file names the context package: WstxContext: UseCases.sysml"). `markers`
  passes (135 markers). The Pilot validates the new tree with 0 errors.
- Tests that read the real model: 11 files, 190 failing results on HEAD (168 of them in
  `test_radio_properties`). Suites hit: sysml-documentation, sysml-tools,
  sysml-architecture, sysml-architecture-context. The 36 equivalence tests read pinned
  commits only and pass.
- `harness/project/suites.yaml`: two selected files gone (`Station.sysml`,
  `backend/station/Station.sysml`); value-reading suites name the wrong files (some already
  wrong on master).

## The tool (tools/sysml.py) — by class

**Holds** (no change): the FSD absence, the folder, the authority marker, the identity
patterns, binding roots, the declaration forms, derivation ownership (239 of 239 clauses
have exactly one), test levels and locations, the ModelBindings names and shapes, the
ModelNotes markers, Proves-tag agreement, model values, the Pilot pin, equivalence and
identities (except the dependency part), the oracle file mechanism, rules 8 and 9.

**Rewrite** (the rule stays, in the foundation's form):
1. Required packages: `WstxArchitecture` → `WstxShack` (M2.1, M4.3).
2. Context package: `UseCases.sysml` may name it (M3.1, M4.9); better a general layer rule.
3. A `"a" + "b"` joined value is one value (171 values; Authoring rule 10). Also in `paths`.
4. A clause's code binding: the `@ImplementedIn` of its subject's part def, overridden by
   its named rule element (Authoring requirements-and-cases rule 8).
5. Composition file `Station.sysml` → `Shack.sysml`; station type `StationProcess` →
   `Station` under `shack.stations`; station parts under `<station>.backend`;
   `RustRadioDriver` → `CatAdapter`.
6. Roles: `shack`, `stations[*]`, `backend.supervisor`, `stations.frontend.browsers`,
   `backend.web`; the chain ranking/auto/qso under `backend.operating`.
7. Part folder: `backend/operating/*.sysml` is the part operating (M2.1, M3.3).
8. Layer rule: judge every file by layer (M3.1–M3.4) instead of the external/internal
   sub-rule.
9. Rule 10: every clause and case has a subject (M6.9); an FR has none (M6.1); a use-case
   step `requirement :> X` is a subsetting, not a requirement.
10. A clause without a case is allowed (3-Method: a case only where a test exists).

**Retire** (old content the rebuild dropped):
- the `verification def` takeover; the attribute forms (`coverage`, `executable`, …);
  `dependency` ownership and its reciprocity rule (M7.1); `RadioAuthority` (3-Method: the
  radio authorization is not part of the model); the pending-structure exemption list
  (M8.2 "no exemption list"); the "proven removals" CL-014-22 and `cost-wordings.json`;
  the context list `OutsideThing` (CL-014-03).

**Findings in the model or code** (repairs, not questions):
- TC-009-002 `method = "started by hand"` is no method value.
- TC-022-011: `tests/profiles.test.cjs` names no TC-022-011.
- `ProfileDocument.sysml:11` names `WstxCountryFile` (an M3.3 fault).
- 61 Proves tags in code name identities the rebuild retired (36 files); 476 tag/binding
  pairs disagree (50 files).
- Four `implemented` clauses have no case (CL-003-01, CL-008-11, CL-037-06, CL-039-25):
  either a test exists and the case is missing, or the state is wrong.
- `harness/project/suites.yaml` and `Project-Specifics.md` name test readers' packages that
  no longer exist (`WstxProfiles::StartupOutcome`, `WstxModemDecode`, `WstxDecodes::FrameStatus`,
  `WstxOperatingReceive`, …); the readers in the tests are repaired first, the lists follow.

## The tests — by class

- **Retire:** `test_radio_properties` (5 methods, 168 results) and its two `.tsv` files:
  operator answer 6 of 2026-11-15 ("the old property catalogue stays out of the model … each
  rig's properties come with its code", radioControl report).
- **Rewrite:** `test_architecture_context` against `ShackContext` (ten boxes, ports only,
  each port joined once to a station function through an `interfaces/external` type, an owner
  table, no `OutsideThing`).
- **Needs the tool fix only:** decoder_mode_traces (the TC-004 rule holds), real_model_catalog
  ×2, test_level L3, paths R6, architecture_integrity R7/R8, architecture_structure P1,
  stated_once T10.
- **Needs a name too:** real_model_structure (`Shack.sysml`), model_tree T7 (`WstxShack`),
  trace_selection T1 (probe and the suite's select list).
- Fixture tests (18 files) that write `package WstxArchitecture` into their own trees change
  only with the tool's renames.

## The harness texts

- **Replace:** `harness/project/docs/Finished-Model.md` by the rebuild's
  `1-Finished-Model.md` (same path and name; HOW header; no history; stale `docs/sysmlV2`
  paths out).
- **Project harness** (`harness/project/docs`, config, suites, `model_bindings.py`), root
  `README.md`, `tools/sysml/README.md`, `.github/ISSUE_TEMPLATE/cr.md`: about 40 places
  name `Station.sysml`, `StationProtocol.sysml`, `WstxArchitecture`, `Requirements.sysml` as
  the catalog of clauses and cases, the attribute form, or lettered case conditions.
- **Generated** (`.claude/agents`, `.claude/skills`): from `harness/general/core/agents/roles.md`,
  the language packs and `Agent-Working-Rules.md`; fixed at the source, then
  `install_skills.py`. `config.yaml` has no `skill_additions` yet.
- **General harness** (`harness/general`, its own repository): `Foundation/Authoring/` is
  the general sysml-authoring skill unchanged. The foundation differs from it in: an FR
  without subject and a clause without satisfier (M6.1, M6.2); no `dependency` (M7.1); a test
  case is skeleton + title (harness#129, open); a clause may have no case; use cases (M4.9,
  M6.11); naming (M7.5). The same four points recur in about ten general texts (CR-Process
  Accept, test-design, conformance-review, documentation, roles.md definer, the standards).

## Decided

- **Where the model rules live** (by rule, not asked): the project's rules in
  `harness/project`, reaching the generated skills through `skill_additions` (harness#134);
  the authoring skill lets the project harness win where it fixes a form; the general points
  go upstream through harness#129, #118 and #135.
- **Route to master** (operator 2026-11-17, A): (1) harness change with the rules
  (`Finished-Model.md` replaced, `skill_additions`, Project-Specifics' model contract);
  (2) one product CR: the model, `tools/sysml` and its tests, the test readers and Proves
  tags in the code; (3) harness change with the paths (suites' select lists, links,
  agents and skills reinstalled). Harness paths never ride in the CR.
- **Retired identities** (operator 2026-11-17, D: "we do not want to store history … only
  present time, not to confuse the models"): the model holds only present identities;
  `RetiredCase` and the tool's fixed baseline go; the tool refuses an identity that any
  earlier commit of master declared (read from git), and a Proves tag naming an identity the
  model does not declare. The reasons stay in the archived ledger. Authoring rule 9's
  retired list is a project override and a point for upstream.
- **Code links** (operator 2026-11-17, A): status and test links are tags on the clause; the
  code link (`@ImplementedIn`) is a tag on the part definition and a clause inherits it; a
  clause whose code lies in other modules carries its own, which wins. M6.6 is reworded. The
  four ambiguous clauses (CL-009-01, CL-011-01, CL-007-09, CL-024-01) and the eleven interface
  clauses without a link (PskReporter, Udp) are findings for the CR.
- **FR status** (operator 2026-11-17, A): implemented when all its clauses are implemented;
  target when all are target or it has none; partial otherwise. M6.1 is reworded; the tool
  already computes it (FR-016 and FR-017 are partial).
- **Model and code differences** (operator 2026-11-17, proposed by the operator): two checks
  in `tools/sysml.py check`. (1) Model–code: constants, enumeration values, wire names and
  environment variables are compared with the code; a difference stands only under a clause
  with status target or partial, or with the marker `@CodeDiffers` (ModelNotes, a doc of what
  the code does today) on the element; a marker where the code matches is refused. The 196
  verdicts "difference in the code" of the archived parts.json become such markers in the CR.
  (2) Code structure: every code module belongs to exactly one part (its `@ImplementedIn`);
  the code follows the model's tree (A): a part's Rust code in `server/src/<part>/` (operating:
  `server/src/operating/{ranking,auto,qso}/`), its browser code in `client/src/<part>/`, shared
  helpers in `server/src/shared/`, a test file beside its module; a part whose modules stand
  elsewhere carries `@CodeDiffers` naming them (restructuring work for the code).
- **Empty items** (operator 2026-11-17, A): an item is empty when it carries nothing
  nameable: no type, or a type with neither doc nor feature. A command whose type is the
  whole message (Halt) is not empty; an abstract grouping item is allowed when a typed item
  subsets it. M5.8 gets this sentence; the tool checks it.
- **Proves tags** (operator 2026-11-17, A): a tag names only the test cases its test belongs
  to (`// Proves: TC-022-004`): no FR, no clause, no shorthand, no issue number; the tool
  refuses any other identity in a tag; a detail test has no tag. The CR rewrites the 2,315
  mentions mechanically.
- **Negative tests** (operator 2026-11-17: "do not forget the red tests … negative tests that
  do not prove that something works, but that something prevents"): every check of
  `tools/sysml.py`, new or kept, has besides its accepted case one negative test per way the
  rule can be broken, each on a fixture model that breaks it once and is refused with the
  check's message, file and line. For the new checks at least:
  - layer rule: a function file importing another function's file; an external interface
    importing a control interface; a control interface importing a transport file;
  - context: a file other than Context and UseCases naming `WstxContext`;
  - joined values: a path or test name split inside by `+`;
  - code links: a clause with two inherited candidates; a delivered clause without a link;
  - reuse guard: an identity that an earlier commit declared, declared again with other text;
  - tags: a tag naming an FR, a clause, a shorthand, an issue number, an undeclared case, a
    case whose binding does not hold the test;
  - model–code: a difference without a target or partial clause and without `@CodeDiffers`;
    a `@CodeDiffers` where the code matches;
  - code structure: a module of no part; a module of two parts; a part's module outside its
    folder without `@CodeDiffers`;
  - empty items: an untyped item; a type with neither doc nor feature; an abstract grouping
    item that no typed item subsets;
  - FR status: no stated status on an FR; the computed value for all, some and no clauses;
  - naming (M7.5): a name with an underscore; a definition in lowerCamelCase;
  - use cases (M6.11): a clause no step carries and that is not `@Debugging`.
  Each negative test is also red on the parent where the rule is new (CR-Process Implement).
  The same holds for the product: a clause that prevents something (a refusal, a disabled
  control, a MUST NOT) is shown by a test that tries it and sees it refused; the CR's test
  plan lists these clauses and their negative tests.
- **By the foundation's rules** (not asked):
  - one writing-rule check: `check.py`'s rules join `tools/sysml.py check` (M8.2, M8.3);
  - the tool's method clauses CL-014-xx and TC-DOC-xxx leave the CL and TC series, which mean
    clause and test case of an FR (M6.2, M6.5), for a scheme of the tool's own;
  - the architecture oracle stays, regenerated from the new model (it lists the parts, ports
    and connections an issue adds and removes); the pending-structure list goes (M8.2); the
    tests pinned to old commits stay (they test the tool on fixed input, not the model);
  - a clause without a case is allowed at target and partial; an `implemented` clause has a
    case (3-Method: "built and tested is implemented"): CL-003-01, CL-008-11, CL-037-06 and
    CL-039-25 are model findings for the CR;
  - a test value stands in the bound test; 3-Method step 2's "its test case" is reworded;
  - M5.5 is reworded to what it means: the browser client has one port toward the station
    (StationLink); its port toward the operator is the context's;
  - `Udp.sysml` importing `WstxUdpControl` breaks M3.4 (only transport files and the operating
    chain import a control interface): a model finding for the CR;
  - functional prose outside the model (root README, Project-Specifics) is replaced by links
    to the model (operator 2026-11-16: no functional descriptions);
  - "no evidence, no statement" is a project rule (operator 2026-11-15);
  - `test_architecture_context` keeps an independent owner table; `test_stated_once` T10,
    vacuous on both models, retires (cut what has no job);
  - `3-Method.md` splits: its authoring rules go to the project's finished model, its product
    decisions are already in the model and go, its procedure stays in this archive.

## Questions for the operator

All answered 2026-11-17 (see Decided).

## Next

1. Harness change 1, the rules: `harness/project/docs/Finished-Model.md` replaced by the
   foundation (with the rewordings of M5.5, M5.8, M6.1, M6.6 and the decisions above),
   the project's authoring rules from `3-Method.md`, `skill_additions` in `config.yaml`,
   Project-Specifics' model contract; skills and agents reinstalled.
2. The product CR (issue first, its test plan with red-on-parent proofs): model, `tools/sysml`
   and its tests and README (its method clauses in a scheme of the tool's own; `tools/` is a
   product path), the test readers, the Proves tags, the model findings listed above, the
   196 `@CodeDiffers` markers.
3. Harness change 2, the paths: suites' select lists and their identities of the tool's
   scheme, links, reinstall.
4. Upstream to the general harness: harness#129, #118, #135, and the points of this document
   marked general.
