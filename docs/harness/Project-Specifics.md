# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/V2/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/V2/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

## Windows build and packaging

The Rust executable serves the embedded browser, versioned station interfaces and implemented receive services. Native Windows audio, typed CAT adapters and the pure FT4/FT8 decoder are separate modules. Their presence does not establish complete mode parity or live acceptance; current implementation and verification declarations belong to the functional model and issue evidence.

The root Cargo workspace contains the station-server package in `server/`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` files are embedded at Rust compile time, without a frontend build step.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml)
is a manual alternative, started explicitly from the Actions page. Pushes and pull
requests do not trigger it. Normal development, the full test suite and release packaging
run on the Windows PC; a local pass is not automatically repeated on GitHub.

The workflow uses a GitHub-hosted Windows Server 2022 x64 runner with the MSVC build tools. It installs Rust 1.99.0, matching `rust-toolchain.toml`, and checks formatting, Clippy warnings, tests, release compilation, and execution of the built program. The executable is uploaded as the `wstx-rust-windows-x64` artifact with a 14-day retention period.

No radio, sound device, third-party decoder or repository secrets are required. Rust dependencies implement HTTP/WebSockets, asynchronous networking, JSON and TLS. Node 24 test dependencies provide a real Chromium browser, independent WebSocket peer and disposable TLS certificates. The workflow runs browser tests against the compiled release executable. The selected suites state which communication, receive and modem promises they exercise; an unexecuted hardware case is not a passed check.

The workflow has read-only repository permissions and pins its checkout and artifact actions to specific commits. It does not publish GitHub releases or packages.

## Native Windows FFI boundary

The `wstx-rust` library crate may contain the Windows audio and CAT adapters. Its
crate root uses `#![deny(unsafe_code)]`; the binary crate retains
`#![forbid(unsafe_code)]`. Only the `audio::windows` and `radio_control::windows`
module declarations may use `#[allow(unsafe_code)]`. Public interfaces crossing
those boundaries are safe Rust. The decoder and canonical source-value modules
retain `forbid(unsafe_code)`; portable processing and protocol code have no exception.

The `audio_contract`, `audio_hardware`, `audio_listen`, `radio_control`,
`radio_native` and `radio_hardware` integration-test targets may use
`#![deny(unsafe_code)]` when they import those actual adapters. They inherit the
same two narrowly scoped adapter exceptions. Only `radio_native` additionally
permits an explicitly named Windows fixture module containing the owned-handle
and local named-pipe FFI calls. Test setup, assertions and protocol logic remain
outside that fixture exception. Test targets using only safe library APIs retain
`#![forbid(unsafe_code)]`.

Every unsafe block states its preconditions in a `// SAFETY:` comment. Tests cover
handle and buffer ownership, initialization, cancellation, failure ordering and
acknowledged release. Failed native close retains its owning resources rather
than granting another owner access. Independent review checks changes to these
boundaries. Crate-wide `allow(unsafe_code)`, an exception on the whole audio/CAT
module, new exceptions outside these locations, and compiler or gate bypasses
are prohibited.

## Local Windows development

