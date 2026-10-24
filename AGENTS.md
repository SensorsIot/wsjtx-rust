# Working in this repository

This project uses the harness (https://github.com/SensorsIot/harness, branch `V2`),
installed for the user at `~/.claude/skills/harness` as the `harness` skill. Where its
documents write `harness/`, read `~/.claude/skills/harness/`.

- Product changes follow its CR process (`core/docs/CR-Process.md`); changes to how the
  project is built, tested or gated follow its Harness changes (`core/docs/Harness-Changes.md`).
- The constraints a change must respect are indexed in
  [docs/harness/Harness-Overview.md](docs/harness/Harness-Overview.md). Read only the parts
  relevant to the task.
- Once per clone: `python3 ~/.claude/skills/harness/core/tools/install_hooks.py`.
