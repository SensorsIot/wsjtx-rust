# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/V2/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/V2/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

## Windows build and packaging

The Rust executable serves an embedded browser status client and a versioned WebSocket interface. Radio functionality is not implemented.

The root Cargo workspace contains the station-server package in `server/`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` files are embedded at Rust compile time, without a frontend build step.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml)
is a manual alternative, started explicitly from the Actions page. Pushes and pull
requests do not trigger it. Normal development, the full test suite and release packaging
run on the Windows PC; a local pass is not automatically repeated on GitHub.

The workflow uses a GitHub-hosted Windows Server 2022 x64 runner with the MSVC build tools. It installs Rust 1.99.0, matching `rust-toolchain.toml`, and checks formatting, Clippy warnings, tests, release compilation, and execution of the built program. The executable is uploaded as the `wstx-rust-windows-x64` artifact with a 14-day retention period.

No radio, sound device, third-party decoder or repository secrets are required. Rust dependencies implement HTTP/WebSockets, asynchronous networking, JSON and TLS. Node 24 test dependencies provide a real Chromium browser, independent WebSocket peer and disposable TLS certificates. The workflow runs browser tests against the compiled release executable. These checks validate status communication, not FT4/FT8 behavior.

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
| `sysml-documentation` | FSD/model synchronization, semantic and architecture checks, model/tool tests | FSD, SysML and model tooling |

All existing test files remain registered. The recording test file is partitioned by
names: `^TC-018-` goes to storage, `^TC-010-002` to thin-link checks, and the complement
to display. The complement includes future names instead of silently omitting them.
The unchanged standalone fixture tests have their own group. No test assertion or
test case is removed by selection.

The FSD and model have an explicit documentation owner. Their edits select model
validation; runtime oracles are selected by changed implementation and executable
tests. The required independent contract comparison still checks that executable
tests cover changed promises. Full input fingerprints retain the FSD, so changed
contract input invalidates previous evidence when a runtime group is selected.

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

The first product CR after harness adoption uses an empty run ledger, as required by
the harness rollout process. Test networking remains isolated cost 2; this selection
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
[communication contract](../WSTX%20Rust%20FSD.md#121-connection-and-security).

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
see the [measurement limits](../WSTX%20Rust%20FSD.md#124-thin-link-budget-and-test-model).

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)

## Product model maintenance

The reusable [SysML authoring instruction](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md)
explains how to write models without project-specific assumptions. This binding selects
Markdown-primary authority and the local toolchain below. Product model artifacts,
coverage and view scope belong to [the architecture](../WSTX%20Rust%20FSD.md#1111-functional-model-and-views);
functional promises and application test cases remain in
[the FSD](../WSTX%20Rust%20FSD.md). The project model-maintenance contract and
documentation-tool test definitions are recorded below.
Harness instructions are not represented in product SysML.

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

## Synchronization workflow

Edit the authoritative Markdown first, preserving IDs. For FSD changes, regenerate:

```powershell
python tools/sysml.py sync
```

Both model fingerprints now refer to the single FSD. For every FSD change, review its
effect on the manually modeled architecture, reconcile affected parts, ports and
connections, and update the architecture source-hash marker after that review. Updating
the marker alone is not a conformance review. Print the normalized FSD source hash with:

```powershell
python -c "from pathlib import Path; import hashlib; print(hashlib.sha256(Path('docs/WSTX Rust FSD.md').read_text(encoding='utf-8').encode()).hexdigest())"
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
features, conjugated directed items, reference subsetting, binding-versus-ordinary connector kinds
and backend variants. Python
checks an independently authored endpoint/identity oracle bound to FSD
section 11.9: required physical/delegation paths, recording and encode paths, one profile
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
expected diagnostics remain executable companions to the FSD's durable case definition.

Successful parsing/resolution is not execution of modeled verification cases, proof
that Rust satisfies the model, or proof of prose behavior. Actual application outcomes
belong to test output and the implementing CR. Source/model correspondence and connector coverage require review against the Markdown arrows; a disconnected but well-typed model can pass semantic validation.

## Project model documentation contract

### Required sequence for functional issues

1. Write and approve the requirements and test cases in the single Markdown FSD first.
   Preserve stable IDs and define setup, actions, expected results, independent oracles,
   test level and execution location before implementation.
2. Transfer the approved functional contract into the SysML model, keeping the Markdown.
3. Compare Markdown and SysML for equivalent meaning: behavior, interfaces, ownership,
   states, timing, failure outcomes and verification cases. Resolve gaps and disagreements
   against the approved Markdown before code is written. Syntax or matching names alone
   is not this comparison.
   For every mismatch, record the cause and review the shared SysML authoring rules and
   checks. Correct the model, improve reusable guidance or project-specific enforcement
   where it was insufficient, and add a focused regression where useful. Enforce a clear
   existing rule rather than adding a duplicate. Repeat the comparison before proceeding.
4. Implement the product code from the reconciled SysML slice and its declared normative
   references. If a required decision is missing, return to requirements/model alignment;
   do not invent behavior or silently fill the gap during coding.
