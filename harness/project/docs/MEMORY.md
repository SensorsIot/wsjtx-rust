# Current project memory

**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings.

Pointers only: every rule and fact lives in the document named here, and the current state
lives in Git and the GitHub issues. Recheck them before continuing.

- **Start:** [AGENTS.md](../../../AGENTS.md), then the `harness-coordinator` skill (the main
  session's role) and the [Harness Overview](Harness-Overview.md).
- **Product authority:** the [functional authority binding](specifics/product-model-maintenance.md#exclusive-functional-authority);
  entry point `docs/sysml/Requirements.sysml`.
- **Machine and its runtime locations:** [HB9BLA](specifics/machine.md#machine), the
  factory's one PC.
- **Test inputs and build folders:** [Inputs](specifics/local-windows-development.md#inputs).
- **Keying the radio:** [Keying the radio](specifics/deployment-authority.md#keying-the-radio),
  [standing consent at 1 %](specifics/deployment-authority.md#standing-consent-at-1-) and
  [simulator live tests](specifics/deployment-authority.md#simulator-live-tests).
- **Deploy:** the one deploy line, its exits and the standing deploy policy:
  [deployment authority](specifics/deployment-authority.md#deployment-authority).
- **Merge queue worker:** [Merge queue](specifics/merge-queue.md#merge-queue).
- **Taking a new harness pin on this clone:** [every clone takes the pin](../../general/core/docs/Harness-Changes.md#every-clone-takes-the-pin).
- **Where every CR stands:** `python harness/general/core/tools/cr_state.py status` and
  `python harness/general/core/tools/merge_queue.py status`.
- **Open work and decisions:** the open issues and their newest comments; a paused CR's
  [checkpoint](../../general/core/docs/CR-Reporting.md#restart-and-handoff-checkpoint)
  names its next action and owner.
- **The harness layout:** [Layout](Harness-Overview.md#layout).
