**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Product model maintenance

The reusable [SysML authoring instruction](../../../general/core/docs/standards/sysml-v2.md)
explains how to write models without project-specific assumptions. The project harness
selects the exclusive authority policy below and the local toolchain. The rules of this
project's model are the [finished model](../Finished-Model.md) (M0 to M8 and its authoring
rules); where they differ from the general skill and standard, they win. The
functional entry point is [Requirements.sysml](../../../../docs/sysml/Requirements.sysml), with the
[architecture](../../../../docs/sysml/Shack.sysml) and the model packages it references.
Harness instructions are not represented in product SysML.

### Exclusive functional authority

`Requirements.sysml` declares SysML authority with the exact first-level comment
`// Canonical authority: SysML`, the one comment a model file holds (M7.6). Canonical SysML requires the active
`docs/WSTX Rust FSD.md` to be absent. `check`, `traces` and `fingerprints` refuse a
missing or invalid marker and refuse an active FSD, with or without the marker; there is no Markdown
authority or projection path.

When the marker is present, only SysML owns functional requirements, architecture,
behaviour, interfaces, constraints and the test cases (skeleton and title, M6.5) bound to
their tests. There is no Markdown FSD. Optional views present existing model facts and
carry no additional authority.
HOW rollout and product publication remain separate: a harness change is reviewed and
published, a product change follows the CR process.

The model tools' contract (toolchain pins, commands, validation limits, the rules TR-nn and their tests TV-nnn, the catalog and source bindings) is in [tools/sysml/README.md](../../../../tools/sysml/README.md).
