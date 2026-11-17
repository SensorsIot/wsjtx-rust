# From the rebuild to production

Operator 2026-11-17: an updated master, an updated model, an updated Goldratt factory and the old
stuff removed; then production starts again. Order 1 → 2 → 3 → 4 → 5; the sweep of phase 3 is
prepared while the CR of phase 1 runs.

## Phase 1: model and tool to master

The product CR drafted in `cr-draft.md`, through the full CR process, driven by hand (Alex's
configuration still names the former work): Decide (the operator's go), Define (the test plan
with positive and negative tests), Check (`Ready: PASS`), Implement (the coordinator: the model's
findings; the coder: the tool, its tests, the tags, the test readers; each new test red on the
parent), Review, Land through the merge queue, Install, Accept. The candidate is cut from master
and takes `docs/sysml/` from `sysmlv2-rebuild`; the rebuild's archive does not land.

## Phase 2: harness change 2

The suites' select lists, the links to the new model files, the `model_bindings.py` docstring,
the sentence on the archived FSD; the three product sections leave Project-Specifics and #232
closes; skills and agents reinstalled; every clone pulls (the main checkout, the second PC).

## Phase 3: remove the old stuff (nothing deleted before it is checked)

1. Issue sweep: the 107 open issues, one list for the operator, each marked done by the rebuild
   (closed with a pointer), overtaken (closed), still valid and rewritten against the new model,
   code split matched to M2.3 and `@CodeDiffers`, or kept.
2. Branches and worktrees: cr70-slowtests, cr80-traffic, cr97-strategy, cr98-contest,
   pilot/band-activity-pane, harness-issue/105, 106, 126, 136, 184, 203, wip-old,
   backup/sysmlv2-pre-master-merge and the temporary red-on-parent worktree, each checked for
   unmerged work, then deleted or kept. `sysmlv2-rebuild` stays as the archive.
3. Master's leftovers: `docs/archive/`, `docs/sysml/reference/` and the pending-structure list go
   with the CR (phase 1); MEMORY's "Inputs and unfinished work" is renewed.

## Phase 4: update the factory

`alex.first` in `harness/project/config.yaml` takes the new order from the sweep; its
restrictions (#192) are checked. #172: its open points and its meter are gone through, what is
done is closed, the rest stays as single issues; harness#120 stays upstream. The meter's baseline
starts after the rebuild.

## Phase 5: pilot, then production

A pilot CR through Alex end to end: the code restructuring of the smallest part (clock) under
M2.3, which tests the rules, the tool, the gate, the queue and the roles together; a fault found
is a harness change. Then the operator chooses the first product CRs from the rebuild's work for
the code (#226, #227, #228, #229, #225, the WSJT-X UI targets, the `@CodeDiffers` list), and #231
traced once to the new model.
