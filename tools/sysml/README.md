# Model tools

The contract of the model tools (`tools/sysml.py`, `tools/sysml/Validate.java`): the pinned
toolchain, the commands, the limits of validation, the method clauses CL-014 and their
tests TC-DOC. The project's process rules for the model stay in
[Project-Specifics](../../docs/harness/Project-Specifics.md#product-model-maintenance).

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
This trusted development cache is not an independent authorization boundary for
deployment or radio operations.

## Model authoring and validation

Read the declared authority and affected model packages first. Under canonical SysML,
edit and independently review requirements and verification expectations in the model,
then implement and check code using independent expectations. Preserve all stable IDs.
Do not infer functional truth from a regenerated artifact or observed defective code.

```powershell
python tools/sysml.py check
python tools/sysml.py traces
python tools/sysml.py status
python tools/sysml.py oracle
python -m unittest discover -s tools/sysml/tests -q
```

`check` admits only canonical SysML, checks canonical identities/states and trace
bindings, loads the complete model set in the pinned Pilot, then compares the resolved
inventory with the architecture oracle file. `fingerprints` prints one hash per model file by key (its
path relative to `docs/sysml`, with forward slashes), sorted by key, for review;
it never renews model approval. No command writes a model, except `paths`, which rewrites only the code paths of a rename list (CL-014-20).
`traces` requires canonical SysML and checks only authority, catalog and source/model
bindings. It never invokes Java, the mutation suite or application behavior. Source-only
edits select this fast check; model/tool changes retain the full checks as well.

After the architecture comparison, `check` applies the ten structure checks of the
target (CL-014-18) to what is already in target form. What is not yet is listed in the
pending list `tools/sysml/pending-structure.json`:

- `files`: model file keys, each exempt from every rule; `elements`: the qualified name
  of a model element, exempt with its members, mapped to the function whose rewrite
  takes it off. Placeholder item types (rule 3) and outside things without a connection
  (rule 4) are listed under `elements`, also inside `Context.sysml` and `interfaces/`.
- `Context.sysml` and files under `interfaces/internal/` and `interfaces/external/` are
  never listed as files. A new or renamed file is checked unless a reviewed diff lists
  it; a stale entry refuses the whole list. The deployment rules apply once
  `Station.sysml` is off the list; a rewrite takes its entries off, and an empty list
  means the target is reached.
- The names the rules keep (usages `station`, `frontend`, `browsers`, `web`, `ranking`,
  `auto`, `qso`, `transmit`, `operator`; the files `interfaces/internal/StationLink.sysml`,
  `StationCommands.sysml`, `OperatingChain.sysml`, `interfaces/external/Mcp.sysml`,
  `OperatorInteraction.sysml`; the suffix `Control`) and the browser client's allowed
  outside interfaces are fixed in the tool: renaming one is a tool change.
- The Pilot inventory of `check` carries what the rules read: each connection's model
  types (`CONN`), the file and lines of each named element and each definition's model
  features (`ELEM`), the qualified name and file of each part and port (`WHERE`), the
  items of each interface definition (`IITEM`), the members of each part directly in the
  root and of its types (`OUTSIDE`, `MEMBER`) and each requirement's subject (`SUBJECT`).
  Only `check` reads the list; the other commands work without it.
- A check on a pinned model is `check` entered with a commit by a Python-level setting of
  the tool (`CHECK_COMMIT`), set by its caller as the oracle file and the Pilot inventory
  are; there is no command-line option, and without it `check` reads only the working
  tree's list and model and refuses a list that is missing or malformed. Authority,
  catalog, trace bindings and the validation's file keys are read from the working tree;
  the Pilot inventory is what `validate` returns, the commit's as the caller supplies it;
  the oracle file is the tool's `ORACLE`. The pending list is the commit's own
  `tools/sysml/pending-structure.json`, and the key set it is checked against and the model
  files, keys and sources of the structure stage are the commit's `docs/sysml`.
- A commit without the file predates the structure checks: no structure stage runs, and
  `Structure checks not run: <commit> has no pending list` takes the structure line's
  place; the exit code is that of the stages before. A file present there is refused or
  applied with the form rules above, against the commit's key set, its elements resolved
  against the supplied inventory; `{"files": [], "elements": {}}` means the target is
  reached and all ten rules apply, and a zero-byte file is refused as malformed.

`python tools/sysml.py status` prints each FR's status as computed from its clauses
(CL-014-19):

- It needs the authority and the catalog as `traces` does, runs no Java and writes nothing.
- One line per FR in identity order:
  `<FR> <status>: <n> clauses, <i> implemented, <p> partial, <t> target`. Where the FR
  states a different status, `; stated <state>` is added.
- A last line gives `<n> FRs: <count> implemented, <count> partial, <count> target`.
- Exit 0, or 2 with the catalog's message (`SysML check failed: <message>`).

`python tools/sysml.py oracle` writes the architecture oracle file
`tools/sysml/architecture-oracle.json` from the resolved inventory of the working tree
(CL-014-06):

- It needs the canonical authority, runs the Pilot validation of `check` and then the fixed
  rules; on a refusal it exits 2 (`SysML check failed: <message>`) and leaves the file
  unchanged. It runs no catalog check, and the gate never runs it.
- It prints one line per difference to the file it replaces, sorted:
  `added part <path> <type>`, `removed part <path> <type>`, `added port <path> <contract>`,
  `removed port <path> <contract>`, `added connection <owner> <end> <-> <end>`,
  `removed connection <owner> <end> <-> <end>`, and `changed <section> <key>` for any
  other difference (a reference, a binding, a contract's items, a type or a population).
- Then `Architecture oracle written: <counts>`, or `Architecture oracle unchanged` with no
  change line and the file not rewritten.
- The file has the form `check` reads, sections and keys sorted, and keeps the file's
  `about` text, or a fixed sentence when there is no file.

`python tools/sysml.py markers [<Kind> ...]` lists what the model leaves open:

- It needs the canonical authority, as `traces` does. It runs neither the catalog checks
  nor Java, and writes nothing.
- The kinds are the `metadata def` names in the model file whose package is `ModelNotes`.
  A kind added there is listed without a tool change.
- It lists every use outside comments: `@Kind { ... }`, `@Kind;` and
  `metadata <name> : Kind [about <targets>] { ... }`, with or without `ModelNotes::`.
- One line per marker: `<key>:<line>: <Kind>: <text>`, or
  `<key>:<line>: <Kind> about <targets>: <text>`. The line is that of `@` or `metadata`,
  counted from 1. The text is the string values of the body, each with its `+` parts
  joined, several values separated by `; `.
- Lines are sorted by key, then line. The last line is `<n> markers: <count> <Kind>, ...`
  over all kinds in name order; without a `ModelNotes` file it is `0 markers`. Exit code 0.
- Named kinds restrict lines and counts to those kinds. An unknown kind: exit 2,
  `Unknown marker kind: <name>`.

`python tools/sysml.py paths <list>` rewrites the code paths the model names from a rename
list (CL-014-20):

- **Authority.** It needs the canonical authority, as `traces` does. It runs no Java and
  moves no file. It runs after the files have been moved in the working tree.
- **List.** The list is a UTF-8 text file. Each line is `<old> -> <new>`, both
  repository-relative with forward slashes. A line holding a `\` is not of this form.
  Blank lines and lines starting with `#` are ignored. An entry is a file or a folder,
  judged by what exists at `<new>`; a trailing `/` is allowed.
- **What is rewritten.** Every occurrence, in every model file (`*.sysml` below
  `docs/sysml`), of an old path, or of a path below an old folder:
  (a) in the string value of `attribute implementation`, `attribute executable`,
  `@ImplementedIn module`, `@TestedBy test`, `@DetailTests tests` and `@RetiredCase test`,
  with or without package names on the metadata. A `::symbol` suffix is kept.
  (b) in the target of a relative Markdown link, resolved from the model file's folder. The
  new target is written relative to the same folder. A `#fragment` and the link label are
  kept.
  (c) in any other text of the file, including doc, comments and strings, where the path
  stands whole. "Whole" means it is neither preceded nor followed by a path character: a
  letter, a digit, `_`, `-`, `/`, or a `.` followed by one of these. For a folder entry, the
  path must be followed by `/`. `::` may follow.
- **Only paths change.** Bytes outside the rewritten paths stay as they are. Line endings
  and encoding stay as they are. Only changed model files are written.
- **Output on success.** One line per rewrite, sorted by key, line and column:
  `rewrote <key>:<line> <old text> -> <new text>`, where old and new text are as written in
  the file. Then `Path rewrite: <n> rewrites in <m> model files`. Exit 0.
- **Refusals.** The run is refused, with no file written, when any of these holds. The
  faults are judged in three steps, and a step runs only when the steps before it found no
  fault:
  1. The form of the list:
     - `Invalid rename line <n>`: a line that is not of the form above.
     - `Empty rename list`: the list has no entries.
     - `Invalid rename path: <path>`: a path that is absolute, contains `..`, or lies
       under `docs/sysml/`.
     - `Duplicate rename: <old>`
     - `Overlapping renames: <old>, <old>`: one old path lies below another.
     - `Chained rename: <path>`: an old path equal to another entry's new path.
     - `Rename to itself: <old>`
  2. The moved files:
     - `Old path still present: <old>`
     - `New path missing: <new>`
  3. The model:
     - `Path not named by the model: <old>`: neither the old path nor any path below the
       old folder occurs in the model.
     - `Path missing after rename: <key>:<line> <path>`: after the rewrite, a path binding
       that the catalog checks, rewritten or not, fails the file checks of
       `source_binding` (an existing file under `client/`, `server/` or `tests/`), or a
       link target of (b) names no existing file or folder. The path bindings the catalog
       checks are: the binding of an FR, CL or TC declaration (its
       `attribute implementation`, `attribute executable`, `@ImplementedIn module` or
       `@TestedBy test`); a function `@ImplementedIn module` outside every declaration; a
       `@DetailTests tests` value; and a `@RetiredCase test`, which the catalog checks
       through the `@DetailTests` that names it. Other strings of (a) are rewritten but not
       checked. One example is the `attribute executable` of an unnamed verification
       usage, which holds a command line.

  Each fault of the step prints one line, sorted. The lines are followed by
  `Path rewrite refused: <k> faults`, exit 2.
- **Other errors.** A missing or unreadable list, or a missing authority, exits 2 with
  `SysML check failed: <message>`.
- **Not changed and not reported:** symbols (left to `traces`);
  `docs/sysml/reference/*.txt`, which is not a model file; code, tests, `.harness/` and
  `docs/harness/`. Updating those is part of each move issue's work.

`python tools/sysml.py equivalence <base> [<head>]` shows that a model move changed no
meaning (CL-014-17):

- Each revision is a commit-ish; without `<head>` the head is the working tree. Each side
  is extracted with `git archive` into a temporary folder that is removed afterwards and
  exported once per distinct tree by the pinned Pilot (`Validate.java --export`).
- Lines: `missing|added <relative name> <package> <file>`,
  `changed <relative name> <property> <base file> -> <head file>`,
  `missing|added package-level <class> "<text>" <file>`, `missing|added note "<text>" <file>`,
  `stale-by-change <file>:<line> <citation>`, then `moved <relative name> <base package>
  <base file> -> <head package> <head file>`, `pair <base file> -> <head file>: <count>`,
  `unresolved <file>:<line> <citation>`, `exempt <file>:<line> <citation> (pinned|fixture)`
  and a summary.
- A tracked file below `tools/sysml/tests/` is a pinned reader when one of its lines is
  `PINNED = "<7 to 40 hex>"` and that value names a commit of the repository; it is judged
  by this rule only, even when it also declares a package. A citation in it is exempt from
  `stale-by-change` only if it resolves in the pinned commit's model (a name in that
  commit's export, one more export per distinct pinned commit, or a `docs/sysml/` path in
  its tree); one that does not is judged as before. A pinned commit failing the Pilot
  validation exits 2, as any side.
- A file there without a `PINNED` line is a fixture reader of each `<Top>` its text
  declares as `package <Top> {` or `library package <Top> {`: its name citations whose
  first segment is such a `<Top>` are exempt. Every other citation, in any other file,
  keeps the rule above.
- Each exempt citation that would have been `stale-by-change` prints its `exempt` line, no
  difference and no change of the exit code; the summary then ends with
  `; exempt: <file> <count>, ...`, one entry per file in file order with its number of
  exempt lines, and is unchanged without any. This holds in each commit of `--marked`.
- Proven removals (CL-014-22) print `proven` lines and are no difference. The mapping of
  cost wordings they read is `tools/sysml/cost-wordings.json`.
- Exit 0 equivalent, 1 differences, 2 cannot compare (unknown revision, a side failing
  the Pilot validation, or a missing or malformed `tools/sysml/cost-wordings.json`).
- `equivalence --marked` checks each commit of `master..HEAD` with the trailer
  `Model-Move: pure` against its first parent and prints `checked`/`skipped` per commit and
  the number of exports; without a marked commit it prints `no marked commit`, exit 0.

`python tools/sysml.py identities <base> [<head>]` lists the identity diff: one line
`<ID> <status> <base file> -> <head file>` per FR/CL/TC identity of either side (status
unchanged, moved, changed, added, removed, or retired with `test <path>` or, for a
superseded retirement, `superseded by <TC>, <TC>`), FR, CL, TC
in order, then `<n> identities: <count> <status>, ...`. It reads `docs/sysml` of each side
without the Pilot or the catalog checks; exit 0, or 2 when a side cannot be read.

The `sysml-documentation` level-2 suite owns these checks. Application outcomes remain
in their existing functional suites and issue evidence; no duplicate application build
is required merely to inspect model syntax. A selected compiler or behavioural gate
remains binding. Missing tools, files or evidence fail rather than becoming a skip/PASS.

## Meaning and limits of semantic validation

`tools/sysml/Validate.java` calls the pinned Pilot's `SysMLInteractive` API, including
its actual parser, name resolution and Xtext semantic validator. `check` passes to the
Pilot `Requirements.sysml` first, then every other model file once, sorted by key. The
order does not change the result (the adapter resolves all files as one graph).
`validate <files>` with an explicit list is unchanged:

```powershell
python tools/sysml.py validate docs/sysml/Requirements.sysml docs/sysml/Station.sysml
```

Syntax/type/reference errors fail. Missing/invalid tools, model libraries or model files,
or missing completion evidence, fail rather than falling back to a lightweight checker.
Self-tests feed legal, malformed and unresolved-reference fixtures to the actual Pilot.
They also exercise authority ambiguity and refusal, missing identities/files, broken traces, archive independence and unavailable tool/library cases.

The `check` command also requests a resolved semantic inventory from the same Pilot
process. The Java adapter traverses actual usage/type/connector objects, inherited
features, conjugated directed items, reference subsetting, binding-versus-ordinary connector kinds
and backend variants.

- **The inventory is complete.** The *deployment* is the one package-level part usage of
  the model files, whatever its name and package, and everything reachable from it; with
  none or several, the inventory lists only the package-level part usages. The inventory holds every part, reference, port with
  its items, connection and binding of the deployment, whatever package declares the
  element or its definition, also a feature a definition inherits from a definition of
  another package. Left out are only the elements of the pinned model library's files; an
  element of a model file is never left out, also in a `library package`. Definitions and
  item types are named by qualified name; paths are dot paths from the deployment's name.
- **The oracle is data.** `check` compares the inventory with the file
  `tools/sysml/architecture-oracle.json`, which only `oracle` writes. It states `root` (the qualified name of the one
  deployment); `parts` (per path below the root: qualified type, population `"1..1"` or
  `"0..*"`, and `variation: true` when it is one); `references` (per path: type,
  population, target path); `contracts` (per port definition: its items as name,
  direction `in`/`out` and qualified item type, and the bindings and connections it
  declares itself); `ports` (per path: the contract, a leading `~` for the conjugate);
  `connections` and `bindings` (per owner path: the pairs of ends as the inventory gives
  them); and `about`, one free text. No other key exists; an empty section means none of
  this kind. A slice that adds a port, part, reference or connection names it there.
- **Nothing unlisted passes, nothing listed may be missing.** Inventory and file agree
  exactly: part by path, type, population and variation (the top-level parts are parts
  like any other); reference by path, type, population and target; port by path,
  definition and conjugation, with its complete item set, each item's direction (reversed
  on a conjugate) and type; connection and binding by owner, kind and both ends. The
  edges a contract declares count at every port typed by it.
