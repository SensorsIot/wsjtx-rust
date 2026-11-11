# Agent working rules


**Status:** present-state. **Layer:** HOW. **Scope:** WSTX Rust bindings.

How an AI agent session works with the operator on this project. The build procedure is
the [CR process](../../harness/core/docs/CR-Process.md); this page holds the standing
rules around it. Agent memory only points here.

## Who changes what

- **One repository leader.** Repository changes (commits, hand-ins to the
  [merge queue](../../harness/core/docs/Merge-Queue.md), harness pushes) come from one
  session at a time; another session reads, copies and reports. A CR reaches the main
  branch through the queue (the single exception the merge queue document names aside).
- **Heavy runs yield to the gate by priority.** A long build or test run outside the gate
  runs at BelowNormal with 2 build jobs beside the gate, without waiting for `busy`, and
  reruns a timing-sensitive failure once before treating it as real.
- **Pushing and hand-in** follow the core: only the merge queue pushes CRs, and a CR agent
  hands in at once after red on the parent and the fast checks
  ([CR process](../../harness/core/docs/CR-Process.md#steps), steps 2-4). This project's
  cheap contract check among them is `python tools/sysml.py traces`.
- **Per approved issue.** A session changes the main branch or the running installation
  only for an issue the operator has approved for it, each issue on its own; the approval
  is recorded on that issue. Without it the session writes the change text (outcome,
  changes, acceptance, evidence) and the operator implements it.
- **Another person's checkout** is never touched.
- **Development placement.** Follow [machines and roles](Project-Specifics.md#machines-and-roles): the two PCs have no roles and either does any work; HB9BLA is needed for what needs the transceiver, and both for a test of client and server across the network. The issue's `owner:` label names the machine building it. Shared model ownership, integration and publication remain serialized across both PCs.

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
  and edits nothing. It may run the tests of what changed and of its surroundings to reproduce a
  finding ([CR process step 3](../../harness/core/docs/CR-Process.md#steps)), never the whole suite
  or a gate.

## GitHub issues are the memory

- An issue holds a change's request, rationale, current status, settled questions,
  required review and acceptance records, actual run evidence, the closing summary
  and outstanding approved scope.
  Findings follow [intake](../../harness/core/docs/CR-Process.md#intake-and-authorization).
  Continuation state uses the bounded [checkpoint](../../harness/core/docs/CR-Reporting.md#restart-and-handoff-checkpoint).
  Required evidence lives in these records, rather than only in a session or chat;
  the issue is not a running diary.
- **Records are cited as read.** A comment, commit, run or other record is cited by the
  id, sha or url read from its source (`gh api repos/<owner>/<repo>/issues/<n>/comments --jq '.[] | .html_url'`,
  `git log`, `gh run list`), never from memory.
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

## Agent role additions

This project's layer of the [agent roles](../../harness/core/agents/roles.md), the coordinator
included, installed with `python harness/core/tools/install_skills.py --project . --host claude --skill harness --skill documentation --skill domain-modeling --skill coordinator --skill grill-me --skill sysml-authoring --skill test-design --skill conformance-review --skill improvement --skill fsd-from-model --skill restructuring --agent definer --agent checker --agent coder --agent reviewer --agent harness-improver --agent tester --agent prober --agent explainer`.

### Role: definer

```yaml
guard:
  writes: [".git/harness-parallel/worktrees/*/docs/**"]
```

The model is under `docs/sysml/`; its checks are the `sysml.py` commands of
[model authoring and validation](Project-Specifics.md#model-authoring-and-validation),
run in an issue worktree by the worktree path rule under "Role: every" below.
A browser control that writes to the radio or keys it states what it does before its
scripts have loaded over the 32 kbit/s link and after they fail to load.

### Role: checker

```yaml
guard:
  commands:
    - 'gh issue comment [0-9]+ --body ''Ready: (PASS|not yet)(\n[^'']*)?'''
```

The checker posts its verdict as its own issue comment, in the posting form under
"Role: every" below. Its first line is exactly `Ready: PASS` or `Ready: not yet`, as the
[ready check](../../harness/core/docs/CR-Process.md#ready-check) says; the hook refuses any
other first line.

### Role: coder

```yaml
guard:
  commands:
    - 'node --test( --test-concurrency=1| --test-name-pattern=([\[\]A-Za-z0-9_.,:^+=/-]+|''[^'']+'')){0,2}( \.git/harness-parallel/worktrees/(cr|issue-)[A-Za-z0-9._-]+(/(?!\.\.?(?=[/\s]|$))[A-Za-z0-9_.@+-]+)+)+'
    - 'python (\.git/harness-parallel/worktrees/(cr|issue-)[A-Za-z0-9._-]+/)?fixtures/transmit/generate\.py( --(bin|compare-bin|ft4sim) C:/WSJT/[A-Za-z0-9._/-]+)+'
  deny:
    - '^(?!(python3?|py)(\.exe)? \S*red_on_parent\.py )(?!(NODE_PATH=D:/Github/wsjtx-rust/node_modules )?(WSTX_TEST_EXE=D:/wstx-build/(?P<wt>(cr|issue-)(?=[A-Za-z0-9_-])[A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)*)/debug/wstx-rust\.exe (?!.*worktrees/(?!(?P=wt)/)))?node ).*\bnode\s+--test'
```

- **Builds and tests** use the build and temp folders of the
  [HB9BLA handover](HB9BLA-HANDOFF.md#inputs-and-unfinished-work) and run beside the gate
  as [heavy runs yield to the gate](Agent-Working-Rules.md#who-changes-what) says, a timing failure rerun once.
  In the hook's one-command form: `CARGO_TARGET_DIR=D:/wstx-build/<worktree>
  TEMP=D:/wstx-build/<worktree> TMP=D:/wstx-build/<worktree> CARGO_BUILD_JOBS=2 nice -n 10
  cargo test --manifest-path .git/harness-parallel/worktrees/<worktree>/Cargo.toml …`;
  under Git Bash `nice -n 10` is BelowNormal. Node tests run as
  `NODE_PATH=D:/Github/wsjtx-rust/node_modules
  WSTX_TEST_EXE=D:/wstx-build/<worktree>/debug/wstx-rust.exe node --test
  --test-concurrency=1 --test-name-pattern=<pattern>
  .git/harness-parallel/worktrees/<worktree>/<test file> …`: each prefix and both options
  optional, the two prefixes in that order and no other, the pattern bare (letters, digits,
  brackets and `_.,:^+=/-`) or in single quotes without a `'`. A test file may also be named
  from a session inside the worktree or by its absolute path. `WSTX_TEST_EXE` (read by
  `tests/support.cjs`) runs the tests on the role's own build; its `<worktree>` is the one
  every test file of the command lies in.
- **Oracle generator and node red on the parent** (harness#44): the coder runs the WSJT-X
  vector generator itself, from the project folder with the worktree path and only reference
  binaries under `C:/WSJT/` (`python .git/harness-parallel/worktrees/<worktree>/fixtures/transmit/generate.py
  --bin … --compare-bin …`, then `--ft4sim …`), and proves a Node test red on the parent through
  `red_on_parent.py … -- bash -c "cargo build --locked --bin wstx-rust && NODE_PATH=D:/Github/wsjtx-rust/node_modules
  node --test --test-concurrency=1 --test-name-pattern=<pattern> tests/<file>"` without `WSTX_TEST_EXE`, so
  the tests run on the build of the temporary tree (its pack `CARGO_TARGET_DIR`).
- **Delivery facts** in the model are a requirement's `coverage`, a case's `automation`
  and its `executable` binding
  ([source bindings](Project-Specifics.md#canonical-model-catalog-and-source-bindings));
  the hook refuses any other model line.
- **Proves tags:** this project's tag syntax for test-design step 5 is a `// Proves: <ID>`
  comment, on a real `#[test]` (or Node `test(...)`) that exercises the promise, never on
  a helper, a module or a `#[cfg(test)]` block.

### Role: reviewer

```yaml
guard:
  commands:
    - 'node --test( --test-concurrency=1| --test-name-pattern=([\[\]A-Za-z0-9_.,:^+=/-]+|''[^'']+'')){0,2}( \.git/harness-parallel/worktrees/(cr|issue-)[A-Za-z0-9._-]+(/(?!\.\.?(?=[/\s]|$))[A-Za-z0-9_.@+-]+)+)+'
  deny:
    - '^(?!(NODE_PATH=D:/Github/wsjtx-rust/node_modules )?(WSTX_TEST_EXE=D:/wstx-build/(?P<wt>(cr|issue-)(?=[A-Za-z0-9_-])[A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)*)/debug/wstx-rust\.exe (?!.*worktrees/(?!(?P=wt)/)))?node ).*\bnode\s+--test'
```

The reviewer reads the candidate as [Reviews](Agent-Working-Rules.md#reviews) says, runs Node tests in the
coder's form above, and posts its verdict in the
posting form under "Role: every" below.

### Role: harness-improver

```yaml
guard:
  deny:
    - '\s(--repo(?=[\s=]|$)|-R)(?!\sSensorsIot/harness(\s|$))'
```

The harness-improver posts on a harness issue in the posting form under "Role: every"
below, with `--repo SensorsIot/harness` between the number and `--body`; the hook refuses
any other repository, for reading too.

### Role: tester

```yaml
guard:
  commands:
    - '(powershell|pwsh)(\.exe)? -NoProfile -ExecutionPolicy Bypass -File (D:/wstx-tmp/live/[0-9]+/[A-Za-z0-9_-]+|\.harness/deploy/(radio-preflight|live-page-check))\.ps1( .*)?'
  writes: ["D:/wstx-tmp/live/**"]
```

The live-test binding is [Preserve the runtime](HB9BLA-HANDOFF.md#preserve-the-runtime):
the radio preflight and its lease before keying, the power the test sets, the bands, no
abort at or after RR73 or 73, a contact you did not start, and the settings a cost-4/5
test sets back. A run writes under `D:/wstx-tmp/live/<issue>/`
([limits for experiments](Project-Specifics.md#limits-for-experiments)): its log, and its
scripts, which act on the station only through the station client
`.git/harness-parallel/resources/station-update/agent-client.ps1` (dot-sourced:
`Open-AgentSession`, `Agent-Get`, `Agent-Post`). It runs them, and the radio preflight or
the live page check, as
`powershell -NoProfile -ExecutionPolicy Bypass -File D:/wstx-tmp/live/<issue>/<name>.ps1 …`
or `… -File .harness/deploy/radio-preflight.ps1 -Holder <run> -PowerBcd <value>`. It
installs nothing and restarts the station only through those deploy scripts.

### Role: prober

```yaml
guard:
  commands:
    - '(python|py)(\.exe)? D:/wstx-tmp/experiments/[0-9]+/[A-Za-z0-9_-]+\.py( .*)?'
    - '(powershell|pwsh)(\.exe)? -NoProfile -ExecutionPolicy Bypass -File D:/wstx-tmp/experiments/[0-9]+/[A-Za-z0-9_-]+\.ps1( .*)?'
  writes: ["D:/wstx-tmp/experiments/**"]
```

The experiment folder is `D:/wstx-tmp/experiments/<issue>/`, within the
[limits for experiments](Project-Specifics.md#limits-for-experiments); its scripts run as
`python D:/wstx-tmp/experiments/<issue>/<name>.py …` or
`powershell -NoProfile -ExecutionPolicy Bypass -File D:/wstx-tmp/experiments/<issue>/<name>.ps1 …`.
They read recordings, logs and the code; they do not use the station client, open COM3 or
key the radio: that is a live test for the tester.

### Role: every

```yaml
guard:
  commands:
    - 'python (\.git/harness-parallel/worktrees/[A-Za-z0-9._-]+/)?tools/sysml\.py (check|traces|fingerprints|markers( [A-Za-z]+)*)'
```

The [agent working rules](Agent-Working-Rules.md) hold for every role. Gate build folders
are on D: (`gate.cargo_target_root` in `.harness/config.yaml`); a role's own build folders
are the coder's above.

- **Worktree paths.** A role's session folder is the project folder, and a change of folder
  is refused. In an issue worktree, run each command from the project folder with the
  worktree's path in it: `python .git/harness-parallel/worktrees/cr39-holdtx/tools/sysml.py check`
  (the tool checks the repository it lives in), `git -C .git/harness-parallel/worktrees/cr39-holdtx status`,
  `cargo test --manifest-path .git/harness-parallel/worktrees/cr39-holdtx/Cargo.toml`, and
  write its files by that path.
- **Posting form.** A role that posts on an issue uses exactly
  `gh issue comment <number> --body '<text>'`: single quotes, no `'`, `$` or backticks in the
  text, no `--body-file`, and no `--repo` on this project's issues (the harness-improver's
  harness issues above are the one exception).
