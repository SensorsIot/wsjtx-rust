# Working in this repository

For the container transfer, first read [the handoff and project memory](docs/harness/MEMORY.md).
It records the last verified state and skills setup; current contracts and GitHub issues
remain authoritative. Recheck repository state before continuing.

This project uses the harness (https://github.com/SensorsIot/harness, branch `V2`) as a
git submodule at `harness/`. That copy is the version this project pins and the place
the harness is maintained; use it, not the user-level `harness` skill.

- Product changes follow [CR process](harness/core/docs/CR-Process.md); changes to how the
  project is built, tested or gated follow [Harness changes](harness/core/docs/Harness-Changes.md).
  A gap in the harness itself is fixed inside `harness/` (Harness changes, "Improving the
  harness from a project").
- The constraints a change must respect are indexed in
  [docs/harness/Harness-Overview.md](docs/harness/Harness-Overview.md). Read only the parts
  relevant to the task.
- Once per clone: `git submodule update --init`, then
  `python3 harness/core/tools/install_hooks.py`, and the same inside the submodule
  (`cd harness && python3 core/tools/install_hooks.py`) for its own gate.