- **Refusals and their order.** `check` exits 2 with
  `SysML check failed: Architecture integrity: <message>`, naming the first difference in
  this order: the oracle file; an empty inventory; the fixed rules; each listed
  reference (`invalid endpoint/resource/authority association`); missing, then
  unexpected connections and bindings; the set of ports, then each port's items
  (`semantic exchange signature mismatch`, `wrong exchange direction`, `wrong semantic
  item type`); then `wrong port definition`, `missing part`, `unexpected part`,
  `wrong part type or population`, `unexpected reference` and, last,
  `port joined to no function <path>`.
- **Fixed rules stay in the tool** and hold whatever the file lists: exactly one part
  usage at package level in all model files (the root); no view in any model file adds a
  part or connection; exactly one part typed by `RadioAuthority` (the authority); exactly
  one part typed by `StationProcess` (the station population), variable (`0..*`); directly
  in it exactly one `audioAdapter : AudioDeviceAdapter`, one `catAdapter : RustRadioDriver`
  and one `profile : PersistedProfile`, found by usage name, each `1..1` and no variation,
  and no other part of the two adapter types; and a non-empty inventory. A type is matched
  by the simple name of the part's definition or of a definition it specializes, directly
  or through other definitions, in any package; no rule names a root, a path or a package.
  `check` applies these rules and `oracle` applies them before it writes. Then `check`
  alone: every port of the deployment is an end of at least one connection of the
  deployment; an end reached through a reference resolves to the referenced part's port
  (`authority.requests` to `context.station.backend.radioAuthority.requests`), and a
  binding, also one a contract declares, joins no port. Otherwise the first unjoined port
  in sorted path order is named. The rule cannot tell an outside thing from a function:
  an outside part put back with its connection is refused only while the oracle file does
  not list it. A change to a fixed rule is a tool change with its own issue.
- **The oracle file fails closed.** A missing, unreadable or non-JSON file is refused
  with `Architecture oracle unavailable: <path>`. A missing section, an unknown key, a
  key stated twice, an entry of another shape, a direction other than `in` or `out`, a
  malformed population, a port naming a contract the file lacks, or a pair listed twice
  or as both connection and binding is refused with
  `Invalid architecture oracle: <what>: <key>`. Neither prints a passed line.
- **Generated, independent in the issue.** Only `python tools/sysml.py oracle` writes the
  file, from the resolved inventory of the working tree, after the Pilot validation and
  the fixed rules pass; otherwise it exits 2 and leaves the file unchanged. The gate never
  runs `oracle`; `check` compares inventory and file exactly as before. The independence
  is in the issue: every issue that changes the architecture lists the parts and
  connections it adds or removes, written by the definer before the generator is run and
  never from its output; comparing `oracle`'s change lines with that list is a numbered
  acceptance item and a review step. `check` and `oracle` read the file; `traces`,
  `markers`, `fingerprints`, `status`, `validate` and `setup` work without it.

Identity obligations require binding connectors; ordinary connections between the same
endpoints do not satisfy them. The oracle is deliberately specific to this target
architecture, not a general SysML connectivity theorem; a regenerated file approves
nothing until its change lines are compared with the issue's list of additions and
removals.

TC-DOC-005 fixtures remove connections, bypass authority, split authority, duplicate a
backend, redirect association/context identity, change waveform/provider directions or semantic item kinds, weaken identity bindings, add detached
stations, add runtime structure to a view and put back removed outside things. They judge
the pinned model of commit `1df1ba3a5` against the oracle file of the same commit, both
extracted with `git archive`, so a rewrite of the working tree's model changes no such
test. They run through the real Pilot before
the integrity assertions. Legal but disconnected/miswired models must fail the explicit
integrity oracle even when ordinary semantic validation succeeds. The fixture list and
expected diagnostics remain executable companions to the HOW test definitions below.

Successful parsing/resolution is not execution of modeled verification cases, proof
that Rust satisfies the model, or proof of prose behavior. Actual application outcomes
belong to test output and the implementing CR. Code/model correspondence and connector coverage require independent review against the canonical contract; a disconnected but well-typed model can pass semantic validation.

## Method clauses (Markdown only)

These are HOW bindings, not product requirements and not SysML model elements.

