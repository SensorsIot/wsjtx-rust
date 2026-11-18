# Model tools

The contract of the model tools (`tools/sysml.py`, `tools/sysml/Validate.java`): the pinned
toolchain, the commands, the rules `TR-01` to `TR-21` they check and the tests `TV-nnn`
that prove them. The rules of the model itself are the
[finished model](../../harness/project/docs/Finished-Model.md); each rule below names the
rule of the finished model it checks. `TR` and `TV` are identities of the tool: no
`Proves:` tag names one, and each tool test names its `TV` in its docstring.

## Pinned local validation

The full tool is the official OMG SysML v2 Pilot **0.62.0**, release **2026-08**, with
its matching bundled standard model libraries. The portable Windows bootstrap uses
Eclipse Temurin JDK **21.0.12.1+1**, x64. Version pins, official URLs and SHA-256 values
are in `tools/sysml/toolchain.json`.

```powershell
python tools/sysml.py setup
```

Setup downloads/extracts under `%USERPROFILE%/.cache/wsjtx-rust/sysml-tools/` and verifies
official archive SHA-256 values first. JAR and aggregate model-library hashes derived
from the verified Pilot archive are checked before validation. No JDK/JAR is committed
or packaged in the station executable. No global PATH, registry, Maven installation or
Jupyter service is required. Windows x64 is the verified bootstrap target; an explicit
`WSTX_SYSML_JAVA` path can supply an existing Java 21+ on another platform.

