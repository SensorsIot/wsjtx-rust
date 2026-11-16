# Foundation of the new model

**First rule.** The model exists for three things: it tells the definer what holds, the
Markdown documentation is written from it, and it keeps the objects in order. A construct
that serves none of the three is not written. A fact that two correct implementations could
differ on without anyone outside the part noticing is not written.

Three documents govern everything written under `docs/sysmlV2`.

| # | Document | Says |
|---|---|---|
| 1 | [1-Finished-Model.md](1-Finished-Model.md) | where everything stands in the finished model (rules M1 to M8) |
| 2 | [Authoring/](Authoring/SKILL.md) | how each element is written: the authoring skill, its five references, the written example, the standards behind them, and the skill that writes the documentation from the model |
| 3 | [3-Method.md](3-Method.md) | how the new model is built from the old one: the steps per part, the ledger, the checks, and when a part is done |

`1-Finished-Model.md` is the working copy. It started as `docs/harness/Finished-Model.md`
and differs from it in M0, M2.1 (`Startup` stands in `station/`; operating's
`StrategySelection`), M5.1 (the operator's
shared folder), M6.2, M6.4, M6.10, M7.1 and open point 3.

`Authoring/` is a copy of the harness at 697765f, unchanged, so that the foundation can be
read in one place. The harness stays the source: a change is made there and copied again.

Where two of the documents disagree, the difference is an open point for the operator. It
is not resolved while writing.