Install Rust through [rustup](https://rustup.rs/) and the Visual Studio C++ Build Tools with the Desktop development with C++ workload and a Windows SDK. The toolchain file selects the compiler version automatically.

The local pre-push gate is the authoritative check:

```powershell
python harness/core/tools/gate.py
```

It selects affected compiler checks and functional test groups from the declared
change owners and downstream dependencies in `.harness/suites.yaml`. The ordinary
push hook uses the same gate and its valid memoized results. Do not repeat the checks
below when the gate has already supplied their evidence for the same candidate.
Release packaging also runs on this PC; start the packaged candidate for the dry run.

### Functional test selection

`paths` lists a group's complete inputs for evidence fingerprints and dirty-input
checks. `select` lists the files whose edits directly select it. `depends_on` names
producer groups whose changes can affect this group; these edges select downstream
regressions and inherit producer inputs, rather than ordering test commands.

| Group | Functional coverage | Direct change owners |
|---|---|---|
| `wstx-rust` | Rust unit and integration tests | Native sources, Cargo inputs and Rust toolchain |
| `protocol` | Status messages, sessions, reconnect and protocol thin-link budget | Server code, shared status client, protocol tests/helpers and runtime dependencies |
| `profiles` | Saved settings, independent stations, profile lifecycle and pending-status behavior | Profile tests and recording client/layout, which owns the shared controls container |
| `recording-storage` | Import, validation, storage, jobs, cancellation and source provenance | Shared recording test file; also affected by profile and fixture producers |
| `recording-display` | Spectrum, waterfall, calibrated bins, palette, sliders, readouts and geometry | Shared recording test file; also affected by recording source/job producers |
| `recording-thin` | Optional display pacing, bounded subscribers and the full 32 kbit/s display/status regression | Shared recording test file; also affected by display rendering |
| `recording-fixtures` | Offline fixture planning, integrity and refusal paths | Fixture tool, plans and tests, plus Node package metadata |
| `sysml-documentation` | Canonical catalog/trace checks, full semantic and architecture validation, model/tool tests | Model and tooling changes; bound source remains a complete fingerprint/dirty-guard input |
| `source-model-traces` | Fast canonical source/model identity and binding checks; no Java or model mutation suite | Client, server and test source, plus model/tool changes |

All existing test files remain registered. The recording test file is partitioned by
names: `^TC-018-` goes to storage, `^TC-010-002` to thin-link checks, and the complement
to display. The complement includes future names instead of silently omitting them.
The unchanged standalone fixture tests have their own group. No test assertion or
test case is removed by selection.

The model has an explicit documentation owner. Its edits select full model validation;
runtime oracles are selected by changed implementation and executable tests. Source
edits also select the fast binding check, without a dependency that runs the full Pilot
mutation suite on every code edit. Both model suites fingerprint the model, tool and
complete client/server/test source inputs they read. A source edit or deletion invalidates
old trace evidence and full-model evidence, even when only the fast suite is selected.
Independent contract comparison still checks that tests prove the changed promises.

Selection is conservative at shared-file boundaries: a recording client edit also
selects profile regressions because that client moves and sizes the shared controls
container; server edits select protocol and every downstream browser group. An edit
to the shared recording test file selects all three recording groups. The selector
does not infer changed functions from a file or guess dependencies from an agent's
description. Unmapped inputs select every group that declares them; entirely unknown
paths and selection-policy changes cause a full fallback. The workflow is a shared
unmapped input of every group, so workflow edits also select them all.

Preview the selected commands and reasons without running checks or recording a pass:

```powershell
python harness/core/tools/gate.py --plan --base <base-commit>
```

Run all eligible groups and compiler checks without memo reuse when a full validation
is required:

```powershell
python harness/core/tools/gate.py --full
```

Test networking remains isolated cost 2; this selection
does not authorize hardware or external-service tests.

From the repository root:

```powershell
rustup target add x86_64-pc-windows-msvc
cargo fmt --all -- --check
cargo clippy --workspace --locked --all-targets --target x86_64-pc-windows-msvc -- -D warnings
cargo test --workspace --locked --all-targets --target x86_64-pc-windows-msvc
cargo build --workspace --locked --release --target x86_64-pc-windows-msvc
./target/x86_64-pc-windows-msvc/release/wstx-rust.exe
```

The server stays running. Open `http://127.0.0.1:8080` in a browser; stop the server
with Ctrl+C. Remote TLS and access settings are defined in the
[communication contract](../sysml/Requirements.sysml).

For automated browser tests, install Node 24 and run from the repository root:

```powershell
npm ci --ignore-scripts
npx playwright install chromium
cargo build --locked
npm test
```

This is the same full suite selected by the local gate, including the bandwidth test.
Use the standalone command for targeted development or when that evidence is missing;
it is not an extra mandatory run after a successful gate. The manual GitHub workflow
remains an alternative execution location for this full recipe when explicitly chosen.

`WSTX_TEST_EXE` optionally selects an exact packaged executable. Otherwise tests use
the debug executable under `CARGO_TARGET_DIR` when set, or `target/`.
Screenshots and the thin-link measurement report are written to ignored `test-results/`.
The portable link simulator uses modelled network overhead, not packet capture;
see the [measurement limits](../sysml/Requirements.sysml).

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)

