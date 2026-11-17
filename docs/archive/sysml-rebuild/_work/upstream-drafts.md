# Drafts for SensorsIot/harness (not posted)

## Comment on #129 (verification cases without prose conditions)

wsjtx-rust has taken this form as its project rule (wsjtx-rust#233, `harness/project/docs/Finished-Model.md`
M6.5): a test case is its identity, a one-line title, `subject`, `verify`, `@TestLevel`,
`@Automation` and `@TestedBy`; the bound test is the description of the test; a case is written
only when its test exists, and a clause without a case stands at target or partial (its status
shows the gap). Measured on the rebuilt model: 241 cases, no setup, conditions or planned lines.

The same prose form is asked beyond the skill, so the change reaches further than
`references/requirements-and-cases.md` rule 5 and SKILL.md's edge-case table:
- `core/agents/roles.md`, Role: definer (edge cases as lettered conditions in a verification case);
- `core/skills/test-design/SKILL.md` (the case as "the short form of … the setup, then one line per
  condition"; reconcile "setup/steps, expected observations and independent oracles");
- `core/skills/conformance-review/SKILL.md` (reconcile "case IDs, setup/steps, expected
  observations/oracles");
- `core/skills/documentation/SKILL.md` (durable test definitions "including case IDs, steps, oracles");
- `core/docs/standards/sysml-v2.md` (the case description; the worked example);
- `core/docs/standards/testing.md` ("the project's functional description owns the durable
  definitions of the contract tests").
The issue's test plan keeps its detail; only the model's case becomes skeleton and title.

## Comment on #118 (the reciprocal dependency example)

wsjtx-rust binds `verify` alone and has no `dependency` at all (wsjtx-rust#233, M7.1: the links are
`satisfy`, `verify`, derivation and the subsetting of a clause by a use-case step). The example in
SKILL.md lines 12-13 and in `templates/sysml/authoring-example.sysml` (lines 34-63: `satisfy`
on a clause, `dependency`, lettered conditions) shows the form this project's tools now refuse.

## Comment on #135 (fold a project's fork into the skill)

Measured after the rebuild: the copy in wsjtx-rust (`Foundation/Authoring/`) was never edited; it
equals `core/skills/sysml-authoring` apart from the term "binding" (now "project harness",
harness#133). The project's differences stood in its own documents and are now its
`skill_additions` (wsjtx-rust#233); the copy stays only in the project's archive and is not
installed. What remains generic, for the skill and the standards: #129 (skeleton and title),
#118 (no reciprocal dependency in the example), and the three issues opened with this comment
(tags name test cases; no retired list; negative tests). What stays the project's: an FR without
subject and a clause without satisfier, use cases that carry every clause, the naming rule.

## Comment on #126 (ratchet)

A data point: wsjtx-rust's model rules forbid an exemption list for the model's checks
(Finished-Model M8.2: "every rule that a tool can check is checked in the gate, with no exemption
list"), after its pending-structure list kept 51 old files outside the structure rules. If the
ratchet comes, a project should be able to declare a check as having no exception list.

## Comment on #139 (merge_queue across the layout move)

Confirmed by use (2026-11-17): merging master (after wsjtx-rust#230) into a worktree of an older
branch left `harness/.git` and the old submodule's files; repaired by hand as wsjtx-rust's
MEMORY says (delete `harness/.git`, remove the old files, `git submodule update --init`).

## New issue: sysml-authoring / test-design: a Proves tag names test cases only

**Duplicate check**
#129 and #118 change the case and the link form; none says what a source tag names.

**Failure of the method**
The examples tag a test with FRs (`Proves: FR-004, FR-005` in `core/skills/test-design/SKILL.md`,
`core/docs/standards/testing.md`, `lang/rust/standard.md`). An FR or a clause in a tag restates
the model's chain (case → clause by `verify`, clause → FR by derivation) and goes stale when a
clause splits: wsjtx-rust's rebuild left 61 tags naming identities that no longer exist, among
2,315 FR, CL and TC mentions in tags.

**Task**
The examples and the rule say: a tag names the test cases its test belongs to, nothing else; the
clause and the FR follow from the model. A project harness may fix another form.

## New issue: sysml-authoring rule 9: no retired list in the model

**Duplicate check**
None.

**Failure of the method**
Rule 9 keeps retired identities "listed as retired … where the project harness keeps such a
list". In the model such a list is history, and a reader (an agent above all) meets identities
that mean nothing now. wsjtx-rust decided (wsjtx-rust#233, M1.5, M6.12): the model states the
present only; an identity any earlier commit of the main branch declared is never declared again,
which the project's tool reads from git.

**Task**
Rule 9 offers the guard from history as the default and the listed retirement as a project's
choice; the reuse rule itself stays.

## New issue: test-design: negative tests per rule and per preventing promise

**Duplicate check**
#124 (test-audit) finds weak tests in an existing suite; none plans negative tests.

**Failure of the method**
A test plan shows that the accepted case passes; whether a check refuses each way its rule can be
broken, and whether a promise that prevents something (a refusal, a disabled control, a MUST
NOT) is shown by trying it, is left to chance. Red on the parent proves a test can fail, not
that the rule prevents what it should.

**Task**
test-design asks, for each rule or check, one negative test per way it can be broken, refused
with its message, and for each preventing promise a test that tries it and sees it refused;
conformance-review checks the plan for them.
