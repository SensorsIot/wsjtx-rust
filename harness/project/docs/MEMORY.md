# Current project memory

Pointers only: every rule and fact lives in the document named here, and the current state
lives in Git and the GitHub issues. Recheck them before continuing.

- **Start:** [AGENTS.md](../../AGENTS.md), then the `harness-coordinator` skill (the main
  session's role) and the [Harness Overview](Harness-Overview.md).
- **Product authority:** the [functional authority binding](Project-Specifics.md#exclusive-functional-authority);
  entry point `docs/sysml/Requirements.sysml`.
- **Machines:** [machines and roles](Project-Specifics.md#machines-and-roles); the issue's
  `owner:` label names the machine building it.
- **Runtime and data locations on HB9BLA:** [HB9BLA handover](HB9BLA-HANDOFF.md).
- **Taking a new harness pin on this clone:** [every clone takes the pin](../../harness/core/docs/Harness-Changes.md#every-clone-takes-the-pin).
- **Where every CR stands:** `python harness/core/tools/cr_state.py status` and
  `python harness/core/tools/merge_queue.py status`.
- **Open work and decisions:** the open issues and their newest comments; a paused CR's
  [checkpoint](../../harness/core/docs/CR-Reporting.md#restart-and-handoff-checkpoint)
  names its next action and owner. Deployed source: the issue checkpoint and the private
  runtime receipt, never a remembered version.
