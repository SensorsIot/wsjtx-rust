# Model tools

The contract of the model tools (`tools/sysml.py`, `tools/sysml/Validate.java`): the pinned
toolchain, the commands, the rules `TR-01` to `TR-24` they check and the tests `TV-nnn`
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
python tools/sysml.py tests <rev>
python tools/sysml.py check <rev>
python tools/sysml.py traces <rev>
python tools/sysml.py status
python tools/sysml.py markers
python tools/sysml.py oracle
python tools/sysml.py test-hooks
python -m unittest discover -s tools/sysml/tests -q
```

- `traces`: the authority (TR-01), the catalog (TR-10, TR-12, TR-19), the tags and their
  bindings (TR-14), the code links (TR-13), model and code (TR-16), the code structure
  (TR-17) and the history in comments, names and test strings (TR-22). No Java. It is the
  check a code change selects. A pass ends with `Canonical source/model trace checks passed:
  <n> identities; <f> files read for history, <e> comment exceptions used; ...`.
- `check`: everything `traces` checks, then the Pilot validation of every model file
  (TR-02), the architecture oracle (TR-09), the identity history (TR-15) and the rules of
  the model text and the deployment (TR-03 to TR-08, TR-11, TR-18). Every rule fault of a
  run is printed, one line each, sorted by rule, file or path and line, as
  `<message>: <key>:<line>` (a deployment fault: `<message>: <path>`); then
  `SysML check failed: <n> faults`, exit 2. A pass ends with `Model rules passed: <n>
  model files.`
- `tests <rev>`, `check <rev>`, `traces <rev>`: the code proof at the commit `<rev>` names
  (TR-23): its test inventory, its model check and its trace listing; they read that
  revision only and write nothing.
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
- `test-hooks [--lines]`: the product files that hold a test item, a test switch or a hook
  (TR-24); the command of the ratchet `product-knows-no-test`. It reads the working tree and
  writes nothing.

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
  Java, JAR (hash) or library fails; there is no lightweight fallback. The Pilot run allows
  600 s; each run prints `validator: <s> s (limit 600 s)` to stderr, and a run past the
  limit fails with `SysML check failed: validator timed out after 600 s`, exit 2, never as a
  model fault.
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
  connection from the frontend ends at one of those two. Each literal of
  `WstxStationCommands::AgentRefusal` names a command of `StationOperations` or a collection of
  `SettingsCollection` (`AgentRefusal literal <x> names no command or collection`). mcp's port
  toward the supervisor is typed `AgentOperations` and not `StationOperations`;
  `AgentOperations` specializes `StationOperations`, redefines exactly the refused commands to
  `[0]` (`mcp offers the refused command <x>`, `mcp lacks the command <x>`) and redefines the
  `collection` of each of `createEntry`, `updateEntry` and `deleteEntry` to `AgentCollection`
  (`an agent's <command> takes every collection`). `AgentCollection` is an `attribute def`
  that specializes `SettingsCollection`; the `SettingsCollection` literals it names are exactly
  those AgentRefusal does not name (`an agent's entry command on <x>`, `AgentCollection lacks
  the collection <x>`).
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
  `verify` of declared clauses. A delivered case names each of its tests as `<file>::<test>`
  (TR-14). A value joined by `+` is one value.
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
  <path>:<line>`. It names declared cases only, and each case's binding holds the test as
  `<file>::<test name>` (`Proves tag outside the verification binding: ...`, one message
  after the other faults). Every test below the source roots (each `#[test]`,
  `#[tokio::test…]` or JavaScript `test(` line of a `.rs`, `.js` or `.cjs` file) is one of
  two kinds: a contract test carries the tag of each case it proves (an attached tag, or
  for a JavaScript test its title naming the case), and each of those cases names it in its
  `@TestedBy` as `<file>::<test>` (`<test>` the Rust function name or the JavaScript title);
  a detail test carries no tag, and its file is named in the `@DetailTests` of a part. A
  file may hold both kinds. Refused, one line each, sorted with the tag faults:
  `TestedBy binds a whole file: <case>: <path>` (a case of either method);
  `Bound test lacks the Proves tag of its case: <case>: <path>:<line> <test>`;
  `Test neither tagged nor a detail test: <path>:<line> <test>`, for a test no case binds.
  `<line>` is the line of the test's `#[test]`, `#[tokio::test…]` or `test(`. A test whose
  tag names only undeclared cases gives the tag's line and none of these.
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
  string literal; V2, a test bound to a case of a clause reaching it (the test `symbol` of
  its `path::symbol` binding) holds in its own code, outside comments, its qualified name,
  or its definition's qualified name and the feature's name. Its own code is its body and the bodies of the
  functions of its file it calls, directly or through each other. A comment is a Rust `//`,
  `///`, `//!` or block comment, a Node `//` or block comment, or a Python `#` comment or
  docstring. Another test, the file's top level, a comment before the test and a comment
  inside it do not count. A feature of an `item
  def` in the files named above is a command field: its value is verified when its name is
  found. The forms of V1 are tried in that order; at the first form that has a candidate, two
  candidates, or a module `F` that another compared value of that name also has in its code,
  are `Name twice in one code: <name>`. A constant found unequal is `Model and code differ:
  <element>: model <value>, code <value>`, whatever V2 says; an element none of V1 to V4
  covers is `Value not verified: <element>`; each with its key and line. Constant arithmetic
  takes `_` separators, Rust type suffixes and `as` casts, `Duration::from_secs` and
  `from_millis`, and other constants of the same module.
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
  holds its own identity, a date, an issue number or a history word; an underscore stands only
  in a quoted name (`'rst_sent'`), and a definition is in UpperCamelCase; a package is `Wstx`
  and its file's name, a part's own file adding `Part`; no `//` comment but the authority
  marker, no `/* */` outside a `doc`; no line over 100 characters; a joined value meets where
  one literal ends in a space or `;`, or right after the `::` of a `<path>::<test name>`
  binding, or where the next begins with a space or `;`, never inside a word or a path.
- **TR-19 Test level.** A case states `@TestLevel { cost = <1..5>; location =
  TestLocation::<developmentPc|station|simulator|flexRadio>; }`, each pair once; anything
  else, or `@TestLevel` on another element, is `Invalid test level: <identity>`.
- **TR-20 Values read, markers, paths, status.** A contract test reads a model value by its
  qualified name through the one reader of its language (`tools/test/rust/src/model_values.rs`,
  `tools/test/node/model-values.cjs`); a missing, duplicate or unreadable value fails. `markers` lists
  `<key>:<line>: <Kind>[ about <targets>]: <text>` per marker of the `WstxModelNotes` kinds,
  then the counts. `paths` rewrites the paths of `@ImplementedIn`, `@TestedBy` and
  `@DetailTests` (a joined value read as one text), relative links and whole paths in text,
  and refuses a malformed list, missing moved files or a path that stays missing.
- **TR-21 Equivalence and identities.** `equivalence` exports each side with the Pilot and
  compares every named element by meaning; a citation of the model in the tracked files
  that resolved on the base and not on the head is a difference, except a name citation of
  a fixture reader below `tools/sysml/tests/` of its own fixture package. A name written in a
  comment, in Markdown or in product code resolves as the Pilot resolves it (imports, aliases
  and re-exports followed). In the string literals of test and tool code (as TR-22 reads
  them) a name is a lookup citation and resolves on a side only where that side declares the
  element under that qualified name: a whole qualified name in a string, and a composed name,
  each string literal that is a name or a relative qualified name (not starting with a top
  package) joined to each lookup prefix of the file. A lookup prefix is a qualified name
  ending in `::` whose first segment is a top package, followed by a `${` or `{` placeholder
  (`{{` is none) or by the end of its string. A composed name is cited at the literal's line
  only when the base declares it. A file whose strings cannot be read adds no lookup
  citation. Exit 0 equivalent, 1 differences, 2 cannot compare. `identities` lists each FR, CL and TC identity of two
  revisions as unchanged, moved, changed, added or removed.
