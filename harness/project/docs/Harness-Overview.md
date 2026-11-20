# Harness reference index

**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings.

The build procedure is the [CR process](../../general/core/docs/CR-Process.md); method changes
follow [Harness changes](../../general/core/docs/Harness-Changes.md). The declared canonical functional artifact is the product
contract; the references below are the constraints a change must respect.

| Subject | Reference |
|---|---|
| Product contract | [Functional model entry point](../../../docs/sysml/Requirements.sysml); [exclusive authority selection](Project-Specifics.md#exclusive-functional-authority) |
| Product component/interface boundaries | [Architecture](../../../docs/sysml/Shack.sysml) and its referenced behaviour/interface packages |
| The finished model: the rules every model change and its check name (M1–M8) | [Finished model](Finished-Model.md); read first by the definer and the reviewer of a model change |
| Product SysML artifacts and view scope | [Architecture model](../../../docs/sysml/Shack.sysml); [catalog and validation](../../../tools/sysml/README.md#the-rules) |
| Behavior baseline and provenance | [Functional model](../../../docs/sysml/Requirements.sysml) and its referenced scope/provenance packages; distribution notices in [README](../../../README.md#license-and-attribution) |
| The machine (HB9BLA, with the transceiver) | [Machine](Project-Specifics.md#machine) |
| Project-specific environment, build and model validation | [Project specifics](Project-Specifics.md), `.github/workflows/windows-rust.yml` |
| Language rules | the packs in `harness/project/config.yaml`: [Rust](../../general/lang/rust/standard.md), [Rust supply chain](../../general/lang/rust-supply-chain/standard.md), [Python](../../general/lang/python/standard.md); [crates that need `unsafe`](Project-Specifics.md#crates-that-need-unsafe) |
| Security | [principles](../../general/core/docs/standards/security.md); [deployment authority](Project-Specifics.md#deployment-authority) |
| Testing | [testing](../../general/core/docs/standards/testing.md); suites in `harness/project/suites.yaml` |
| Change and harness-improvement reports; restart checkpoints | [Reporting](../../general/core/docs/CR-Reporting.md); shared harness overview: `python harness/general/core/tools/report_cr.py --harness --root harness/general` |
| The coordinator (main session), parallel issue workspaces and sub-agents | [Agent roles](../../general/core/agents/roles.md), [workspace tool](../../general/core/docs/Workspaces.md); `python harness/general/core/tools/parallel.py status` |
| Writing functional SysML models | [SysML v2 authoring](../../general/core/docs/standards/sysml-v2.md) |
| How an agent session works with the operator | [Agent working rules](Agent-Working-Rules.md) |
| Prohibitions (index) | [Do-Not-Do](Do-Not-Do.md) |
| Escapes | the escape log, `../../general/core/tools/escapes.py list` ([self-measurement](../../general/core/docs/standards/testing.md#self-measurement)) |
| The coordinator's handoff (pointers) | [MEMORY](MEMORY.md) |
| Backlog | [GitHub issues](https://github.com/SensorsIot/wsjtx-rust/issues); rules in [Backlog](#backlog) |

## Layout

Everything under `harness/` is the harness (HOW); everything else is product.

- `harness/general/` is the general harness: the git submodule `harness-general`
  (https://github.com/SensorsIot/harness, branch `main`) at the commit this project pins. The
  reusable process is in `harness/general/core/`; Rust rules and compiler checks are in
  `harness/general/lang/rust/`. Fixes to it are made inside it.
- `harness/project/` is the project harness, this project's own part:
  - `config.yaml`: the harness configuration (packs, gate, queue, machines, Alex);
  - `suites.yaml`: the test registry;
  - `model_bindings.py`: the gate's model bindings (`gate.model_bindings`);
  - `deploy/`: the radio preflight (`radio-preflight.ps1`, `radio-port.json`), the station
    switch and the IC-7300 emulator's start and stop for simulator tests (`station-switch.ps1`,
    `emulator.ps1`), the shared station control (`station-control.ps1`) and their tests
    (`deploy/tests/`);
  - `tests/`: the tests of the project's role additions (`test_role_context.py`), run with
    `python -m unittest discover -s harness/project/tests`;
  - `mcp/station.json`: the station tester's MCP servers (`alex.launcher.mcp.station`);
  - `docs/`: [Agent working rules](Agent-Working-Rules.md), [Do-Not-Do](Do-Not-Do.md),
    [Finished model](Finished-Model.md), this overview,
    [MEMORY](MEMORY.md) and [Project specifics](Project-Specifics.md).

The machine's notifier secrets are outside the repository, in `~/.harness/wsjtx-rust/secrets.md`
(`python harness/general/core/tools/notify.py check` names a missing key, never a value).

The generated anchors `AGENTS.md`, `CLAUDE.md` and `.claude/` stay at the repository root,
where the hosts look for them. Project-specific environment, build and model-maintenance
instructions are in [Project specifics](Project-Specifics.md).

## Bindings

- **Main branch:** `master`; the push gate compares against `origin/master`.
- **Execution mode:** local. HB9BLA is authoritative for compiler checks,
  selected functional groups including their required bandwidth measurements, and release
  packaging. The local pre-push hook enforces the ordinary gate. GitHub Actions has
  only a manual trigger and is an explicit alternative when requested, not a second
  automatic build after a local pass.
- **Configuration:** `execution_mode: local` in `harness/project/config.yaml` selects local
  gate execution. The manual-only hosted workflow supplies the alternative location
  when explicitly selected; it does not add a routine second run.
- **Test selection:** explicit file owners and downstream functional dependencies in
  `harness/project/suites.yaml`; see [functional test selection](Project-Specifics.md#functional-test-selection).
  Shared or unmapped changes select broader checks. `--plan` explains the selection;
  `--full` executes every eligible group without memo reuse.
- **Deploy:** a Windows release executable built and installed on HB9BLA
  ([machine](Project-Specifics.md#machine)); the dry run uses that
  candidate on HB9BLA. The manual hosted workflow can supply build and test evidence
  when explicitly chosen; its artifact is never installed on the station. A deploy needs no
  OK under the standing deploy policy, also for a change to the deploy
  mechanism ([deployment authority](Project-Specifics.md#deployment-authority)).
- **Live tests:** tests that need a radio, a sound device or the network are cost 3–5,
  marked `#[ignore]`, get their own suites and run only on HB9BLA, where the transceiver is
  connected. Live tests key the simulator; the real IC-7300 once the operator has decided
  #239 ([simulator live tests](Project-Specifics.md#simulator-live-tests)). Cost 4 and 5 then
  run without asking under the standing consent at 1 %
  ([deployment authority](Project-Specifics.md#deployment-authority)); QSO tests are not
  covered by it.

## Harness paths

The paths a harness change may touch; everything else is product:

- `harness/` (`harness/general/`, the submodule at its pinned version, fixes made inside it;
  and `harness/project/`, the project harness)
- `AGENTS.md`, `CLAUDE.md`, `.claude/` (the agent guard and skill entrypoints)
- `.github/ISSUE_TEMPLATE/`
- `.github/workflows/rust-advisories.yml` (the pack's scheduled advisories sensor)
- `deny.toml` (the `rust-supply-chain` pack's licence and source policy)
- `.gitmodules` (the harness submodule's name, path, URL and branch; it holds only that
  submodule, and adding another submodule is a product change)

They are declared as `harness_paths` in `harness/project/config.yaml`: a push that changes only
these paths is a harness change: no review and no gate (harness Harness-Changes.md).

Maintained with the harness but inputs of product suites, so a change to them is gated
as a CR: `.github/workflows/windows-rust.yml` (the CI build), `tools/sysml.py` and
`tools/sysml/` (authority/trace checks, semantic validation and product contract oracles
such as coverage tables and property tests), and `tools/deploy/` (the deploy mechanism, its
drill and tests, suite `deploy-tooling`).
`.github/workflows/fortran-stage-diagnostics.yml` is product diagnostic tooling. A reviewer of a `deny.toml` change runs `cargo deny --locked --workspace check bans
licenses sources`, since the gate does not. The `rust-supply-chain` pack's
advisories sensor is `.github/workflows/rust-advisories.yml`: weekly and on demand, read-only,
it runs `cargo deny --locked --workspace check advisories`. A red run is GitHub's failed-workflow
notice to the operator (the user who last edited the schedule); it names the crate and the advisory, and the fix is a CR.

## Documentation is current-state

The [exclusive authority binding](Project-Specifics.md#exclusive-functional-authority)
selects one functional authority. With the canonical model declaration, SysML alone owns
product requirements, behaviour, architecture, interfaces and durable verification
definitions. Harness instructions, skills,
standards, process, build and gate documentation remain Markdown.

For each functional issue follow the [required sequence](Project-Specifics.md#required-sequence-for-functional-issues):
settle the canonical requirements and independent verification expectations, implement
against the model, test the function with independent oracles, for real where it matters, and
only then have the independent review, to find undesired behaviour. Reconcile delivered functionality, source bindings and test cases before
manual issue closure. A test's presence, actual execution and live acceptance are distinct.

The model owns the FR, CL and TC identities: each FR in `Requirements.sysml`, each clause
and test case in the function file of its part ([finished model](Finished-Model.md) M4.2,
M4.5, M6.5); a test case is a skeleton and a title, and its bound test is the description of
the test. Executable assertions and fixture data remain linked companions. Protocol, states, errors and bounds are in the responsible model packages,
not duplicated into another active specification. Product-specific tests and additive
execution wiring remain with their functional CR; reusable method changes follow the
harness rollout process.

The model tools' own rules (TR-nn) and tests (TV-nnn) are in
[tools/sysml/README.md](../../../tools/sysml/README.md), not in product SysML. Full parsing/name checking, architecture integrity and trace checks do not prove
behavioural equivalence or implementation readiness; the ready check, independent review
and relevant application tests supply that evidence.

The active canonical contract and these bindings state the rule that holds now, never
its history ([documentation](../../general/core/docs/standards/documentation.md)).
Open work and review/execution evidence live in GitHub issues; history is `git log`.

## Backlog

GitHub issues of `SensorsIot/wsjtx-rust` are the project's one to-do list.

- **Labels of a product issue:** one `cr:<state>` ([lifecycle states](../../general/core/docs/CR-Process.md#lifecycle-states)),
  at most one class label ([classes of change](../../general/core/docs/CR-Process.md#classes-of-change)),
  and an owner label only where several machines work. Nothing else: the class is the route,
  the blast is a line of the body, and there are no issue types and no priority labels.
  Harness issues are not here: they live in
  [SensorsIot/harness](https://github.com/SensorsIot/harness/issues).
- **Order:** the [pull order](../../general/core/docs/CR-Process.md#pull-order): the `After:` predecessors
  first, then `alex.first`, then an issue a later step put back, then the longest wait.
- **Ageing:** an open issue is overdue 30 days after it was created; the only ways out are
  to start it or to close it as not planned. An issue whose `After:` predecessors have not
  landed never ages.