Sources: [Pilot release](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation/releases/tag/2026-08),
[Pilot kernel documentation](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation/blob/2026-08/org.omg.sysml.jupyter.kernel/README.adoc)
and [Temurin archive guidance](https://adoptium.net/installation/archives/).

## Model authoring and validation

```powershell
python tools/sysml.py check
python tools/sysml.py traces
python tools/sysml.py status
python tools/sysml.py markers
python tools/sysml.py oracle
python -m unittest discover -s tools/sysml/tests -q
```

- `traces`: the authority (TR-01), the catalog (TR-10, TR-12, TR-19), the tags and their
  bindings (TR-14), the code links (TR-13), model and code (TR-16) and the code structure
  (TR-17). No Java. It is the check a code change selects.
- `check`: everything `traces` checks, then the Pilot validation of every model file
  (TR-02), the architecture oracle (TR-09), the identity history (TR-15) and the rules of
  the model text and the deployment (TR-03 to TR-08, TR-11, TR-18). Every rule fault of a
  run is printed, one line each, sorted by rule, file or path and line, as
  `<message>: <key>:<line>` (a deployment fault: `<message>: <path>`); then
  `SysML check failed: <n> faults`, exit 2. A pass ends with `Model rules passed: <n>
  model files.`
- `status`: each FR's status computed from its clauses (TR-12); no Java, writes nothing.
- `markers [<Kind> ...]`: the `WstxModelNotes` markers of the model (TR-20).
- `fingerprints`: one hash per model file by key, after the catalog; writes nothing.
- `oracle`: writes `tools/sysml/architecture-oracle.json` from the resolved inventory
  (TR-09); no other command writes it.
- `paths <list>`: rewrites the code paths of a rename list in the model files (TR-20); no
  other command writes a model file.
- `equivalence <base> [<head>]`, `equivalence --marked`, `identities <base> [<head>]`:
  compare two revisions of the model (TR-21); they read the repository only.
- `validate <files>`: the Pilot on the files given, in that order (TR-02).

A command that cannot run exits 2 with `SysML check failed: <message>`.

## The rules

- **TR-01 Authority.** `docs/sysml/Requirements.sysml` holds the marker
  `// Canonical authority: SysML` once, on its first line; `docs/WSTX Rust FSD.md` does
  not exist. Refused: no marker (`No declared functional authority: canonical SysML marker
  required`); another or a second marker (`Invalid or duplicate canonical-authority
  declaration`); the FSD with the marker (`Two functional authorities: canonical SysML and
  active FSD`) and without it (`Retired Markdown FSD is not a functional authority: archive
  it and declare canonical SysML`).
- **TR-02 Validation.** The pinned Pilot parses, resolves and validates the model files as
  one graph, `Requirements.sysml` first. A syntax error, an unresolved name or a missing
  Java, JAR (hash) or library fails; there is no lightweight fallback.
- **TR-03 Tree (M2.1).** The model files are exactly the files of M2.1 (`MODEL_TREE`).
  Refused: a model file outside the tree (`model file outside the tree`), a file of the
  tree missing (`model file of the tree missing`), and a file in `docs/sysml/` that is no
  model file and stands outside `data/` (`file outside the model files and data/`). The
  packages `WstxRequirements`, `WstxShack` and `WstxContext` are each the package of exactly
  one file (`Canonical model packages missing: <names>`, `Duplicate canonical model package:
  <package>: <keys>`).
- **TR-04 Layers (M3.1 to M3.4).** A file names, by `import` or by a qualified name in
  code, only packages of its own file, of an earlier layer (shared, interfaces, parts,
  Shack, Context, UseCases) and of Requirements; a part names no other part's package; the
  control interfaces are the packages `WstxStationLink::WireNames` names; a control
  interface names no StationLink, Mcp or OperatingChain; an external interface names no
  control interface; Requirements names only shared packages; `WstxContext` is named by
  Context and UseCases only.
- **TR-05 File contents (M4.1 to M4.3, M4.9).** Requirements holds its imports,
  `BehaviorBaseline` and the FRs, each FR a doc only and no issue reference; an FR stands in
  Requirements only. Shack holds packages, imports, part definitions and usages,
  connections and `satisfy` of an FR, nothing else; no other file holds a `satisfy`.
  UseCases holds use cases with their subject, actors, objective, steps and the steps'
  `requirement :>` subsettings: no value, no declared requirement, no identity in a text.
  Context declares no identity.
- **TR-06 Roles (M2.2, M5.5, M5.10).** One package-level part usage, `context :
  ShackContext`; the roles of `ROLES` at their paths and multiplicities, the adapters by
  their types and no second part of an adapter's type; no view adds a part; the browser
  client has one port toward the station, typed by a port definition of StationLink and
  joined to `web`, and its other port is the operator's, joined to `context.operator`; a
  connection from the frontend ends at one of those two. `WstxStationCommands::AgentRefusal`
  names commands of `StationOperations`; mcp's port toward the supervisor is typed
  `AgentOperations`, `StationOperations` with exactly the refused commands redefined to
  `[0]`.
- **TR-07 Context (M4.1).** Each outside thing of the deployment (a part directly in
  `context` other than `shack`) has ports, attributes and metadata only; each port is
  joined exactly once, through an interface of `interfaces/external`, to a station
  function; no requirement names an outside thing as its subject.
- **TR-08 Connections and items (M5.8).** Every connection is typed by an interface
  definition of `interfaces/`. No item of a port definition is empty: none is untyped
  (an abstract one stands when a typed item subsets it), none is typed by a definition
  with neither doc nor feature.
- **TR-09 Architecture oracle.** `check` compares the resolved inventory with
  `tools/sysml/architecture-oracle.json` exactly: parts, references, ports with their items,
  connections and bindings. Its fixed rules (one deployment, no view-made part) hold
  whatever the file lists; a missing or malformed file is refused. Only `oracle` writes the
  file, after the Pilot validation and the fixed rules; it prints one line per change. The
  issue that changes the architecture lists the parts and connections it adds or removes,
  and the change lines are compared with that list.
- **TR-10 Catalog.** Every `requirement '<FR|CL>' {` and `verification '<TC>' {` is
  read; another form with an identity is refused (`Unreadable canonical declaration: <ID>:
  <key>`), so are a duplicate identity, a wrong kind, a derivation that does not join an FR
  to clauses (`Invalid canonical clause derivation: <CL> -> <FR>`) and a clause without one
  (`Canonical clause lacks requirement ownership: <CL>`). A clause states `@Status { build }`
  (target, partial, implemented), a case `@Automation { run }` (planned, partial,
  implemented) with an optional `method` (`manual`, `automated`), `@TestedBy { test }` and
  `verify` of declared clauses. A delivered case names its tests; each test file of a case
  that is not manual tags or names the case. A value joined by `+` is one value.
- **TR-11 Clauses and cases (M6.1, M6.2, M6.3, M6.5, M6.9, M6.11, M7.1).** Every clause
  and case names its subject; a clause stands in a function file of its part, its subject
  that part's definition, or in an interface file, its subject a definition of that file;
  it derives from one FR, which its part serves (Shack's `satisfy`), or for an interface
  clause, which a part at one of its ends serves. A case is its identity, a one-line title,
  `subject`, `verify` in its objective, `@TestLevel`, `@Automation` and `@TestedBy`. An
  implemented clause has a case. Every clause is carried by a use-case step or carries
  `@Debugging`. No `dependency`.
- **TR-12 FR status (M6.1).** An FR states no status and no binding (`FR states a status or
  a binding: <FR>`); its status is computed: implemented when all its clauses are, target
  when all are target or it has none, partial otherwise. `status` prints
  `<FR> <status>: <n> clauses, <i> implemented, <p> partial, <t> target` per FR, then
  `<n> FRs: <i> implemented, <p> partial, <t> target`.
- **TR-13 Code links (M6.6).** `@ImplementedIn` stands on a part definition or a clause
  only. A clause's code is its own `@ImplementedIn`, else that of its subject's part
  definition; two inherited links (a definition and its supertype) are refused, and so is
  a delivered clause without a code link.
- **TR-14 Tags (M6.7).** A tag is `// Proves: TC-ddd-ddd`, several joined by `, `, on a
  test (`#[test]`, `#[tokio::test]`, `test(`); anything else is `Invalid Proves tag:
  <path>:<line>`. It names declared cases only, and each case's binding holds the test, as
  its file or as `<file>::<test name>` (`Proves tag outside the verification binding: ...`).
- **TR-15 Identity history (M6.12).** The main branch is `master`, its history that of
  `git merge-base HEAD master`. An identity whose declaration that history added and which
  the merge base does not declare is not declared again: `Identity declared again: <ID>:
  <key>:<line>`, whatever its text. Without a repository, `master` or git: `Identity history
  unavailable: <reason>`, exit 2.
- **TR-16 Model and code (M6.8, M6.13).** Compared are each attribute value below a
  definition, each enumeration literal outside `shared/`, the feature names of StationLink,
  StationCommands, the control interfaces, Mcp and ProfileDocument, the `'type'` values and
  each `WSTX_*` variable the model names; Requirements.sysml is not compared. The code of an
  element is its part's modules (the part definition's and its clauses' `@ImplementedIn`),
  for `interfaces/` and `shared/` every module. An element is covered by, in order: V3,
  every clause naming or reaching it through typed features is target or partial; V4, it
  carries `@CodeDiffers`, refused where its code matches (`Code matches its CodeDiffers:
  <element>`); V1, its constant equals it (`D::F` an associated constant of the type `D`
  with fields or variants, or in JavaScript a key of `const D = Object.freeze({...})`, else
  `d::F` in `mod d`, else the module constant `F`; `F` the feature in upper snake case,
  `d` the owner in snake case; constant arithmetic evaluated, `Duration` read in the
  name's unit, a Real compared at the model's decimals, an enumeration value as its wire
  name), its name is found as an identifier or a word of a string literal in the model's,
  the snake_case or the UpperCamelCase form (a command field by its key), its variable is a
  string literal; V2, a test bound to a case of a clause reaching it holds its qualified
  name. Otherwise: `Model and code differ: <element>: <what>`, `Name twice in one code:
  <name>` or `Value not verified: <element>`, each with its key and line.
- **TR-17 Code structure (M2.3).** The code modules are every `*.rs` below `server/src/`
  but `*_tests.rs`, `tests.rs` and a module declared only under `#[cfg(test)]` or from a
  test file, and every `*.js` below `client/`. Each module is named by exactly one part
  definition's `@ImplementedIn` (`module of no part`, `module of two parts`), except one
  below `server/src/shared/`. A part's modules, and those its clauses name, stand in
  `server/src/<folder>/` or `client/src/<folder>/` (`<folder>` its model folder below
  `backend/`, or `frontend`) or are named by its part definition's `@CodeDiffers`; such a
  marker names no module inside the folder.
- **TR-18 Writing rules (M5.10, M6.4, M6.10, M7.3 to M7.6).** No word "user"; a clause is
  one sentence with MUST, SHOULD or MAY that names an element defined in its file; no text
  holds its own identity, a date, an issue number or a history word; no name holds an
  underscore and a definition is in UpperCamelCase; a package is `Wstx` and its file's
  name, a part's own file adding `Part`; no `//` comment but the authority marker, no
  `/* */` outside a `doc`; no line over 100 characters; a joined value meets at a space or
  `;`, never inside a word or a path.
- **TR-19 Test level.** A case states `@TestLevel { cost = <1..5>; location =
  TestLocation::<developmentPc|station|simulator|flexRadio>; }`, each pair once; anything
  else, or `@TestLevel` on another element, is `Invalid test level: <identity>`.
- **TR-20 Values read, markers, paths, status.** A contract test reads a model value by its
  qualified name through the one reader of its language (`server/src/model_values.rs`,
  `tests/model-values.cjs`); a missing, duplicate or unreadable value fails. `markers` lists
  `<key>:<line>: <Kind>[ about <targets>]: <text>` per marker of the `WstxModelNotes` kinds,
  then the counts. `paths` rewrites the paths of `@ImplementedIn`, `@TestedBy` and
  `@DetailTests` (a joined value read as one text), relative links and whole paths in text,
  and refuses a malformed list, missing moved files or a path that stays missing.
- **TR-21 Equivalence and identities.** `equivalence` exports each side with the Pilot and
  compares every named element by meaning; a citation of the model in the tracked files
  that resolved on the base and not on the head is a difference, except a name citation of
  a fixture reader below `tools/sysml/tests/` of its own fixture package. Exit 0 equivalent,
  1 differences, 2 cannot compare. `identities` lists each FR, CL and TC identity of two
  revisions as unchanged, moved, changed, added or removed.

## Meaning and limits of semantic validation

`tools/sysml/Validate.java` calls the pinned Pilot's `SysMLInteractive` API, including its
parser, name resolution and Xtext semantic validator, on all model files as one graph.
With `--inventory` it also lists the resolved deployment and the inputs of the rules
(`PART`, `REF`, `PORT`, `ITEM`, `EDGE`, `CONN`, `ELEM` with each definition's features and
doc, `IITEM`, `PITEM`, `OUTSIDE`, `MEMBER`, `SUBJECT`, `WHERE`). Successful validation is no
execution of modelled behaviour and no proof that the code meets the model.

## Tests

Each test of `tools/sysml/tests/` names its `TV` and rule in its docstring. The suites that
run them are those of `harness/project/suites.yaml`.

<!-- TV table -->

| TV | Rule | Test | What it shows |
|---|---|---|---|
| TV-001 | TR-07 | `test_architecture_context.py` ShackContextOwnerTests.test_outside_things_join_their_owners | each outside thing of ShackContext has the ports the owner table lists, each joined once, through an interface of interfaces/external, to its function. |
| TV-002 | TR-07 | `test_architecture_context.py` ShackContextOwnerTests.test_each_difference_from_the_table_is_found | an outside thing added or removed, a join removed, doubled, moved to another function or typed by an internal interface differs from the table. |
| TV-003 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_oracle_then_check_accepts_the_finished_form | `oracle` writes the fixture's parts, ports and connections; `check`'s comparison then passes with the fixture's counts; `oracle` again leaves the file. |
| TV-004 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_other_about_text_is_accepted | the oracle's free `about` text does not take part in the comparison. |
| TV-005 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_each_oracle_entry_removed_is_refused | each entry of the written oracle, removed alone, is refused. |
| TV-006 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_removed_connection_is_refused | a connection the oracle lists, removed from the model, is refused. |
| TV-007 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_wrong_port_type_is_refused | a port typed otherwise than the oracle lists is refused: the conjugate turns its items' directions, another definition is another port definition. |
| TV-008 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_wrong_item_type_is_refused | an item of another type than the oracle's contract is refused. |
| TV-009 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_unlisted_part_port_and_connection_are_refused | a part, a port or a connection the oracle does not list is refused. |
| TV-010 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_fixed_rules_hold_whatever_the_oracle_lists | a second deployment and a view that adds a part are refused, by `check` and by `oracle`, which then leaves the file as it was. |
| TV-011 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_missing_inventory_is_refused | a validator output without the resolved inventory is refused. |
| TV-012 | TR-09 | `test_architecture_integrity.py` ArchitectureIntegrityTests.test_missing_or_malformed_oracle_file_is_refused | the comparison refuses a missing or malformed oracle file whole. |
| TV-013 | TR-09 | `test_architecture_oracle.py` OracleCommandTests.test_oracle_then_check_round_trip | `oracle` writes the deployment and prints each addition; the comparison passes; `oracle` again leaves the file; an added connection is refused until `oracle` lists it. |
| TV-014 | TR-09 | `test_architecture_oracle.py` OracleCommandTests.test_each_edit_prints_its_change_line | one edit at a time, each followed by `oracle`: exactly the line written before the run. |
| TV-015 | TR-09 | `test_architecture_oracle.py` OracleCommandTests.test_refused_model_leaves_the_file | a model the fixed rules or the Pilot refuse leaves the oracle file as it was, absent or present; no other command creates or changes it. |
| TV-016 | TR-09 | `test_architecture_oracle.py` OracleCommandTests.test_fixed_rules_on_the_deployment | the inventory starts at the one package-level part usage; the fixed rules refuse none, two, or a view that adds a part. |
| TV-017 | TR-09 | `test_architecture_oracle.py` OracleCommandTests.test_outside_port_joined_to_a_function | an outside thing's port joined to a function passes; unjoined, `oracle` prints the removed connection and the comparison refuses the port. |
| TV-018 | TR-06 | `test_architecture_structure.py` DeploymentRuleTests.test_finished_form_passes_every_deployment_rule | the finished deployment, with Halt as a whole-message command and an abstract command item that typed items subset, passes TR-06 to TR-08. |
| TV-019 | TR-06 | `test_architecture_structure.py` DeploymentRuleTests.test_each_role_missing_is_refused | each role of M2.2 and M5.5 removed alone is refused, with every role inside it. |
| TV-020 | TR-06 | `test_architecture_structure.py` DeploymentRuleTests.test_roles_at_their_places_and_multiplicities | one deployment, stations of any number, one catAdapter, ranking inside operating, and no view that adds a part. |
| TV-021 | TR-06 | `test_architecture_structure.py` DeploymentRuleTests.test_browser_client_has_one_port_to_web | the browser client has one port toward the station, joined to web, and the frontend connects to nothing else of the station. |
| TV-022 | TR-07 | `test_architecture_structure.py` DeploymentRuleTests.test_outside_things_are_black_boxes_joined_once_to_a_function | an outside thing holds ports only, each joined once, through an interface of interfaces/external, to a station function, and is no requirement's subject. |
| TV-023 | TR-08 | `test_architecture_structure.py` DeploymentRuleTests.test_connections_typed_and_items_not_empty | every connection is typed by an interface of interfaces/; no port item is untyped, typed by a definition with neither doc nor feature, or an abstract item no typed item subsets. |
| TV-024 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_finished_form_passes | AgentOperations removes exactly the commands AgentRefusal names and mcp's port toward the supervisor is typed by it. |
| TV-025 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_mcp_offering_a_refused_command_is_refused | an AgentRefusal command that AgentOperations keeps is refused. |
| TV-026 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_mcp_port_typed_by_every_command_is_refused | mcp's port toward the supervisor typed by StationOperations offers the refused commands. |
| TV-027 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_mcp_lacking_another_command_is_refused | a command AgentOperations removes that AgentRefusal does not name is refused. |
| TV-028 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_refusal_literal_naming_no_command_is_refused | an AgentRefusal literal that names no command of StationOperations is refused. |
| TV-029 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_tagged_tests_in_their_bindings_are_accepted | tests in a bound file, tests bound by name, and a manual case's untagged file are accepted. |
| TV-030 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_each_test_or_file_outside_the_binding_is_refused | a tagged test its case's binding lacks, a bound file without a test that names the case, a tag on no test and a bound test name that no test has are each refused. |
| TV-031 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_marker_and_no_fsd_make_sysml_the_authority | the marker on the first line of Requirements.sysml and no FSD make SysML the authority. |
| TV-032 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_each_fault_of_the_authority_is_refused | no marker, two markers, and an FSD with or without the marker are each refused. |
| TV-033 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_model_file_naming_the_fsd_is_refused | a model file that names the FSD as a source is refused with its key. |
| TV-034 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_skeleton_case_target_clause_and_interface_clause_are_accepted | a skeleton case, a target clause without case and an interface clause from an end's FR. |
| TV-035 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_debugging_clause_without_step_is_accepted | a clause of a debugging function carries no use-case step. |
| TV-036 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_each_fault_of_a_clause_or_case_is_refused | each way to break the rules of clauses and cases is refused with its message, key and line. |
| TV-037 | TR-13 | `test_code_links.py` CodeLinkTests.test_clause_inherits_its_part_link | a clause without its own code link inherits its part definition's, joined value as one. |
| TV-038 | TR-13 | `test_code_links.py` CodeLinkTests.test_own_link_wins | a clause's own code link wins over its part's. |
| TV-039 | TR-13 | `test_code_links.py` CodeLinkTests.test_each_fault_of_a_code_link_is_refused | a link on an action definition, two inherited candidates and a delivered clause without a link are each refused with key and line. |
| TV-040 | TR-17 | `test_code_structure.py` CodeStructureTest.test_each_module_in_one_part_folder_is_accepted | each module in one part's folder, a module and a page outside it named by the part's CodeDiffers, a shared module, test files and modules declared only under `#[cfg(test)]` or from a test file are accepted. |
| TV-041 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_of_no_part_is_refused | a module no part names outside server/src/shared/ is refused. |
| TV-042 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_of_two_parts_is_refused | a module two part definitions name is refused. |
| TV-043 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_outside_its_folder_unmarked_is_refused | a part's module, or a module its clause names, outside the part's folder and not named by its CodeDiffers is refused. |
| TV-044 | TR-17 | `test_code_structure.py` CodeStructureTest.test_marker_naming_a_module_inside_is_refused | a CodeDiffers naming a module inside the part's folder is refused. |
| TV-045 | TR-10 | `test_decoder_mode_traces.py` DecoderModeTraceTests.test_each_mode_case_binds_tests_of_that_mode | each mode case binds named tests that select its mode and load a fixture of that mode. |
| TV-046 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e2_doc_character | E2: doc character. |
| TV-047 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e3_dropped_element | E3: dropped element. |
| TV-048 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e4_changed_target | E4: changed target. |
| TV-049 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e5_value_multiplicity_rename | E5: value multiplicity rename. |
| TV-050 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e6_reference_resolving_to_another_element | E6: reference resolving to another element. |
| TV-051 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e7_move_listed_and_equivalent | E7: move listed and equivalent. |
| TV-052 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e8_citations_outside_the_model | E8: citations outside the model. |
| TV-053 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e15d_fixture_reader_exempts_only_its_declared_package | E15 d: a fixture reader's citations of its own package are exempt, of another package not. |
| TV-054 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e15e_other_files_keep_p6 | E15 e: a file outside tools/sysml/tests/, or one declaring no package, keeps P6. |
| TV-055 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e9_cannot_compare | E9: cannot compare. |
| TV-056 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12_each_mutation_is_named | E12: each mutation is named. |
| TV-057 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12o_values_swapped_between_same_named_owners | E12 o: values swapped between same named owners. |
| TV-058 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12s_same_named_owners_pair_by_their_members | E12 s: same named owners pair by their members. |
| TV-059 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12p_member_moved_between_same_named_owners | E12 p: member moved between same named owners. |
| TV-060 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12q_expose_is_compared | E12 q: expose is compared. |
| TV-061 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12r_comment_outside_any_package | E12 r: comment outside any package. |
| TV-062 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e13_equal_same_named_elements_pair_in_their_package | E13: equal same named elements pair in their package. |
| TV-063 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e14_changed_element_leaves_its_equal_namesake_paired | E14: changed element leaves its equal namesake paired. |
| TV-064 | TR-21 | `test_equivalence.py` IdentityTests.test_e10a_one_identity_of_each_status | E10 a: one identity of each status. |
| TV-065 | TR-21 | `test_equivalence.py` IdentityTests.test_e15_link_following_a_moved_file | E15: link following a moved file. |
| TV-066 | TR-21 | `test_equivalence.py` IdentityTests.test_e15_guard_link_retargeted_to_another_file | E15: guard link retargeted to another file. |
| TV-067 | TR-21 | `test_equivalence.py` IdentityTests.test_e10b_real_revisions_list_the_union | E10 b: real revisions list the union. |
| TV-068 | TR-21 | `test_equivalence.py` RealHistoryTests.test_e1_divided_requirements_are_equivalent | E1: divided requirements are equivalent. |
| TV-069 | TR-21 | `test_equivalence.py` ReaderRecognitionTests.test_r_real_readers_of_this_repository | R-real: the architecture tests' fixture trees are fixture readers of the packages they declare; server/src/main.rs reads no model of its own. |
| TV-070 | TR-21 | `test_equivalence.py` MarkedCommitTests.test_e11_marked_commits_against_their_first_parent | E11: marked commits against their first parent. |
| TV-071 | TR-05 | `test_file_contents.py` FileContentsTest.test_accepted | Requirements, Shack, Context and UseCases in the forms of M4.1 to M4.3 and M4.9 are accepted. |
| TV-072 | TR-05 | `test_file_contents.py` FileContentsTest.test_negatives | each way to break what a file holds is refused with its one fault line. |
| TV-073 | TR-05 | `test_file_contents.py` FileContentsTest.test_real_model_contents | the real model `docs/sysml` holds in each file what M4 allows. |
| TV-074 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_status_is_computed_from_the_clauses | all implemented gives implemented, mixed gives partial, all target or none gives target. |
| TV-075 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_computed_status_of_each_mix_of_states | each mix of clause states gives the status the rule names. |
| TV-076 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_status_lines_name_each_fr_with_its_counts | status prints each FR's computed status with its clause counts, then the summary. |
| TV-077 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_fr_stating_a_status_is_refused | an FR that states a status or a code link is refused. |
| TV-078 | TR-15 | `test_identity_history.py` IdentityHistoryTest.test_kept_and_new_identities_are_accepted | a kept identity with changed text and a new identity are accepted. |
| TV-079 | TR-15 | `test_identity_history.py` IdentityHistoryTest.test_used_identity_declared_again_is_refused | an identity of an earlier commit that the merge base does not declare is refused when declared again, with other text and with its old text. |
| TV-080 | TR-15 | `test_identity_history.py` NoMainBranchTest.test_history_without_master_is_unavailable | a repository without a `master` branch gives no identity history. |
| TV-081 | TR-04 | `test_layers.py` LayerTest.test_accepted | imports from earlier layers, UseCases naming Context's actors and QsoControl importing a type of TransmitControl are accepted. |
| TV-082 | TR-04 | `test_layers.py` LayerTest.test_control_interfaces | the control interfaces are the packages `WstxStationLink::WireNames` lists. |
| TV-083 | TR-04 | `test_layers.py` LayerTest.test_negatives | each way to break the layers is refused with its one fault line. |
| TV-084 | TR-04 | `test_layers.py` LayerTest.test_real_model_layers | the real model `docs/sysml` keeps its layers. |
| TV-085 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_lists_every_marker_by_key_and_line_with_counts_by_kind | every marker of a WstxModelNotes kind is listed by key and line, then the counts by kind; a binding, a doc and a string are not markers. |
| TV-086 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_lists_a_joined_value_as_one_text | a marker value of literals joined by `+` is listed as one text. |
| TV-087 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_refuses_a_kind_that_is_not_a_wstxmodelnotes_kind | a kind that no WstxModelNotes `metadata def` declares is refused and nothing is listed. |
| TV-088 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_without_a_wstxmodelnotes_file_lists_none | without a file of package WstxModelNotes there is no kind and no marker. |
| TV-089 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_needs_the_authority_marker | `markers` refuses a model without the authority marker and writes nothing. |
| TV-090 | TR-10 | `test_model_tree.py` CatalogTests.test_rebuilt_forms_are_read_into_the_catalog | the FR, the clause with its derivation and the case of the rebuilt forms are read. |
| TV-091 | TR-10 | `test_model_tree.py` CatalogTests.test_duplicate_identity_is_refused | an identity declared twice is refused. |
| TV-092 | TR-10 | `test_model_tree.py` CatalogTests.test_wrong_kind_is_refused | an FR or a clause declared as a verification is refused. |
| TV-093 | TR-10 | `test_model_tree.py` CatalogTests.test_unreadable_form_is_refused | a definition, a typed declaration and a short name with an identity are refused. |
| TV-094 | TR-10 | `test_model_tree.py` CatalogTests.test_derivation_from_a_missing_fr_is_refused | a derivation whose original is no declared FR is refused. |
| TV-095 | TR-10 | `test_model_tree.py` CatalogTests.test_clause_without_derivation_is_refused | a clause that derives from no FR is refused. |
| TV-096 | TR-10 | `test_model_tree.py` CatalogTests.test_required_package_missing_is_refused | each of WstxRequirements, WstxShack and WstxContext declared by no file is refused. |
| TV-097 | TR-10 | `test_model_tree.py` CatalogTests.test_required_package_declared_twice_is_refused | each of WstxRequirements, WstxShack and WstxContext declared by two files is refused. |
| TV-098 | TR-20 | `test_model_tree.py` StatedTests.test_states_and_bindings_are_read_once_each | package names, a manual method and a binding of joined literals are read as one value each. |
| TV-099 | TR-20 | `test_model_tree.py` StatedTests.test_each_fault_of_a_state_or_binding_is_refused | a missing, unknown or repeated state, a repeated binding or method, an unknown method, a missing or outside file, and a delivered case without a test are each refused. |
| TV-100 | TR-20 | `test_paths.py` PathRewriteTests.test_file_renames_rewrite_every_form_and_nothing_else | file renames rewrite @ImplementedIn, @TestedBy, @DetailTests, relative links and whole paths in text, and nothing that is not a whole path; a second run is refused. |
| TV-101 | TR-20 | `test_paths.py` PathRewriteTests.test_folder_rename_rewrites_paths_below_it_only | a folder rename rewrites the paths below the folder, not the folder named alone nor a name that only begins like it. |
| TV-102 | TR-20 | `test_paths.py` PathRewriteTests.test_each_literal_of_a_joined_value_is_rewritten | the paths of every literal of a value joined by `+` are rewritten and checked. |
| TV-103 | TR-20 | `test_paths.py` PathRewriteTests.test_a_joined_value_is_one_path | a joined value is one value: a path that ends at `::` in one literal, or that is split inside by `+`, is read and rewritten as one path. |
| TV-104 | TR-20 | `test_paths.py` PathRewriteTests.test_unchecked_strings_are_rewritten_but_not_checked | a binding the catalog does not check is rewritten but refuses nothing. |
| TV-105 | TR-20 | `test_paths.py` PathRewriteTests.test_refusals_write_nothing | a malformed list, a missing moved file or a path that stays missing is refused with its faults and nothing is written. |
| TV-106 | TR-20 | `test_paths.py` PathRewriteTests.test_real_model_rewrites_a_moved_test_file_and_traces_keep_their_verdict | on the model of HEAD, every path of a moved test file is rewritten, nothing outside the model is written, and `traces` gives the verdict it gave before the move; the repository is not written. |
| TV-107 | TR-12 | `test_real_model_catalog.py` RealModelStatusTests.test_status_on_this_tree_prints_each_fr_of_the_catalog_with_its_computed_status | `status` on this tree prints each FR of the catalog with the status its clauses give it, then the counts. |
| TV-108 | TR-10 | `test_real_model_catalog.py` RealModelPackageTests.test_this_tree_is_accepted | the catalog accepts this tree; Shack.sysml holds the package WstxShack. |
| TV-109 | TR-06 | `test_real_model_structure.py` RealModelStructureTests.test_check_on_this_tree_passes_every_model_rule | `check` on this tree, whose Shack.sysml holds WstxShack, prints the architecture line and then the model rules' line for every model file. |
| TV-110 | TR-09 | `test_reference_target.py` ReferenceTargetTests.test_nested_and_absolute_forms_give_equal_reference_rows | a reference written from the root and one written from its enclosing usage give equal REF rows, rooted at the deployment. |
| TV-111 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_rejects_files_that_stitch_invalid_syntax | files that only stitch into valid syntax are refused, each named. |
| TV-112 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_resolves_complete_graph_and_keeps_file_diagnostics | file order hides neither a valid reference nor its diagnostic. |
| TV-113 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_accepts_valid_and_rejects_syntax_and_reference | the Pilot accepts a valid model and refuses a syntax error and an unresolved name. |
| TV-114 | TR-02 | `test_sysml.py` ValidatorTests.test_missing_tool_never_reports_semantic_pass | a missing Java or JAR never reports a semantic pass. |
| TV-115 | TR-02 | `test_sysml.py` ValidatorTests.test_empty_or_corrupt_cached_library_is_refused | an empty or corrupt cached library is refused. |
| TV-116 | TR-14 | `test_tags.py` TagTests.test_tags_of_one_and_two_cases_are_accepted | a tag of one case and a tag of two cases joined by a comma are accepted. |
| TV-117 | TR-14 | `test_tags.py` TagTests.test_each_tag_outside_the_form_is_refused | a tag naming an FR, a clause, shorthand, an issue number or added text is refused with its line. |
| TV-118 | TR-14 | `test_tags.py` TagTests.test_tag_naming_an_undeclared_case_is_refused | a tag naming a case the model does not declare is refused with its line. |
| TV-119 | TR-19 | `test_test_level.py` LevelTests.test_levels_of_a_case_are_read | a case states no level, one, several or each location, with or without package names. |
| TV-120 | TR-19 | `test_test_level.py` LevelTests.test_each_fault_of_a_level_is_refused | a cost, location, feature or form outside the rule, and a level on anything but a verification, are each refused naming the case or the element and its key. |
| TV-121 | TR-19 | `test_test_level.py` PilotLevelTests.test_pilot_resolves_the_level_and_refuses_a_misspelt_location | the pinned Pilot resolves TestLevel of WstxModelBindings and refuses a misspelt feature. |
| TV-122 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_code_changes_select_fast_trace_check_without_full_model_suite | a code change selects traces, not the full model suite. |
| TV-123 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_model_file_in_a_subfolder_selects_the_model_suites | a model file in a subfolder selects the model suites. |
| TV-124 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_source_change_or_deletion_invalidates_both_evidence_fingerprints | a source change or deletion invalidates both evidence fingerprints. |
| TV-125 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_every_admitted_source_root_is_fingerprinted_and_selects_fast_traces | every source root is fingerprinted and selects traces. |
| TV-126 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_model_and_model_data_changes_select_the_working_model_suite_not_the_validator | a model edit selects the working-model suite, not the validator tests. |
| TV-127 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_tool_changes_select_the_architecture_suites_they_feed | a tool change selects the architecture suites it feeds. |
| TV-128 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_suite_definitions_select_both_architecture_suites | the suite definitions select both architecture suites. |
| TV-129 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_source_change_selects_neither_architecture_suite_and_invalidates_only_the_validator | a source edit selects neither architecture suite and invalidates only the validator's evidence. |
| TV-130 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_every_sysml_test_file_runs_in_exactly_one_suite | every tool test file runs in exactly one suite. |
| TV-131 | TR-03 | `test_tree.py` TreeTest.test_tree_is_m21 | the tool's tree is M2.1's, 116 files, each with its M7.5 package. |
| TV-132 | TR-03 | `test_tree.py` TreeTest.test_accepted_tree | the M2.1 tree with a data file in `data/` is accepted. |
| TV-133 | TR-03 | `test_tree.py` TreeTest.test_extra_model_file | a model file outside the tree is refused. |
| TV-134 | TR-03 | `test_tree.py` TreeTest.test_listed_file_missing | a file of the tree that is missing is refused. |
| TV-135 | TR-03 | `test_tree.py` TreeTest.test_reference_readme | a file beside the model files outside `data/` (`reference/README.md`) is refused. |
| TV-136 | TR-03 | `test_tree.py` TreeTest.test_required_packages_accepted | the tree, each required package declared once, passes the catalog. |
| TV-137 | TR-03 | `test_tree.py` TreeTest.test_required_package_missing | a required package declared by no file is refused. |
| TV-138 | TR-03 | `test_tree.py` TreeTest.test_required_package_twice | a required package declared by two files is refused. |
| TV-139 | TR-03 | `test_tree.py` TreeTest.test_real_model_tree | the real model `docs/sysml` is the M2.1 tree with only `data/` beside it. |
| TV-140 | TR-16 | `test_values.py` ValuesTest.test_every_way_of_verifying_is_accepted | constants with expressions, `200.`, a rounded Real and `from_millis`; `A::F`, `B::F` and `a::F`, `b::F` in one module; a module `F`; a JavaScript `D.F`; a bound test; a target clause in another file; a marker; a literal, wire name, variable and command field found: all accepted. |
| TV-141 | TR-16 | `test_values.py` ValuesTest.test_unequal_constant_is_refused | a constant unequal to its model value is refused. |
| TV-142 | TR-16 | `test_values.py` ValuesTest.test_value_none_verifies_is_refused | a value that no constant, marker, target clause or bound test verifies is refused. |
| TV-143 | TR-16 | `test_values.py` ValuesTest.test_name_absent_is_refused | a literal, wire name or variable the code does not hold is refused. |
| TV-144 | TR-16 | `test_values.py` ValuesTest.test_marker_where_the_code_matches_is_refused | a CodeDiffers on a value the code holds as the model states is refused. |
| TV-145 | TR-16 | `test_values.py` ValuesTest.test_name_twice_is_refused | a value with two candidates, or whose only module `F` stands where another value of that name has its code, is refused as named twice. |
| TV-146 | TR-16 | `test_values.py` ValuesTest.test_constant_outside_its_binding_is_not_verified | `D::F` or `d::F` outside its code, `D::F` on a unit struct `D` and `F` in a `mod` named after no owner verify nothing. |
| TV-147 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_accepted | the model's forms, a joined path at `; ` and a line of 100 columns are accepted. |
| TV-148 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_negatives | each way to break the writing rules is refused with its one fault line. |
| TV-149 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_doc_line_names_no_element | a word that begins a wrapped doc line is no element of the file, so a clause naming only that word names no element of its file. |
| TV-150 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_real_model_writing | the real model `docs/sysml` meets the writing rules. |
| TV-151 | TR-20 | `server/tests/model_values.rs` model_values_reads_every_fixture_value_in_lf_and_crlf | the Rust reader accepts every value of the fixture list, in LF and CRLF. |
| TV-152 | TR-20 | `server/tests/model_values.rs` model_values_refuses_every_fixture_fault_naming_name_and_reason | the Rust reader refuses every fault of the fixture list, naming the name and the reason. |
| TV-153 | TR-20 | `tests/model-values.test.cjs` model values: every fixture value is read, in LF and CRLF | the JavaScript reader accepts every value of the fixture list. |
| TV-154 | TR-20 | `tests/model-values.test.cjs` model values: every fixture fault is refused naming the name and the reason | the JavaScript reader refuses every fault of the fixture list. |
