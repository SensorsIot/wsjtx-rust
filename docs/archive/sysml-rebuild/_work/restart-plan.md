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
| Phase 3: harness change 2 | H |
| Phase 4: production | P |

## Phase 1: polish the factory (–, H; nothing deleted before it is checked)

1. Issue sweep: the open issues, one list for the operator, each marked done by the rebuild
   (closed with a pointer), overtaken (closed), still valid and rewritten against the new model,
   code split matched to M2.3 and `@CodeDiffers`, or kept. The harness issues (#172, #188) stand
   in a short list of their own and go through no CR state.
2. Branches and worktrees, checked 2026-11-18 for work not on master:
   - no unique work: cr70-slowtests, cr80-traffic, cr97-strategy (local and remote),
     harness-issue/106, 126, 184, 203; harness-issue/136 (its worktree holds one change of the
     former model's `ReceiveJob.sysml`, for the model conversion #136); the backup branch (all
     its commits are in `sysmlv2-rebuild`); the temporary red-on-parent worktree (clean);
   - unique work, decided with its issue in the sweep: cr98-contest (4 commits, the contest data
     of #98 in the former model and a WIP), harness-issue/105 (one WIP commit for #105),
     pilot/band-activity-pane (6 model pilot commits), wip-old (2 commits of the model skeleton
     #194);
   - kept: the merge queue's worktree; `sysmlv2-rebuild`, the archive.
3. The factory: `alex.first` in `harness/project/config.yaml` takes the new order from the sweep,
   with #235 first; its restrictions (#192) are checked. #172: its open points and its meter are
   gone through, what is done is closed, the rest stays as single issues; harness#120 stays
   upstream. The meter's baseline starts after the rebuild.
4. MEMORY's "Inputs and unfinished work" is renewed.

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
