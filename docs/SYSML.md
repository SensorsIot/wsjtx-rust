# Parallel product SysML representation

**Authority:** Markdown-primary. The [FSD](WSTX%20Rust%20FSD.md) owns functional
requirements/test definitions, [ARCHITECTURE.md](ARCHITECTURE.md) owns component boundaries,
and [COMMUNICATION.md](COMMUNICATION.md) owns implemented wire contracts. The model
supports structured review; it does not supersede those sources or renumber their IDs.

## Model root and scope

| File under `docs/sysml/` | Authoritative input | Maintenance and coverage |
|---|---|---|
| `Requirements.sysml` | Product FR/CL/TC definitions in the FSD | Generated typed requirements, clause dependencies and verification objectives, preserving identities and prose. Regenerate rather than hand-edit. |
| `Architecture.sysml` | ARCHITECTURE.md | Manually reviewed target parts/dependencies: variable station processes, profiles, web/MCP boundary, receive/modem/transmit/QSO, separate audio/control and optional native FlexRadio coordination. |

This representation is for **product functional documentation only**. Harness/process
rules, skills, gate policies and documentation-tool methods remain Markdown. In particular,
CL-014 and TC-DOC definitions are excluded from the SysML projection. Supporting
heartbeat/simulator tool fixtures remain in the FSD/test source rather than becoming
invented radio requirements. The source hash covers the full FSD as a drift tripwire,
including text outside the modeled slices; it does not expand the declared modeling scope.

Coverage attributes describe the accepted status slice: FR-019/FR-021 are partial;
CL-003 describes implemented status functions; corresponding communication cases have
implemented automation. Other product requirements remain target descriptions. An
automation flag is not a passed-test verdict. The architecture separates the implemented
status subset from planned radio components; dependencies express design/trace
relationships rather than behavioral satisfaction.

This initial model does not mathematically formalize the whole FSD, numerical/timing
constraints, complete state machines, wire schemas, waveforms or test vectors. Prose
inside a SysML `doc` block remains prose. Those details retain their authoritative
Markdown/contracts and executable checks.

## Pinned local validation

The full tool is the official OMG SysML v2 Pilot **0.62.0**, release **2026-08**, with
its matching bundled standard model libraries. The portable Windows bootstrap uses
Eclipse Temurin JDK **21.0.12.1+1**, x64. Version pins, official URLs and SHA-256 values
are in `tools/sysml/toolchain.json`.

```powershell
python tools/sysml.py setup
```

Setup downloads/extracts under `%USERPROFILE%/.cache/wsjtx-rust/sysml-tools/` and verifies
official archive SHA-256 values first. JAR and aggregate model-library hashes derived
from the verified Pilot archive are checked before validation. No JDK/JAR is committed
or packaged in the station executable. No global PATH, registry, Maven installation or
Jupyter service is required. Windows x64 is the verified bootstrap target; an explicit
`WSTX_SYSML_JAVA` path can supply an existing Java 21+ on another platform.

Sources: [Pilot release](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation/releases/tag/2026-08),
[Pilot kernel documentation](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation/blob/2026-08/org.omg.sysml.jupyter.kernel/README.adoc)
and [Temurin archive guidance](https://adoptium.net/installation/archives/).
This trusted development cache is not an independent authorization boundary for
deployment or radio operations.

## Synchronization workflow

Edit the authoritative Markdown first, preserving IDs. For FSD changes, regenerate:

```powershell
python tools/sysml.py sync
```

For architecture changes, reconcile the manually modeled parts/dependencies and update
its source-hash marker after review. Print the expected normalized-source hash with:

```powershell
python -c "from pathlib import Path; import hashlib; print(hashlib.sha256(Path('docs/ARCHITECTURE.md').read_text(encoding='utf-8').encode()).hexdigest())"
```

Check synchronization, real model validation and the tool's negative fixtures:

```powershell
python tools/sysml.py check
python -m unittest discover -s tools/sysml/tests -q
```

The scoped `sysml-documentation` level-2 suite selects these commands for the relevant
Markdown/model/tool changes. The application suites are unchanged. Tool tests live
under `tools/sysml/tests/`, avoiding the application's unrelated `tests/` trigger.
Missing/corrupt/stale generated content fails comparison. The architecture-source hash
detects unreconciled input changes; merely updating it is not semantic review.

## Meaning and limits of semantic validation

`tools/sysml/Validate.java` calls the pinned Pilot's `SysMLInteractive` API, including
its actual parser, name resolution and Xtext semantic validator. `check` loads the
requirements before architecture, then additional root model files in sorted order.
Additional cross-file dependencies must respect that order. A focused invocation accepts
an explicit ordered file list:

```powershell
python tools/sysml.py validate docs/sysml/Requirements.sysml docs/sysml/Architecture.sysml
```

Syntax/type/reference errors fail. Missing/invalid tools, model libraries or model files,
or missing completion evidence, fail rather than falling back to a lightweight checker.
Self-tests feed legal, malformed and unresolved-reference fixtures to the actual Pilot.
They also exercise source drift, missing/corrupt output and unavailable tool/library cases.

Successful parsing/resolution is not execution of modeled verification cases, proof
that Rust satisfies the model, or proof of prose behavior. Actual application outcomes
belong to test output and the implementing CR. Source/model correspondence requires review.

## Authoring reference

The reusable [SysML authoring chapter](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md)
remains Markdown. This project's explicit binding keeps Markdown authoritative and limits
SysML to product documentation. The investigated reference is `USKAch/uska-webpage`,
branch `sysml`, commit `b568183a3ab88d0eca4cdbd3f86d4f34c4de3b3c`. Useful practices are
stable identities, typed links, declared coverage and real semantic validation. Its
project-specific lightweight checker is not this project's full validator.