| ID | Subject | Rule | Verification |
|---|---|---|---|
| CL-014-01 | Authority | One declared functional authority applies. Canonical SysML and an active FSD cannot coexist; archived Markdown is never an ongoing input after cutover. | TC-DOC-001; TC-DOC-007 |
| CL-014-02 | Functional scope | Model product requirements, behaviour, architecture/interfaces and verification. Keep harness, skills, process and build documentation Markdown-only. | TC-DOC-001; manual scope review |
| CL-014-03 | Architecture | The architecture model is functional: a part of the deployment is a function of the software, a port is the interface one function offers to another, and every connection joins two functions. An outside thing (hardware, a person, another program, a file or a service) is no function. It is an entry of the context list `OutsideThing` with exactly one owning function in the deployment and the `@FollowsSource` reference of its protocol or format. Where `Context.sysml` exists, it is also a black-box part there (CL-014-18 rule 4), each of its ports joined to a port of its owning function, and its owner is the function its ports join. An outside thing without an interface yet is a black box without a connection, on the pending list under its owner. What an outside thing is made to do is a promise of its owning function, observed at the peer system. Preserve population, identity, ownership and directed semantic exchanges. Views select existing model facts and cannot supply missing architecture. | TC-DOC-005 |
| CL-014-04 | Real validation | Required checks use the pinned full validator/library. Missing tools/files, syntax/name/semantic errors or missing completion evidence fail with no lint fallback. | TC-DOC-003; TC-DOC-004 |
| CL-014-05 | Stable identities and traces | Preserve stable FR/CL/TC identities and declared states; a verification case may instead retire under CL-014-15. A clause is owned by its FR by derivation or by a `dependency` from the clause to the FR. It is verified by the cases whose `verify` names it, in an objective or directly; no `dependency` from a clause to a case is needed. Where one is written, its case verifies the clause; one whose case does not is refused (`Nonreciprocal canonical verification links: <TC>`). A clause derived from its FR by a derivation connection of the pinned model library (`#original` the FR, `#derive` the clause) is owned by that FR and verified by the cases whose objective verifies it; no reciprocal `dependency` is written for it. Clause and case keep their declared states; an FR's status is computed (CL-014-19). Delivered declarations name existing implementation/executable or explicit manual bindings; no declared status means a test passed. | TC-DOC-001; TC-DOC-002; TC-DOC-007; TC-DOC-019 |
| CL-014-06 | Structural integrity | Validate the resolved architecture against the independent end-to-end oracle, including identity bindings, exclusive backend and shared authority. A legal but miswired model fails the oracle. The oracle is the data file `tools/sysml/architecture-oracle.json`. Only `python tools/sysml.py oracle` writes it, from the resolved inventory of the working tree, after the Pilot validation and the fixed rules pass; otherwise it exits 2 and leaves the file unchanged. The gate never runs `oracle`; `check` compares inventory and file exactly as before. The independence is in the issue: every issue that changes the architecture lists the parts and connections it adds or removes, written by the definer before the generator is run and never from its output; comparing `oracle`'s change lines with that list is a numbered acceptance item and a review step. `oracle` prints one line per difference to the file it replaces, sorted (`added`/`removed part <path> <type>`, `added`/`removed port <path> <contract>`, `added`/`removed connection <owner> <end> <-> <end>`, and `changed <section> <key>` for any other difference), then `Architecture oracle written: <counts>`, or `Architecture oracle unchanged` with no change line and the file not rewritten; it writes the file's form with sorted keys and keeps its `about` text, or writes a fixed sentence when there is no file. The file lists every part, reference, port with its items, connection and binding of the deployment, whatever package declares them; an unlisted or a missing one is refused, and so is a missing or invalid file. The inventory starts at the one package-level part usage and names every path from it. The fixed rules find the station population as the parts typed by `StationProcess`, the authority as the parts typed by `RadioAuthority`, and `profile : PersistedProfile`, `audioAdapter : AudioDeviceAdapter` and `catAdapter : RustRadioDriver` by usage name directly in the station process; a type is matched by the simple name of its definition or of a definition it specializes, in any package. The rules on the one deployment, views, the one authority, the adapters, the profile and the station population are fixed in the tool and hold in every model file. A port joined to no function is refused. | TC-DOC-005 |
| CL-014-07 | Implementation readiness | Before code, the issue's ready check passes: the selected model slice settles observable behaviour, interfaces/data, ownership, state/timing/error choices and independent oracles. Explicit implementation freedoms do not authorize unresolved functional decisions. | TC-DOC-006 |
| CL-014-08 | Functional sequence and closure | Use the declared canonical artifact first, pass the ready check, implement against it and verify with independent expected results. Reconcile delivered behaviour and durable cases before closing the issue. SysML-only authority requires no maintained/generated Markdown specification. | TC-DOC-006; TC-DOC-007; independent closure review |
| CL-014-09 | Modeling feedback | Correct differences against the declared authority; do not bless code defects by rewriting requirements. Record causes/review on the issue and improve demonstrated reusable/project-specific gaps, with a focused regression where useful. | TC-DOC-006; independent review |
| CL-014-10 | Model file tree | The model is every `*.sysml` file at any depth below `docs/sysml`, named by its path relative to that folder. The required packages are `WstxRequirements` and `WstxArchitecture`, and `WstxContext` whenever the model file `Context.sysml` exists; each is the package of exactly one model file, whatever the file's name and folder, and the entry file stays at the root. `Context.sysml` declares the package `WstxContext` and no identity, and no other model file names `WstxContext` in code. Any other package is accepted without a reference; a lost model file stays noticed through the required identities, name resolution and the `Proves:` tags. Identities and links hold across folders and packages. | TC-DOC-007; TC-DOC-008 |
| CL-014-11 | Stated once | Status and bindings are read as attributes or as `ModelBindings` metadata, once per declaration. A delivered clause without a binding takes the function binding of its model file; a case takes automation from the verification definition of its file that it is typed by. A declaration with an identity in a form the catalog does not read is refused. | TC-DOC-009 |
| CL-014-12 | Marker listing | `markers` lists every `ModelNotes` marker of the model by file key and line, with counts by kind; it checks nothing and writes nothing. | TC-DOC-010 |
| CL-014-13 | Tag and binding agree | Every test that names a verification case, by an attached `Proves:` tag or a JavaScript test name, is in that case's binding, as its file or as `path::symbol`. A `path::symbol` binding of a manual case names an existing test. The gate's model bindings report a revision and do not apply this rule. | TC-DOC-011 |
| CL-014-15 | Retired case | A verification case retires by `@RetiredCase { identity = "<TC>"; test = "<path>"; }` directly in the body whose `@DetailTests` names that path as written; an FR, a clause, another spelling, a path that body's detail tests do not name, an identity retired twice and a retired identity declared again are refused. A case whose checks went to other contract cases retires as superseded by `@RetiredCase { identity = "<TC>"; supersededBy = "<TC>; <TC>"; }` in any model file, at package level or in a definition body, with no `@DetailTests`; each named case is declared and not retired, and both features, neither, a value that is not one literal, a malformed or repeated identity or the case itself are refused. A retired identity counts as present for the stable baseline, is not a catalog entry and is never declared again; tags, test names and clause dependencies naming it are refused as for any undeclared identity. `retired` checks the catalog and lists the retirements; the gate's model bindings list neither the retired identity nor its test file. | TC-DOC-013 |
| CL-014-16 | Model values in tests | A contract test reads a value the model holds as data from the `.sysml` text by its qualified name, through the one reader of its language. It never writes the value again or parses the model with its own patterns. A value with a unit ends its name in a member of `WstxUnits::UnitSuffix`. A missing, duplicate or unreadable value, or a broken unit rule, fails the test; it never skips. | TC-DOC-014 |
| CL-014-17 | Equivalence and identity diff | `equivalence <base> [<head>]` compares two revisions (head omitted: the working tree), each extracted whole with `git archive` into a temporary folder that is removed; nothing in the repository is written. Exit 0 equivalent, 1 differences listed, 2 cannot compare (unknown revision, or a side failing the Pilot validation). Every named element of the model files has exactly one counterpart, matched by qualified name without its top-level package; several of one name on a side pair by equal content, their named members included, the rest is missing or added. Among equal candidates a member of a paired owner pairs first under its owner's counterpart, then a top-level element or a member of an unpaired owner in its own package, then any; file order decides only among candidates neither tells apart. A member keeps its owner: a pair whose owners are not paired with each other is a difference. The counterpart has the same kind, declared and short name, doc and comment texts, literal values, multiplicities and directions, the same relationships (typing, specialization, subsetting, redefinition, satisfy, verify, subject, dependency, connection ends, metadata with its values) to counterparts, and the same unnamed owned elements in declaration order. A difference names the element, the property or relationship kind and both files. A difference that CL-014-22 proves is not a difference. Free to differ: the file and top-level package of an element, the set of top-level packages, imports and aliases (an `expose` is compared), and how a reference is spelled. Package-level unnamed elements, package docs and the members outside any package (a file's header comment) compare as a multiset by content, and line notes as a multiset of texts over the model. A qualified name in text is equal when it resolves on each side, by the Pilot's resolution with imports, aliases and public re-exports, to counterparts, and a relative Markdown link when it resolves to the same file or to the model file of the same package. Each element whose file or package changed is listed with both, and a count per file pair. At the head, model citations in the tracked files under `server/`, `client/`, `tests/`, `tools/`, `fixtures/`, `docs/harness/`, `.harness/` and `README.md` (qualified names starting with a top-level package of either side, `docs/sysml/` paths) that resolved on the base and not on the head are differences (stale-by-change); those resolving on neither side are listed. Two kinds of tracked file below `tools/sysml/tests/` read another model. A file with a line `PINNED = "<7 to 40 hex>"` naming a commit of the repository is a pinned reader and is judged by this rule only, even when it also declares a package: a citation in it is exempt only if it resolves in the pinned commit's model (a name in that commit's export, one more Pilot export per distinct pinned commit, or a `docs/sysml/` path in its tree), and one that does not is judged as before; a pinned commit failing the Pilot validation exits 2. A file there without a `PINNED` line is a fixture reader of each `<Top>` it declares as `package <Top> {` or `library package <Top> {`, and its name citations whose first segment is such a `<Top>` are exempt. Every other citation, in any other file, keeps the stale-by-change rule. An exempt citation that would have been stale-by-change prints `exempt <file>:<line> <citation> (pinned\|fixture)`, is no difference and leaves the exit code unchanged; the summary then ends with `; exempt: <file> <count>, ...`, one entry per file in file order with its number of exempt lines, and is unchanged without any, also in each commit of `--marked`. `identities <base> [<head>]` reads the FR/CL/TC declarations of `docs/sysml` of each side without validating the tree and the Pilot, and prints one line per identity with its status (unchanged, moved, changed, added, retired with its test file or the cases superseding it, removed) and both files, then a count per status. Text compares from the keyword to the closing brace with LF line endings, relative Markdown links resolved as `equivalence` resolves them, a leading top-level package dropped from each qualified name and the dependency lines of its `from` identity. `equivalence --marked` checks each commit of `master..HEAD` with the trailer `Model-Move: pure` against its first parent, with one Pilot export per distinct tree, prints the number of exports, and reports "no marked commit" with exit 0 when there is none. | TC-DOC-015; TC-DOC-020 |
| CL-014-18 | Target structure checks | `check` applies the rules below to every model file and element not on the pending list `tools/sysml/pending-structure.json`, and the deployment rules (3 for connections, 4, 5, 6 and 7) to the whole deployment once `Station.sysml` is not on the list; a listed file is exempt from every rule, a listed element with its members. Names: the root is the one package-level part usage; the station is `station` directly in the root; the frontend `frontend` directly in the station; the browser client `browsers` directly in the frontend; the station process the parts typed by `StationProcess`, and in it the station service `station`, `web`, `ranking`, `auto`, `qso` and `transmit`, each directly in it; the operator `operator` directly in the root. A port is typed by an internal interface when its port definition is declared in a file under `interfaces/internal/`, conjugated or not; typed by `StationLink` when declared in `interfaces/internal/StationLink.sysml`, by `OperatorInteraction` when declared in `interfaces/external/OperatorInteraction.sysml`. The control family is every `interface def` whose name ends in `Control`, its files `interfaces/internal/*Control.sysml`. The commanding end of a connection is its first end. A role part or file that is missing while its rule applies is refused, naming it. Rules: (1) a file of a part folder (each folder directly under `backend/` other than `operating/`, each folder directly under `backend/operating/`, and `frontend/`) names, by `import` or by qualified name in code (not in comments or `doc`), only packages of its own part folder, of files under `interfaces/` and `shared/`, of `Requirements.sysml` and of the pinned library; a file under `interfaces/` only packages of its own file, `shared/`, `Requirements.sysml`, the library and other files under `interfaces/`, where a file under `interfaces/external/` names no file under `interfaces/internal/` (except `interfaces/external/Mcp.sysml` naming control interface files), and a control interface file never names `interfaces/internal/StationLink.sysml`, `interfaces/internal/StationCommands.sysml`, `interfaces/external/Mcp.sysml` or `interfaces/internal/OperatingChain.sysml`. (2) `Station.sysml` holds, at package level and inside its part definitions, only its package declaration, part definitions, part usages and reference parts, connections and binding connectors, `satisfy` of an FR by a part, imports, `doc` and comments. (3) Every connection of the deployment (binding connectors excepted) is typed by an `interface def` declared in a file under `interfaces/`; an interface definition under `interfaces/` has at least one item (items in one direction only pass); every item is typed by a definition that has a feature of its own or inherited from a model definition, or by a placeholder on the pending list. (4) An outside part is a part usage directly in the root other than `station`: its type and its own body have ports and attributes only (with `doc` and metadata); no requirement's subject is an outside part or its type; it has at least one port joined to a port of a function, unless it is on the pending list. (5) An interface of the control family has the station service at its commanding end. (6) The browser client has exactly one port typed by an internal interface, typed by `StationLink` and connected to `web` of a station process; its only other port is typed by an outside interface the tool lists (today `interfaces/external/OperatorInteraction.sysml`, connected to `operator`); no connection with an end in `frontend` ends anywhere else. (7) Among `ranking`, `auto`, `qso` and `transmit` only `ranking` to `auto`, `auto` to `qso` and `qso` to `transmit` are connected, first end to second end. (8) An FR states no status (`coverage`, `@Status`), no code or test binding (`implementation`, `@ImplementedIn`, `@TestedBy`, `@DetailTests`) and no issue reference (`#` followed by digits) in its text, its `doc` included. (9) No `dependency` is declared. (10) Every requirement, definition or usage, declares a `subject`. The pending list is JSON: `files`, a list of model file keys, and `elements`, a map from the qualified name of a model element to its owning function, whose rewrite takes the entry off. It is refused whole, `check` exiting 2 with no passed line, when it is missing, unreadable or not JSON, lists a key or a name twice, a key that is no model file or a name that resolves to no element, an element with an empty owner, or lists in `files` `Context.sysml` or a file under `interfaces/internal/` or `interfaces/external/`. `check` prints every structure fault, one line each, `Structure rule <n>: <what>: <key>:<line>` for a file rule or `Structure rule <n>: <what>: <path>` for a deployment rule, sorted by rule, key and line, then exits 2 with `SysML check failed: <k> structure faults`; on a pass it prints `Structure checks passed: <a> files in target form, <b> files and <c> elements pending; deployment rules on\|off`. Only `check` reads the list. A check on a pinned model is `check` entered with a commit by the tool's Python-level setting `CHECK_COMMIT`, set by its caller as the oracle file and the Pilot inventory are; there is no command-line option, and without it `check` reads only the working tree's list and model and refuses the list as above. Authority, catalog, trace bindings and the validation's file keys come from the working tree, the Pilot inventory from `validate` as the caller supplies it, and the oracle file from `ORACLE`; the pending list is the commit's own `tools/sysml/pending-structure.json`, and the key set it is checked against and the model files, keys and sources of the structure stage are the commit's `docs/sysml`. A commit without the file predates the structure checks: it is not refused, no structure stage runs, `Structure checks not run: <commit> has no pending list` takes the structure line's place and the exit code is that of the stages before. A file present there is refused or applied with the form rules above, against the commit's key set and the supplied inventory; `{"files": [], "elements": {}}` means the target is reached and all ten rules apply, the deployment rules among them, and a zero-byte file is refused as malformed. | TC-DOC-016 |
| CL-014-19 | Computed FR status | An FR's status is computed from the clauses derived from it, by derivation or by the clause's `dependency` to the FR: `implemented` when all its clauses are implemented, `target` when all are target or it has none, `partial` in every other case, so two partial clauses give a partial FR. The catalog accepts an FR without a stated status and without a binding; the FR's catalog entry carries the computed status, and an FR that states a status has it checked as any declaration's. `status` prints each FR's computed status with its clause counts and the stated status where it differs; it runs no Java and writes nothing. | TC-DOC-017 |
| CL-014-20 | Path rewrite | `python tools/sysml.py paths <list>` rewrites the code paths the model names from a rename list. Authority: it needs the canonical authority, as `traces` does; it runs no Java and moves no file; it runs after the files have been moved in the working tree. List: a UTF-8 text file; each line is `<old> -> <new>`, both repository-relative with forward slashes; a line holding a `\` is not of this form; blank lines and lines starting with `#` are ignored; an entry is a file or a folder, judged by what exists at `<new>`; a trailing `/` is allowed. What is rewritten: every occurrence, in every model file (`*.sysml` below `docs/sysml`), of an old path, or of a path below an old folder, (a) in the string value of `attribute implementation`, `attribute executable`, `@ImplementedIn module`, `@TestedBy test`, `@DetailTests tests` and `@RetiredCase test`, with or without package names on the metadata, a `::symbol` suffix kept; (b) in the target of a relative Markdown link, resolved from the model file's folder, the new target written relative to the same folder, a `#fragment` and the link label kept; (c) in any other text of the file, including doc, comments and strings, where the path stands whole: neither preceded nor followed by a path character (a letter, a digit, `_`, `-`, `/`, or a `.` followed by one of these); for a folder entry the path must be followed by `/`; `::` may follow. Only paths change: bytes outside the rewritten paths, line endings and encoding stay as they are; only changed model files are written. Output on success: one line per rewrite, sorted by key, line and column, `rewrote <key>:<line> <old text> -> <new text>` with old and new text as written in the file, then `Path rewrite: <n> rewrites in <m> model files`, exit 0. Refusals: the run is refused, with no file written, when any of these holds; the faults are judged in three steps, and a step runs only when the steps before it found no fault. (1) The form of the list: `Invalid rename line <n>` (a line not of the form above), `Empty rename list` (no entries), `Invalid rename path: <path>` (absolute, containing `..`, or under `docs/sysml/`), `Duplicate rename: <old>`, `Overlapping renames: <old>, <old>` (one old path below another), `Chained rename: <path>` (an old path equal to another entry's new path), `Rename to itself: <old>`. (2) The moved files: `Old path still present: <old>`, `New path missing: <new>`. (3) The model: `Path not named by the model: <old>` (neither the old path nor any path below the old folder occurs in the model); `Path missing after rename: <key>:<line> <path>` (after the rewrite, a path binding that the catalog checks, rewritten or not, fails the file checks of `source_binding`, an existing file under `client/`, `server/` or `tests/`, or a link target of (b) names no existing file or folder). The path bindings the catalog checks are the binding of an FR, CL or TC declaration (its `attribute implementation`, `attribute executable`, `@ImplementedIn module` or `@TestedBy test`), a function `@ImplementedIn module` outside every declaration, a `@DetailTests tests` value, and a `@RetiredCase test`, which the catalog checks through the `@DetailTests` that names it; other strings of (a) are rewritten but not checked, such as the `attribute executable` of an unnamed verification usage, which holds a command line. Each fault of the step prints one line, sorted, followed by `Path rewrite refused: <k> faults`, exit 2. Other errors: a missing or unreadable list, or a missing authority, exits 2 with `SysML check failed: <message>`. Not changed and not reported: symbols (left to `traces`), `docs/sysml/reference/*.txt`, and code, tests, `.harness/` and `docs/harness/`. | TC-DOC-018 |
| CL-014-21 | Test level and location | A verification case states the cost level of its test and where it runs as `@TestLevel { cost = <n>; location = TestLocation::<place>; }`, with or without package names. `TestLevel` and the enumeration `TestLocation` are in `ModelBindings`. `cost` is an integer literal 1 to 5: the cost levels of the testing standard. `location` is one of `developmentPc` (isolated on a development PC, either machine), `station` (HB9BLA with the IC-7300), `simulator` (the SIM-IC7300 profile with the FT-8 Band Simulator) and `flexRadio` (a FlexRadio reached over the network). A case may state several, each (cost, location) pair once, or none. A case that states none and is typed by a verification definition of its file takes that definition's levels, as it takes automation. Consent is not stated: a level-4 or level-5 test needs the operator's consent or a standing consent policy; the simulator rule is such a policy. Refused with `Invalid test level: <identity>`, or `Invalid test level: <name>: <key>` on an element without identity: a cost outside 1 to 5, or one that is not an integer literal; a location not in the list; a missing, repeated or other feature; the same pair twice; the `metadata` keyword form; `@TestLevel` on an FR, a clause or any other element than a verification case, definition or usage. The catalog entry of a case carries `levels`: its (cost, location) pairs, sorted. | TC-DOC-019 |
| CL-014-22 | Proven removals | `equivalence` accepts five removals. For each, the tool proves that the fact is still stated formally on the head. There is no exemption list; a removal that fails its proof is a difference as before. Text is compared with runs of whitespace taken as one space, trimmed. The head text of an element must equal its base text with only proven spans deleted; nothing may be inserted. A deleted span may take the one separator that directly follows it: `; `, `, `, `: `, `. `, ` — ` or ` - `. (1) **case-number**: in the doc of case `<TC>`, the identity exactly as its name, optionally preceded by a Markdown heading marker (`#` to `######` and a space). (2) **clause-list**: in the doc of a verification case, definition or usage, an optional `Proves ` followed by identities joined by `, `, ` and `, `; `, or shorthand as `references` reads it; the expanded set must equal the set of the element's own `verify` targets, and a list naming a TC is not a clause list. (3) **cost**: in the doc of a verification case, definition or usage, a wording of `tools/sysml/cost-wordings.json`; matching is case-sensitive and the wording must stand whole, with no letter or digit directly before or after it. A line wording counts only at the start of a doc line and may be followed by `; ` and a place phrase, which goes with it and must agree with its location; a bold wording counts anywhere (at a line start in the doc text of the Pilot, which drops the first `*` of a comment line); an element wording counts only in its own element. Where several wordings or phrases match at one place, the longest is taken. On the head, the element's levels must equal its base levels plus the pairs of its removed wordings. (4) **dependency**: a base `dependency <name> from <CL> to <TC>` that is missing on the head, where the head's counterpart of `<TC>` verifies the counterpart of `<CL>`; a dependency to an FR is not covered. (5) **status**: in an FR, CL or TC declaration, `attribute coverage`, `automation`, `method`, `implementation` or `executable` replaced by its `@Status`, `@Automation`, `@ImplementedIn` or `@TestedBy` form; the state, method and bindings that the catalog reads must be equal on both sides, and the declaration's other facts unchanged. Each proven change prints `proven <rule> <relative name> <base file> -> <head file>`, one line per rule and element (for a dependency the head file is that of the case's counterpart), after the differences; the summary then ends `; proven: <count>`, and is unchanged without any. The exit code is that of the unproven differences, in each commit of `--marked` too. When an element has any unproven change of its doc, the element is reported as today and no `proven` line is printed for its docs; its status is proven apart, and so is an unproven status change apart from its docs. A change of any other fact of the element proves nothing for it. A missing or malformed `cost-wordings.json` exits 2 (cannot compare), naming the file. | TC-DOC-020 |

## Documentation-tool test definitions

These checks prove HOW clauses, not radio functionality. Level 2 means isolated
verification using local fixtures. TC-DOC-014 runs in the Rust and Node suites on the test
machine without the Pilot; the other rows run on the documentation development PC with the
pinned portable Pilot. No radio, live service, Jupyter server or global Java is needed.

| ID | Clauses | Independent actions and expected observations | Method and location |
|---|---|---|---|
| TC-DOC-001 | CL-014-01, CL-014-02, CL-014-05 | Inspect stable IDs, declared states, scope and FR/CL/TC relationships. Tooling reads the canonical model directly, checks bindings and never rewrites it, except `paths` under CL-014-20, or requires a Markdown view. | Automated local model/tool fixtures; independent scope/meaning review. |
| TC-DOC-002 | CL-014-05 | Mutate declared state/identity/link or remove a required artifact and expect a named nonzero refusal. A clause derived from its FR and verified by a case, with no dependency, is accepted, also with package names on the metadata and the ends, and the pinned Pilot resolves that form; a clause with both dependencies and no derivation is accepted, and so are a clause owned by its FR dependency with no dependency to its case and a case verifying a clause owned by dependency without a dependency to it (TC-DOC-019). Refused: a clause with neither a derivation nor a dependency to an FR (`Canonical clause lacks requirement ownership`), a derived clause no case verifies (`Canonical clauses lack verification links`), a derivation from a missing FR or deriving an FR (`Invalid canonical clause dependency`), and a derivation body other than one `#original` and one or more `#derive` ends (`Invalid canonical derivation: <key>:<line>`). | Automated isolated fixtures on this PC. |
| TC-DOC-003 | CL-014-04 | Feed the actual Pilot a valid model, malformed syntax and unresolved names/types. Accept only the valid model; other cases return diagnostics and nonzero. | Automated pinned Pilot, local fixtures. |
| TC-DOC-004 | CL-014-04 | Remove/corrupt Java, validator/library or model paths. Required validation fails nonzero and never reports semantic PASS. | Automated tool/prerequisite fixtures on this PC. |
| TC-DOC-005 | CL-014-03, CL-014-06 | Load the complete architecture with the actual Pilot, inspect resolved port/item/association/binding inventory and compare with independent endpoint expectations. Remove/delegate/bypass/split/duplicate/redirect a required path or authority, change item type/direction, weaken identity binding or add view-only runtime parts. Each negative fails semantics or integrity; a rendered view cannot repair it. Remove each entry of the oracle file alone, damage or remove the file, declare a port, a part and a bypass connection in a definition of another package, used as a type or inherited, and put a second deployment, a view-made part and a subtype of the authority into a library package or another package: each is refused. A function of another package with its port and connection passes once the oracle file names them. Put back the parent's removed outside things with their ports and connections: refused while unlisted. List a port that no connection joins: refused, naming the first in sorted path order. The context list names exactly the issue's outside things, each with one owner in the deployment and one `@FollowsSource`. Where `Context.sysml` exists, an outside part there without ports and without a connection is refused by `check` with `Structure rule 4: outside part joined to no function: <path>`, and passes when listed under `elements` of the pending list with its owner. The mutation and fixture cases judge the model of commit `1df1ba3a5` against the oracle file of the same commit, both extracted by `git archive`. `oracle` on that model writes a file equal as data to its hand-written oracle and prints no change line. On a fixture tree in the skeleton's form (root `context` in `Context.sysml`, parts and interfaces in packages of their own folders): `oracle` then `check` pass, a second `oracle` prints `unchanged` and leaves the bytes equal, and an added connection is refused by `check` until `oracle` runs again; a part, a port and a connection added and removed and an item type changed, one at a time, each print exactly their one change line; a model the Pilot refuses, a second authority in another package, a second package-level part usage, a duplicate `catAdapter` and a station population `1..1` make `oracle` exit 2 with today's message and the file unchanged, and `traces`, `markers`, `fingerprints`, `status` and `check` neither create nor change it; an outside part joined to its owner's port passes and unjoined is refused with `port joined to no function`. | Automated full-validator mutation fixtures and independent architecture review on this PC. |
| TC-DOC-006 | CL-014-07, CL-014-08, CL-014-09 | An agent that did not write the issue reads it and the canonical contract it names; missing required decisions, missing test cases or a shared-only generated oracle give `Ready: not yet`, and `cr_state.py` refuses `implementing` without a `Ready: PASS`. The independent review of the candidate rechecks exact changes and closure reconciliation. On request, a model-readiness review traces the contract to code boundaries. No syntax/fingerprint result establishes implementation sufficiency. | Manual source/model/meaning reading on this PC; automation cannot establish complete intended meaning. |
| TC-DOC-007 | CL-014-01, CL-014-05, CL-014-08 | Refuse dual/missing authority and an active FSD without the marker, missing/duplicate stable IDs, missing required packages, invalid state, nonreciprocal verification links, missing/escaping source paths and unsupported executable claims. Refuse dangling active references to retired FSD content. Edited/missing archived Markdown does not change canonical checks; no command rewrites the model, except `paths` under CL-014-20. A new package needs no reference and is validated in full; a model with or without `WstxProductScope` is accepted. `Context.sysml` with `WstxContext` is accepted; `Context.sysml` with another package or none, `Context.sysml` declaring an identity, and another file importing, naming or declaring `WstxContext` are refused; with `Context.sysml` removed while another file names `WstxContext`, the pinned Pilot refuses. Source edits/deletions invalidate both model suites' evidence; source-only changes select fast traces without the full model suite. A change to the architecture model files, the oracle file or the pending list selects the working-model suite and `sysml-documentation`, not the validator suite. A tool change selects both; the validator, its library pin and its test files select the validator suite. Source edits select neither and invalidate the validator suite's evidence. Every file `tools/sysml/tests/test_*.py` runs in exactly one suite. Fast traces refuses a deleted binding and never invokes Java. | Automated isolated Python fixtures on this PC; full integrated Pilot validation remains separate. |
| TC-DOC-008 | CL-014-10 | Place a clause and its case in a subfolder file, move, rename and split the file of a required package, remove the package (`WstxRequirements`, `WstxArchitecture`), declare it in two files, move the entry file, verify and link a clause through a package-qualified name, add an additional package referred to by import, by alias and not at all, with and without `WstxProductScope`, and a former library package and a file without a package. The real model is accepted. The tree is accepted, each fault is refused by package or key, fingerprints and the gate's model list name every file by key, and the real model with one file of a required package moved into a folder under another name passes the full validation with the same identities. | Automated isolated Python fixtures and one full Pilot validation on this PC. |
| TC-DOC-009 | CL-014-11 | Write status, bindings and method as metadata, state one twice, leave a clause's binding to none, one and two function bindings, type a case by a definition with and without automation in its file and in another, bind a test on a definition, and declare an identity in an unread form. The new forms give the catalog and gate bindings of the attribute forms, each fault is refused by identity or key, and the real model rewritten to metadata passes the full validation with the same identities. | Automated isolated Python fixtures and full Pilot validations on this PC. |
| TC-DOC-010 | CL-014-12 | List markers in each form across folders, in comments, with joined strings, by kind, with an added kind, an unknown kind, no ModelNotes file, a broken catalog and no authority. | Automated isolated Python fixtures on this PC. |
| TC-DOC-011 | CL-014-13 | Tag a test in a file its case does not bind, and as another symbol of a file bound by symbols; name a case by shorthand, in a tag for two cases, in a JavaScript test name, above a helper, on an ignored test, on a planned and on a manual case, and outside the source roots; bind a manual case to a missing symbol. Each fault is refused naming case, path and test; adding the binding or removing the identity is accepted; the gate's bindings still report such a revision. | Automated isolated Python fixtures on this PC. |
| TC-DOC-013 | CL-014-15 | Remove a baseline case and retire it beside the `@DetailTests` that names its file, with and without package names, two in one body, in a subfolder file and in a comment; retire an FR and a clause, a malformed identity, a missing, repeated or other feature, a value that is not one literal, a test with `;` or `::`, the `metadata` keyword form, a file named only by another body or by no `@DetailTests`, one identity twice in one file and in two, and a retired identity declared again; name the retired identity in a tag, a JavaScript test name and a clause dependency. Each accepted model passes with the declared identities only, each fault is refused with its message, key and line, and the existing messages are unchanged. List three retirements in two files and none with `retired`, on a broken catalog and with no authority. The gate's bindings of a retiring revision equal those of the revision without the case. The pinned Pilot resolves the def text and refuses a misspelt feature. Superseded: with the extended `RetiredCase` definition in the fixture's `shared/ModelBindings.sysml`, TC-A superseded by TC-B and TC-C at package level of a subfolder file, with package names, and directly in a definition body, with TC-B and TC-C declared, counts for the baseline and is no entry, and `retired` prints `TC-A: superseded by TC-B, TC-C: <key>:<line>`, sorted beside a retirement into the detail tests. Refused: TC-C missing and TC-C retired (`Superseding case missing or retired`); naming itself, both `test` and `supersededBy`, neither, a sequence or a `+` join, a malformed, repeated or empty identity and the feature twice (`Invalid retired case`); a `Proves:` tag naming TC-A. The pinned Pilot accepts the extended definition with both forms and refuses a misspelt `supersededBy`. | Automated isolated Python fixtures and full Pilot validations on this PC. |
| TC-DOC-014 | CL-014-16 | Each reader reads the fixture tree `tests/fixtures/model-values/`, with its own `WstxUnits::UnitSuffix`, against the hand-written list of expected values there, in an LF and a CRLF copy: a value two folders deep in a file named other than its package; package-level, definition and usage-redefinition values; a quoted name; integer, negative real, a string holding `\"`, `;`, braces and `//`, `true`, `false`, `null` and an enumeration value; enum members in both forms after a definition `doc` and with a doc body; three usages of a definition, one typed by its qualified name; declarations in comments and `doc` not read; numbers with and without their unit. Each refusal names the qualified name and the reason: a missing and an empty folder, a non-UTF-8 file, a package in no file and in two, a name not declared and declared twice, a value missing, an expression, a `+` join, a list, a unit expression, a feature only the definition states, an empty table, an unlisted suffix, a value with a unit read as a plain number, and the suffix list missing and empty. The six tests that read `WstxOperatingReceive` pass with the parent's assertions, also with its file moved and renamed, and go red on a scratch copy with a changed or removed vector, a changed or removed band entry, a renamed `ft8Hz` and `Hz` removed from the suffix list. | Automated fixtures in the Rust and Node suites on the test machine, without the Pilot; scratch-copy runs on the test machine, quoted on the owning issue. |
| TC-DOC-015 | CL-014-17 | On the real history, the parent of the commit that divided `Requirements.sysml` by part against that commit is equivalent and leaves `git status` unchanged; their identities are 522, 202 moved exactly as that issue's assignment table, among them the two cases with rewritten links, and 320 unchanged; a revision against itself is equivalent. On a small model in a temporary repository each mutation exits 1 naming the element and the kind: a doc character; a dropped attribute and action definition; a dependency, a `verify` and a type target; a value, a multiplicity and a rename (missing plus added); an unqualified reference resolving to another element after a move (qualified: equivalent); kind, short name, direction, specialization, subsetting, redefinition, `satisfy` target, subject type, connection end, a status and a module value; a package-level comment dropped and altered and a package-level `satisfy` dropped; a link retargeted to another file; one of two same-named definitions, both moved, with a changed value; values swapped between two same-named definitions; a member moved from one to the other (changed owner); an `expose` changed and dropped; a comment outside any package altered and dropped. Two same-named definitions with equal own facts, one moved to a file read first, are equivalent, paired by their members. Two equal same-named enumerations in two packages, the file of one renamed to be read after the other's, are equivalent, the renamed one listed as moved within its own package; with a literal added to the renamed one, only it is missing and added, with its new literal added, and no line names the other's file or a typing target. A case moved in the commit that moves the file its link targets, the link updated, is moved; its link retargeted to another file, changed. A move of two elements to a new package and file, with imports, an updated qualified name in text and an updated link, is equivalent and listed with a count of 2; that name pointing to another element, or a dropped line note, is a difference. A code and a suite citation of a moved element or file are stale until updated, a citation unresolved on both sides is listed only, and a citation reached through a public re-export resolves. Readers below `tools/sysml/tests/`, the head moving the cited element: a pinned reader whose `PINNED` names the base, citing the moved name, prints `exempt <file>:<line> Core::Run (pinned)`, exits 0 and the summary ends `; exempt: <file> 1` (E15 a); its `PINNED` naming a commit without that name (E15 b), naming no commit of the repository (E15 c), or naming that commit while the file also declares `package Core {` (E15 f), the citation stays stale-by-change with exit 1 and no exempt entry; a fixture reader declaring `package Core {` prints `exempt ... Core::Limits (fixture)` while its `Extra::Limits` stays stale, exit 1, counting 1 (E15 d); a file outside `tools/sysml/tests/` with both signs and a file below it with neither stay stale with no exempt entry (E15 e). On this repository `test_architecture_integrity.py` is a pinned reader of `1df1ba3a5` and no fixture reader, the names it cites in `tools/sysml/tests/test_architecture_integrity.py` (among them those of R7's "port path twice" and "direction inout" cases) resolving in that commit's export; `test_architecture_oracle.py` is a fixture reader with `WstxArchitecture` among its declared packages, the names at its lines 135-136 starting with it; an ordinary file is neither (R-real). An unknown revision and a head failing the Pilot exit 2. Identities of a pair with one of each status count 1 per status, the retired one with its test file; a case declared in the base and superseded in the head is retired `superseded by TC-B, TC-C`; on two real revisions the lines are the union of both sides. With marked, unmarked and altering commits `--marked` checks the marked ones with 3 exports, names the altering commit with exit 1, and reports no marked commit. | Automated isolated Python fixtures in temporary git repositories and the repository's own history, with the pinned Pilot, on this PC. |
| TC-DOC-016 | CL-014-18, CL-014-03 | Without the Pilot, on small trees: a part file naming its own folder's package, an `interfaces/` package, a `shared/` package, `WstxRequirements` and `ScalarValues` passes, and so do `StationLink` and `Mcp` importing `QsoControl`, `RadioControl` naming `RadioProperties`, `Hearing` naming `PskReporter`, `ReceiveControl` and `OperatingChain` naming `QsoControl`, and a qualified name in `doc`; refused: a part file importing another part's package or naming it in code, `QsoControl` naming `StationLink` or `OperatingChain`, and `Cat` naming `ReceiveControl` (rule 1). `Station.sysml` with its package, part definitions and usages, a reference, a connection, a binding and `satisfy 'FR-001'` passes; refused with key and line: at package level an `attribute def`, a `port def`, a requirement, a `satisfy` of a clause and a `dependency`, in a part definition an attribute and a port; `backend/station/Station.sysml` is not judged (rule 2). An FR with `coverage`, `@Status`, `implementation`, `@ImplementedIn` or `#40` in its `doc` is refused (rule 8); a `dependency` is refused and a derived clause with its case passes (rule 9); a requirement definition and usage without `subject` are refused (rule 10). Each faulty file on the pending list passes. With the pinned Pilot, on a fixture tree in the target form that passes every rule with the deployment rules on, one edit at a time: an untyped connection, one typed by an interface outside `interfaces/`, an interface without items, an untyped item and one typed by a featureless `Empty` (passing with `Empty` under `elements`) are refused, and with `Station.sysml` listed the connection faults pass (rule 3); an outside part whose type has a part, an action or a state, whose body has a part, or that is a requirement's subject is refused (rule 4); a control interface commanded from its second end, `transmit` to `radioControl` and `auto` to `qso` typed by a control interface, and no station service are refused (rule 5); a second internal browser port, the `StationLink` port connected to `receive`, a third port to an outside part, a connection from inside the frontend to `receive` and no operator are refused (rule 6); `auto` to `transmit`, `ranking` to `qso`, `qso` to `auto` and no `ranking` are refused (rule 7); an outside part joined to no function is refused unless listed (rule 4, CL-014-03). The pending list missing, empty, not JSON, with a key or a name twice, an unknown or renamed key, a name resolving to nothing, an empty owner, or `files` naming `Context.sysml` or `interfaces/internal/X.sysml` exits 2 with no passed line; element entries inside `Context.sysml` and `interfaces/` are accepted; two faults of two rules are listed in rule, key and line order before `2 structure faults`. On this tree `check` passes and prints the structure line of its pending list after the architecture line. Pinned checks: on `1df1ba3a5`, which has no list, with the working tree's list carrying `WstxContext::browserOwner`, `check` prints `Structure checks not run: 1df1ba3a5 has no pending list`, runs no rule and exits 0 (P1); on a fixture commit whose list is `{"files": [], "elements": {}}` and whose model declares a `dependency`, `Structure rule 9: dependency declared: <key>:<line>` with exit 2, and without the `dependency` the passed line with 0 files and 0 elements pending and the deployment rules on (P2); a commit's list naming a file key of that commit absent from the working tree is accepted, one naming an element absent from the supplied inventory is refused with `no model element`, and a malformed or zero-byte list there is refused (P3); the architecture integrity tests on `1df1ba3a5` as pinned checks, with a temporary working list carrying `WstxContext::browserOwner`, pass with their oracle and other-command assertions unchanged (P4). | Automated isolated Python fixtures, full Pilot validations of the fixture states and one `check` of this tree on this PC. |
| TC-DOC-017 | CL-014-19 | A synthetic catalog with one FR per case, the FRs stating no status and no binding, the first clause of each FR owned by a dependency and the second by a derivation: (implemented, implemented) gives implemented; (partial, partial), (implemented, target) and (implemented, partial) give partial; (target, target) and no clause give target. Both forms of ownership count. `status` prints the lines and the summary counted by hand, an FR stating another status shows `; stated <state>`, and nothing is written; a broken catalog and a missing authority exit 2. On the working tree `status` exits 0 and prints one line per FR of the catalog in identity order in that form; each line's status and counts agree with its clauses' states as the catalog reads them, and the summary's counts equal the per-line statuses. | Automated isolated Python fixtures and the real model on this PC, without the Pilot. |
| TC-DOC-018 | CL-014-20 | On temporary trees with the marker in `docs/sysml/Requirements.sysml` and files under `server/`, `client/`, `tests/` and `tools/`, with `validate` patched to fail if called and the expected texts written by hand. R1 file rename: `server/src/contact.rs -> server/src/qso/contact.rs` and `server/tests/vectors.rs -> server/tests/qso/vectors.rs`, both moved, occurring in each of the six binding forms (one using `@ModelBindings::TestedBy`, one `path::symbol`), a `@DetailTests` value with two paths, a Markdown link in a model file two folders deep, a doc sentence ending in `.rs.` and a `// (server/src/contact.rs)` comment: each occurrence is rewritten to the expected text, the file is otherwise byte-equal, a CRLF file stays CRLF, the `rewrote` lines appear in key, line and column order, then `Path rewrite: <n> rewrites in <m> model files`, exit 0. R2 folder rename `server/src/radio_control -> server/src/radio/control`: every path below the folder and `server/src/radio_control/mod.rs::Configuration` are rewritten; `server/src/radio_control_tests.rs` and the plain word `server/src/radio_control` without a following `/` are not. R3: `server/browser`, `tools/call`, `server/src/contact.rsx`, `xserver/src/contact.rs` and `../server/src/contact.rs` outside a link are not rewritten. R4 refusals, each alone, with its fault line, `Path rewrite refused: 1 faults`, exit 2 and every model file byte-equal: a malformed line and a line holding `\`; an empty list; an absolute path, a `..` path and a path under `docs/sysml/`; a duplicate entry; a file entry inside a folder entry; a chain `a -> b`, `b -> c`; `a -> a`; an old path still on disk; a new path not on disk; an entry the model does not name; a path an FR declaration's `attribute implementation` binds renamed to `tools/x.rs`; an unrelated FR declaration binding, a function `@ImplementedIn`, a `@DetailTests` path and a TC declaration's `attribute executable`, each to a missing file; a link to a missing file. Two faults of one step are listed sorted before `2 faults`; a fault of step 1 with one of step 2 shows only the step-1 fault; a missing list file and a missing authority exit 2 with `SysML check failed:`. R5: the R1 list run again gives `Path not named by the model` for both entries, exit 2, nothing written. R6: on a `git archive` of HEAD with `tests/communication.test.cjs` moved to `tests/protocol/communication.test.cjs`, `paths` exits 0, its `rewrote` lines number the substring count of the old path in the `*.sysml` files counted before the run, no file outside `docs/sysml/` changes, `traces` there exits 0 and the repository's `git status` is unchanged. R7: the R1 fixture with an unnamed verification usage holding `attribute executable : String = "tools/sysml.py check; tools/missing.py";` exits 0 as R1, with no `Path missing after rename` line and that line byte-equal; with `"server/src/contact.rs"` there, it is rewritten by (a); with `tools/sysml.py -> tools/model/sysml.py` moved and named only in that command line, the run exits 0 with that one `rewrote` line and the string becomes `tools/model/sysml.py check; tools/missing.py`. | Automated isolated Python fixtures and a `git archive` of the real model on this PC, without the Pilot. |
| TC-DOC-019 | CL-014-05, CL-014-21 | V1: a clause owned by a dependency to its FR and verified by a case's `verify`, with no dependency to the case, is accepted and the entry's `refs` names the clause; with the dependency and its `verify`, accepted. V2: a dependency to a case that does not verify the clause, `Nonreciprocal canonical verification links: <TC>`; a clause no case verifies, `Canonical clauses lack verification links: <CL>`. V3: the existing subtests "the FR dependency, no dependency to its case" and "a case verifying a clause owned by dependency without the reciprocal one" are accepted, "the clause's only case retired" (both places) is refused with `Canonical clauses lack verification links: CL-003-01`, and `git grep -n 'lacks a declared verification case' -- tools/` has no hit. L1, accepted: `@TestLevel` with and without package names, two pairs on one case, a case typed by a definition of its file with levels and stating none takes them, a case stating its own keeps them; the `levels` of each entry are the hand-written pairs. L2, refused with its message, one fault at a time: cost 0, 6, `"2"` and `2.0`; location `lab`; `location` missing, `cost` twice, a feature `consent`; the same pair twice; the `metadata` keyword form; `@TestLevel` on an FR, a clause and a `part def`; on a definition the message names name and key. L3: the pinned Pilot accepts the real `ModelBindings` with `TestLocation` and `TestLevel` and refuses a misspelt `locaton`; `check` and `traces` pass on the real model. | Automated isolated Python fixtures on this PC without the Pilot, plus one full Pilot validation. |
| TC-DOC-020 | CL-014-22, CL-014-17 | Pilot export on temporary git repositories, expected lines written by hand. P1, each rule alone in one base and one head commit, exit 0, its `proven` line and the summary `; proven: 1`: case-number (`#### TC-001-001 — Title` becomes `Title`, a plain `TC-001-001, ` removed); clause-list (`Proves CL-001-01, CL-001-02.`, a bare line `CL-001-01, CL-001-02` and `CL-001-01/02` removed); cost (a line wording with `; Windows development PC` removed plus `@TestLevel { cost = 2; location = TestLocation::developmentPc; }`, a bold wording, an element wording in its own element); dependency (a `verified_by` dependency whose case keeps its `verify`); status (each of `coverage`, `automation`, `method`, `implementation` and `executable` turned into its metadata form with the same value). P2, a difference as today, exit 1 and no `proven` line for that element: another case's number; `TC001001`; a clause list with one clause more, one fewer or naming a TC; a cost wording with a wrong pair, with no `@TestLevel` or with an extra pair; an element wording in another element; a line wording not at a line start (`\| 2 — …`); a dependency whose case no longer verifies the clause; a dependency to an FR; a status value changed; an attribute removed without its metadata; one other word changed beside proven spans. P3: all five rules in one case at once, five `proven` lines, exit 0; with `--marked`, a marked commit doing this is `checked` with exit 0. P4: the mapping file missing, not JSON, or an entry with cost 7, exit 2 naming the file. P5, mapping guard, on the model of `f80c243c9` read by `git archive`: every line wording occurs at a doc line start, every bold wording occurs, every element wording occurs in its element, and every doc line of a verification element that begins with a digit 1 to 5 and ` — ` begins with a listed line wording. P6: a temporary repository holds HEAD's tree; its head commit converts TC-007-002 and TC-085-006 by all five rules and removes their `verified_by` dependencies; `equivalence` exits 0 with their `proven` lines, `traces` passes on the head and `git status` of the repository is unchanged. | Automated Pilot exports on temporary git repositories and on the repository's own commits, on this PC. |

The mapping of cost wordings that CL-014-22 reads is `tools/sysml/cost-wordings.json`: `line`, `bold` and
`element` wordings with their (cost, location), and the `places` phrases that may follow a line wording.

Executable companions are `tools/sysml.py`, `tools/sysml/tests/` and the pinned
`tools/sysml/Validate.java` adapter; for TC-DOC-014 they are the two model-value readers
and their tests. Results and independent review
are recorded on the owning issue, never as invented model verdicts.

## Canonical model catalog and source bindings

The canonical entry point is `docs/sysml/Requirements.sysml`. The model set includes the
required packages `WstxRequirements` and `WstxArchitecture`, and `WstxContext` whenever
the model file `Context.sysml` exists. Additional packages are discovered, scanned and
fully validated without a reference; a model with or without `WstxProductScope` is
accepted. A lost model file stays noticed through the required identities, name
resolution and the `Proves:` tags. A missing required package fails.

A model file is a file `*.sysml` at any depth below `docs/sysml`; its key is its path
relative to `docs/sysml` with forward slashes, and every message that names a model file
names it by its key. No folder is excluded; a file kept out of the model keeps a suffix
other than `.sysml`. The package of a model file is its first package declaration outside
comments; a file without one has no package. A package named only in a comment, nested in
another package or declared after the first package of its file is not the file's package.

- **Required packages.** Each package in the tool's list of required packages
  (`REQUIRED_PACKAGES` in `tools/sysml.py`, the two named above), and `WstxContext` while
  `Context.sysml` exists, is the package of exactly
  one model file, whatever that file's name and folder. The name is compared whole. None:
  `Canonical model packages missing: <names>`, the names sorted and joined by `, `. Two or
  more files: `Duplicate canonical model package: <package>: <keys>`, the keys sorted and
  joined by `, `. The catalog asks for no model file name: two model files of one name in
  different folders are accepted, each judged by its package and named by its key. The
  file of a required package may be moved, renamed or split while one file keeps the
  package. A change that renames or removes a required package changes the name in the
  list in the same change, with this section and the code comments that cite it; there
  is no alias from an old name to a new one. Any other package, and a file without a
  package, is an additional package and needs no reference; the file name decides
  nothing.
- **Entry file.** `Requirements.sysml` with the marker `// Canonical authority: SysML` is
  required directly in `docs/sysml`. Elsewhere or absent, the commands refuse with
  `No declared functional authority`.
- **Context file.** `Context.sysml` directly in `docs/sysml` is the top layer: nothing
  imports it and it holds no identity. While it is absent, two packages are required;
  once it exists, `WstxContext` is required too, with no tool change. Before the
  required-package check, `traces`, `check`, `fingerprints`, `retired` and `status`
  refuse: a `Context.sysml` whose package is not `WstxContext` (another package or none),
  `Context file package is not WstxContext: Context.sysml`; a `Context.sysml` declaring an
  FR, CL or TC identity, `Context file declares an identity: <ID>: Context.sysml`; and any
  other model file naming `WstxContext` outside comments and strings (an import, a
  qualified name or a package declaration),
  `Model file names the context package: WstxContext: <key>`.

Each clause declares `coverage : ImplementationState` as target, partial or implemented;
an FR may declare it too or leave it out, and its status is computed (CL-014-19). Each
verification declares `automation : AutomationState` as planned, partial or implemented.
These are declarations of available companions, not execution or acceptance results.

- **Clause ownership.** A clause is owned by its FR in one of two forms. By dependency:
  `dependency <name> from '<CL>' to '<FR>';`. By derivation, the form of the pinned model
  library (Domain Libraries/Requirement Derivation):
  `#derivation connection { end #original ::> '<FR>'; end #derive ::> '<CL>'; }`,
  with or without package names on the metadata and the ends. In either form the clause
  is verified by the cases whose `verify` names it (CL-014-05); a
  `dependency <name> from '<CL>' to '<TC>';` is not needed, and where one is written its
  case must verify the clause: `Nonreciprocal canonical verification links: <TC>`. A
  connection body other than one `#original` end and one or more `#derive` ends:
  `Invalid canonical derivation: <key>:<line>`; a derivation from an FR that does not
  exist or deriving anything but a clause: `Invalid canonical clause dependency: <CL> ->
  <FR>`. A clause with neither form: `Canonical clause lacks requirement ownership: <CL>`;
  verified by no case: `Canonical clauses lack verification links: <CL>`.
- **Test level.** A verification case, definition or usage states its levels as
  `@TestLevel { cost = <n>; location = TestLocation::<place>; }` (CL-014-21); the
  catalog entry of a case carries them as `levels`.
- **Computed FR status.** The status of an FR is computed from the clauses it owns in
  either form: `implemented` when all are implemented, `target` when all are target or it
  owns none, `partial` otherwise. An FR without a stated status needs no binding. The
  catalog entry of an FR carries `status` (computed), `stated` (the stated state, or
  none) and `clauses`; its `state` is the stated one, or the computed one when none is
  stated.

Partial/implemented requirement and clause definitions carry a root-relative binding:

```sysml
attribute implementation : String = "server/src/profile.rs; client/app.js";
```

Partial/implemented verification definitions carry existing executable bindings:

```sysml
attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
```

Bindings are semicolon-separated repository-root-relative files, never absolute or
escaping paths. Automated cases require a matching `Proves:` case identity, an exact
Node test-name identity, or an explicit `path::test_symbol` binding. A Rust symbol must
exist; independent review still establishes its relationship to the promised behaviour.
The checker admits bindings under the exact Git roots `client/`, `server/` and `tests/`,
which both model suites fingerprint. These are validation-input coverage bounds, not a
product limitation. A new source root requires a reviewed HOW update to the admission
constant, both suites' complete inputs, fast selection and their regression together;
an unregistered binding is refused rather than silently borrowing stale evidence.

A *declaration* is a requirement or verification with a stable identity that the catalog
reads. The forms above are the *attribute form*. The *metadata form* uses the names of the
harness template `harness/core/templates/sysml/model-bindings.sysml` with this project's
status names; a metadata name may carry package names (`@ModelBindings::Status`), and so
may an enumeration value. Both forms are read:

```sysml
action def StandardContact {
    @ImplementedIn { module = "server/src/contact.rs"; }
    @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
}
requirement 'CL-010-18' {                      // takes server/src/contact.rs
    subject qso : WstxQsoPart::QsoAndLogging;
    @Status { build = ImplementationState::implemented; }
}
verification def EngineCase {
    subject qso : WstxQsoPart::QsoAndLogging;
    attribute level : Integer = 2;
    attribute location : String = "Windows development PC, isolated, no RF";
    @Automation { run = AutomationState::implemented; }
}
verification 'TC-007-010' : EngineCase {
    objective { verify 'CL-010-02'; }
    @TestedBy { test = "server/src/contact_tests.rs"; }
}
```

- **Status as metadata.** In a requirement body `@Status { build = ImplementationState::<state>; }`
  is read as `attribute coverage`. In a verification body
  `@Automation { run = AutomationState::<state>; }` is read as `attribute automation`, and it
  may also hold `method = "manual";` or `method = "automated";`, read as `attribute method`.
  States and their meaning are unchanged.
- **Bindings as metadata.** In a requirement body `@ImplementedIn { module = "<bindings>"; }`
  is read as `attribute implementation`. In a verification body
  `@TestedBy { test = "<bindings>"; }` is read as `attribute executable`. The value is one
  string literal with the grammar, checks and messages of the attribute form.
- **Once per declaration.** Status, binding and method are each stated at most once per
  declaration, in either form. Status stated twice, or not at all and not taken from a
  definition: `Missing or invalid declared model state: <ID>`. Binding or method stated
  twice, a value that is not one string literal, or a method other than the two:
  `Invalid verification/implementation metadata: <ID>`.
  Nothing is taken over where the declaration names the fact itself. A declaration whose
  own body names status, binding or method in a spelling the tool does not read
  (`attribute implementation`, `attribute automation` or `attribute method` with a value
  that is not the read form, such as a `+` expression or a qualified state; the feature
  redefined in the attribute form, such as `attribute :>> automation = ...`; an own
  `@ImplementedIn`, `@Status` or `@Automation` body with a non-blank statement the tool
  did not read, such as `:>> module = ...`; or the same metadata written with the
  `metadata` keyword, such as `metadata ImplementedIn { ... }`) is refused with the message
  above for that fact wherever a value would otherwise be taken over (a delivered clause
  beside a function binding; the state of a case; the method of a case beside a
  definition that states one); elsewhere the result is that of the attribute form. It
  never gets the value of its function binding or of its definition.
  `@Automation {}` and `@Automation { method = "automated"; }` keep taking the state over.
- **Shared case definition.** `verification '<TC>' : <Definition> {` is read as a case, as
  `verification '<TC>' {` is. A case that states no automation state takes the state of its
  definition, and a case that states no method takes its method, when the definition is a
  `verification def` in the same model file, named without package names, and states them
  in either form. A state or method the case states itself wins. Nothing is taken from a
  definition in another file or from the definition's own supertypes; such a case states
  its own. A `@TestedBy` or `attribute executable` on a verification definition without
  identity is refused: `Verification definition carries a test binding: <name>: <key>`.
- **Function binding.** An `@ImplementedIn` outside the body of every declaration is a
  function binding of its model file. It is checked as a clause binding is, and its
  messages name the file key in place of an identity.
- **A clause takes its module from its function.** A requirement that is `partial` or
  `implemented` and states no binding takes the function binding of its own model file.
  None in the file: `Delivered declaration lacks implementation/test binding: <ID>`. Two or
  more: `Ambiguous function binding: <ID>: <key>`. A requirement that states its own
  binding is not affected by either.
- **Detail tests.** `@DetailTests { tests = "<paths>"; covers = "<text>"; }` anywhere in a
  model file: each path of `tests`, separated by semicolons, must be an existing file
  under the source roots, else the binding messages with the file key. No `Proves:` tag is
  asked, and the gate's bindings do not list it.
- **Retired case.** A verification case whose test shows nothing at a part boundary
  retires into the detail tests of its part: its test stays and loses the case tag, and
  the body that names the test file in `@DetailTests` lists the identity as retired:

  ```sysml
  action def StandardContact {
      @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
      @RetiredCase { identity = "TC-007-020"; test = "server/src/contact_tests.rs"; }
  }
  ```

  The form is typed by
  `metadata def RetiredCase { attribute identity : String; attribute test : String; }` in
  the `ModelBindings` package, beside `DetailTests`. It is this project's own form, not one
  of the harness template `model-bindings.sysml`. It is read outside comments, with or
  without package names (`@ModelBindings::RetiredCase`); one annotation retires one
  identity and names one file, and a body may hold several. Only verification cases
  retire. `traces`, `check`, `fingerprints`, `retired` and `status` refuse, in this order:
  - per model file, after its `@DetailTests` path check and its declaration checks, each
    `@RetiredCase` in the order of the file: an FR or clause identity,
    `Only a verification case retires: <ID>: <key>`; any other spelling (a missing,
    repeated or other feature, a value that is not one string literal, an identity not of
    the form `TC-ddd-ddd`, a `test` holding `;` or `::`, or the `metadata` keyword form
    `metadata r : RetiredCase { ... }`), `Invalid retired case: <key>:<line>`, the line of
    the `@` or of the word `metadata`; a `test` that no `@DetailTests` directly in the same
    body names as written, `Retired case outside the detail tests: <TC>: <path>: <key>`.
    The retirement has no file check of its own: its file is a `@DetailTests` path of the
    same body, which the binding messages with the key have already judged;
  - after all model files, before the baseline: an identity retired more than once,
    `Duplicate retired case: <TC>: <keys>`, each key once, sorted and joined by `, `; a
    retired identity that is also declared,
    `Retired case declared again: <TC>: <key>`, with the key of the declaration; then each
    case a superseded retirement names that is not a declared case or is retired,
    `Superseding case missing or retired: <TC>: <named TC>: <key>`.

  **Superseded.** A verification case whose checks went to other contract cases, not to
  detail tests, retires as superseded:

  ```sysml
  @RetiredCase { identity = "TC-039-041"; supersededBy = "TC-097-002; TC-097-003"; }
  ```

  The tool reads it against
  `metadata def RetiredCase { attribute identity : String; attribute test : String[0..1]; attribute supersededBy : String[0..1]; }`;
  the model's definition is extended to it in the change that writes the first such
  marker. An annotation has `identity` and exactly one of `test` and `supersededBy`;
  `supersededBy` is one string literal of one or more `TC-ddd-ddd` identities separated by
  `;`. Any other spelling (both features, neither, a value that is not one literal, a
  malformed or repeated identity, the case itself) gives
  `Invalid retired case: <key>:<line>`. A superseded retirement stands in any model file,
  at package level or directly in a definition body, and needs no `@DetailTests`. Each
  named case must be a declared case of the catalog and not retired, checked as above.
  The rest is as for a retired case.

  A retired identity counts as present for the stable baseline. It is not a catalog
  entry: the identity count of `traces` and `check` leaves it out, and a `Proves:` tag, a
  JavaScript test name or a clause dependency naming it is refused by the rules for an
  undeclared identity. A clause whose only case retires is refused
  (`Canonical clauses lack verification links: <CL>`) until another case verifies it. `python tools/sysml.py retired` checks the authority and the catalog
  as `fingerprints` does, then prints one line per retirement sorted by identity,
  `<TC>: <test path>: <key>:<line>` or `<TC>: superseded by <TC>, <TC>: <key>:<line>`,
  and the summary `<n> retired cases`; it writes nothing, and a broken catalog or a
  missing authority gives the existing refusal and exit 2. The gate's bindings list no
  retired identity and no retirement test file.
- **No unread declaration.** A `requirement` or `verification` declaration whose name or
  short name is a stable identity, in a form the catalog does not read (`:>`,
  `<'ID'> name`, a typed `requirement`), is refused:
  `Unreadable canonical declaration: <ID>: <key>`.

The gate's model bindings (`.harness/model_bindings.py --rev REV`) report the effective
values, so a model in the metadata form gives the JSON of the same model in the attribute
form.

Recognized numeric product identities in source `Proves:` comments must exist in the
canonical catalog; same-prefix shorthand is expanded. HOW and fixture-specific names
are not product declarations. A tag's presence still does not establish test execution.
A manual physical case uses `attribute method : String = "manual";` and names its
existing probe/source, without claiming an automated or executed result. A planned case
may lack an executable. Source tags and existing files prove presence, not conformance.

A test *names* a case when an attached `Proves:` tag above it holds the case identity after
shorthand expansion, or when it is a JavaScript test whose name holds the case identity. A
test is *in the binding* of a case when its file is bound as a file, or when
`path::<its name>` is bound; the binding is the effective `attribute executable` or
`@TestedBy` value.

- **Tag and binding agree.** For every case, each test that names it, in a `.rs`, `.js` or
  `.cjs` file below `client/`, `server/` or `tests/`, is in the case's binding. Otherwise
  `traces` and `check` refuse with one message naming every such pair, sorted by case, path
  and test name: `Proves tag outside the verification binding: <TC>: <path>::<test name>;
  <TC>: <path>::<test name>`. It holds for every case: automated, manual or planned, with or
  without a binding, and in either form of the binding. A tag that is not attached to a test
  names no test and is not judged. A test that is ignored or left out by a build
  configuration still names its case: a tag states presence, not execution. Files outside
  the three source roots are not judged. The refusal comes after the existing catalog and
  binding refusals, whose messages are unchanged.
- **A manual case's symbol exists.** A `path::symbol` binding of a case with method
  `manual` must name a test of that file. Otherwise:
  `Missing executable test symbol: <TC>: <binding>`.
- **The gate's bindings report, they do not judge.** `.harness/model_bindings.py --rev REV`
  gives its JSON for a revision whose tags stand outside a binding. Such a test is not
  listed for the case.

Canonical documents link to active model elements or existing repository paths with
correct model-file-relative Markdown links. Retired FSD section dependencies, source-hash
markers and broken file references fail. The minimum stable identity baseline includes
all 23 FRs, 38 clauses and 38 verification identities present in the reviewed application
baseline; a verification identity counts as present when it is declared or retired under
**Retired case**. Additions retain unique identities, and a retired identity is never
declared again. A verification case retires only in that form, in a change of its own;
any other retirement or an authority change requires explicit review rather than deleting
a definition to obtain a green check.

## Model values read by tests

This section is CL-014-16; TC-DOC-014 verifies it.

- **Rule.** Where the model holds an observable value as data (a typed value, an
  enumeration of external names, a table of instances), the contract test that compares the
  product with it reads the value from the model and does not write it again. A value that
  exists only in the prose of a case stays in the test. A test reads the `.sysml` files
  themselves, at run time, through the one reader of its language:
  `server/src/model_values.rs` for tests under `server/`, `tests/model-values.cjs` for tests
  under `tests/`. No file is generated from the model for a test, and no test parses the
  model with its own patterns. The one exception is the test "TC-097-019 the model carries
  no superseded wording" in `tests/ui-operating.test.cjs`: it reads no model value and
  compares nothing with the product, but scans the model text for superseded wording, so it
  reads the model files itself. The model it reads is every model file as defined in
  "Canonical model catalog and source bindings". Transition tables and other behaviour
  (states, transitions, actions) are not read yet; the change that first needs one extends
  this rule and both readers.
- **Naming.** A value is named by its qualified name `Package::Element(::Feature)*`.
  `Package` is the package of a model file. Each further segment names an element or
  feature declared directly in the body of the segment before it; a quoted name keeps its
  quotes (`WstxDecodes::FreeTextFields::'type'`). The file's name and folder are never
  part of the name, so moving, renaming or splitting a model file changes no name while one
  file keeps the package. Renaming an element, or moving it to another package, changes the
  name; the tests that cite it change in the same change, as code comments that cite
  elements do.
- **What is read.**
  - The value of an attribute: `attribute <name> [: <Type>] = <literal>;`, or a
    redefinition `attribute :>> <name> = <literal>;`, in a package, a definition body or a
    usage body.
  - The members of an `enum def`, in declaration order, written `a;` or `enum a;`. A `doc`
    on the definition is skipped. A member may also carry a body that holds only a `doc`
    comment; that is valid SysML, although `WstxUnits::UnitSuffix` does not use it.
  - The attribute usages declared directly in a named package or body and typed by a named
    attribute definition (short or qualified name), in declaration order. Each comes with
    its name and the literal values of its own body.
  - Literals: integer and real, with a sign; string, with its escapes, where `;`, braces
    and `//` inside it belong to the string; `true`, `false`; `null`; an enumeration value
    `Def::member`.
  - Only what the element's own body states is read. Specialization, inherited defaults,
    imports and aliases are not followed: a value stated on a definition is named on the
    definition.
  - Text in `//` and `/* */` comments and in `doc` bodies is not read. A file read with
    CRLF and the same file read with LF give the same values.
- **Units.** The unit suffixes are the members of `WstxUnits::UnitSuffix`. The readers read
  them from the model they read, through "What is read". A value with a unit carries one of
  them as the last part of its name. A name *ends in a suffix* when its last characters are
  the suffix and the character before them is a lowercase letter or a digit (`ft8Hz`,
  `pollMs`, `workerMemoryMaxMiB`). The value is written in the unit its promise is stated
  in, as an integer where one exists. No literal is a unit expression; existing quantity
  types stay, and they type fields without values.

  A test reads a number either *with its unit* or *as a plain number*:
  - Read with its unit, the name must end in a suffix. Otherwise the read fails
    (`unit suffix not on the list`), so a misspelt or unlisted suffix such as
    `ft8WindowMaxSecs` is refused.
  - Read as a plain number, the name must not end in a suffix. Otherwise the read fails
    (`value has a unit; read it with its unit`). A count without a unit (`pageRecords`,
    `candidateCap`, `caseId`) is read this way.
  - `null` is read in either way.
  - Strings, Booleans and enumeration values carry no unit and are not judged by the
    suffixes.

  A suffix is added as a member of `UnitSuffix`, with its sentence in the definition's
  `doc`, in the change that first needs it.
- **Failure: fail, never skip.** The reader returns an error naming the qualified name and
  the reason (Rust), or throws it (JavaScript), and a test that reads a value fails on it.
  The reasons are:
  - the model folder is missing, holds no model file, or holds a file that is unreadable
    or not UTF-8;
  - no file, or more than one file, has the package;
  - the name is not declared, or is declared twice in one body;
  - the value is missing (an attribute declared without `=`), or is not one literal of
    "What is read": an expression, a `+` join, a list, or a unit expression;
  - a unit rule of "Units" is broken, or `WstxUnits::UnitSuffix` is missing or has no
    member;
  - a table has no usage.

  No test that reads a model value skips, returns early, passes with nothing read, or
  reports NOT RUN because a value is missing.
- **What the test still states.** A provenance pin, an expected count, and the order and
  shape checks of a table stay in the test, as independent checks of what it read.
- **Scratch copy.** A test that reads a value is shown to read it by the scratch-copy
  check: in a scratch copy of the model the value is changed or removed, the test goes red,
  and it is green on the real model. Both readers find the model folder from their own
  file (`docs/sysml` beside `server/` and `tests/`), so the scratch copy is a throwaway
  checkout of the candidate (`git worktree add`) whose model files are edited; the tests
  run there unchanged, the Node tests on that checkout's own build (`WSTX_TEST_EXE`). A
  damaged copy inside a test replaces the text of the file of one package
  (`Model::with_package_text`, `withPackageText`), found by package, not by path.
