# Parallel product SysML representation

**Authority:** Markdown-primary. The [FSD](WSTX%20Rust%20FSD.md) owns functional
requirements/test definitions, [ARCHITECTURE.md](ARCHITECTURE.md) owns component boundaries,
and [COMMUNICATION.md](COMMUNICATION.md) owns implemented wire contracts. The model
supports structured review; it does not supersede those sources or renumber their IDs.

## Purpose, model and views

The product model is intended to become a sufficient functional contract for an AI
agent to implement the complete product. Markdown remains authoritative: approved
functional decisions are reconciled into the model before their implementing CR writes
code. The agent may choose declared implementation freedoms such as internal algorithms
or code organization; it must not invent missing behavior, state transitions, interface
semantics, timing/error policy or acceptance oracles. Normative external protocols must
have pinned references. Harness/process HOW remains Markdown and is not product SysML.

A model defines parts, relationships, exchanges and, as functional CRs prepare them,
behavior, states, constraints and verification intent. A view selects existing model
facts for human review. It does not complete, change or replace those facts. A code
implementation agent consumes the functional model and its declared normative references;
it does not need diagram views as an additional source of product semantics. Many
views may present the same model without creating additional runtime instances.

**Current readiness:** this repair provides a connected structural foundation and a
requirements/prose projection. It does not make the full product implementation-ready.
Concrete contracts and behavior still belong to the named preparation gates in
ARCHITECTURE.md sections 8/10 and the relevant functional CRs. TC-DOC-006 requires a manual
readiness review before each slice is implemented. An unresolved slice remains not
ready; a passing parser, connectivity check or diagram review cannot grant readiness.
The full-product AI implementation target therefore remains unfulfilled, explicitly.

## Model root and scope

| File under `docs/sysml/` | Authoritative input | Maintenance and coverage |
|---|---|---|
| `Requirements.sysml` | Product FR/CL/TC definitions in the FSD | Generated typed requirements, clause dependencies and verification objectives, preserving identities and prose. Regenerate rather than hand-edit. |
| `Architecture.sysml` | ARCHITECTURE.md | Manually reviewed target parts, typed logical ports and usage connections: one four-role physical deployment, variable station processes, scoped client/radio attachments, profile-owned recording input, receive/encode modem paths, QSO/contact persistence, independent audio/control, a common authority and exclusive standard/native backend alternatives. |

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

This model does not mathematically formalize the whole FSD, numerical/timing
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

For architecture changes, reconcile the manually modeled parts, ports and connections and update
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

The `check` command also requests a resolved semantic inventory from the same Pilot
process. The Java adapter traverses actual usage/type/connector objects, inherited
features, conjugated directed items, reference subsetting and backend variants. Python
checks an independently authored endpoint/identity oracle bound to ARCHITECTURE.md
section 9: required physical/delegation paths, recording and encode paths, one profile
and backend variation per station, common authority, correlated resource context and
no extra bypass edges or detached runtime inventories. Views may expose existing
structure but cannot add runtime parts/connections. Empty/missing inventory fails closed.
The oracle is deliberately specific to this target architecture, not a general SysML
connectivity theorem or generated approval of whatever the candidate model contains.

TC-DOC-005 fixtures remove connections, bypass authority, split authority, duplicate a
backend, redirect association/context identity, change waveform direction, add detached
stations and add runtime structure to a view. They run through the real Pilot before
the integrity assertions. Legal but disconnected/miswired models must fail the explicit
integrity oracle even when ordinary semantic validation succeeds. The fixture list and
expected diagnostics remain executable companions to the FSD's durable case definition.

Successful parsing/resolution is not execution of modeled verification cases, proof
that Rust satisfies the model, or proof of prose behavior. Actual application outcomes
belong to test output and the implementing CR. Source/model correspondence and connector coverage require review against the Markdown arrows; a disconnected but well-typed model can pass semantic validation.

## Authoring reference

The reusable [SysML authoring chapter](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md)
remains Markdown. This project's explicit binding keeps Markdown authoritative and limits
SysML to product documentation. The investigated reference is `USKAch/uska-webpage`,
branch `sysml`, commit `b568183a3ab88d0eca4cdbd3f86d4f34c4de3b3c`. Useful practices are
stable identities, typed links, declared coverage and real semantic validation. Its
project-specific lightweight checker is not this project's full validator.

## Physical context and software decomposition

The ordinary `physicalInterconnection` view in `Architecture.sysml` exposes the immediate
members of the existing `physicalStation` usage. The four physical roles are `user`,
`viewer`, `controller` and `radio`; their four connections are local interaction, the IP
station link, radio audio and optional radio control. A view is a presentation selection;
it neither creates the underlying architecture nor repairs missing semantic connections.
No separate entry model, image or viewer helper is required by the architecture.

