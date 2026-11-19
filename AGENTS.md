# Working in this repository

The main session (the coordinator) first reads [the handoff and project memory](harness/project/docs/MEMORY.md);
a sub-agent role skips it. It records the last verified state and skills setup; current
contracts and GitHub issues remain authoritative. Recheck repository state before continuing.

Everything under `harness/` is the harness. This project uses the general harness
(https://github.com/SensorsIot/harness, branch `main`) as a git submodule at
`harness/general/`; that copy is the version this project pins and the place the harness is
maintained; use it, not the user-level `harness` skill. The project's own part of the harness,
its project harness, is `harness/project/`.

- The main session is the coordinator: load the `harness-coordinator` skill first. It is
  composed from the [coordinator role](harness/general/core/agents/roles.md#role-coordinator) and
  this project's additions.
- Read the [functional authority binding](harness/project/docs/Project-Specifics.md#exclusive-functional-authority) before contract edits. Canonical SysML is edited directly. Harness/process documentation stays Markdown.
- Product changes follow [CR process](harness/general/core/docs/CR-Process.md); changes to how the
  project is built, tested or gated follow [Harness changes](harness/general/core/docs/Harness-Changes.md).
  A gap in the harness itself is fixed inside `harness/general/` (Harness changes, "Improving the
  harness from a project"). Harness changes have no review and no gate; use and the
  improvement retrospective judge them.
- The constraints a change must respect are indexed in
  [harness/project/docs/Harness-Overview.md](harness/project/docs/Harness-Overview.md). Read only the parts
  relevant to the task.
- A new clone is set up by the operator ([Local Windows development](harness/project/docs/Project-Specifics.md#local-windows-development)).
