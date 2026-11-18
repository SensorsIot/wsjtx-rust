---
name: harness-test-design
description: "Design the tests of a CR or a bug before implementing it \u2014 from\
  \ the issue's goal, acceptance items and blast to a test plan of promise, test,\
  \ cost level, cases, oracle and suite, written on the issue \u2014 then implement\
  \ them, each contract test tagged with the promise it proves, proven red on the\
  \ parent. Use at the Define and Implement steps of a CR, when asked \"which tests\
  \ does this issue need\", \"write the tests for"
---

Read [the canonical test-design skill](../../../harness/general/core/skills/test-design/SKILL.md) in full BEFORE following this skill.
Filesystem path relative to this entrypoint: `../../../harness/general/core/skills/test-design/SKILL.md`.
Resolve the canonical skill's own references from its source directory, not this entrypoint.
If the source is missing, stop and report it; do not substitute another checkout.

<!-- canonical-source-sha256=e5419686fb4d7dbd1b9792fcda1ef6c5518fcd9e19dcd8e307145432936f55c8 -->
<!-- source harness/project/docs/Finished-Model.md#m6-requirements-clauses-and-tests sha256=e50146b2b979540e767db7d86450406f1636d49064ed8b9feb9337a96e5f4e5c -->

## This project

## M6. Requirements, clauses and tests

- **M6.1** An FR is about the station as a whole and names no subject; `Shack.sysml` gives
  it to the part that carries it. Its status is computed from its clauses: implemented when
  all are implemented, target when all are target or it has none, partial otherwise.
- **M6.2** A clause stands in the function file of its part, names that part as its
  subject, and derives from one FR, the one its part serves. That it uses another function's
  output, or is shown on a screen, adds no second FR. Nothing satisfies a clause formally:
  the subject names its owner.
- **M6.3** A clause about an exchange stands in the interface file, with the interface as
  its subject.
- **M6.4** A clause is one promise: one sentence with MUST, SHOULD or MAY, complete without
  its values. Its values, ranges, sequences and rules stand in the typed element it names,
  one sentence per feature, effect or rule. A clause is divided only where its members
  belong to different parts, are shown by different tests or change for different reasons.
- **M6.5** A test case stands beside its clause and verifies it. It is a skeleton and a
  title: its identity, a one-line title, `subject`, `verify`, `@TestLevel`, `@Automation`
  and `@TestedBy`; the bound test is the description of the test. A test case is written
  only when its test exists, and is bound only to tests that show what its clause promises.
  A clause without a case stands at target or partial; built and tested is `implemented`,
  and an implemented clause has a case. A clause that prevents something (a refusal, a
  disabled control, a MUST NOT) has a case bound to a negative test: a test that tries it
  and sees it refused.
- **M6.6** Status and test links are tags on the clause and on its case. The code link
  (`@ImplementedIn`, the modules) is a tag on the part definition, and a clause inherits it;
  a clause whose code lies in other modules carries its own, which wins.
- **M6.7** Model and code are bound in both directions by stable names: the model binds a
  case to its tests (`@TestedBy`), and each such test names its cases in a tag
  (`// Proves: TC-022-004`), on the test itself. A tag names test cases only: no FR, no
  clause, no shorthand, no issue number. A detail test carries no tag; its file is named by
  its part's `@DetailTests`.
- **M6.8** A contract test takes its values from the model. Every value of the model is
  verified in one of two ways: the code holds it in a constant named after the value's
  feature, which the model tool compares; or a contract test bound to the clause's case reads
  it from the model and compares a measured behaviour with it. No test compares a value of
  the program with itself.
- **M6.9** Every clause and every test case names its subject.
- **M6.10** The element that holds a clause's values and rules stands directly after the
  clause, in the same file, and the clause's sentence names it. Where that element uses
  something defined in another file, it refers to it by type, not only by name in a text.
- **M6.11** Every clause is carried by a step of a use case (`UseCases`), except a clause of
  a debugging function, which carries `@Debugging`.
- **M6.12** An identity keeps its meaning and is never declared again with another one. The
  model lists only the identities that exist; one that any earlier commit of the main
  branch declared counts as used. A new identity takes the next free number of the series
  it was split from.
- **M6.13** Where the code does not yet do what the model states, the model says so in the
  present: by the status of the clause (target or partial), or, for a value, a name or an
  enumeration literal below the clauses, by `@CodeDiffers` on the element, saying what the
  code does today. Where the code matches, there is no `@CodeDiffers`.

<!-- harness-forwarder-v1 sha256=9f0ec5a2fbf80dd12551ae91e99cfd69dd2a33138b0ce0ea506780062377c641 -->
