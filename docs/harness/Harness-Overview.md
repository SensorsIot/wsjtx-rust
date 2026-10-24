# Harness reference index

The build procedure is the [CR process](https://github.com/SensorsIot/harness/blob/V2/core/docs/CR-Process.md); method changes
follow [Harness changes](https://github.com/SensorsIot/harness/blob/V2/core/docs/Harness-Changes.md). The FSD is the product
contract; the references below are the constraints a change must respect.

| Subject | Reference |
|---|---|
| Product contract | [WSTX Rust FSD](../WSTX%20Rust%20FSD.md) |
| Upstream relation and provenance | [Upstream](../UPSTREAM.md), [Samples](../SAMPLES.md) |
| Build environment and CI | [Building](../BUILDING.md), `.github/workflows/windows-rust.yml` |
| Language rules | [Rust standard](https://github.com/SensorsIot/harness/blob/V2/lang/rust/standard.md) |
| Security | [principles](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/security.md) |
| Testing | [testing](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/testing.md); suites in `.harness/suites.yaml` |
| How an agent session works with the operator | [Agent working rules](Agent-Working-Rules.md) |
| Prohibitions (index) | [Do-Not-Do](Do-Not-Do.md) |
| Escapes | [Escapes ledger](Escapes-Ledger.md) |
| Backlog | [GitHub issues](https://github.com/SensorsIot/wsjtx-rust/issues); rules in [Backlog](#backlog) |

## Bindings

- **Main branch:** `master`; the push gate compares against `origin/master`.
- **Deploy:** a release build of the Windows executable ([Building](../BUILDING.md));
  the dry run is the CI run of the candidate.
- **Live tests:** none yet. Tests that need a radio, a sound device or the network are
  cost 3–5, marked `#[ignore]`, and get their own suites.

## Harness paths

The paths a harness change may touch; everything else is product:

- `.harness/`
- `docs/harness/`, `AGENTS.md`, `CLAUDE.md`
- `.github/ISSUE_TEMPLATE/`
- `.github/workflows/` (the CI build)

## Documentation is current-state

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
