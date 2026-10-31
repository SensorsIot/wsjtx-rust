# Escapes ledger


**Layer:** HOW (method self-measurement). The rule is
[testing](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/testing.md) §Self-measurement.

An **escape** is a defect caught later, or by a more expensive check, than the cheapest
check that should have caught it: by the review or the operator when a wired check
missed it (a **near miss**, discovered while building), or in use (a **warranty case**,
discovered by a live check, the operator or a user). Attribution follows where the
defect was made, not where it was found. A defect discovered in use gets its row before
its fix is reported done.

Each row names what broke, the cheapest check that should have caught it, what caught
it, **the hole that let it through**, and **the fix to the check**, demonstrated against
the original defect (re-run on the state before the fix), never asserted. Review rounds
are effort, not escapes, and earn no row.

A row is removed once its fix is a standing check that still fails on the original
defect; `git log` keeps it.

| Date | What broke | Cheapest check that should have caught it | Caught by | Hole | Fix to the check (proof) |
|---|---|---|---|---|---|
| <YYYY-MM-DD> | <defect> | <check> | <review / live check / operator / user> | <why the check missed it> | <commit, and the red run on the old state> |
