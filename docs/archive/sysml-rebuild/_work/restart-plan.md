# From the rebuild to production

Operator 2026-11-17: an updated master, an updated model, an updated Goldratt factory and the old
stuff removed; then production starts again. Order (operator 2026-11-18): #235 whole, now,
driven by hand, so that the model reaches master; the factory's polish (the sweep, the branches,
Alex's configuration, #172, MEMORY) is prepared alongside by read-only agents and done after it;
then harness change 2; then production. No implementer session runs in parallel.

**The goal** (operator 2026-11-18): "an absolutely clean and polished master where Alex likes to
work and the quality of the output is marvelous". Done means: master holds the present only (no
history, no stale issue, branch or worktree), the model meets every rule of the finished model and
the gate checks all of them, every open issue is current against the model, and Alex's work order
names only current work.

Each step is one of three kinds (operator 2026-11-17: "distinguish between harness issues and
product issues; harness issues can be managed much simpler"):

- **H, harness issue:** only harness paths (`harness/`, `.claude/`, `.github/ISSUE_TEMPLATE/`,
  `AGENTS.md`, `CLAUDE.md`). An issue labelled `harness`, one commit `Harness: … (#N)`, the push
  when the merge queue is idle, the rollout comment, closed. No states, no definer, no review,
  no gate.
- **P, product issue (CR):** any other path (the model, the code, the tests, `tools/`). The full
  lifecycle with `cr:` states.
- **–, no issue:** bookkeeping and housekeeping.

| Step | Kind |
|---|---|
| #233, #234 (done) | H |
| Phase 2 (first): #235, model, tool, tests, tags, by hand | P |
| Phase 1.1: issue sweep | – (the operator's decisions per issue; harness issues in a short list of their own) |
| Phase 1.2: branches and worktrees | – |
| Phase 1.3: Alex's configuration, #172, the meter's baseline | H |
| Phase 1.4: MEMORY's "Inputs and unfinished work" | H |
| Phase 1.5: every branch and worktree resolved, master alone | – (valid work through its issue) |
| Phase 1.6: historical files and passages off master | H for harness paths, P for product paths |
| Phase 3: harness change 2 | H |
| Phase 4: production | P |

## Phase 1: polish the factory (–, H; nothing deleted before it is checked)

1. Issue sweep: the open issues, one list for the operator, each marked done by the rebuild
   (closed with a pointer), overtaken (closed), still valid and rewritten against the new model,
   code split matched to M2.3 and `@CodeDiffers`, or kept. The harness issues (#172, #188) stand
   in a short list of their own and go through no CR state.
2. Branches and worktrees: done 2026-11-18 (operator's OK). Removed after the check for work not
   on master: cr70-slowtests, cr80-traffic, cr97-strategy (with their worktrees; cr97 also on
   GitHub), harness-issue/106, 126, 184, 203, 136 (its workspace stopped and cleaned by
   `parallel.py`, its one old-model edit discarded), backup/sysmlv2-pre-master-merge, wip-old,
   pilot/band-activity-pane (GitHub), the temporary red-on-parent worktree; #230's workspace
   entry retired. Left: cr98-contest (local, GitHub, worktree) and harness-issue/105 (GitHub),
   decided with #98 and #105 in the sweep; the merge queue's worktree; `sysmlv2-rebuild`.
3. The factory: `alex.first` in `harness/project/config.yaml` takes the new order from the sweep,
   with #235 first; its restrictions (#192) are checked. #172: its open points and its meter are
   gone through, what is done is closed, the rest stays as single issues; harness#120 stays
   upstream. The meter's baseline starts after the rebuild.
4. MEMORY's "Inputs and unfinished work" is renewed.
5. Every branch and worktree is resolved (operator 2026-11-18): work that is still valid reaches
   master through its issue, the rest is removed; the result is master alone, beside the merge
   queue's own worktree. `sysmlv2-rebuild` is tagged `archive/sysml-rebuild` and removed after
   #235 has landed.
6. Historical files and passages leave master (operator 2026-11-18): an inventory of master's
   files and of the history inside current documents (dates, issue narratives, "formerly",
   superseded copies, frozen archives, ledgers kept only as record), each removed, or kept
   where a rule needs it, with the reason.

## Phase 2 (first): #235 by hand (P)

The product CR #235, kept whole and driven by hand by the coordinator: Check (`Ready: PASS`), Implement (the coordinator: the
model's findings; the coder: the tool, its tests, the tags, the test readers; each new test red
on the parent), Review, Land through the merge queue, Install, Accept. The candidate is cut from
master and takes `docs/sysml/` from `sysmlv2-rebuild`; the rebuild's archive does not land;
`docs/archive/`, `docs/sysml/reference/` and the pending-structure list leave master with it. A
fault of the factory found on the way is a harness issue.

## Phase 3: harness change 2 (H)

The suites' select lists, the links to the new model files, the `model_bindings.py` docstring,
the sentence on the archived FSD; the three product sections leave Project-Specifics and #232
closes; skills and agents reinstalled; every clone pulls (the main checkout, the second PC).

## Phase 4: production (P)

The operator chooses the first product CRs from the rebuild's work for the code (#226, #227,
#228, #229, #225, the WSJT-X UI targets, the `@CodeDiffers` list, the code restructuring per
part under M2.3), and #231 traced once to the new model.

## Factory review, 2026-11-18 (read only)

Findings: a stale Alex runs since 2026-11-15 (PID 49084, `harness/core/tools/alex.py`, a path
gone since #230; it read its settings once and holds the lock); runs ended by the host's usage
limit become "no output" stops (alex.py `ClaudeLauncher.poll`); the workspace registry held #136
and #230 (cleaned and retired 2026-11-18); `alex.first` is all done work; the restriction
"until #192 accepted" forbids the emulator, which is allowed, and ties the real radio to #192;
`queue.flake_issue: 8` is closed; `limit.json` holds a stale override; stale comments in
`config.yaml`, Agent-Working-Rules (review rounds, step numbers, hand-in) and MEMORY (worker
path, migration notes, #7–#12, "parallel agents and radio work"); #230 and #85 at `cr:landed`
fill `queued_landed`. #172: built in the general harness; the rest as single issues (general:
usage limit, settings re-read, stale workspaces, `queued_landed` count, the spending-limit text;
project: restart the factory, Agent-Working-Rules, items after #235, optional Install/Accept and
the second PC's records). Questions: the radio restriction; the stale Alex; #235 through Alex or
by hand; fuses for #235; Install and Accept; the meter's baseline date; the second PC; closing
harness#120; `queue.flake_issue`; #230 and #85.

## History inventory of master, 2026-11-18 (read only)

Files to remove (P): `docs/reference/Hamlib-Rust-Model.md` (an audit report, no reader),
`fixtures/radio/catalogue-proposal.json` and `ic7300-manifest.json` (proposals, no reader; the
catalogue `ic7300-catalogue.json` stays), `fixtures/decoder/likelihood-cases.json` and
`fixtures/decoder/pair-chain/` (oracles of removed tests), `client/.gitkeep`,
`tools/deploy/tests/test_references.py` (a migration guard), two legacy fields of
`fit-metric-cases.json`. With #188 (H, and P for the drill's approval cases): the prepared deploy
authority. Kept: Escapes-Ledger (a rule's input), MEMORY (trimmed), provenance data, protocol
vectors. Passages: README (status, broken links, branch `original` that does not exist, licence
wording), AGENTS.md (archive sentence), MEMORY (dated quotes, migration handoff, #7–#12, the
layout section), Harness-Overview (dates, archive wording, "harness issues live in
SensorsIot/harness" against practice), Agent-Working-Rules, Project-Specifics, config.yaml,
suites.yaml and the deploy scripts (issue pointers, dates, measurement histories). Code comments:
issue numbers and narratives 1,306 lines in 155 files, dates 125, change-history words 173,
slice labels 33, old paths or FSD 13, old model package names 239. Code paths kept for old states
in the deploy mechanism (pre-#230, pre-#33) and product data migrations (strategy schemas 2 and
3, device names, authorization hint). Questions: the code-comment cleanup (one CR or with each
restructuring); the deploy mechanism's old-layout code; #188 now; data folders with history in
their names; issue pointers in harness texts; approval records of standing policies; product data
migrations; README in #235 or #231; where harness issues live.

## Factory decisions (phase 1.3, one harness change)

1. Radio restriction (operator 2026-11-18, A, stated positively): "Live tests key the simulator:
   the IC-7300 emulator (SIM-IC7300) and the band simulator. The real IC-7300 is keyed once the
   operator has decided so in #<new decision issue>." `restrictions` is tied to that new issue;
   Project-Specifics' "until #192 is accepted" follows.
2. Install and Accept through Alex (operator 2026-11-18, A): the deploy gets a command that takes
   only the commit; `alex.install` and `alex.accept` are switched on; #235 installs by hand. The
   goal: "a completely automated factory run by Alex and optimized by Jonah".
3. The meter's baseline (operator 2026-11-18, A): `meter: rules_start` is the day the polished
   Alex takes its first job; the queue history and the refusal log are pruned to it that day;
   Jonah counts his 10 CRs from then.
4. The second PC (operator 2026-11-18, B): Andreas is no longer used; it leaves `machines:`
   and every text that names it; the factory runs on HB9BLA alone.
5. Flaky tests (operator 2026-11-18, A): `queue.flake_issue` is null; a flake is commented on the
   CR whose gate saw it; `merge_queue.py history --flakes` keeps the count; TC-096-001 and
   `clock_state_is_pushed_to_every_profile` each get an issue.
6. #230 and #85 at `landed` (operator 2026-11-18, A): before Alex starts, #230 installs and is
   accepted with the next deploy (#235's install); #85 is accepted live on the emulator; both
   slots of `queued_landed` are free when Alex starts.
7. #172 and harness#120 closed (operator 2026-11-18, A). Remainders: general harness#146 (usage
   limit), #147 (settings re-read), #148 (stale workspaces), #149 (`queued_landed` count), #150
   (spending-limit text); harness#151, moved from #238 (factory restart: decisions 1 to 6, Agent-Working-Rules,
   MEMORY). After #235, as product issues: the deploy command that takes a commit alone (tool
   change), and one issue each for the flaky TC-096-001 and `clock_state_is_pushed_to_every_profile`.

## History decisions (phase 1.6)

1. Code comments (operator 2026-11-18, A): Agent-Working-Rules gains "A comment states what the
   code does now: no issue number, date or change story" (with #238); one product CR right after
   #235 cleans every comment before the restructurings start.
2. Deploy code for old versions (operator 2026-11-18, A): removed in one product CR once the
   station's running and previous versions are both after #230 (`active.json`), with the pins,
   drill cases, tests and the matching harness lines (MEMORY, Project-Specifics).
3. Deploy authority (operator 2026-11-18, A): #188 is carried out now: `harness/project/deploy/
   authority/`, its test and the two Project-Specifics sections go (harness change); the station
   drill's approval cases go in a product CR after #235. #188 drops its `cr` labels.
4. Data folders (operator 2026-11-18, A): one `.git/test-inputs/` holds the test inputs and the
   simulator samples, renamed in one harness change with the handover manifest after #235;
   folders nothing reads are deleted; the tests' fallback to `issue-7/downloads` goes.
5. Issue pointers in harness texts (operator 2026-11-18, A): every pointer that only names a
   rule's origin goes; a pointer whose rule depends on the issue's state stays.
6. Approval records (operator 2026-11-18, A): a standing policy keeps one issue pointer and its
   quoted principle; dates and comment ids go.
7. Product data migrations (operator 2026-11-18, A): check HB9BLA's saved profiles and strategies
   for old forms; with none, the migrations (strategy schemas 2 and 3, the authorization hint;
   device names with #229) go in a product CR; otherwise they stay until those files are
   converted once.
8. README status (operator 2026-11-18, A): #235 rewrites the README's status paragraph to the
   present, from the model's statuses (to be added to #235's item 19 with the checker's answers).
9. Where harness issues live (operator 2026-11-18): the rule stands — every harness issue, also
   about `harness/project/`, lives in SensorsIot/harness (Harness-Changes, Intake). #238 moved
   there as harness#151; `.github/ISSUE_TEMPLATE/harness.md` leaves this repository with it.