## Product model maintenance

The reusable [SysML authoring instruction](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md)
explains how to write models without project-specific assumptions. This binding selects the exclusive authority policy below and the local toolchain. The
functional entry point is [Requirements.sysml](../sysml/Requirements.sysml), with the
[architecture](../sysml/Architecture.sysml) and the model packages it references.
Harness instructions are not represented in product SysML.

### Exclusive functional authority

`Requirements.sysml` declares SysML authority with the exact first-level comment
`// Canonical authority: SysML`. Canonical SysML requires the active
`docs/WSTX Rust FSD.md` to be absent. `check`, `traces` and `fingerprints` refuse a
missing or invalid marker and refuse an active FSD, with or without the marker; there is no Markdown
authority or projection path.

When the marker is present, only SysML owns functional requirements, architecture,
behaviour, interfaces, constraints and durable verification definitions. Functional
Markdown is historical archive material: it is not edited, regenerated, synchronized
or read by preparation, implementation or validation. There is no replacement Markdown
FSD. Optional views present existing model facts and carry no additional authority.
The archived FSD lives under `docs/archive/markdown-functional-specification/`.
HOW rollout and product publication remain separate: a harness change is reviewed and
published, a product change follows the CR process.

### Pinned local validation

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

## Model authoring and validation

Read the declared authority and affected model packages first. Under canonical SysML,
edit and independently review requirements and verification expectations in the model,
then implement and check code using independent expectations. Preserve all stable IDs.
Do not infer functional truth from a regenerated artifact or observed defective code.

```powershell
python tools/sysml.py check
python tools/sysml.py traces
python -m unittest discover -s tools/sysml/tests -q
```

`check` admits only canonical SysML, checks canonical identities/states and trace
bindings, loads the complete model set in the pinned Pilot, then applies the independent
architecture integrity oracle. `fingerprints` prints current input hashes for review;
it never renews model approval. No command writes a model.
`traces` requires canonical SysML and checks only authority, catalog and source/model
bindings. It never invokes Java, the mutation suite or application behavior. Source-only
edits select this fast check; model/tool changes retain the full checks as well.

The `sysml-documentation` level-2 suite owns these checks. Application outcomes remain
in their existing functional suites and issue evidence; no duplicate application build
is required merely to inspect model syntax. A selected compiler or behavioural gate
remains binding. Missing tools, files or evidence fail rather than becoming a skip/PASS.

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
They also exercise authority ambiguity and refusal, missing identities/files, broken traces, archive independence and unavailable tool/library cases.

The `check` command also requests a resolved semantic inventory from the same Pilot
process. The Java adapter traverses actual usage/type/connector objects, inherited
features, conjugated directed items, reference subsetting, binding-versus-ordinary connector kinds
and backend variants. Python
checks an independently authored endpoint/identity oracle for the declared architecture: required physical/delegation paths, recording and encode paths, one profile
and backend variation per station, common authority, correlated resource context and
no extra bypass edges or detached runtime inventories. Every boundary role is checked
against its independently specified complete item-kind/direction signature, including
physical radio providers and inherited/delegated ports. Identity obligations require
binding connectors; ordinary connections between the same endpoints do not satisfy them. Views may expose existing
structure but cannot add runtime parts/connections. Empty/missing inventory fails closed.
The oracle is deliberately specific to this target architecture, not a general SysML
connectivity theorem or generated approval of whatever the candidate model contains.

