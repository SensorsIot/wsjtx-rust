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
  `@DetailTests` (each literal of a joined value), relative links and whole paths in text,
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
