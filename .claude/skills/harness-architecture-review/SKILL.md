---
name: harness-architecture-review
description: Find where the structure of the code causes friction (shallow modules,
  a concept spread over many modules, coupling that leaks across an interface, code
  hard to test through its interface, code that does not follow the model's parts),
  report the candidates, and record the ones the operator picks as restructurings
  or product changes. Use on the operator's request, such as "review the architecture
  of X" or "what should we restructure", when the improvement review hands over a
  hot spot or escape with a structural cause, and before a large file is split; not
  for moving code (restructuring).
---

Read [the canonical architecture-review skill](../../../harness/general/core/skills/architecture-review/SKILL.md) in full BEFORE following this skill.
Filesystem path relative to this entrypoint: `../../../harness/general/core/skills/architecture-review/SKILL.md`.
Resolve the canonical skill's own references from its source directory, not this entrypoint.
If the source is missing, stop and report it; do not substitute another checkout.

<!-- canonical-source-sha256=d45ae6266e55a34e9e21e3ba3232dd65397bfeadea74be5db04dfb9f9689a3d8 -->
<!-- harness-forwarder-v1 sha256=371b365229c23c25fc4d7bf8b72cf24e0565efbd63d85b289e7006f7d5a93190 -->