5. Verify the resulting code against the original Markdown requirements and the test
   expectations defined there. Do not derive both implementation and expected results
   solely from SysML or from the new code: that could reproduce the same mistake twice.
6. Record results and reconcile the FSD/model before closing the issue.

Markdown is the authority and independent verification reference; SysML is the functional
implementation specification. Views are optional presentations, not another source of
behavior. This sequence applies to product functionality; harness HOW remains Markdown.

Markdown remains authoritative initially. The FSD owns functional requirements and
test definitions, architecture, interface responsibilities and implemented wire contracts. A synchronized SysML v2
representation supports structured review without changing this authority or renumbering
the existing identities. This section specifies documentation behavior, not radio behavior.
Only product functional documentation is represented in SysML. Harness/process/skill
rules and these CL-014/TC-DOC method definitions remain Markdown-only.

| Clause | Area | Required behavior | Verification |
|---|---|---|---|
| CL-014-01 | Documentation authority | The parallel model MUST preserve the authoritative Markdown sources and stable FR/CL/TC identities. Model syntax or tool conventions MUST NOT silently migrate authority or replace a requirement with an implementation deviation. | TC-DOC-001 |
| CL-014-02 | Model coverage | The model MUST declare its covered source slices and distinguish target architecture, partial requirements and implemented status-slice/test elements. It MUST NOT claim that prose projection or successful semantic validation proves full behavior or implementation conformance. | TC-DOC-001; review |
| CL-014-03 | Architecture boundaries | The structured architecture MUST retain separate audio and radio-control interfaces, variable station processes and optional native FlexRadio implementations behind those interfaces. It MUST retain the scoped Rust control implementation rather than imply a complete Hamlib replacement or a mandatory Hamlib dependency. | TC-DOC-001; semantic validation and review |
| CL-014-04 | Validation | Reproducible checks MUST compare the covered Markdown projection and run a pinned full SysML parser/name resolver/semantic validator. Missing/invalid tools, model libraries or model files MUST fail; lightweight synchronization/lint checks MUST NOT masquerade as semantic proof or runtime test verdicts. | TC-DOC-002; TC-DOC-003; TC-DOC-004 |
| CL-014-05 | Synchronization | Changes to a covered Markdown source and its model MUST be reconciled in the same change. Generated content MUST be regenerated and checked; manually modeled architecture MUST be reviewed against its source. Unsupported or unmodeled detail MUST remain explicit. | TC-DOC-001; TC-DOC-002 |
| CL-014-06 | Architecture integrity | The structured architecture MUST represent one coherent physical deployment and its connected software decomposition. Physical links MUST delegate to the same browser/station/backend usages; receive and transmit modem paths and profile-owned recording input MUST remain connected. Per-station backend selection MUST be exclusive, station count variable, and control paths for a shared radio MUST use one effective authority rather than independent per-station authorities. Directed semantic exchanges MUST retain independent audio/control responsibilities without inventing wire schemas. | TC-DOC-005 |
| CL-014-07 | Implementation sufficiency | The product SysML companion is intended to support AI implementation of the complete functional product. Before code for a functional CR, its approved model slice MUST settle the behavior, interfaces, data ownership, states, timing, errors and independent verification oracles required to implement that slice, with pinned normative external protocol references. An implementing agent MAY choose only declared implementation freedoms and MUST NOT guess unresolved functional decisions. Views only present existing model facts and are not required inputs for code generation. Markdown remains authoritative; unresolved slices MUST be marked not implementation-ready, and structural validation MUST NOT imply complete code-generation readiness. | TC-DOC-006; manual preparation review |
| CL-014-08 | Functional implementation sequence | Each functional issue MUST define Markdown requirements and tests first, transfer them to SysML, compare both for semantic equivalence before coding, implement from the reconciled model, and verify the code against the original Markdown requirements and independent test expectations. The Markdown MUST remain available as the authority and verification reference. Missing decisions return to contract alignment; implementation and expected results MUST NOT share the model or code as their sole oracle. | TC-DOC-006; independent review |
| CL-014-09 | Modeling feedback | A Markdown/SysML mismatch MUST trigger a model correction, recorded cause and review of the authoring instructions/checks. Missing or ambiguous reusable guidance MUST be corrected in the shared harness; project-specific safeguards belong in this binding. Add a focused regression where useful, enforce already-clear rules, and repeat semantic correspondence review before coding continues. Correct Markdown MUST NOT be rewritten merely to agree with an incorrect model. | TC-DOC-006; independent review |