TC-DOC-005 fixtures remove connections, bypass authority, split authority, duplicate a
backend, redirect association/context identity, change waveform/provider directions or semantic item kinds, weaken identity bindings, add detached
stations and add runtime structure to a view. They run through the real Pilot before
the integrity assertions. Legal but disconnected/miswired models must fail the explicit
integrity oracle even when ordinary semantic validation succeeds. The fixture list and
expected diagnostics remain executable companions to the HOW test definitions below.

Successful parsing/resolution is not execution of modeled verification cases, proof
that Rust satisfies the model, or proof of prose behavior. Actual application outcomes
belong to test output and the implementing CR. Code/model correspondence and connector coverage require independent review against the canonical contract; a disconnected but well-typed model can pass semantic validation.

## Project model documentation contract

### Required sequence for functional issues

1. Identify the current canonical contract, implemented baseline and affected owners.
2. Define changed requirements and independent verification expectations in the canonical
   artifact. For SysML authority, update the model directly; do not edit archived Markdown.
3. Obtain independent meaning/readiness review of behaviour, data, ownership, states,
   timing, errors and test oracles before implementation. Unresolved decisions block the slice.
4. Implement against the reviewed model and declared normative references. Verification
   keeps independent expected values and does not generate its sole oracle from that code.
5. Run the ordinary selected checks and independently review the exact candidate. Keep
   test existence, actual execution, model readiness and live acceptance separate.
6. Before issue closure reconcile delivered functionality, durable cases and model/source
   bindings. Current issues retain approval, review, deployment and dated execution evidence.

### Method clauses (Markdown only)

These are HOW bindings, not product requirements and not SysML model elements.

| ID | Subject | Rule | Verification |
|---|---|---|---|
| CL-014-01 | Authority | One declared functional authority applies. Canonical SysML and an active FSD cannot coexist; archived Markdown is never an ongoing input after cutover. | TC-DOC-001; TC-DOC-007 |
| CL-014-02 | Functional scope | Model product requirements, behaviour, architecture/interfaces and verification. Keep harness, skills, process and build documentation Markdown-only. | TC-DOC-001; manual scope review |
| CL-014-03 | Architecture | Preserve physical roles, population/identity/ownership, actual ports and directed semantic exchanges. Views select existing model facts and cannot supply missing architecture. | TC-DOC-005 |
| CL-014-04 | Real validation | Required checks use the pinned full validator/library. Missing tools/files, syntax/name/semantic errors or missing completion evidence fail with no lint fallback. | TC-DOC-003; TC-DOC-004 |
| CL-014-05 | Stable identities and traces | Preserve stable FR/CL/TC identities and declared states. Clause ownership and verification links are reciprocal. Delivered declarations name existing implementation/executable or explicit manual bindings; no declared status means a test passed. | TC-DOC-001; TC-DOC-002; TC-DOC-007 |
| CL-014-06 | Structural integrity | Validate the resolved architecture against the independent physical/end-to-end oracle, including identity bindings, exclusive backend and shared authority. A legal but miswired model fails the oracle. | TC-DOC-005 |
| CL-014-07 | Implementation readiness | Before code, the selected model slice settles observable behaviour, interfaces/data, ownership, state/timing/error choices and independent oracles. Explicit implementation freedoms do not authorize unresolved functional decisions. | TC-DOC-006 |
| CL-014-08 | Functional sequence and closure | Use the declared canonical artifact first, independently review it, implement against it and verify with independent expected results. Reconcile delivered behaviour and durable cases before closing the issue. SysML-only authority requires no maintained/generated Markdown specification. | TC-DOC-006; TC-DOC-007; independent closure review |
| CL-014-09 | Modeling feedback | Correct differences against the declared authority; do not bless code defects by rewriting requirements. Record causes/review on the issue and improve demonstrated reusable/project-specific gaps, with a focused regression where useful. | TC-DOC-006; independent review |

## Documentation-tool test definitions

