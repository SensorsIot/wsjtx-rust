# Harness reference index

The build procedure is the [CR process](https://github.com/SensorsIot/harness/blob/V2/core/docs/CR-Process.md); method changes
follow [Harness changes](https://github.com/SensorsIot/harness/blob/V2/core/docs/Harness-Changes.md). The FSD is the product
contract; the references below are the constraints a change must respect.

| Subject | Reference |
|---|---|
| Product contract | [WSTX Rust FSD](../WSTX%20Rust%20FSD.md) |
| Product component/interface boundaries | [Target architecture](../ARCHITECTURE.md) |
| Product SysML artifacts and view scope | [Architecture model](../ARCHITECTURE.md#11-functional-model-and-views) |
| Behavior baseline and provenance | [FSD](../WSTX%20Rust%20FSD.md), [Samples](../SAMPLES.md); notices in [README](../../README.md#license-and-attribution) |
| Project-specific environment, build and model validation | [Project specifics](Project-Specifics.md), `.github/workflows/windows-rust.yml` |
| Language rules | [Rust standard](https://github.com/SensorsIot/harness/blob/V2/lang/rust/standard.md) |
| Security | [principles](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/security.md) |
| Testing | [testing](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/testing.md); suites in `.harness/suites.yaml` |
| Writing functional SysML companions | [SysML v2 authoring](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md) |
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
  the full automated suite including the 60-second bandwidth measurement, and release
  packaging. The local pre-push hook enforces the ordinary gate. GitHub Actions has
  only a manual trigger and is an explicit alternative when requested, not a second
  automatic build after a local pass.
- **Configuration:** `execution_mode: local` in `.harness/config.yaml` selects local
  gate execution. The manual-only hosted workflow supplies the alternative location
  when explicitly selected; it does not add a routine second run.
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
- `docs/harness/`, `AGENTS.md`, `CLAUDE.md`
- `.github/ISSUE_TEMPLATE/`
- `.github/workflows/` (the CI build)

## Documentation is current-state

The Markdown FSD remains authoritative. Only functional product documentation has a
SysML companion: requirements, product behavior, architecture/interfaces and verification
cases. Harness instructions, skills, workflows, standards and gate documentation remain
Markdown. The harness authoring chapter explains how to write product models; the harness
itself is not modeled in SysML.

The [FSD](../WSTX%20Rust%20FSD.md#61-browser-and-server-test-catalogue) owns this project's
stable functional clauses and test descriptions. Test source holds executable assertions
and promise tags; issues retain change approval and execution evidence. This explicit
operator binding overrides the generic preference to keep test descriptions next to
the test source. Detailed protocol fields, errors and limits remain canonical in the
FSD's linked communication contract rather than being repeated across the documents.
Product-specific acceptance tests, fixtures and the provisioning/wiring needed to run
them belong to the functional CR they verify. Changes to the reusable development method
belong to harness work; adding browser and thin-link verification for FR-019/FR-021 is
functional verification rather than a separate harness improvement.

Documentation-maintenance clauses CL-014 and tool cases TC-DOC are HOW bindings in
[Project specifics](Project-Specifics.md#project-model-documentation-contract). They
remain Markdown-only. The FSD owns application functionality and its durable acceptance
cases; the product SysML represents that functional contract and the declared architecture.

The FSD, its companions and these bindings state the rule that holds now, never the path
to it ([documentation](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/documentation.md)). Open work lives in
GitHub issues; history is `git log`.

## Backlog

GitHub issues of `SensorsIot/wsjtx-rust` are the project's one to-do list.

- **Labels say how:** `cr`, `harness`, `efficiency` or `operator-task`; `waiting`
  is added to any of them.
- **Types say what:** `Bug`, `Feature`, `Task`.
- **Ageing:** an open issue is overdue 30 days after it was created; a `waiting` issue
  never ages and names what it waits for.
- **Priority:** prerequisites first, then `Bug`, then `Task`, then `Feature`; within
  a type, the oldest first.