- **TR-22 History in comments.** `traces` reads every tracked `.rs`, `.js`, `.cjs`, `.mjs`,
  `.css`, `.html`, `.py`, `.ps1`, `.java`, `.sysml`, `.toml`, `.yml` and `.md` file below
  `server/` (not `server/third-party/`), `client/`, `tests/`, `tools/` and `fixtures/`, the
  workflows of `.github/workflows/` that are no `harness_paths` of
  `harness/project/config.yaml`, and `README.md`, `Cargo.toml`, `server/Cargo.toml` and
  `rust-toolchain.toml`. A comment (line, block and doc comments, Python comments and
  docstrings, PowerShell `#` and `<# #>`, CSS and HTML comments, TOML and YAML `#`) and
  Markdown prose hold no issue pointer, date or change story (`history in a comment: issue
  pointer <text>`, `history in a comment: date <text>`, `history in a comment: change story
  <text>`). The string literals of test and tool code (below `tests/`, `server/tests/`,
  `tools/` and `fixtures/`, and the `*_tests.rs` and `*_test.rs` files below `server/`: Rust
  strings and raw strings, JavaScript quoted and template strings, Python strings, PowerShell
  strings and here-strings), Markdown code spans and fenced code blocks, and the names of Rust
  and Python test functions hold no issue pointer (`issue pointer in a string: <text>`,
  `issue pointer in Markdown code: <text>`, `issue pointer in a test name: <name>`). An issue
  pointer is `#` and digits, not right after `&` or `#` and not followed by a letter or
  digit; `<repo>#N` and `<owner>/<repo>#N`, a name of letters, digits, `.`, `_` and `-`;
  `issue`, `cr` or `pr` in any letter case, then at most one of ` `, `-`, `_` and `#`, then
  digits, neither right after nor followed by a letter or digit; `review`, a space and six or
  more digits. Of two forms that match one text, the longer is the fault. A date is
  `YYYY-MM-DD`. A change story is, in any letter case, `formerly`, `previously`, `no longer`,
  `any more`, `anymore`, `as before`, `used to`, `originally`, `retired`, `legacy`, `was
  changed`, `were changed`, `red on the parent`, `review finding`, `finding N`, `round N`,
  `operator grill`, `operator decision`, `coordinator decision`, `coordinator's decision`,
  `live defect` or `live finding`. A test name holds no `issue`, `cr` or `pr` joined to a
  number directly or by `_`. Not read: the text of a URL and of a Markdown link target,
  JavaScript regular-expression literals (one token each, quotes inside included), the other
  strings, data files and `server/third-party/`. `tools/sysml/comment-exceptions.json` is a
  JSON array of `{"path": ..., "text": ..., "kind": ...}`, kind `D1` (an epoch or calendar
  constant the code computes with), `D2` (a version of an external specification or data
  source), `D3` (a date of the test's own data), `M` (a model term), `S` (a data string
  holding a pointer form) or `I` (a pointer whose rule depends on an open issue's state); an
  entry exempts every occurrence of its exact text in its own file. Refused at the line of the
  entry's opening brace: an entry that exempts nothing (`comment exception unused: <path>
  <text>`) and a malformed entry (`comment exception malformed: <reason>`), at line 1 a list
  that is no JSON array; refused by path, a file that is not UTF-8 (`source not UTF-8`), and
  at its line a text its reader cannot read (`source not readable: <reason>`).
- **TR-23 Code proof listings.** The three commands of the code proof read one revision:
  - `tests <rev>` prints one line per product test of the commit `<rev>` names, sorted,
    and exits 0; a test that occurs twice is printed twice, and no line holds a path. A
    Rust line is `rust <function name>`, for every function under `#[test]` or
    `#[tokio::test…]` (`#[ignore]` included) in every `.rs` file below `client/`, `server/`
    and `tests/`. A Node line is `node <title>`, for every call of `test`, `it`,
    `test.skip`, `test.only`, `test.todo` or `.test` (a subtest) whose first argument is a
    string or template literal, in the files named `*.test.js`, `*.test.cjs` or
    `*.test.mjs` below those roots; a quoted title is its value with its escapes resolved,
    a template title is written as between the backticks, `${…}` unexpanded and a line
    break written `\n`. A `.test(` call whose first argument is no literal is a RegExp test
    and not listed. A Python line is `python <Class>.<name>` for a `def test_…` or `async
    def test_…` directly in a class body and `python <name>` for one at module level, in
    the tracked `test_*.py` files outside `tools/sysml/` and outside the `harness_paths`
    of that revision's `harness/project/config.yaml`. Comments, strings and JavaScript
    regular-expression literals are not read.
  - `check <rev>` runs every check of `check` on the revision's files: the revision's
    model, sources, `tools/sysml/architecture-oracle.json` and
    `tools/sysml/comment-exceptions.json`, the identity history (TR-15) against `git
    merge-base <rev> master`, and for TR-22 the revision's tracked files and its
    `harness_paths`. Its output and exit codes are those of `check`. Only the running
    tool's own code and the toolchain cache are not taken from the revision.
  - `traces <rev>` runs every check of `traces` on the revision's files, as `check <rev>`
    reads them. When they pass it prints the trace listing and exits 0: one line per
    identity, FR then CL then TC, each in identity order, with no path and no model file
    key. `FR-nnn <status> clauses <CL,…>`; `CL-nnn-nn <state> from <FR,…> cases <TC,… or
    -> link <L>`, `<L>` being `own <file names>` (the sorted, comma-joined file names of
    the clause's own `@ImplementedIn` modules), `part <part definition name>` or `none`;
    `TC-nnn-nnn <state> <automated|manual> verifies <CL,…> tests <T>`, `<T>` the sorted,
    `; `-joined inventory lines of the tests bound to the case (for `path::symbol` the test
    `symbol`) or `-`. On a fault it prints the fault lines and exits 2, with no listing.
  - They read the revision with git into a temporary folder that is gone when the command
    ends, never a working-tree file, staged or untracked, and write nothing into the
    repository: no checkout, no index change. Without a revision, `check` and `traces`
    read the working tree as above; `tests` without a revision is refused.
  - Refused with exit 2, `SysML check failed: <message>` and nothing on stdout: an unknown
    revision (`unknown revision: <rev>`), a Node `test(` or `it(` whose title is no
    literal (`unreadable test name: <path>:<line>`), and a source its reader cannot read
    (`source not readable: <path>:<line>: <reason>`).
- **TR-24 The product knows no test (testing standard, Test tools; Rust pack, Ports are
  traits).** `test-hooks` lists the product files that hold a test item, a test switch or a
  hook:
  - It reads the working tree: the tracked files (`git ls-files`) present on disk, and the
    model files below `docs/sysml/`. It writes nothing and runs no Java, no Pilot and no
    network access. The product files are the code modules of TR-17 that are tracked, except
    any file named `*_test.rs`.
  - It prints each product file holding at least one form below: one path per line,
    relative and `/`-separated, sorted, each path once, and exits 0 with or without paths.
    With `--lines` it prints one line per form found, `<path>:<line>: <form>: <text>`,
    sorted by path and line, `<line>` the first line of the form, and exits 0. `<form>` is
    one of `cfg test`, `test file declared`, `debug_assertions`, `doc(hidden)`,
    `environment`, `CommonJS export`, `process.env`, `unread global`, `unread member`;
    `<text>` is the attribute, call or name found.
  - Comments (line, block and doc comments), strings, raw strings, template strings and
    JavaScript regular-expression literals are not read, with the readers of TR-22. An
    attribute is read whole across line breaks; CRLF and LF read alike.
  - Test predicates (Rust). A cfg predicate is the predicate of `#[cfg(…)]`, `#![cfg(…)]`
    or `cfg!(…)`, or the first argument of `#[cfg_attr(…)]`; it names `test` when the word
    `test` stands in it. Listed (`cfg test`): every predicate naming `test`, except the
    attributes of a test-file declaration: `cfg(not(test))`, `cfg(any(windows, test))`, an
    inline `#[cfg(test)] mod tests { … }`, and `#[cfg(test)]` on a field, function,
    statement, `use` or `impl`. A test-file declaration is a `mod <name>;` item, of any
    visibility and without a body, one of whose outer attributes is `#[cfg(test)]` or
    `#[cfg(all(…))]` with `test` as a direct argument, and which resolves to a file named
    `tests.rs`, `*_tests.rs` or `*_test.rs`: by `#[path = "…"]` relative to the declaring
    file's folder, otherwise as `rust_modules` finds it. Every outer attribute of that item
    belongs to the declaration and is not listed (`#[path]`, a second
    `#[cfg(not(debug_assertions))]`, `cfg(all(test, not(debug_assertions)))`). A `mod
    <name>;` with a test predicate that resolves to a file not named as a test file is
    listed (`cfg test`); a `mod <name>;` that resolves to a test file without a test
    predicate among its attributes is listed (`test file declared`).
  - Build-profile branches (Rust). Listed (`debug_assertions`): every predicate in which the
    word `debug_assertions` stands, except the attributes of a test-file declaration. Not
    listed: `debug_assert!`, `debug_assert_eq!` and `debug_assert_ne!`.
  - Hidden items (Rust). Listed (`doc(hidden)`): every `doc` attribute holding `hidden`,
    whatever the item's visibility.
  - Environment reads (Rust). A read is a call of `env::var`, `env::var_os`, `env::vars` or
    `env::vars_os`, whatever path stands before `env::`; the macro `env!` or `option_env!`;
    or a `use` that imports one of those four functions from `std::env`. Each is listed
    (`environment`) unless its first argument is a string literal naming a product
    variable: a name that stands as a whole word in the text of a model file below
    `docs/sysml/`, or, for `env!` and `option_env!` only, a name that begins with
    `CARGO_PKG_`. Always listed: `vars`, `vars_os`, a name that is not a literal, and the
    `use`.
  - Client modules (`*.js` below `client/`). Listed (`CommonJS export`): `module.exports`,
    an assignment to `exports.<name>`, and `typeof module` or `typeof exports`. Listed
    (`process.env`): every `process.env`. Listed (`unread global`): an assignment
    `window.<name> =` or `globalThis.<name> =` when no client file holds `window.<name>` or
    `globalThis.<name>` other than as the target of an assignment; an `=` that is part of
    `==`, `===` or `=>` is no assignment. Listed (`unread member`): when the value assigned
    is an object literal, directly or as the argument of `Object.freeze(`, each of its
    members (shorthand or key) that no client file reads as `<global>.<member>` or
    `<global>?.<member>` after `window.` or `globalThis.`. A read in a test, a tool or a
    file outside `client/` does not count; a read through another variable (`const c =
    window.x; c.load()`) is not recognised, so the member stays listed.
  - The exception list `tools/sysml/product-knows-no-test.txt`, in the form
    `harness/general/core/tools/ratchet.py` reads: a first comment line naming the ratchet
    and the command, then one path per line, each with a comment naming its forms. Its
    paths are exactly what `test-hooks` prints. TR-22 does not read `.txt` files, so an
    `# approved: <decision>` line is not refused as history.
  - Refused with exit 2, `SysML check failed: <message>` and nothing on stdout: a product
    file that is not UTF-8 (`source not readable: <path>:1: source not UTF-8`), a source
    its reader cannot read (`source not readable: <path>:<line>: <reason>`), no git work
    tree, or git failing.
  - Limits: the command finds forms, not intent. Not found: a function only tests call; a
    visibility widened for tests; a custom `--cfg` or a Cargo feature; a client switch read
    from storage or the URL.

## Meaning and limits of semantic validation

`tools/sysml/Validate.java` calls the pinned Pilot's `SysMLInteractive` API, including its
parser, name resolution and Xtext semantic validator, on all model files as one graph.
With `--inventory` it also lists the resolved deployment and the inputs of the rules
(`PART`, `REF`, `PORT`, `ITEM`, `EDGE`, `CONN`, `ELEM` with each definition's features and
doc, `IITEM`, `PITEM`, `OUTSIDE`, `MEMBER`, `SUBJECT`, `WHERE`). Successful validation is no
execution of modelled behaviour and no proof that the code meets the model.

## Tests

Each test of `tools/sysml/tests/` names its `TV` and rule in its docstring. The suites that
run them are those of `harness/project/suites/`.

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
| TV-028 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_refusal_literal_naming_no_command_is_refused | an AgentRefusal literal that names no command and no collection is refused. |
| TV-029 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_agent_entry_command_on_strategies_passes | an agent's entry commands take AgentCollection, which admits strategies. |
| TV-030 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_agent_entry_command_on_udp_targets_is_refused | AgentCollection admitting udpTargets, which AgentRefusal names, is refused. |
| TV-031 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_agent_collection_lacking_wanted_list_is_refused | AgentCollection lacking wantedList, which AgentRefusal does not name, is refused. |
| TV-032 | TR-06 | `test_architecture_structure.py` AgentCommandTests.test_agent_entry_command_on_every_collection_is_refused | an agent's entry command whose collection is not AgentCollection is refused. |
| TV-033 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_tagged_tests_in_their_bindings_are_accepted | a test bound by name with its case's tag, a tag of two cases bound by both, a `#[tokio::test(...)]` bound by name with its tag, a JavaScript test bound by its title that names the case, an untagged test in a `@DetailTests` file, and a `@DetailTests` file that also holds a tagged test bound by name are accepted. |
| TV-034 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_each_test_or_file_outside_the_binding_is_refused | a tagged test its case's binding lacks, a tagged test in a file no case binds and a bound test name that no test has are each refused. |
| TV-035 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_marker_and_no_fsd_make_sysml_the_authority | the marker on the first line of Requirements.sysml and no FSD make SysML the authority. |
| TV-036 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_each_fault_of_the_authority_is_refused | no marker, two markers, and an FSD with or without the marker are each refused. |
| TV-037 | TR-01 | `test_canonical_authority.py` AuthorityTests.test_model_file_naming_the_fsd_is_refused | a model file that names the FSD as a source is refused with its key. |
| TV-038 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_skeleton_case_target_clause_and_interface_clause_are_accepted | a skeleton case, a target clause without case and an interface clause from an end's FR. |
| TV-039 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_debugging_clause_without_step_is_accepted | a clause of a debugging function carries no use-case step. |
| TV-040 | TR-11 | `test_clauses_and_cases.py` ClauseTests.test_each_fault_of_a_clause_or_case_is_refused | each way to break the rules of clauses and cases is refused with its message, key and line. |
| TV-041 | TR-13 | `test_code_links.py` CodeLinkTests.test_clause_inherits_its_part_link | a clause without its own code link inherits its part definition's, joined value as one. |
| TV-042 | TR-13 | `test_code_links.py` CodeLinkTests.test_own_link_wins | a clause's own code link wins over its part's. |
| TV-043 | TR-13 | `test_code_links.py` CodeLinkTests.test_each_fault_of_a_code_link_is_refused | a link on an action definition, two inherited candidates and a delivered clause without a link are each refused with key and line. |
| TV-044 | TR-17 | `test_code_structure.py` CodeStructureTest.test_each_module_in_one_part_folder_is_accepted | each module in one part's folder, a module and a page outside it named by the part's CodeDiffers, a shared module, test files and modules declared only under `#[cfg(test)]` or from a test file are accepted. |
| TV-045 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_of_no_part_is_refused | a module no part names outside server/src/shared/ is refused. |
| TV-046 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_of_two_parts_is_refused | a module two part definitions name is refused. |
| TV-047 | TR-17 | `test_code_structure.py` CodeStructureTest.test_module_outside_its_folder_unmarked_is_refused | a part's module, or a module its clause names, outside the part's folder and not named by its CodeDiffers is refused. |
| TV-048 | TR-17 | `test_code_structure.py` CodeStructureTest.test_marker_naming_a_module_inside_is_refused | a CodeDiffers naming a module inside the part's folder is refused. |
| TV-049 | TR-10 | `test_decoder_mode_traces.py` DecoderModeTraceTests.test_each_mode_case_binds_tests_of_that_mode | each mode case binds named tests that select its mode and load a fixture of that mode. |
| TV-050 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e2_doc_character | E2: doc character. |
| TV-051 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e3_dropped_element | E3: dropped element. |
| TV-052 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e4_changed_target | E4: changed target. |
| TV-053 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e5_value_multiplicity_rename | E5: value multiplicity rename. |
| TV-054 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e6_reference_resolving_to_another_element | E6: reference resolving to another element. |
| TV-055 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e7_move_listed_and_equivalent | E7: move listed and equivalent. |
| TV-056 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e8_citations_outside_the_model | E8: citations outside the model. |
| TV-057 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e15d_fixture_reader_exempts_only_its_declared_package | E15 d: a fixture reader's citations of its own package are exempt, of another package not. |
| TV-058 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e15e_other_files_keep_p6 | E15 e: a file outside tools/sysml/tests/, or one declaring no package, keeps P6. |
| TV-059 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e9_cannot_compare | E9: cannot compare. |
| TV-060 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12_each_mutation_is_named | E12: each mutation is named. |
| TV-061 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12o_values_swapped_between_same_named_owners | E12 o: values swapped between same named owners. |
| TV-062 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12s_same_named_owners_pair_by_their_members | E12 s: same named owners pair by their members. |
| TV-063 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12p_member_moved_between_same_named_owners | E12 p: member moved between same named owners. |
| TV-064 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12q_expose_is_compared | E12 q: expose is compared. |
| TV-065 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e12r_comment_outside_any_package | E12 r: comment outside any package. |
| TV-066 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e13_equal_same_named_elements_pair_in_their_package | E13: equal same named elements pair in their package. |
| TV-067 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_e14_changed_element_leaves_its_equal_namesake_paired | E14: changed element leaves its equal namesake paired. |
| TV-068 | TR-21 | `test_equivalence.py` IdentityTests.test_e10a_one_identity_of_each_status | E10 a: one identity of each status. |
| TV-069 | TR-21 | `test_equivalence.py` IdentityTests.test_e15_link_following_a_moved_file | E15: link following a moved file. |
| TV-070 | TR-21 | `test_equivalence.py` IdentityTests.test_e15_guard_link_retargeted_to_another_file | E15: guard link retargeted to another file. |
| TV-071 | TR-21 | `test_equivalence.py` IdentityTests.test_e10b_real_revisions_list_the_union | E10 b: real revisions list the union. |
| TV-072 | TR-21 | `test_equivalence.py` RealHistoryTests.test_e1_divided_requirements_are_equivalent | E1: divided requirements are equivalent. |
| TV-073 | TR-21 | `test_equivalence.py` ReaderRecognitionTests.test_r_real_readers_of_this_repository | R-real: the architecture tests' fixture trees are fixture readers of the packages they declare; server/src/main.rs reads no model of its own. |
| TV-074 | TR-21 | `test_equivalence.py` MarkedCommitTests.test_e11_marked_commits_against_their_first_parent | E11: marked commits against their first parent. |
| TV-075 | TR-05 | `test_file_contents.py` FileContentsTest.test_accepted | Requirements, Shack, Context and UseCases in the forms of M4.1 to M4.3 and M4.9 are accepted. |
| TV-076 | TR-05 | `test_file_contents.py` FileContentsTest.test_negatives | each way to break what a file holds is refused with its one fault line. |
| TV-077 | TR-05 | `test_file_contents.py` FileContentsTest.test_real_model_contents | the real model `docs/sysml` holds in each file what M4 allows. |
| TV-078 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_status_is_computed_from_the_clauses | all implemented gives implemented, mixed gives partial, all target or none gives target. |
| TV-079 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_computed_status_of_each_mix_of_states | each mix of clause states gives the status the rule names. |
| TV-080 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_status_lines_name_each_fr_with_its_counts | status prints each FR's computed status with its clause counts, then the summary. |
| TV-081 | TR-12 | `test_fr_status.py` ComputedStatusTests.test_fr_stating_a_status_is_refused | an FR that states a status or a code link is refused. |
| TV-082 | TR-15 | `test_identity_history.py` IdentityHistoryTest.test_kept_and_new_identities_are_accepted | a kept identity with changed text and a new identity are accepted. |
| TV-083 | TR-15 | `test_identity_history.py` IdentityHistoryTest.test_used_identity_declared_again_is_refused | an identity of an earlier commit that the merge base does not declare is refused when declared again, with other text and with its old text. |
| TV-084 | TR-15 | `test_identity_history.py` NoMainBranchTest.test_history_without_master_is_unavailable | a repository without a `master` branch gives no identity history. |
| TV-085 | TR-04 | `test_layers.py` LayerTest.test_accepted | imports from earlier layers, UseCases naming Context's actors and QsoControl importing a type of TransmitControl are accepted. |
| TV-086 | TR-04 | `test_layers.py` LayerTest.test_control_interfaces | the control interfaces are the packages `WstxStationLink::WireNames` lists. |
| TV-087 | TR-04 | `test_layers.py` LayerTest.test_negatives | each way to break the layers is refused with its one fault line. |
| TV-088 | TR-04 | `test_layers.py` LayerTest.test_real_model_layers | the real model `docs/sysml` keeps its layers. |
| TV-089 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_lists_every_marker_by_key_and_line_with_counts_by_kind | every marker of a WstxModelNotes kind is listed by key and line, then the counts by kind; a binding, a doc and a string are not markers. |
| TV-090 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_lists_a_joined_value_as_one_text | a marker value of literals joined by `+` is listed as one text. |
| TV-091 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_refuses_a_kind_that_is_not_a_wstxmodelnotes_kind | a kind that no WstxModelNotes `metadata def` declares is refused and nothing is listed. |
| TV-092 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_without_a_wstxmodelnotes_file_lists_none | without a file of package WstxModelNotes there is no kind and no marker. |
| TV-093 | TR-20 | `test_markers.py` MarkerListingTests.test_markers_needs_the_authority_marker | `markers` refuses a model without the authority marker and writes nothing. |
| TV-094 | TR-10 | `test_model_tree.py` CatalogTests.test_rebuilt_forms_are_read_into_the_catalog | the FR, the clause with its derivation and the case of the rebuilt forms are read. |
| TV-095 | TR-10 | `test_model_tree.py` CatalogTests.test_duplicate_identity_is_refused | an identity declared twice is refused. |
| TV-096 | TR-10 | `test_model_tree.py` CatalogTests.test_wrong_kind_is_refused | an FR or a clause declared as a verification is refused. |
| TV-097 | TR-10 | `test_model_tree.py` CatalogTests.test_unreadable_form_is_refused | a definition, a typed declaration and a short name with an identity are refused. |
| TV-098 | TR-10 | `test_model_tree.py` CatalogTests.test_derivation_from_a_missing_fr_is_refused | a derivation whose original is no declared FR is refused. |
| TV-099 | TR-10 | `test_model_tree.py` CatalogTests.test_clause_without_derivation_is_refused | a clause that derives from no FR is refused. |
| TV-100 | TR-10 | `test_model_tree.py` CatalogTests.test_required_package_missing_is_refused | each of WstxRequirements, WstxShack and WstxContext declared by no file is refused. |
| TV-101 | TR-10 | `test_model_tree.py` CatalogTests.test_required_package_declared_twice_is_refused | each of WstxRequirements, WstxShack and WstxContext declared by two files is refused. |
| TV-102 | TR-20 | `test_model_tree.py` StatedTests.test_states_and_bindings_are_read_once_each | package names, a manual method and a binding of joined literals are read as one value each. |
| TV-103 | TR-20 | `test_model_tree.py` StatedTests.test_each_fault_of_a_state_or_binding_is_refused | a missing, unknown or repeated state, a repeated binding or method, an unknown method, a missing or outside file, and a delivered case without a test are each refused. |
| TV-104 | TR-20 | `test_paths.py` PathRewriteTests.test_file_renames_rewrite_every_form_and_nothing_else | file renames rewrite @ImplementedIn, @TestedBy, @DetailTests, relative links and whole paths in text, and nothing that is not a whole path; a second run is refused. |
| TV-105 | TR-20 | `test_paths.py` PathRewriteTests.test_folder_rename_rewrites_paths_below_it_only | a folder rename rewrites the paths below the folder, not the folder named alone nor a name that only begins like it. |
| TV-106 | TR-20 | `test_paths.py` PathRewriteTests.test_each_literal_of_a_joined_value_is_rewritten | the paths of every literal of a value joined by `+` are rewritten and checked. |
| TV-107 | TR-20 | `test_paths.py` PathRewriteTests.test_a_joined_value_is_one_path | a joined value is one value: a path that ends at `::` in one literal, or that is split inside by `+`, is read and rewritten as one path. |
| TV-108 | TR-20 | `test_paths.py` PathRewriteTests.test_unchecked_strings_are_rewritten_but_not_checked | a binding the catalog does not check is rewritten but refuses nothing. |
| TV-109 | TR-20 | `test_paths.py` PathRewriteTests.test_refusals_write_nothing | a malformed list, a missing moved file or a path that stays missing is refused with its faults and nothing is written. |
| TV-110 | TR-20 | `test_paths.py` PathRewriteTests.test_real_model_rewrites_a_moved_test_file_and_traces_keep_their_verdict | on the model of HEAD, every path of a moved test file is rewritten, nothing outside the model is written, and `traces` gives the verdict it gave before the move; the repository is not written. |
| TV-111 | TR-12 | `test_real_model_catalog.py` RealModelStatusTests.test_status_on_this_tree_prints_each_fr_of_the_catalog_with_its_computed_status | `status` on this tree prints each FR of the catalog with the status its clauses give it, then the counts. |
| TV-112 | TR-10 | `test_real_model_catalog.py` RealModelPackageTests.test_this_tree_is_accepted | the catalog accepts this tree; Shack.sysml holds the package WstxShack. |
| TV-113 | TR-06 | `test_real_model_structure.py` RealModelStructureTests.test_check_on_this_tree_passes_every_model_rule | `check` on this tree, whose Shack.sysml holds WstxShack, prints the architecture line and then the model rules' line for every model file. |
| TV-114 | TR-09 | `test_reference_target.py` ReferenceTargetTests.test_nested_and_absolute_forms_give_equal_reference_rows | a reference written from the root and one written from its enclosing usage give equal REF rows, rooted at the deployment. |
| TV-115 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_rejects_files_that_stitch_invalid_syntax | files that only stitch into valid syntax are refused, each named. |
| TV-116 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_resolves_complete_graph_and_keeps_file_diagnostics | file order hides neither a valid reference nor its diagnostic. |
| TV-117 | TR-02 | `test_sysml.py` ValidatorTests.test_actual_pilot_accepts_valid_and_rejects_syntax_and_reference | the Pilot accepts a valid model and refuses a syntax error and an unresolved name. |
| TV-118 | TR-02 | `test_sysml.py` ValidatorTests.test_missing_tool_never_reports_semantic_pass | a missing Java or JAR never reports a semantic pass. |
| TV-119 | TR-02 | `test_sysml.py` ValidatorTests.test_empty_or_corrupt_cached_library_is_refused | an empty or corrupt cached library is refused. |
| TV-120 | TR-14 | `test_tags.py` TagTests.test_tags_of_one_and_two_cases_are_accepted | a tag of one case and a tag of two cases joined by a comma are accepted. |
| TV-121 | TR-14 | `test_tags.py` TagTests.test_each_tag_outside_the_form_is_refused | a tag naming an FR, a clause, shorthand, an issue number or added text is refused with its line. |
| TV-122 | TR-14 | `test_tags.py` TagTests.test_tag_naming_an_undeclared_case_is_refused | a tag naming a case the model does not declare is refused with its line. |
| TV-123 | TR-19 | `test_test_level.py` LevelTests.test_levels_of_a_case_are_read | a case states no level, one, several or each location, with or without package names. |
| TV-124 | TR-19 | `test_test_level.py` LevelTests.test_each_fault_of_a_level_is_refused | a cost, location, feature or form outside the rule, and a level on anything but a verification, are each refused naming the case or the element and its key. |
| TV-125 | TR-19 | `test_test_level.py` PilotLevelTests.test_pilot_resolves_the_level_and_refuses_a_misspelt_location | the pinned Pilot resolves TestLevel of WstxModelBindings and refuses a misspelt feature. |
| TV-126 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_code_changes_select_fast_trace_check_without_full_model_suite | a code change selects traces, not the full model suite. |
| TV-127 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_model_file_in_a_subfolder_selects_the_model_suites | a model file in a subfolder selects the model suites. |
| TV-128 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_source_change_or_deletion_invalidates_both_evidence_fingerprints | a source change or deletion invalidates both evidence fingerprints. |
| TV-129 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_every_admitted_source_root_is_fingerprinted_and_selects_fast_traces | every source root is fingerprinted and selects traces. |
| TV-130 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_model_and_model_data_changes_select_the_working_model_suite_not_the_validator | the inputs of the working-model suite select it, not the validator tests; another model file, an internal interface among them, and the oracle file select neither. |
| TV-131 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_tool_changes_select_the_architecture_suites_they_feed | a tool change selects the architecture suites it feeds. |
| TV-132 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_suite_definitions_select_both_architecture_suites | the suite definitions select both architecture suites. |
| TV-133 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_source_change_selects_neither_architecture_suite_and_invalidates_only_the_validator | a source edit selects neither architecture suite and invalidates only the validator's evidence. |
| TV-134 | TR-02 | `test_trace_selection.py` TraceSelectionTests.test_every_sysml_test_file_runs_in_exactly_one_suite | every tool test file runs in exactly one suite. |
| TV-135 | TR-03 | `test_tree.py` TreeTest.test_tree_is_m21 | the tool's tree is M2.1's, 116 files, each with its M7.5 package. |
| TV-136 | TR-03 | `test_tree.py` TreeTest.test_accepted_tree | the M2.1 tree with a data file in `data/` is accepted. |
| TV-137 | TR-03 | `test_tree.py` TreeTest.test_extra_model_file | a model file outside the tree is refused. |
| TV-138 | TR-03 | `test_tree.py` TreeTest.test_listed_file_missing | a file of the tree that is missing is refused. |
| TV-139 | TR-03 | `test_tree.py` TreeTest.test_reference_readme | a file beside the model files outside `data/` (`reference/README.md`) is refused. |
| TV-140 | TR-03 | `test_tree.py` TreeTest.test_required_packages_accepted | the tree, each required package declared once, passes the catalog. |
| TV-141 | TR-03 | `test_tree.py` TreeTest.test_required_package_missing | a required package declared by no file is refused. |
| TV-142 | TR-03 | `test_tree.py` TreeTest.test_required_package_twice | a required package declared by two files is refused. |
| TV-143 | TR-03 | `test_tree.py` TreeTest.test_real_model_tree | the real model `docs/sysml` is the M2.1 tree with only `data/` beside it. |
| TV-144 | TR-16 | `test_values.py` ValuesTest.test_every_way_of_verifying_is_accepted | constants with expressions, `200.`, a rounded Real and `from_millis`; `A::F`, `B::F` and `a::F`, `b::F` in one module; a module `F`; a JavaScript `D.F`; a bound test; a target clause in another file; a marker; a literal, wire name, variable and command field found: all accepted. |
| TV-145 | TR-16 | `test_values.py` ValuesTest.test_unequal_constant_is_refused | a constant unequal to its model value is refused. |
| TV-146 | TR-16 | `test_values.py` ValuesTest.test_value_none_verifies_is_refused | a value that no constant, marker, target clause or bound test verifies is refused. |
| TV-147 | TR-16 | `test_values.py` ValuesTest.test_name_absent_is_refused | a literal, wire name or variable the code does not hold is refused. |
| TV-148 | TR-16 | `test_values.py` ValuesTest.test_marker_where_the_code_matches_is_refused | a CodeDiffers on a value the code holds as the model states is refused. |
| TV-149 | TR-16 | `test_values.py` ValuesTest.test_name_twice_is_refused | a value with two candidates, or whose only module `F` stands where another value of that name has its code, is refused as named twice. |
| TV-150 | TR-16 | `test_values.py` ValuesTest.test_constant_outside_its_binding_is_not_verified | `D::F` or `d::F` outside its code, `D::F` on a unit struct `D` and `F` in a `mod` named after no owner verify nothing. |
| TV-151 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_accepted | the model's forms, a joined path at `; ` and a line of 100 columns are accepted. |
| TV-152 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_negatives | each way to break the writing rules is refused with its one fault line. |
| TV-153 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_quoted_underscore_name_and_join_after_a_binding_separator_pass | an underscore stands in a quoted name ('rst_sent'), and a joined value may meet right after the `::` of a <path>::<test name> binding; the unquoted underscore stays refused. |
| TV-154 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_doc_line_names_no_element | a word that begins a wrapped doc line is no element of the file, so a clause naming only that word names no element of its file. |
| TV-155 | TR-18 | `test_writing_rules.py` WritingRulesTest.test_real_model_writing | the real model `docs/sysml` meets the writing rules. |
| TV-156 | TR-20 | `tools/test/rust/tests/model_values.rs` model_values_reads_every_fixture_value_in_lf_and_crlf | the Rust reader accepts every value of the fixture list, in LF and CRLF. |
| TV-157 | TR-20 | `tools/test/rust/tests/model_values.rs` model_values_refuses_every_fixture_fault_naming_name_and_reason | the Rust reader refuses every fault of the fixture list, naming the name and the reason. |
| TV-158 | TR-20 | `tools/test/node/model-values.test.cjs` model values: every fixture value is read, in LF and CRLF | the JavaScript reader accepts every value of the fixture list. |
| TV-159 | TR-20 | `tools/test/node/model-values.test.cjs` model values: every fixture fault is refused naming the name and the reason | the JavaScript reader refuses every fault of the fixture list. |
| TV-160 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_bound_test_without_the_tag_of_its_case_is_refused | a test a case binds by name without the case's tag is refused with its one line: a `#[test]` without a tag, a `#[test]` tagged with another case only, a `#[tokio::test(flavor = "current_thread")]` without a tag, a JavaScript test bound by its title without a tag and without the case in its title. |
| TV-161 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_test_neither_tagged_nor_a_detail_test_is_refused | a test no case binds, untagged and outside the `@DetailTests` files, is refused with its one line: an untagged `#[test]`, an untagged JavaScript `test(`, an untagged `#[test]` in a `#[cfg(test)]` module of a product source file, an untagged test beside a tagged test bound by name. |
| TV-162 | TR-14 | `test_binding_agreement.py` BindingAgreementTests.test_file_binding_is_refused | a `@TestedBy` naming a whole file is refused with its line: a case binding one file, a file and a test name in one value, a manual case binding a file, a bound file whose tests name no case, a bound file whose tag stands on no test (with that tag's line). |
| TV-163 | TR-22 | `test_comments.py` CommentRuleTest.test_this_repository | `traces` on this repository passes and every exception entry is used. |
| TV-164 | TR-22 | `test_comments.py` CommentRuleTest.test_accepted | one fixture per syntax with present-tense comments, tags, identities, a licence header, a WSJT-X reference, a URL, `#[test]`, a raw string, a regular expression, a CSS colour, callsigns, a timed test name, strings of product code, a third-party file, a harness workflow and one exception entry of each kind gives no fault. |
| TV-165 | TR-22 | `test_comments.py` CommentRuleTest.test_pointer_in_each_comment_syntax | `#N` in a comment of each syntax is refused at its line. |
| TV-166 | TR-22 | `test_comments.py` CommentRuleTest.test_each_pointer_form_in_a_comment | each further pointer form in a comment, in letter-case variants, is refused with its text; `PR #N` and `Issue #N` with the text `#N`. |
| TV-167 | TR-22 | `test_comments.py` CommentRuleTest.test_pointer_in_a_test_or_tool_string | a pointer in each string syntax and at each place of test and tool code, and in a Markdown code span and fenced block, is refused. |
| TV-168 | TR-22 | `test_comments.py` CommentRuleTest.test_pointer_in_a_test_name | a Rust or Python test function whose name joins issue, cr or pr to a number is refused with its name. |
| TV-169 | TR-22 | `test_comments.py` CommentRuleTest.test_date_in_a_comment | a date in a comment of each reader, and a date with its time, is refused. |
| TV-170 | TR-22 | `test_comments.py` CommentRuleTest.test_change_story_in_a_comment_and_in_prose | each word and phrase of the change-story list, in lower, upper and mixed case, at line start and mid-line, is refused in a comment and in Markdown prose. |
| TV-171 | TR-22 | `test_comments.py` CommentRuleTest.test_pointer_after_a_url | a pointer after a URL on the same line is refused; the URL's digits are not. |
| TV-172 | TR-22 | `test_comments.py` CommentRuleTest.test_exception_holds_only_its_file_and_text | a listed date in another file, and a second trigger on the listed line, are refused. |
| TV-173 | TR-22 | `test_comments.py` CommentRuleTest.test_unused_exception | an exception entry that matches nothing is refused at its line. |
| TV-174 | TR-22 | `test_comments.py` CommentRuleTest.test_malformed_exception | an entry without path or text or with a kind outside D1, D2, D3, M, S, I, and a list that is no JSON array, are refused. |
| TV-175 | TR-22 | `test_comments.py` CommentRuleTest.test_source_not_utf8 | a read file that is not UTF-8 is refused by its path; so is a text its reader cannot read. |
| TV-176 | TR-22 | `test_comments.py` CommentRuleTest.test_each_place_read | `#N` in a comment is refused at each place read. |
| TV-177 | TR-23 | `test_code_proof.py` InventoryTests.test_tv177_rust_lines | `#[test]`, both `#[tokio::test(...)]` forms, an ignored test, a `pub async fn` test and two `parses` in two modules give exactly their `rust` lines; a test attribute in a comment, a string or a raw string, a plain fn and a file outside the roots give none. |
| TV-178 | TR-23 | `test_code_proof.py` InventoryTests.test_tv178_node_lines | each Node call form gives its title, a template as written; a two-line template is written with `\n`; comments, strings, regular expressions, `describe`, a file not named `*.test.*` and a file outside the roots give none. |
| TV-179 | TR-23 | `test_code_proof.py` InventoryTests.test_tv179_unreadable_node_title | a `test(` or `it(` whose title is a variable is refused with its line and prints nothing; `x.test(name)` is not refused. |
| TV-180 | TR-23 | `test_code_proof.py` InventoryTests.test_tv180_python_lines | module-level and class-body Python tests give their lines; a nested def, a helper, the model tool's tests, a harness path, a file not named `test_*.py` and an untracked file give none. |
| TV-181 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv181_working_tree_is_not_read; `test_revision_check.py` RevisionCheckTests.test_tv181_check_does_not_read_the_working_tree | after tests are added and removed, a clause's state edited and an untracked test and model file added, `tests`, `traces` and `check` at the revision print what they printed; the status, the stash list and the temporary folder are unchanged. |
| TV-182 | TR-23 | `test_code_proof.py` InventoryTests.test_tv182_move_keeps_the_inventory | moving a Rust, a Node and a Python test to other files keeps the inventory; a rename drops the base line, a removal leaves a base line out, a duplicate adds one. |
| TV-183 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv183_trace_listing | two FRs, three clauses (own link, link through a part definition, none) and three cases (a Rust test bound by name with its tag, two Node tests bound by name and named by tag and by title, manual) print exactly their eight lines; a detail test beside them prints none. |
| TV-184 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv184_move_keeps_the_listing | a linked module, a file of bound tests and a bound test moved, the model's paths updated: the listing is the same. |
| TV-185 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv185_each_change_differs | each change of a trace (state, verified clause, test name, a `Proves:` tag with its name binding, own link file, part link, FR clauses, automated or manual) leaves a base line out. |
| TV-186 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv186_trace_faults_at_a_revision | a TR-13 or TR-14 fault at the revision prints its fault line and no listing while the working tree passes; a clean revision passes while the working tree holds the fault. |
| TV-187 | TR-23 | `test_revision_check.py` RevisionCheckTests.test_tv187_model_check_at_a_revision | `check <rev>` passes on a clean revision while the working tree has a writing-rule fault, fails on the revision with it, and judges an identity declared again against `merge-base <rev> master`. |
| TV-188 | TR-23 | `test_code_proof.py` TraceListingTests.test_tv188_refusals | an unknown revision is refused by `tests`, `check` and `traces`, `tests` without a revision is refused, and a raw string without its end is a source `tests` cannot read. |
| TV-189 | TR-23 | `test_code_proof.py` ThisRepositoryTests.test_tv189_this_repository; `test_revision_check.py` RevisionCheckTests.test_tv189_check_head | on this repository `tests HEAD` lists every test attribute and every `tests/*.test.cjs`, `traces HEAD` every FR, CL and TC; `tests` passes at `HEAD^`; `check HEAD` passes. |
| TV-190 | TR-23 | `test_code_proof.py` ThisRepositoryTests.test_tv190_traces_without_a_revision; `test_real_model_structure.py` RealModelStructureTests.test_check_on_this_tree_passes_every_model_rule (TV-113) | `traces` and `check` without a revision print their summary lines on this repository. |
| TV-191 | TR-02 | `test_sysml.py` ValidatorRunTests.test_limit_is_600_seconds | the Pilot run is started with a time limit of 600 s. |
| TV-192 | TR-02 | `test_sysml.py` ValidatorRunTests.test_command_line_and_pass_unchanged | the Pilot's command line is unchanged, and stdout and the exit code are the process's pass. |
| TV-193 | TR-02 | `test_sysml.py` ValidatorRunTests.test_duration_line_after_a_pass | after a pass, stderr holds exactly one duration line whose value is the run's duration; stdout holds none. |
| TV-194 | TR-02 | `test_sysml.py` ValidatorRunTests.test_duration_line_after_a_validation_error | after a validation error the duration line is printed once, the error line on stdout, and the exit code is 1. |
| TV-195 | TR-02 | `test_sysml.py` ValidatorRunTests.test_duration_line_without_the_completion_marker | a pass without the completion marker prints the duration line, then the missing marker, and exits 2. |
| TV-196 | TR-02 | `test_sysml.py` ValidatorRunTests.test_no_duration_line_when_the_validator_does_not_start | a missing tool and a missing model file print no duration line and exit 2 with their message. |
| TV-197 | TR-02 | `test_sysml.py` ValidatorRunTests.test_timeout_is_no_model_fault | a run past the limit prints the duration line, then `validator timed out after 600 s` as the last line, exits 2 and reports no model fault. |
| TV-198 | TR-02 | `test_sysml.py` ValidatorRunTests.test_timeout_names_the_limit_in_force | a lowered limit is the limit the duration line and the timeout message name. |
| TV-199 | TR-02 | `test_sysml.py` ValidatorRunTests.test_timeout_in_oracle_keeps_the_oracle_file | `oracle` with the Pilot run timing out exits 2 with the timeout message and leaves the oracle file byte for byte. |
| TV-200 | TR-02 | `test_sysml.py` ValidatorRunTests.test_export_run_unchanged | the Pilot export keeps its 900 s limit and its 1 GB heap and prints no duration line. |
| TV-201 | TR-02 | `test_real_model_structure.py` RealModelStructureTests.test_check_on_this_tree_prints_one_validator_duration | `check` on this tree passes and prints exactly one validator duration line with the limit 600 s, on stderr only. |
| TV-202 | TR-02 | `test_sysml.py` ValidatorRunTests.test_traces_prints_no_duration_line | `traces` starts no Pilot and prints no duration line. |
| TV-203 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_l1_javascript_template_prefix | L1: a JavaScript template prefix joined to a literal cites the moved element. |
| TV-204 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_l2_rust_format_prefix | L2: a Rust format prefix joined to a literal, below server/tests/ and in a *_tests.rs module. |
| TV-205 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_l3_python_prefix_and_joined_string | L3: a Python f-string prefix and a prefix ending its string, each joined to a literal. |
| TV-206 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_l4_deeper_prefix_and_relative_name | L4: a deeper prefix and a relative qualified name give the composed line. |
| TV-207 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_l5_declared_not_imported | L5: a lookup name is judged by declaration, a comment by resolution. |
| TV-208 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n1_updated_reader | N1: readers rewritten to the new package cite nothing stale. |
| TV-209 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n2_nothing_declared | N2: a joined name declared on neither side is no citation. |
| TV-210 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n3_not_a_prefix | N3: other text after `::`, a comment and an escaped brace are no prefix. |
| TV-211 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n4_not_test_or_tool_code | N4: the strings of product code hold no lookup prefix. |
| TV-212 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n5_fixture_reader | N5: a lookup of a fixture reader's own package is exempt, of another package not. |
| TV-213 | TR-21 | `test_equivalence.py` SyntheticEquivalenceTests.test_n6_whole_name_not_joined | N6: a literal that is a whole qualified name is not joined to a prefix. |
| TV-214 | TR-21 | `test_equivalence.py` ReaderRecognitionTests.test_r_lookup_readers_of_this_repository | R-lookup: the composed names of the profile tests are lookup citations that resolve on HEAD by declaration, and HEAD against itself has no stale citation. |
| TV-215 | TR-16 | `test_values.py` BoundTestCodeTest.test_rust_test_by_symbol_holding_the_name_in_a_string_is_accepted | a test bound by `path::symbol` whose Rust body holds the qualified name in a string literal verifies the value. |
| TV-216 | TR-16 | `test_values.py` BoundTestCodeTest.test_node_test_named_by_its_title_is_accepted | a Node test bound by its title, which names the case, holding the qualified name in its callback verifies the value. |
| TV-217 | TR-16 | `test_values.py` BoundTestCodeTest.test_rust_test_named_by_proves_with_definition_and_feature_is_accepted | a Rust test bound by name and tagged with `Proves:`, holding the definition's qualified name and the feature's name in its body's code, verifies the value. |
| TV-218 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_in_a_helper_two_calls_away_is_accepted | the qualified name in a function of the file that the bound test calls through a second function verifies the value. |
| TV-219 | TR-16 | `test_values.py` BoundTestCodeTest.test_definition_in_a_node_arrow_helper_and_feature_in_the_test_is_accepted | the definition's qualified name in a Node arrow function the bound test calls and the feature's name in the test's callback verify the value. |
| TV-220 | TR-16 | `test_values.py` BoundTestCodeTest.test_python_test_method_is_accepted | a Python test method bound by `path::Class.test_x`, with or without its `Proves:` tag, holding the qualified name, verifies the value, also after line separators in an earlier string. |
| TV-221 | TR-16 | `test_values.py` BoundTestCodeTest.test_helpers_calling_each_other_end_and_are_accepted | two functions that call each other, one called by the bound test: the check ends and the qualified name in either verifies the value. |
| TV-222 | TR-16 | `test_values.py` BoundTestCodeTest.test_comment_marks_inside_a_string_are_code | the qualified name in a string literal holding `//` or `/*` before it, in Rust, Node and Python, verifies the value. |
| TV-223 | TR-16 | `test_values.py` BoundTestCodeTest.test_raw_and_template_strings_are_code | the qualified name in a Rust raw string and in a Node template literal verifies the value. |
| TV-224 | TR-16 | `test_values.py` BoundTestCodeTest.test_quote_in_a_comment_does_not_hide_a_string | a bound test holding the name in a comment and in a string, after a comment holding a quote mark, verifies the value. |
| TV-225 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_in_another_unbound_test_is_refused | the qualified name in another test of the file, not bound, while the bound test does not hold it, verifies nothing. |
| TV-226 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_in_another_test_bound_to_another_case_is_refused | the qualified name in another test of the file that is bound to another case verifies nothing. |
| TV-227 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_at_the_top_level_is_refused | the qualified name only at the file's top level, as a Rust `const` or `static` and as a Node module `const`, verifies nothing. |
| TV-228 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_in_a_comment_before_the_test_is_refused | the qualified name only in a comment between the `Proves:` tag and the test verifies nothing. |
| TV-229 | TR-16 | `test_values.py` BoundTestCodeTest.test_helper_only_another_test_calls_is_refused | the qualified name in a function that only an unbound test calls verifies nothing. |
| TV-230 | TR-16 | `test_values.py` BoundTestCodeTest.test_two_parts_in_two_tests_are_refused | the definition's qualified name in another test and the feature's name in the bound test verify nothing. |
| TV-231 | TR-16 | `test_values.py` BoundTestCodeTest.test_name_in_an_untagged_test_beside_the_bound_test_is_refused | the qualified name in an untagged test of the file, while the test bound by name (tagged in Rust, named by its title in Node) does not hold it, verifies nothing. |
| TV-232 | TR-16 | `test_values.py` BoundTestCodeTest.test_binding_naming_no_test_of_the_file_is_refused | a name binding that names no test of its file verifies nothing, though another test of the file holds the qualified name. |
| TV-233 | TR-16 | `test_values.py` BoundTestCodeTest.test_unreadable_bound_file_is_not_verified | a bound file that is no UTF-8, or holds a raw string without its end, verifies nothing and raises no exception. |
| TV-234 | TR-16 | `test_values.py` BoundTestCodeTest.test_rust_line_comment_in_the_test_is_refused | the qualified name only in a Rust `//` comment in the bound test verifies nothing. |
| TV-235 | TR-16 | `test_values.py` BoundTestCodeTest.test_rust_doc_comment_in_the_test_is_refused | the qualified name only in a Rust `///` or `//!` comment in the bound test verifies nothing. |
| TV-236 | TR-16 | `test_values.py` BoundTestCodeTest.test_rust_block_comment_in_the_test_is_refused | the qualified name only in a Rust block comment in the bound test, on one line or over lines, or a `/** */` comment, verifies nothing. |
| TV-237 | TR-16 | `test_values.py` BoundTestCodeTest.test_node_line_comment_in_the_test_is_refused | the qualified name only in a Node `//` comment in the test's callback verifies nothing. |
| TV-238 | TR-16 | `test_values.py` BoundTestCodeTest.test_node_block_comment_in_the_test_is_refused | the qualified name only in a Node block comment in the test's callback verifies nothing. |
| TV-239 | TR-16 | `test_values.py` BoundTestCodeTest.test_python_comment_in_the_test_is_refused | the qualified name only in a Python `#` comment in the test method verifies nothing. |
| TV-240 | TR-16 | `test_values.py` BoundTestCodeTest.test_python_docstring_of_the_test_is_refused | the qualified name only in the docstring of the test method verifies nothing. |
| TV-241 | TR-16 | `test_values.py` BoundTestCodeTest.test_comment_in_a_called_helper_is_refused | the qualified name only in a comment of a function the bound test calls, in Rust and in a Node arrow function, verifies nothing. |
| TV-242 | TR-16 | `test_values.py` BoundTestCodeTest.test_second_form_with_one_part_in_a_comment_is_refused | the definition's qualified name in code and the feature's name only in a comment, or the other way round, verify nothing. |
| TV-243 | TR-16 | `test_values.py` BoundTestCodeTest.test_variable_in_the_bound_test_is_still_not_verified | a `WSTX_*` variable whose name stands only in the code of a bound test of a clause reaching it is not verified. |
| TV-245 | TR-24 | `test_product_knows_no_test.py` AcceptedTests.test_tv245_accepted_forms | test-file declarations, forms in comments and strings, product variables, `debug_assert!`, forms in test, tool and fixture files and client globals and members read in another client file print nothing, with and without `--lines`, exit 0. |
| TV-246 | TR-24 | `test_product_knows_no_test.py` TestPredicateTests.test_tv246_test_predicates | each test predicate added to a passing product file lists exactly that file; a test file declared without a test predicate is `test file declared`. |
| TV-247 | TR-24 | `test_product_knows_no_test.py` BuildProfileTests.test_tv247_build_profile_branches | each predicate naming `debug_assertions` is listed alone. |
| TV-248 | TR-24 | `test_product_knows_no_test.py` HiddenItemTests.test_tv248_hidden_items | a `doc` attribute holding `hidden` is listed, on a public or a private item. |
| TV-249 | TR-24 | `test_product_knows_no_test.py` EnvironmentTests.test_tv249_environment_reads | each read of a variable the model does not name, `vars`, `vars_os`, a name that is no literal and the `use` are listed alone; the same file passes once the model names the variable. |
| TV-250 | TR-24 | `test_product_knows_no_test.py` ClientTests.test_tv250_client_modules | CommonJS exports, `process.env`, a global no client file reads and an object member no client file reads through its global are each listed alone. |
| TV-251 | TR-24 | `test_product_knows_no_test.py` OutputTests.test_tv251_paths_and_lines, OutputTests.test_tv251_files_not_read | sorted paths, one `--lines` line per form at its first line, exit 0 with and without findings; an untracked file, a tracked file deleted on disk and a file below `server/examples/` are not listed. |
| TV-252 | TR-24 | `test_product_knows_no_test.py` RefusalTests.test_tv252_refusals | a product file in Latin-1, a raw string without its end and a folder with no git work tree exit 2 with their message and an empty stdout. |
| TV-253 | TR-24 | `test_product_knows_no_test.py` ThisRepositoryTests.test_tv253_this_repository_matches_its_exception_list | `test-hooks` on this repository prints exactly the paths of `tools/sysml/product-knows-no-test.txt`. |