[Functional model and views](../WSTX%20Rust%20FSD.md#1111-functional-model-and-views) defines the model artifacts and coverage.
[Project-specific harness instructions](Project-Specifics.md#product-model-maintenance)
define source synchronization and pinned tool entrypoints. The initial model projects
defined requirement/clause/test identities and selected architecture boundaries; it does
not formalize every protocol rule, numerical constraint, state machine or radio waveform.

## Documentation-tool test definitions

These checks verify CL-014-01 through CL-014-09; they do not test radio functionality.
TC-DOC-006 is the explicitly manual preparation/readiness review; the remaining cases
combine automated model checks with the stated source-correspondence review.
**Level: 2 - isolated local verification, automated unless declared manual. Where they run:** the Windows development PC,
local Markdown/model fixtures and the pinned portable OMG reference validator. They
require no radio, live service, Jupyter server or global Java installation.

| ID | Clauses | Inputs/actions | Expected results |
|---|---|---|---|
| TC-DOC-001 — Projection and identities | CL-014-01, CL-014-02, CL-014-03, CL-014-05 | Generate the declared FSD projection, compare stable IDs/trace relationships and inspect the selected architecture against its Markdown source. | Existing identities/prose remain intact; canonical Markdown is not mutated; the generated representation is current. Audio/control separation, variable station instances and optional native backends remain explicit. Semantic/model review remains distinct from behavior execution. |
| TC-DOC-002 — Source/model drift | CL-014-04, CL-014-05 | In disposable fixtures, change a covered source or remove/corrupt its generated representation; change the architecture source without reconciling its model. | Synchronization fails and identifies the stale/missing artifact. Regeneration alone cannot claim a manually modeled architecture has been reviewed. |
| TC-DOC-003 — Full-tool positive and negative models | CL-014-04 | Run the actual pinned validator on a legal model, unmatched syntax and an unresolved type/reference. | The legal model is accepted; malformed syntax and unresolved references return nonzero semantic-validation outcomes with diagnostics. This does not execute modeled verification cases or prove application behavior. |
| TC-DOC-004 — Unavailable validation | CL-014-04 | Invoke required validation with a missing/invalid Java/validator/library path or absent model file. | The command fails nonzero and never reports semantic PASS. There is no regex-only fallback. |
| TC-DOC-005 - Connected architecture integrity | CL-014-03, CL-014-06 | Load the complete target architecture with the pinned Pilot on the Windows development PC. Extract resolved usage/port/connector chains from its semantic AST and compare with the independent physical and end-to-end path oracle in the FSD architecture chapter. In isolated copies remove a required connection/delegation, reroute an endpoint to bypass authority, duplicate a selected backend, split shared authority, reverse a provider direction, change a semantic item kind, or weaken an identity binding to an ordinary connection. | The accepted model has one connected physical/software deployment, variable stations, profile-owned recording and TX/modem paths, directed semantic port exchanges, one backend variation per station, and one shared authority. Each negative fixture fails semantic validation or an explicit integrity diagnostic. A view-only edit cannot repair a failed underlying path. Level 2: local isolated automated model checks; no radio, service, viewer or network access. This establishes structural correspondence, not runtime safety, protocol compliance or performance. |
| TC-DOC-006 - Functional implementation readiness | CL-014-01, CL-014-02, CL-014-07, CL-014-08, CL-014-09 | Before a functional CR writes code, an independent reviewer compares its Markdown requirements/test definitions with the SysML slice and pinned references for equivalent meaning. Trace every required behavior, interface/data/state/timing/error decision and independent test oracle; list choices explicitly left free. Confirm that implementation uses the reconciled model and verification retains the original Markdown expectations. Repeat with a required decision unresolved, a Markdown/model mismatch with no corrective authoring feedback, or an expected result derived only from the new code/model. | Readiness requires an implementation-sufficient model consistent with Markdown and independent Markdown-based verification. An unresolved decision, disagreement, missing corrective authoring feedback or shared-only implementation/test oracle refuses readiness and identifies the gap; views cannot supply missing semantics. Level 2: manual offline contract review on the Windows development workspace, because syntax/connectivity automation cannot determine whether all product decisions are sufficient for implementation. This repair does not claim the full product passes readiness. |

Executable traces are the scoped tests under `tools/sysml/tests/`, the synchronization
entrypoint `tools/sysml.py` and full-validator adapter `tools/sysml/Validate.java`;
their usage is defined in [project-specific harness instructions](Project-Specifics.md#product-model-maintenance) and their functional coverage in [the architecture](../WSTX%20Rust%20FSD.md#1111-functional-model-and-views). Execution evidence belongs
to the documentation CR, not a fabricated modeled verdict.

## Communication verification model

Functional limits and measurement acceptance are specified in
[the FSD communication chapter](../WSTX%20Rust%20FSD.md#124-thin-link-budget-and-test-model).
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
[the FSD](../WSTX%20Rust%20FSD.md#13-ft8-sample-recordings-and-provenance).

- Obtain candidate fixtures directly from the pinned ft8_lib revision and keep its MIT license and attribution with any imported material. The root license names copyright 2018 Karlis Goba; no separate sample-specific license was found in the reviewed tree.
- Keep original WAV files and expected-output texts unchanged, with hashes and source URLs recorded in a fixture manifest when imported.
- For the selected WSJT-X `v3.3.0-beta4` behavior reference, generate a separate output set and record the exact binary, settings, command, and audio input. Do not overwrite the historical references.