These checks prove HOW clauses, not radio functionality. Level 2 means isolated
verification on the documentation development PC using local fixtures and the pinned
portable Pilot. No radio, live service, Jupyter server or global Java is needed.

| ID | Clauses | Independent actions and expected observations | Method and location |
|---|---|---|---|
| TC-DOC-001 | CL-014-01, CL-014-02, CL-014-05 | Inspect stable IDs, declared states, scope and FR/CL/TC relationships. Tooling reads the canonical model directly, checks bindings and never rewrites it or requires a Markdown view. | Automated local model/tool fixtures; independent scope/meaning review. |
| TC-DOC-002 | CL-014-05 | Mutate declared state/identity/link or remove a required artifact and expect a named nonzero refusal. | Automated isolated fixtures on this PC. |
| TC-DOC-003 | CL-014-04 | Feed the actual Pilot a valid model, malformed syntax and unresolved names/types. Accept only the valid model; other cases return diagnostics and nonzero. | Automated pinned Pilot, local fixtures. |
| TC-DOC-004 | CL-014-04 | Remove/corrupt Java, validator/library or model paths. Required validation fails nonzero and never reports semantic PASS. | Automated tool/prerequisite fixtures on this PC. |
| TC-DOC-005 | CL-014-03, CL-014-06 | Load the complete architecture with the actual Pilot, inspect resolved port/item/association/binding inventory and compare with independent endpoint expectations. Remove/delegate/bypass/split/duplicate/redirect a required path or authority, change item type/direction, weaken identity binding or add view-only runtime parts. Each negative fails semantics or integrity; a rendered view cannot repair it. | Automated full-validator mutation fixtures and independent architecture review on this PC. |
| TC-DOC-006 | CL-014-07, CL-014-08, CL-014-09 | Independent reviewer traces the affected canonical contract to code boundaries and independent expected observations; missing required decisions, model/contract disagreement or a shared-only generated oracle refuse readiness. Recheck exact changes and closure reconciliation. No syntax/fingerprint result establishes implementation sufficiency. | Manual source/model/meaning review on this PC; automation cannot establish complete intended meaning. |
| TC-DOC-007 | CL-014-01, CL-014-05, CL-014-08 | Refuse dual/missing authority and an active FSD without the marker, missing/duplicate stable IDs, missing required packages, invalid state, nonreciprocal verification links, missing/escaping source paths and unsupported executable claims. Refuse dangling active references to retired FSD content. Edited/missing archived Markdown does not change canonical checks; no command rewrites the model. New packages must be referenced by ProductScope and validated in full. Source edits/deletions invalidate both model suites' evidence; source-only changes select fast traces without the full model suite. Fast traces refuses a deleted binding and never invokes Java. | Automated isolated Python fixtures on this PC; full integrated Pilot validation remains separate. |

Executable companions are `tools/sysml.py`, `tools/sysml/tests/` and the pinned
`tools/sysml/Validate.java` adapter. Results and independent review
are recorded on the owning issue, never as invented model verdicts.

## Communication verification model

Functional limits and measurement acceptance are specified in
[the canonical communication requirements](../sysml/Requirements.sysml).
The following describes this project's verification machinery.

The portable test proxy shapes actual TCP-stream bytes (including real TLS records
in TLS tests), in at most 512-byte segments, with a shared 4,000-byte/s schedule in each
direction and 150 ms one-way latency. Each segment is additionally charged 80 bytes
for TCP/IPv6 headers and 80 bytes in the reverse direction for an ACK. This is explicit
modelled network overhead, not a packet capture. It does not reproduce retransmissions,
packet loss, congestion control or exact kernel packetization. Its bulk-transfer timing
is tested independently of the station application. Physical-link certification is outside
this CR; results MUST identify this model rather than claim on-wire measurements.
The simulator disconnects overloaded peers above its 128 KiB per-direction pending/write
buffer cap instead of modelling an unlimited congestion queue.
Browser Navigation/Resource Timing separately reports cold page and asset transfer sizes
at the browser HTTP layer, including its reported HTTP-header overhead; these counters
exclude TLS/TCP/IP overhead. Connection-to-displayed-status time and concurrent visible
Refresh status times are measured separately. Silent loss is exercised by discarding bytes
without closing the established test connections; this is a byte-stream blackhole, not
packet-level loss emulation. Automated real-time bounds allow one second of scheduler
tolerance for the nominal 13-second silent-loss detection bound.

