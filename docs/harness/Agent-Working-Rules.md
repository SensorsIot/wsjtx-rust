# Agent working rules


**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings.

How an AI agent session works with the operator on this project. The build procedure is
the [CR process](https://github.com/SensorsIot/harness/blob/main/core/docs/CR-Process.md); this page holds the standing
rules around it. Agent memory only points here.

## Who changes what

- **One repository leader.** Repository changes (commits, pushes to the main branch)
  come from one session at a time; another session reads, copies and reports.
- **Per approved issue.** A session changes the main branch or the running installation
  only for an issue the operator has approved for it, each issue on its own; the approval
  is recorded on that issue. Without it the session writes the change text (outcome,
  changes, acceptance, evidence) and the operator implements it.
- **Another person's checkout** is never touched.
- **Development placement.** Application implementation, builds and radio acceptance run on HB9BLA. This PC may prepare issues and execute the approved model/authority transition in isolated worktrees. Shared model ownership, integration and publication remain serialized across both PCs.

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
- A reviewer works in a plain copy of the candidate (`git archive <rev> | tar -x`).

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
