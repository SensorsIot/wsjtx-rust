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

## #235 Check round 1: answers

1. Control interfaces (operator 2026-11-18): M3.4 reworded (harness#152): no control interface
   imports a transport file or OperatingChain; it may import another control interface for a
   type that function owns; the control interfaces are those WireNames lists. #235 moves the
   two misplaced types to their owners: RadioPlace to RadioControl, ProcessEnds to
   StationCommands.

## Sweep decisions

1. #107 (operator 2026-11-18, B then A): after every start the built-in "Default" is active,
   nothing restored; "Default" is a new built-in, first, with what no strategy means today
   (every station shown, no ranking order, no filter, no alert, no CQ when idle). Model change
   in #235 (Strategies::BuiltinStrategies, StrategySelection's start and end-of-selection rules,
   `active` always present); #107 rewritten to the Band Activity ordering and filtering.
2. #216 (operator 2026-11-18): "Default" cannot be changed; every other built-in (the examples and
   the contest built-ins) is changed in place; Factory reset puts the selected built-in back to its
   shipped state; a created strategy has none. Model change in #235 (BuiltinOffer, StrategyEditor,
   Strategies::BuiltinStrategies); #216 rewritten for the code.
3. #122 (operator 2026-11-18, B): agents give every browser command except saving the station
   config (profile, rig, CAT/PTT, connection, audio devices, receive settings) and saving the shack
   settings (call sign, locator, strategies file, UDP and PSK Reporter targets); applying radio
   settings to the rig is operating. Model: the supervisor's gate rule (#235); rule: M5.10 reworded
   (harness change, SensorsIot/harness); #122 rewritten for the code.
4. #189 (operator 2026-11-18, A, as WSJT-X): a contact whose transmit stops with device_lost is
   kept, shows the cause, and the operator resumes or cancels it; stated in qso's rules in #235.
5. #213 (operator 2026-11-18, A): the station holds the menu items of the last completed Apply
   (one record in the station's memory); a changed item is set back and shown; model in #235.
6. #215 (operator 2026-11-18, A): VOX held off; split held at the station's split setting and set
   back when changed (M5.6); model in #235.
7. #13 (operator 2026-11-18): FlexRadio stays phase 2; #13 stays open and paused as its place.
8. Timing classes (operator 2026-11-18, A): labels on the tests only; #108 and #130 closed as
   overtaken; #207 shrinks to labelling the timed tests; #126 rewritten.
9. #191 (operator 2026-11-18, A): closed as done; the simulator setup exists.

## #235 Check round 1: model values (operator 2026-11-18)

1. A value is verified by V1 (a code constant named after the feature, equal; a binding check of
   the tool, not a test) or V2 (a contract test bound to the clause's case reads it from the model
   by qualified name and compares a measured behaviour with it, M6.8); neither: refused. No test
   compares a program variable with itself.
2. Not built (V3): a value is covered when a target or partial clause names its element or reaches
   it through typed features (M6.10), in any file; reached by an implemented clause too, it counts
   as built and must match the code.
3. Source values (A4): `ModeProcessing::Period` (FT8/FT4 periods, starts, frames), the safe JSON
   integer (2^53−1, three places) and `DialRange` leave the model's values; each keeps its source
   reference; the dial range becomes a property of `RigModel` from the catalogue.
4. Decode tolerances and repeatability are promises: they stay in the model and the contract tests
   read them (V2).
5. ThinLinkBudget gets a clause in StationLink ("the link to a browser MUST stay within
   ThinLinkBudget"), at target; its case is a manual test judging the link log; implemented once
   the operator has judged it.
6. Mismatches: the display name of a new station is "New station"; the ignore list is one list of
   100 (the merge into one list is #228); Band Activity sorts descending. #235 corrects the model;
   the ignore list's code carries `@CodeDiffers` until #228.
7. The CSS layout (PaneLayout rows) is verified by the browser test reading the row counts from the
   model and counting the visible rows (V2); the CSS stays.

## Unattended run, night of 2026-11-18 (operator: "yes, go")

State at start: #235 at `cr:defining`; its definer is revising the body with every answer of
Check round 1 (checker reasons 1–8, values decisions 1–7, sweep decisions 1–6 that change the
model, README status); master a77610ff4 (harness#152, #153 landed); Alex off (switch stop);
the merge queue worker idle.

Steps, one at a time:
1. #235: post the definer's batch answer, write the body (`cr_state.py body --from-definition`),
   `defined`, then Check round 2 by a fresh checker. PASS: go on. "not yet": stop (second round).
2. Alongside, harness paths only: harness#151 (Alex settings: the radio rule positive with its new
   decision issue, `queue.flake_issue` null, Andreas removed, `skip_labels`, `limit.json` override
   cleared; Agent-Working-Rules and MEMORY current with the comment rule; issue pointers, dates and
   approval records out of harness texts; #188's authority folder and test and the Project-Specifics
   sections; `.github/ISSUE_TEMPLATE/harness.md` removed). `alex.first` and `meter: rules_start`
   wait for #235 landed.
3. #235: Implement (coder in a `parallel.py` workspace; the coordinator writes the model findings),
   Review (fresh reviewer, at most two rounds), Land (merge queue, full gate).
4. Stop at `landed`. Install, acceptance and Alex's first test wait for the operator.

Stop and leave a note here when: a question needs the operator; a second "not yet" in Check or
Review; the gate red twice; the usage limit.

### Log
- #235: the definer answered all eight round-1 reasons (comment 6965638320) and revised the body;
  M5.10's agent rule is now tool-checked (typed set `AgentRefusal`, item 17, TR-06) instead of
  left to the reviewer. Definition 6965638762, body written (24,972 characters, `body_problem`
  none), copied to `cr-235-body.md`; `defined`, then `checking`; Check round 2 started.
- Decision issue #239 "Decision: agents key the real IC-7300" created for factory decision 1.
- #235 Check round 2: `Ready: not yet — a77610ff4` (6965763693). Reasons 1–8 of round 1 are
  resolved; one new blocking reason from the values answer: "Name twice in one code" cannot be
  met for `directiveConfirmed` (a wire key) and the eight `type` literals of ModeProcessing.
  Notes: more name pairs (`closeMaxMs`, PskReporter's retry values), `ft4PublishedByMs`
  either-or, and M3.4 no longer says which interface files may import a control interface
  (TR-04's negative case and Udp rest on the 2026-11-17 decision). Ask posted (6965788369),
  proposal A: refuse two constants of one name, and two compared values of one name only when
  they differ; literals and wire names outside. #235 is at `decided` (`decided → recorded` is not
  an allowed move); the answer goes through Decide, then one fresh Check round on the changed
  statements.
- **STOP** (second "not yet" in Check). Waiting for the operator's answer on #235's Ask.
- harness#151 done: master 45d29d315 (rollout 2026111804), closed; merged into this branch.
  Alex's restriction now tied to #239; `alex.first` empty with `only_first` (Alex takes nothing);
  `flake_issue` null; Andreas and the handover section gone; `limit.json` override cleared;
  #188's authority folder, test and sections gone (#188 keeps the drill's approval cases for a
  product CR, `cr` labels dropped); `.github/ISSUE_TEMPLATE/harness.md` gone. Harness deploy
  tests: 53 passed. Left for the operator: the `paused` and `owner:` labels are unused now.