The stalled-reader test keeps a peer paused with automatic Pong replies disabled
past the liveness deadline plus heartbeat-tick bound, then checks disconnection and
the other peer's responsiveness. It proves bounded unresponsive-peer removal; because
OS buffers can absorb the request burst, it does not claim to observe the two-second
send-timeout branch or independently measure total queue memory.

## Recording fixture acquisition

Candidate recordings and oracle limitations are specified in
[the canonical model](../sysml/Requirements.sysml).

- Obtain candidate fixtures directly from the pinned ft8_lib revision and keep its MIT license and attribution with any imported material. The root license names copyright 2018 Karlis Goba; no separate sample-specific license was found in the reviewed tree.
- Keep original WAV files and expected-output texts unchanged, with hashes and source URLs recorded in a fixture manifest when imported.
- For the selected WSJT-X `v3.3.0-beta4` behavior reference, generate a separate output set and record the exact binary, settings, command, and audio input. Do not overwrite the historical references.

### Canonical model catalog and source bindings

The canonical entry point is `docs/sysml/Requirements.sysml`. The model set includes
Requirements, Architecture, Profiles, RecordingReceive, StationDecode, RadioIO,
OperatingLayout, OperatingReceive, StationProtocol and ProductScope. Additional packages
are discovered, scanned and fully validated; ProductScope references their package so
that removal causes a name-resolution failure. A missing required baseline package fails.

Each requirement/clause declares `coverage : ImplementationState` as target, partial
or implemented. Each verification declares `automation : AutomationState` as planned,
partial or implemented. These are declarations of available companions, not execution
or acceptance results. Clauses have native dependency links to their FR owners and TC
cases; TC objectives verify the same clauses, with reciprocal links checked.

Partial/implemented requirement and clause definitions carry a root-relative binding:

```sysml
attribute implementation : String = "server/src/profile.rs; client/app.js";
```

Partial/implemented verification definitions carry existing executable bindings:

```sysml
attribute executable : String = "tests/profiles.test.cjs; server/src/profile_tests.rs";
```

Bindings are semicolon-separated repository-root-relative files, never absolute or
escaping paths. Automated cases require a matching `Proves:` case identity, an exact
Node test-name identity, or an explicit `path::test_symbol` binding. A Rust symbol must
exist; independent review still establishes its relationship to the promised behaviour.
The checker admits bindings under the exact Git roots `client/`, `server/` and `tests/`,
which both model suites fingerprint. These are validation-input coverage bounds, not a
product limitation. A new source root requires a reviewed HOW update to the admission
constant, both suites' complete inputs, fast selection and their regression together;
an unregistered binding is refused rather than silently borrowing stale evidence.
Recognized numeric product identities in source `Proves:` comments must exist in the
canonical catalog; same-prefix shorthand is expanded. HOW and fixture-specific names
are not product declarations. A tag's presence still does not establish test execution.
A manual physical case uses `attribute method : String = "manual";` and names its
existing probe/source, without claiming an automated or executed result. A planned case
may lack an executable. Source tags and existing files prove presence, not conformance.

Canonical documents link to active model elements or existing repository paths with
correct model-file-relative Markdown links. Retired FSD section dependencies, source-hash
markers and broken file references fail. The minimum stable identity baseline includes
all 23 FRs, 38 clauses and 38 verification identities present in the reviewed application
baseline; additions retain unique identities. An intended retirement or authority change
requires explicit review rather than deleting a definition to obtain a green check.