Expand the same deployment to inspect its software: `viewer.browsers[*]`,
`controller.stations[*]` and each station's single profile and backend variation. The
physical station-link connection owns its per-client `attachments[*]`; these reference
one browser and one actual station, with the operational connectors between those
selected endpoints. MCP has analogous controller-level attachment associations. Physical
radio connections own station-bound `channels[*]` whose endpoints use that station's
selected backend and radio binding. These relationships distinguish aggregate carriers
from routing every operation to every member of a population. Profiles remain isolated.

Every station references `controller.radioAuthority`; it does not compose a private
replacement. Request context binds to the station-owned radio binding, authorization
preserves the original request, and an outcome references that request. This is semantic
correlation, not serialized ID fields or a settled coordination implementation. #8/#13
must determine actual cross-process placement, resource claims, leases and radio limits.

`stations.backend` is one variation with standard-device and optional Phase 2 native
variants. Variants are alternatives, not concurrent running backends. Native audio/control
can share a managed session; both control paths still use the common authority. Logical
presence of a driver does not assert CAT availability or transmit readiness.

Definitions describe reusable types; usages and identity references describe this target
deployment. A general type/dependency graph can omit internal port connections. An
interconnection view can expose nested usages/connections or keep the physical context
collapsed. Viewer layout/expansion does not change the model, and is not a validation
oracle. Current Rust remains the separately labeled status-only subset.

## Source-arrow and semantic-path coverage

The model's role names bind the following Markdown arrows to actual exchanges. Paths
below are relative to one `controller.stations` usage unless identified as physical or
attachment paths. Multi-step paths preserve authority/delegation rather than replacing
them with a direct bypass. This inventory is reviewed against ARCHITECTURE.md; executable
expectations are authored independently in `architecture_integrity` in `tools/sysml.py`.

| Markdown software arrow | Model endpoint path / responsibility |
|---|---|
| Browser ? Web | Physical `stationLink.attachments`: selected `browser.station` ? `clientBoundary` ? selected `station.web.client` |
| MCP ? MA | `controller.mcpAttachments`: selected `client.station` ? selected `station.mcp.client` |
| Web ? Station | `web.station` ? `station.webOperations`; `web.recording` ? `station.upload` validates upload |
| MA ? Station | `mcp.station` ? `station.mcpOperations` |
| Station ? Profile | `station.profile` ? `profile.context`; accepted recording ? `profile.upload` |
| Station ? RX | `station.receive` ? `receive.jobs` |
| Station ? TX | `station.transmit` ? `transmit.operations` |
| Station ? QSO | `station.qso` ? `qso.operations` |
| Station ? Control | `station.control` ? `radioControl.station` |
| RX ? Audio | `audio.receive` ? `receive.audio`, with samples and audio outcomes |
| TX ? Audio | `transmit.audio` ? `audio.transmit` |
| TX ? Control | `transmit.control` ? `radioControl.transmit` |
| Audio ? Devices | `audio.backend` ? selected `backend.audio` ? standard `audioDevices.host`; device radio port via station-bound physical audio channel |
| Control ? Authority | `radioControl.backend` ? `authorityRequest` ? referenced common `authority.requests` |
| Authority ? CAT | Common `authority.authorized` ? `authorizedControl` ? selected `backend.control` ? standard `controlDriver.authorized`; driver radio port via station-bound physical control channel |
| Audio ? Flex | Same selected audio boundary, native variant's `audioDevices` and optional shared `session` |
| Authority ? Flex | Same authorized control boundary, native variant's `controlDriver` and optional shared `session` |
| RX ? Modes | `receive.processing` ? `modes.receive`, request/result directions |
| TX ? Modes | `transmit.encode` ? `modes.encode`, encode request/waveform return |
| Profile ? Recording | `profile.upload` ? owned `recordings.upload`; `recordings.samples` ? `profile.recordedSamples` |
| Recording ? Audio | `profile.recordedSamples` ? `audio.recorded`; no live-device prerequisite |
| QSO ? Profile | `qso.contacts` ? `profile.contacts` |
| Station ? Audio | `audio.status` ? `station.audioStatus`, independent availability/error reporting |

The physical four-arrow inventory is `user.interaction` ? `viewer.operator`,
`viewer.stationLink` ? `controller.viewerLink`, `controller.radioAudio` ? `radio.audio`,
and `controller.radioControl` ? `radio.control`. Local interaction delegates to actual
viewer browsers. IP/radio connections own the scoped attachments/channels above.
Control-request resource bindings and request/outcome identity are also explicit binding
connectors. The integrity check covers both standard/native branches and these bindings;
it does not execute timing, cancellation, authorization or hardware behavior.
