---
name: harness-test-audit
description: Audit the tests already in a suite for weak ones, report them in groups
  and record the groups the operator picks as issues. Finds tautological tests (green
  while their code is wrong, by mutation testing), tests coupled to structure rather
  than behaviour (from the history of restructurings, conflicts and private access)
  and fakes that do not match the real thing. Use on the operator's request, such
  as "audit the tests of X" or "which of these tests are weak", and when the improvement
  review hands over an escape a test stayed green through; not for the tests of a
  new change (test-design).
---

Read [the canonical test-audit skill](../../../harness/general/core/skills/test-audit/SKILL.md) in full BEFORE following this skill.
Filesystem path relative to this entrypoint: `../../../harness/general/core/skills/test-audit/SKILL.md`.
Resolve the canonical skill's own references from its source directory, not this entrypoint.
If the source is missing, stop and report it; do not substitute another checkout.

<!-- canonical-source-sha256=815e0d4746c0e2aab0e51083480913275402118c5f44c121b808320710834b90 -->
<!-- harness-forwarder-v1 sha256=d6dceb0561a65a39890914ba6284311b2752ff7aa4ef3e53fd70e3d5cdd556c5 -->
