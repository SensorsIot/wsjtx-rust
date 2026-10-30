# Harness reference index

The build procedure is the [CR process](https://github.com/SensorsIot/harness/blob/main/core/docs/CR-Process.md); method changes
follow [Harness changes](https://github.com/SensorsIot/harness/blob/main/core/docs/Harness-Changes.md). The declared canonical functional artifact is the product
contract; the references below are the constraints a change must respect.

| Subject | Reference |
|---|---|
| Product contract | [Functional model entry point](../sysml/Requirements.sysml); [exclusive authority selection](Project-Specifics.md#exclusive-functional-authority) |
| Product component/interface boundaries | [Architecture](../sysml/Architecture.sysml) and its referenced behaviour/interface packages |
| Product SysML artifacts and view scope | [Architecture model](../sysml/Architecture.sysml); [catalog and validation](Project-Specifics.md#canonical-model-catalog-and-source-bindings) |
| Behavior baseline and provenance | [Functional model](../sysml/Requirements.sysml) and its referenced scope/provenance packages; distribution notices in [README](../../README.md#license-and-attribution) |
| Project-specific environment, build and model validation | [Project specifics](Project-Specifics.md), `.github/workflows/windows-rust.yml` |
| Language rules | [Rust standard](https://github.com/SensorsIot/harness/blob/main/lang/rust/standard.md) |
| Security | [principles](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/security.md) |
| Testing | [testing](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/testing.md); suites in `.harness/suites.yaml` |
| Change and harness-improvement reports; restart checkpoints | [Reporting](https://github.com/SensorsIot/harness/blob/main/core/docs/CR-Reporting.md); shared harness overview: `python harness/core/tools/report_cr.py --harness --root harness` |
| Parallel issue workspaces and supervised sub-agents | [Parallel work](../../harness/core/docs/Parallel-Work.md); `python harness/core/tools/parallel.py status` |
| Writing functional SysML models | [SysML v2 authoring](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/sysml-v2.md) |
| How an agent session works with the operator | [Agent working rules](Agent-Working-Rules.md) |
| Prohibitions (index) | [Do-Not-Do](Do-Not-Do.md) |
| Escapes | [Escapes ledger](Escapes-Ledger.md) |
| Backlog | [GitHub issues](https://github.com/SensorsIot/wsjtx-rust/issues); rules in [Backlog](#backlog) |

## Bindings

The reusable general process is in `harness/core/`; Rust rules and compiler checks are
in `harness/lang/rust/`. Project configuration is in `.harness/`, and project-specific
environment, build and model-maintenance instructions are in [Project specifics](Project-Specifics.md).

- **Main branch:** `master`; the push gate compares against `origin/master`.
- **Execution mode:** local. The Windows PC is authoritative for compiler checks,
  selected functional groups including their required bandwidth measurements, and release
  packaging. The local pre-push hook enforces the ordinary gate. GitHub Actions has
  only a manual trigger and is an explicit alternative when requested, not a second
  automatic build after a local pass.
- **Configuration:** `execution_mode: local` in `.harness/config.yaml` selects local
  gate execution. The manual-only hosted workflow supplies the alternative location
  when explicitly selected; it does not add a routine second run.
- **Test selection:** explicit file owners and downstream functional dependencies in
  `.harness/suites.yaml`; see [functional test selection](Project-Specifics.md#functional-test-selection).
  Shared or unmapped changes select broader checks. `--plan` explains the selection;
  `--full` executes every eligible group without memo reuse.
- **Deploy:** a locally built Windows release executable ([Project specifics](Project-Specifics.md));
  the dry run uses that candidate on this PC. The manual hosted alternative can provide
  the same evidence when explicitly chosen instead.
- **Live tests:** none yet. Tests that need a radio, a sound device or the network are
  cost 3–5, marked `#[ignore]`, and get their own suites.

## Harness paths

Isolated tests may start disposable loopback servers, browsers, TLS endpoints and link
simulators at level 2. This project binding distinguishes test networking from live
station or external-service access, which remains level 3–5. Communication tests run
with `npm test` after `npm ci`, `npx playwright install chromium` and `cargo build --locked`.
The link simulator accounts for actual encrypted-stream bytes plus modelled transport
overhead; it is not an on-wire packet capture or a physical-network certification.
The simulator disconnects a peer whose pending delivery bytes plus destination write
buffer exceed 128 KiB; it does not emulate arbitrary congestion queues.

The paths a harness change may touch; everything else is product:

- `harness/` (the submodule: its pinned version; fixes are made inside it)
- `.harness/`
- `docs/harness/`, `AGENTS.md`, `CLAUDE.md`, `.claude/` (the agent guard and skill entrypoints)
- `deny.toml` (the `rust-supply-chain` pack's licence and source policy)
- `.github/ISSUE_TEMPLATE/`
- `.github/workflows/rust-advisories.yml` (the pack's scheduled advisories sensor)
- `.gitmodules` (the harness submodule's URL and branch; it holds only that submodule, and adding
  another submodule is a product change)

They are declared as `harness_paths` in `.harness/config.yaml`: a push that changes only
these paths is a harness change, reviewed and not gated.

Maintained with the harness but inputs of product suites, so a change to them is gated
as a CR: `.github/workflows/windows-rust.yml` (the CI build), `tools/sysml.py` and
`tools/sysml/` (authority/trace checks, semantic validation and product contract oracles
such as coverage tables and property tests).
`.github/workflows/fortran-stage-diagnostics.yml` is product diagnostic tooling. A reviewer of a `deny.toml` change runs `cargo deny --locked --workspace check bans
licenses sources`, since the gate does not. The `rust-supply-chain` pack's
advisories sensor is `.github/workflows/rust-advisories.yml`: weekly and on demand, read-only,
it runs `cargo deny --locked --workspace check advisories`. A red run is GitHub's failed-workflow
notice to the operator (the user who last edited the schedule); it names the crate and the advisory, and the fix is a CR.

## Documentation is current-state

The [exclusive authority binding](Project-Specifics.md#exclusive-functional-authority)
selects one functional authority. With the canonical model declaration and archived
functional Markdown, SysML alone owns product requirements, behaviour, architecture,
interfaces and durable verification definitions. Retired Markdown is historical and is
not edited, regenerated or read by the active workflow. Harness instructions, skills,
standards, process, build and gate documentation remain Markdown.

For each functional issue follow the [required sequence](Project-Specifics.md#required-sequence-for-functional-issues):
settle the canonical requirements and independent verification expectations, obtain
meaning/readiness review, implement against the reviewed model and verify with independent
oracles. Reconcile delivered functionality, source bindings and durable cases before
manual issue closure. A test's presence, actual execution and live acceptance are distinct.

The [model catalog](../sysml/Requirements.sysml) owns stable FR/CL/TC identities and
functional verification definitions. Executable assertions and fixture data remain linked
companions. Protocol, states, errors and bounds are in the responsible model packages,
not duplicated into another active specification. Product-specific tests and additive
execution wiring remain with their functional CR; reusable method changes follow the
harness rollout process.

CL-014 and TC-DOC are HOW bindings in
[Project specifics](Project-Specifics.md#project-model-documentation-contract), not product
SysML. Full parsing/name checking, architecture integrity and trace checks do not prove
behavioural equivalence or implementation readiness; independent review and relevant
application tests supply that evidence.

The active canonical contract and these bindings state the rule that holds now, never
its history ([documentation](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/documentation.md)).
Open work and review/execution evidence live in GitHub issues; history is `git log`.

## Backlog

GitHub issues of `SensorsIot/wsjtx-rust` are the project's one to-do list.

- **Labels say how:** `cr`, `harness`, `efficiency` or `operator-task`; `waiting`
  is added to any of them.
- **Types say what:** `Bug`, `Feature`, `Task`.
- **Ageing:** an open issue is overdue 30 days after it was created; a `waiting` issue
  never ages and names what it waits for.
- **Priority:** prerequisites first, then `Bug`, then `Task`, then `Feature`; within
  a type, the oldest first.
