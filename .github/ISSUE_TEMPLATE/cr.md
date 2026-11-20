---
name: Change request (CR)
about: A change to what users or the running system get
---

<!-- Apply CR-Process.md, Intake and authorization, before creating an issue.
     It may start with the problem only; the rest is completed before Check.
     Class (CR-Process.md, Classes of change): a product CR has no class label; any other
     class is recognised by `cr_state.py class` at Record and confirmed at the end of Define,
     from the `Scope:` line the definer writes, the Blast line and, for a refactor, a line
     `Behaviour: unchanged`.
     The body follows the issue body rule (core/agents/roles.md, Role: definer). -->

**Duplicate check**
<open issues considered, and why none asks for exactly this change>

**Problem**
<what is wrong or missing, and the goal; the value: who gains what they will notice, instead of what happens today>

**Functionality**
<Already covered: what existing code, the platform or an installed dependency already does, each with its place>
<what it must do, for each remaining case>

**Test cases**
<how each case is proved>

**Reading list**
<the model files and elements, code files and tests the issue rests on, by path and name>

**Open questions**
<each question, and any experiment that answers it; empty when ready>

**Sequence**
<what must land first, and the related issues; filled by Check>

**Acceptance** (a class whose Accept is full: a product CR, a minor change; checked live after the deploy; each item names what is observed and how; at least one observes the value)
- [ ] 1. <observation, and how it is made>

**Decisions:** <link to the decision comments>

**Approval**
<the operator's OK, or the standing approval it falls under>

Blast: <high | medium | low> — <what the change touches>

<details><summary>Technical details</summary>

<affected code, promises of the product contract, reproduction>

</details>
