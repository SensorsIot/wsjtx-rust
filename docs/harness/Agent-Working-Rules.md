# Agent working rules


**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings.

How an AI agent session works with the operator on this project. The build procedure is
the [CR process](https://github.com/SensorsIot/harness/blob/main/core/docs/CR-Process.md); this page holds the standing
rules around it. Agent memory only points here.

## Who changes what

- **One repository leader.** Repository changes (commits, hand-ins to the
  [merge queue](../../harness/core/docs/Merge-Queue.md), harness pushes) come from one
  session at a time; another session reads, copies and reports. A CR reaches the main
  branch through the queue (the single exception the merge queue document names aside).
- **Heavy runs wait for the gate.** Before a long build or test run outside the gate, a
  session runs `merge_queue.py busy --wait`, so that it does not compete with a gate.
- **CR agents never push.** A CR agent never runs `git push`, not even of its own branch;
  only the merge queue pushes CRs, and harness and pin bumps are pushed by the coordinator
  or a dedicated harness agent from the main checkout or another clone (the agent guard
  refuses any push from a `.git/harness-parallel/worktrees/cr*` or `issue-*` worktree).
- **Hand in at once, do not duplicate the gate.** A CR agent ends its work with red on the
  parent and the fast checks (build, clippy and fmt, the new and changed tests, the cheap
  contract check `python tools/sysml.py traces`); the full suite selection runs once, in
  the queue's gate. A reviewed CR, and each reviewed slice of a multi-slice CR, is handed
  in to the queue at once; the next slice starts from master, never stacked on a
  long-lived branch. Master is merged into a CR only on a `bounced:conflict`, resolving
  only the listed files, and that merge is re-reviewed on its resolution only
  (`harness/core/tools/resolution_diff.py <merge>`).
- **Per approved issue.** A session changes the main branch or the running installation
  only for an issue the operator has approved for it, each issue on its own; the approval
  is recorded on that issue. Without it the session writes the change text (outcome,
  changes, acceptance, evidence) and the operator implements it.
- **Another person's checkout** is never touched.
- **Development placement.** Follow [machines and roles](Project-Specifics.md#machines-and-roles): application implementation, builds, installs, live tests and radio acceptance run on HB9BLA, where the product and the transceiver are; PC Andreas does SysML model work in isolated worktrees, and documentation work. The issue's `owner:` label names the machine building it. Shared model ownership, integration and publication remain serialized across both PCs.

## Deciding

- **Decide from the implementation.** Before asking, check code, configuration and live
  read-only state. When they settle the question and the behaviour is sound, decide,
  record the evidence in the commit body and continue. Ask only when the implementation
  is silent, inconsistent or looks wrong: one question at a time, with evidence and a
  recommendation.
- **Ask design questions before implementing**, not during review.
- **No workarounds.** A red gate, a refused procedure or a denied command is not routed
  around: the gate override only when the operator decides; no stubbed environment; no
  retry of a denied action in another form. Finish what does not depend on it, then
  report the blocker and the sanctioned fix.
- **Remedies are not rules.** One-time cleanup, repair and migration tasks are tracked as
  issues; they never become promises, harness rules or skills.

## Reviews

- Every repair gets the review step 3 of the CR process sets. After 10 review rounds on
  one change the session stops and asks the operator whether to continue.
- A reviewer reads the candidate (`git show`, or a plain copy made with `git archive <rev> | tar -x`)
  and builds or runs nothing; the author runs a reproduction the reviewer writes out.

## GitHub issues are the memory

- An issue holds a change's request, rationale, current status, settled questions,
  required review and acceptance records, actual run evidence, the closing summary
  and outstanding approved scope.
  Findings follow [intake](../../harness/core/docs/CR-Process.md#intake-and-authorization).
  Continuation state uses the bounded [checkpoint](../../harness/core/docs/CR-Reporting.md#restart-and-handoff-checkpoint).
  Required evidence lives in these records, rather than only in a session or chat;
  the issue is not a running diary.
- **Written for a person.** The title states the problem in plain words; the body opens
  with the problem, the decision or task and a status checklist, readable on a phone.
  Commits, test IDs and paths go below, in a collapsed
  `<details><summary>Technical details</summary>` section.

## Secrets

- A secret's value is never printed, not even through a filter meant to mask it.
  Presence and change are checked by counts, labels and modification time; a value is
  used inside a program without being echoed.
- Tests get secrets through the project's secret wrapper.

## This project

- Development and builds run on Windows (x86_64-pc-windows-msvc), with the toolchain of
  `rust-toolchain.toml` ([Project specifics](Project-Specifics.md)).
- Upstream WSJT-X (`upstream` remote) is read for reference only; nothing is pushed there.
