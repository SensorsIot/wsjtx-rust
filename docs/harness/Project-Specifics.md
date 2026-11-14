# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/main/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/main/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

## Machines and roles

Two Windows PCs work on this repository with the same GitHub account: **HB9BLA**
(`192.168.0.37`) and **Andreas** (hostname `Andreas`), both with the checkout
`D:\Github\wsjtx-rust`. Neither has a role: which one is used is a matter of convenience,
and both are set up alike (operator 2026-11-11). Two things decide the machine:

| Work | Machine |
|---|---|
| Anything that needs the transceiver (IC-7300, COM3): live and hardware tests (cost 3 to 5), radio acceptance, installs on the station | HB9BLA, where the transceiver and the station are |
| A test of client and server across the network | Both, one as server and one as client |
| Everything else: definition, model, harness, coding, builds, tests, the gate, FlexRadio work (the FlexRadio is reached over the network) | Either |

What holds whichever machine is used:

- The main branch moves by one gate at a time. Before a hand-in or a push to the main
  branch, the machine checks that no gate runs on the other one.
- Test inputs that are not in the repository, and the timing baseline, exist only where
  they were set up. A suite that needs them runs on a machine that has them; today that
  is HB9BLA.
- Heavy builds and gates on HB9BLA share it with the live station: do not operate the
  radio during a heavy gate (#49, harness#35).

- The `windows-rust.yml` artifact (`wstx-rust-windows-x64`) is build evidence only. It
  shows that the build and tests pass on a clean Windows runner and is never installed
  on the station (operator decision, [#26](https://github.com/SensorsIot/wsjtx-rust/issues/26)).
- The machine that currently builds an issue is named by the issue's single
  `owner: HB9BLA` or `owner: Andreas` label. A machine does not start an issue owned
  by the other one ([harness #23](https://github.com/SensorsIot/harness/issues/23)).
- One PC holds development at a time. `python harness/core/tools/handover.py to <machine>`,
  run on the PC that is left, moves it: the checks, the owner labels, the checkpoints, the
  holder and the arriving PC's setup are the tool's
  ([several machines](../../harness/core/agents/roles.md#several-machines)). The binding
  is `machines:` and `handover:` in `.harness/config.yaml`: HB9BLA is reached from Andreas
  over SSH; on Andreas the arriving half is run by hand (`handover.py arrive`). The test
  inputs it verifies are those of `.git/migration-data/MANIFEST.json`. Everything local is
  pushed before a transfer: the tool pushes nothing (operator 2026-11-11).

## Windows build and packaging

The Rust executable serves the embedded browser, versioned station interfaces and implemented receive services. Native Windows audio, typed CAT adapters and the pure FT4/FT8 decoder are separate modules. Their presence does not establish complete mode parity or live acceptance; current implementation and verification declarations belong to the functional model and issue evidence.

The root Cargo workspace contains the station-server package in `server/`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` files are embedded at Rust compile time, without a frontend build step.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml)
is a manual alternative, started explicitly from the Actions page. Pushes and pull
requests do not trigger it. Normal development, the full test suite and release packaging
run on HB9BLA; a local pass is not automatically repeated on GitHub.

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
checks. `select` lists the files whose edits directly select it; only `select` decides
selection (harness#28). No group declares `depends_on`: the harness follows those edges
transitively, so one server edit fanned out over every browser group. A group instead
names in its own `select` the files whose behaviour its test cases prove.

| Group | Functional coverage | Direct change owners |
|---|---|---|
| `wstx-rust` | Rust unit and integration tests, except the library's `decoder::` unit tests (`wstx-rust-decoder`) | Native sources, the transmit and decoder fixtures the tests include, the model (`docs/sysml/`), whose values its tests read, the model-value fixture tree, Cargo inputs and Rust toolchain |
| `wstx-rust-decoder` | The library's `decoder::` unit tests, optimized with debug assertions and overflow checks | Decoder sources, the transmit packer (`transmit/pack.rs`, `transmit/mod.rs`), the library root, the decoder fixtures they include, the model (`docs/sysml/`), whose values its tests read, the Rust model-value reader, Cargo inputs and Rust toolchain |
| `protocol` | Status messages, sessions, reconnect and TLS login | Router (`main.rs`), status page client (`app.js`, `index.html`, `style.css`), protocol tests/helpers, runtime dependencies |
| `protocol-thin` | Timing: TC-021-007 silence bounds, TC-021-008 32 kbit/s link and 60-second idle budget, stalled-reader liveness, link simulator | Timing inputs: router/websocket, HTTP compression, status page client, protocol tests and link simulator helpers |
| `profiles` | Saved settings, independent stations, authorization and pending-status behavior | Router, profile and authorization owners, page and recording client (shared controls container), profile tests, the model file whose values its tests read (`docs/sysml/backend/profile/Profile.sysml`), `docs/sysml/shared/Units.sysml` and the JavaScript model-value reader |
| `recording-storage` | Import, validation, storage, jobs, cancellation and source provenance | Router, recording owners, recording client, recording test file, fixture tool and recording manifests, the model file whose values its tests read (`docs/sysml/backend/profile/Recordings.sysml`), `docs/sysml/shared/Units.sysml` and the JavaScript model-value reader |
| `recording-display` | Spectrum, waterfall, calibrated bins, palette, sliders, readouts and geometry | Router, recording and spectrum owners, recording client, recording test file and manifests |
| `recording-thin` | Timing: display pacing, bounded subscribers, the full 32 kbit/s display/status regression and the TC-010-005 Detailed peer cadence | Timing inputs: router, recording/spectrum owners, HTTP compression, status and recording clients (loaded cold over the link), recording test file and link helpers, the model-value reader and the Recordings and Units model files |
| `operating-layout` | Operating screen, settings drawer, receive races, logbook, strategy, UDP editor, transmit status | Router and the HTTP owners the operating page calls; page, recording, contact and logbook clients; its test file |
| `contact-browser` | Contact engine, QSO sequencing, logging and halt through the browser | Router, contact/logbook/transmit owners, contact/logbook/recording clients, contact test |
| `radio-selection` | H1 compression negotiation, commissioning, browser selection cases | Router, compression, selection/radio/CAT/receive/source owners, status and recording clients, selection test, the model (`docs/sysml/`), whose values its tests read, the JavaScript model-value reader |
| `radio-selection-thin` | Timing: the native/CAT selection workload on an unshaped TLS connection (no 32 kbit/s link since #80) and its 4230-5000 ms native setup bound | Timing inputs: router, compression, selection/CAT/receive/spectrum owners, status and recording clients, its Rust and browser test files and link helpers |
| `native-flex` | FR-023 native FlexRadio against the loopback emulator: route isolation, reconciliation, capacity, mixed profiles, push-only status | Native session and status (`flex/`, `flex_http.rs`), router, authorization, profile, radio setup, recording, receive, selection and startup owners, page, recording and contact clients, its test and emulator |
| `mcp` | MCP client grant and refusals | Router, MCP/automation/authorization owners, authorization client, MCP test and credential helper |
| `recording-fixtures` | Offline fixture planning, integrity and refusal paths | Fixture tool, plans and tests, the model file whose values its provenance sweep reads (`docs/sysml/backend/profile/Recordings.sysml`), `docs/sysml/shared/Units.sysml` and the JavaScript model-value reader, plus Node package metadata |
| `model-values` | TC-DOC-014: the JavaScript model-value reader on its fixture tree | The JavaScript model-value reader, its test file, the model-value fixture tree, plus Node package metadata |
| `sysml-documentation` | Canonical catalog/trace checks, one full semantic validation (`sysml.py check`), the tests that read the model `test_[dr]*.py` | Model and tooling changes; bound source remains a complete fingerprint/dirty-guard input |
| `sysml-tools` | The SysML tool's own unit tests `test_[!adre]*.py` on isolated models | The SysML tool and its tests |
| `sysml-equivalence-tests` | TC-DOC-015: `equivalence` and `identities` on temporary repositories and the repository's history, `test_e*.py` | `tools/sysml.py`, `Validate.java` and the test file |
| `sysml-equivalence` | CL-014-17: `equivalence --marked` on each commit of `master..HEAD` marked `Model-Move: pure` | The model, the SysML tool and the files whose model citations it reads |
| `sysml-architecture` | TC-DOC-005 architecture integrity: the mutation tests `test_a*.py` on the pinned model of `1df1ba3a5` and its oracle file, and the `oracle` tests and TC-DOC-016's structure-check tests on fixture trees, one Pilot validation per mutation or model state | `Station.sysml`, `Context.sysml`, `Requirements.sysml`, `interfaces/`, the new part files, the SysML tool, `Validate.java`, the oracle file `architecture-oracle.json`, the toolchain pin and the test file |
| `decoder-correctness` | The release `decoder_signal` correctness, #57 thread-parity and #56 jt9-parity passes (all ordinary passes but the 50 ms quantum and busy-period latency) | Decoder fixtures, the library root and the model files whose values its passes read (`docs/sysml/backend/modes/Decode.sysml`, `MessagePayload.sysml`, `docs/sysml/shared/Units.sysml`) (a production decoder source selects `decoder-quality`, which runs the same passes) |
| `decoder-quality` | Timing: all seventeen release decoder passes bound to the artifact, and the owned-Job resource matrix (runs alone) | Timing inputs: the production decoder sources (not its `*_test.rs` or the test-only resource observer), `decoder_signal.rs`, the fixtures and vector tool the timed passes decode, its resource-job tools, the model files holding the budgets the matrix reads and their unit suffixes (`docs/sysml/backend/modes/Decode.sysml`, `docs/sysml/shared/Units.sysml`) and the Rust toolchain/dependency pins |
| `live-station-browser` | Native fixture through the actual Router, receive owner and browser (callsign rows) | Router, profile/recording/receive/source/audio/decoder owners, client, its test files |
| `live-station-latency` | Timing: the #57 busy-period browser latency case | Timing inputs: router, receive/source/audio/decoder pipeline, recording client, its test files, the model files holding the budgets the station process case reads and their unit suffixes (`docs/sysml/backend/modes/Decode.sysml`, `docs/sysml/shared/Units.sysml`) and toolchain |
| `source-model-traces` | Fast canonical source/model identity and binding checks; no Java or model mutation suite | Client, server and test source, plus model/tool changes |

All existing test files remain registered. The recording test file is partitioned by
names: `^TC-018-` goes to storage, except its two 250 ms cancellation bounds;
those, `^TC-010-002` and the TC-010-005 Detailed peer cadence go to thin-link checks,
and the complement to display. The communication test file sends `^TC-021-007`
(silence detection and recovery bounds) to `protocol-thin`, the complement to `protocol`;
TC-021-008 (dead peer removal on a driven clock) and TC-080-001 (the link byte log) are Rust tests in `wstx-rust` (#80). The radio selection Rust fixture `live_native_selection_tls_thin_and_off`
runs in `radio-selection-thin`, the other selection tests in `radio-selection`. Each
complement includes future names instead of silently omitting them. No test assertion,
budget or test case is removed by selection.

A group that holds a test reading a model value (`### Model values read by tests`) names, in
`paths` and `select`, every model file those readers read: each file holding a value they
read, and `docs/sysml/shared/Units.sysml` when they read a value by its unit. `docs/sysml/`
covers them all. The change that adds the first such test to another functional group adds
these files there, as additive wiring of its new coverage (#148). A timing test that reads
its bound from the model has the same files in its suite's `timing_inputs` and `paths`
(SensorsIot/harness#74).

The resource matrix of `decoder-quality` re-measures a configuration whose 50 ms CPU quantum
stayed unmeasured, at most three attempts, and the runtime (including the four-worker 2x
bound), cold-start and 64 MiB budgets of `WstxModemDecode::DecodeBudgets` bind every attempt:
any exceedance in any attempt is a failure.

The **live page check** (`tools/deploy/live-page-check.ps1`, harness#38 item 3) is in no
suite: it needs the installed station and one real restart. It runs on HB9BLA after every
deploy under the [standing deploy policy](#standing-deploy-policy) and at live
acceptance (CR step 6) of a change to `client/`, the receive, recording or logbook owners or
`tests/page-watch.cjs`, receive only, and restarts the station only while nothing is armed,
keyed, in a contact or an automation run. `live-station-browser` gates the same oracle in-process.

Measurements run only when the change touches time-critical code (harness#28). Every
timing, latency, cadence or throughput promise lives in a **timing suite** (`timing: true`:
`protocol-thin`, `recording-thin`, `radio-selection-thin`, `live-station-latency`,
`decoder-quality`). A timing suite has no `select`; its `timing_inputs` name the code that
sets the measured time, and nothing else selects it: no functional owner, unmapped-input
or unowned-path fallback, `.harness/` edit or dependency
([harness testing standard](../../harness/core/docs/standards/testing.md#timing-suites)).
The gate lists a timing suite the change reads but does not time as `TIMING ... not run`.

The timing inputs are, per suite: the router `main.rs` (status websocket, thin anchors
and detail cadence) and HTTP compression for the link suites `protocol-thin` and `recording-thin` and for `radio-selection-thin`; the status client
(`app.js`, `index.html`, `style.css`) for `protocol-thin`, and the status and receive
clients (`app.js`, `index.html`, `recording.js`) for the two others, because those clients
read over the 32 kbit/s link and cross it cold (the #55 cold-load red came from a
client-only change; `recording.js` re-reading `/audio/endpoints` every 5 s, 1b4706c36, was
the one real catch of 481 green minutes); the recording/spectrum producers for
`recording-thin`; the selection, CAT, receive and spectrum owners for `radio-selection-thin`,
but not capture, whose bounds rerun on request (harness#38);
the receive/source/audio/decoder pipeline and the recording client that polls and paints
the rows for `live-station-latency`; the production decoder sources (every one sets the
checkpoint spacing, per-item work or budgets the quantum, latency and matrix measure),
`decoder_signal.rs`, the fixtures and vector tool its timed passes decode, the protocol tables compiled into it and the
resource-job tools for `decoder-quality`. A decoder fixture change that none of them
times (the jt9 parity corpus, baselines, vectors) runs only the functional
`decoder-correctness`, beside other groups: the same passes except the 50 ms quantum and
the busy-period latency. Each suite's own test files
and the link simulator (`tests/support.cjs`, `tests/peer.cjs`) are timing inputs, and so
are the Rust toolchain and dependency pins (and the Node pins for the browser suites);
for `recording-thin` and `radio-selection-thin` (harness#38) only `tests/support.cjs`,
`rust-toolchain.toml`, `Cargo.lock` and `package-lock.json` of these, their own test files, and
`tests/peer.cjs` for `recording-thin`. `recording-thin` also names the model-value reader
`tests/model-values.cjs` and the model files whose values its TC-018 tests read
(`backend/profile/Recordings.sysml`, `shared/Units.sysml`), because nothing else selects it.
The contact, logbook, authorization, MCP, strategy, profile and UDP code, the rest of the
SysML model and the other groups' tests are not: their changes run functional groups only.

A CR that changes the measured behaviour through another path (a client timer or poll
cadence outside those files, a heavier asset, a new background task) asks for the
measurements with the commit trailer `Harness-Timing: yes`; the review checks that such
a CR carries it. `HARNESS_TIMING_REQUEST=1 git push` or `gate.py --timing` does the same for one
run; `gate.py --full` runs every timing suite. Functional groups assert behaviour; a
residual liveness deadline in a functional case (for example the 2 s status refresh and
10 s recovery bounds of the profile tests) is a known follow-up, not a measurement
promise: a mixed group would declare `timing_inputs` and guard those assertions with
`HARNESS_TIMING` (`0` skips them).

### Parallel groups and shared resources

The gate runs up to three groups at a time (`gate.parallel: 3` in
`.harness/config.yaml`), longest first, and prints each group's output whole in name
order. `protocol-thin`, `recording-thin` and `radio-selection-thin` run beside other groups
(`gate.timing_alone: false`). The bounds of the first two are wall-clock bounds on the
simulated 32 kbit/s link (byte budgets are judged from the link byte log since #80, not tested); besides those, `recording-thin` holds two local 250 ms TC-018
cancellation bounds (one while four stations replay a recording) and
`radio-selection-thin` the 4230-5000 ms native setup and 2 s Off-acknowledgement bounds.
All were measured stable beside other groups on HB9BLA (harness#28, 2026-11-03): three
gates of a compression-module edit ran the three concurrently with `wstx-rust`,
`radio-selection` and `source-model-traces`, all green, with the suite times of their
alone runs (177-178 s, 321-324 s, 262-268 s against 177, 319-320 and 260 s) and 373-382 s
wall instead of about 14 min. That evidence does not cover the CPU-heavy decoder groups as
neighbours, so `decoder-correctness` (12-thread busy-period decode) and
`wstx-rust-decoder` hold `exclusive: [link-measurement]`, which the three share
(`radio-selection-thin` again since #102: its socket qualification failed in a gate where
`decoder-quality` ran beside it, operator 2026-11-11). The CPU
measurements run alone (`exclusive: ["*"]`): `decoder-quality` and
`live-station-latency` (a browser row-latency budget on the busy decoder). The groups
declare what they must not share:

- the browser groups run `target/debug/wstx-rust.exe`, which `cargo test` relinks with
  the dev-dependency features, and Windows refuses to replace a running executable. So
  `wstx-rust` builds and runs in its own Cargo output directory
  (`$CARGO_TARGET_DIR/unit`) and `wstx-rust-decoder` in its own profile directory
  (`unit-opt`); neither touches the browser groups' executable, and both run beside them
  (harness#28; before, a `debug-exe` tag kept `wstx-rust` apart from every browser group);
- `radio-selection-evidence`: both radio-selection groups write
  `test-results/radio-selection/`;
- `decoder-quality` runs alone (`exclusive: ["*"]`): its owned-Job CPU matrix measures
  50 ms quanta that concurrent groups would disturb.

Each group names its Cargo build (`build`); the gate runs each distinct build once,
serially, before the groups start, so that the groups share one up-to-date build in the
checkout's own `CARGO_TARGET_DIR` instead of queuing on Cargo's lock. The groups' `run`
still repeats its build, which is then up to date. Ports are chosen free per test
(`tests/support.cjs`), and each browser test station gets its own `LOCALAPPDATA`
(`stationEnv`, #8), so the profile and radio-ownership locks of concurrent groups do not
meet.

The model has an explicit documentation owner. Its edits select the catalog/trace check,
one full semantic validation and the tests that read the model (`sysml-documentation`, about
30 s); the tool's own unit tests (`sysml-tools`, about 50 s) run only when the tool changes;
the architecture mutation tests (`sysml-architecture`, one Pilot JVM per mutation) run
only when `Station.sysml`, `RadioProperties.sysml` or the tool that judges it changes, since the companion
models are validated by `check` itself. Runtime oracles are selected by changed
implementation and executable tests. Source
edits also select the fast binding check, without a dependency that runs the full Pilot
mutation suite on every code edit. Both model suites fingerprint the model, tool and
complete client/server/test source inputs they read. A source edit or deletion invalidates
old trace evidence and full-model evidence, even when only the fast suite is selected.
Independent contract comparison still checks that tests prove the changed promises.

A file selects the groups whose test cases prove its promises, not every group whose
fixture merely loads it. The router `main.rs` (routes, authentication, websocket and
profile HTTP) selects every browser group. The operating page client files select
`operating-layout`, the operating-page regression, besides their owning groups. The
status client (`app.js`, `index.html`, `authorization.js`) also selects every group
whose page boots from it, since `station-ready` starts the recording client. A
contact engine edit therefore selects `wstx-rust`, `contact-browser` and
`source-model-traces`; its HTTP surface adds `operating-layout`. An edit to the shared
recording test file selects all three recording groups. Cargo and Node dependency
inputs select every group that compiles or runs them. The selector does not infer
changed functions from a file or guess dependencies from an agent's description.
Unmapped inputs select every group that declares them; entirely unknown paths and
selection-policy changes cause a full fallback. The workflow is a shared unmapped
input of every group, so workflow edits also select them all.

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

## Merge queue

A reviewed CR reaches master through the harness
[merge queue](../../harness/core/docs/Merge-Queue.md),
whose worker runs on the PC that holds development, either one
([machines and roles](#machines-and-roles), operator 2026-11-11): the coordinator hands in
the reviewed tip (`python harness/core/tools/merge_queue.py submit <issue> <tip>`) and
builds no merge itself. The queue's records are local to that PC.
The `queue:` section of `.harness/config.yaml` names the tools the gate needs (Node 24
or later, npm, Cargo, rustc, `gh`, the MSVC linker), 20 GB free on every drive the gate uses, the
input environment of the [HB9BLA handover](HB9BLA-HANDOFF.md) and the `npm ci` setup of
the queue's worktree. A long build or test run outside the gate does not wait for `busy`;
it runs beside the gate under the priorities below and reruns a timing-sensitive failure once.

Priorities on HB9BLA ([harness#28](https://github.com/SensorsIot/harness/issues/28)): the
station task `WSTX Rust Station HB9BLA` runs at High, above the gate; the gate runs at
ABOVE_NORMAL with unbounded build parallelism; agent builds and tests outside the gate
run at BelowNormal with a bounded `CARGO_BUILD_JOBS` (2, as the
[HB9BLA handover](HB9BLA-HANDOFF.md) sets it).

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## Deployment authority

This is the project's binding of the harness
[deployment authority](../../harness/core/docs/standards/security.md#deployment-authority)
rules (#26).

**Mechanism.** There is one deploy mechanism: the Windows release executable built on
HB9BLA and installed there at user level by the reviewed, versioned deploy scripts under
`tools/deploy/` (operator decisions 2026-10-31, see #30, and 2026-11-13, see #171).
`tools/deploy/` is a product path: a change to it is a CR with review and the merge
queue's gate, and suite `deploy-tooling` tests it. The **mechanism paths** are every file
under `tools/deploy/station-update/` (`station-update.ps1`, `make_package.py`,
`launcher.ps1`) plus `tools/deploy/agent-client.ps1`, `tools/deploy/station-probe.ps1`
and `tools/deploy/live-page-check.ps1`. Every step of the
[standing deploy policy](#standing-deploy-policy) lives in those files. `.gitattributes`
marks them `-text`, so their bytes in git, in a checkout and in a package are the same.
The live page check's checker `tests/live-page-check.cjs` is product, gated by CRs, and is
not pinned: the deploy runs it from the repository root it passes (`-Repo`, the main
checkout `D:\Github\wsjtx-rust`) with that checkout's `node_modules`, not from the package.

A deploy starts with one line in Git Bash on HB9BLA, which runs `make_package.py` as
extracted from the commit it installs, so no working folder is read:

```bash
git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> <push-gate log>
```

It builds a package of a commit on GitHub master whose push gate passed (the push-gate log
is a merge-queue log under `.git\harness-parallel\queue\logs\` that shows the push) in
`.git\harness-parallel\resources\station-update\packages\<ver>\`, never in a working tree,
copies the mechanism files from the commit's `git archive` export into the package's
`deploy\` folder and lists their SHA-256 in the manifest. It prints the next command: the
package's own copy,
`<package>\deploy\tools\deploy\station-update\station-update.ps1 -Manifest <package>\manifest.json [-DryRun]`,
which refuses to run from anywhere else. It verifies the package, checks the pins, waits for
an idle station, stops it gracefully, switches `active.json`, starts the task, switches
back on failure, runs the probe and the live page check from the package, returns to the
previous version when either fails and posts the install record. Exit 0: installed (or the
dry run passed); 1: refused, failed or returned; 3: the station stayed busy, nothing
changed; 6: the radio did not answer, nothing changed. A parameter the script does not
declare stops the call at binding, before any step.
`station-update.ps1 -Rollback` returns to the previous version and never asks. The
operator's one-time `setup-once.ps1` (in `.git\harness-parallel\resources\station-update\`,
not used by deploys) points the scheduled task at `station\launcher.ps1`, which runs the
version named in `active.json`; the task names no repository path and no deploy changes it.
The manual `windows-rust.yml` workflow and its `wstx-rust-windows-x64` artifact are build
evidence only (operator decision 2026-10-30): that artifact is never installed on the station.

### Standing deploy policy

Approved by the operator on 2026-11-13 (#171 comments 6859504815, 6861452505,
6861571300; #196 comments 6866528840, 6867219074), on the decision of 2026-11-12: "The operator is kept out of the loop, with one
exception: when a decision is needed." It binds the deploy part of the harness rule
[standing deploy and consent policies](../../harness/core/docs/CR-Process.md#standing-deploy-and-consent-policies). A deploy
under it needs no OK per install.

1. **When a deploy applies without asking.** All of these hold:
   - the push gate is green on exactly that commit and the package matches it (the package
     checks of `station-update.ps1`);
   - the station is idle, checked inside `station\logs\update.lock`, which the deploy holds
     from the check until the station has stopped. Idle means all of: the update lock is
     free; no live radio lease (`.git\harness-parallel\radio\lease.json` missing or
     expired); exactly one station process; GET /transmit shows `arm_state` `disarmed`,
     `ptt` `released` and `transmitting` false; GET /contact shows no contact, or one that
     is `idle`, `completed` or `cancelled`; GET /automation shows no run, or a stopped one;
     GET /radio shows `state` `ready`, read in the same pass after the others. A state that
     cannot be read counts as busy. While busy, the deploy reads again every
     10 s for up to 300 s, then gives up with the station untouched (exit 3); the CR stays
     landed and the deploy is retried later. A radio that is not `ready` (or whose reply
     cannot be read) is the reason `waiting for the radio (state <state>)` and waits the
     same way; when it still does not answer after 300 s and the station is otherwise idle,
     the deploy prints `WAITING FOR THE RADIO: the radio did not answer for 300 s, nothing
     changed (state <state>)` and exits 6: it stages and stops nothing, runs no probe and
     no page check, makes no return and posts no record; the same command run again later
     repeats the whole check. `-DryRun`, `-Rollback` and the switch-back after a failed
     probe or page check do not read the radio. A station that is down is not idle. A contact
     the agents did not start is never aborted by them; a deploy it blocks past the wait is
     reported to the operator;
   - it is outside the scheduled-job window. The product has no scheduled job, so the
     window is none.
2. **The mechanism is pinned.** [Deploy pins](#deploy-pins) lists one line per mechanism
   file.
3. **The deploy runs the bytes of the commit it installs.** `make_package.py` runs as
   extracted with `git show`; `station-update.ps1`, the probe and the page check run from
   the package. The page check takes the repository root, the shared folder and the agent
   client as parameters and derives none of them from its own location. Before any write,
   `station-update.ps1` compares each mechanism file of the package with the pins of the
   commit's own `Project-Specifics.md` (read with `git show`), and compares the launcher in
   the station folder with its pin (item 4).
4. **A changed mechanism deploys without an OK.** The deploy installs a commit whose
   mechanism files or pins differ from those of the running commit like any other commit:
   pins that differ from the running commit's pins, a running commit without pins and a
   station launcher that differs from its pin are no refusal; the deploy logs one step per
   difference (`deploy mechanism changed: <what>`) and goes on. It refuses before any write,
   with exit 1 and its reason, when the commit to install has no deploy pins, when its pins
   do not name the mechanism files in their order, or when a mechanism file of the package
   differs from its pin (`<path> differs from its pin`). When the station launcher differs
   from the package launcher, it saves the station launcher in the station folder's `logs\`
   and writes the package launcher after the stop, before starting the task; the
   switch-back restores the saved launcher with the profile. The task itself is never
   changed. `-Rollback` never asks and checks no pins, so the automatic return always works.
   `station-update.ps1` has no parameter for an operator's OK: a call that names one stops
   at parameter binding before any step.
5. **Proof and return.** After the switch the probe runs, inside the lock. The deploy then
   releases `update.lock`, and the live page check runs (it takes the lock itself for its
   restart). Probe not `PASS`, page check `RED` or `ERROR`: the previous version is
   reinstalled without asking, under the lock again, and each CR in the install goes back
   to step 2. Page check `BUSY` or `NOT-EXERCISED`: no return, and the result is recorded;
   before the live acceptance of the CRs of that install the page check runs again, and
   acceptance needs its `PASS`.
6. **Install record.** Every install posts its record on each CR issue it moves to
   installed (`cr_state.py installed <commit> --since <previous>` finds them); after a
   return, on each issue the subjects of `<previous>..<commit>` name that is open and carries
   `cr:landed` or `cr:installed` (the deploy reads each with `gh issue view`; for any other
   issue it logs `record not posted on #<n>: <closed | at <label> | no cr state | state
   cannot be read>` and posts nothing). The record holds the
   commit, the previous version, the SHA-256 of the package executable, the SHA-256 of each
   mechanism file, the probe result line, the page check result line, and any return to the
   previous version. It holds no quote, dollar sign or backtick.
7. **Accepted limits** (operator, verbatim):
   - 2026-11-13 (6859504815): "I accept knowingly that this guards against accidents and
     shortcuts, not against a deliberate swap by a session running under my account."

   The rules of the table under [rules not met yet](#rules-not-met-yet) stay not met.

### Deploy pins

The SHA-256 of each mechanism file's blob at this commit, then its path, in the order
`station-update.ps1` reads them. A change to a mechanism file changes its pin in the same
CR (policy item 4). Suite `deploy-tooling`
(`test_deploy_pins.py`) recomputes every pin from git.

```text
0580f8a62387d45dedd6a7908cb61d9b9496f383144413db53259fd1dc34a790  tools/deploy/station-update/station-update.ps1
0d1fb5e9676faafc71a3c1ab3c694793485a0513fe416d2eac0372719b8aa044  tools/deploy/station-update/make_package.py
8579d535aa68596bd466b0fc400e4d8a8ca25c50e42291b3a09648ab01455509  tools/deploy/station-update/launcher.ps1
9d0524dfc1dc536f5d54e3a1b956b737f5b2b8a5a1ccfebaa896b97241c89dd2  tools/deploy/agent-client.ps1
8743e2a12916e12bebbc01eabf6728af6aeb8064e468861fb274f97c9bffad34  tools/deploy/station-probe.ps1
187270d4b645d7c7e123c6718a6f9264698d27749d9810a3b106c7cfcb26bab7  tools/deploy/live-page-check.ps1
```

### Standing consent at 1 %

Approved by the operator on 2026-11-12: "Transmitting is not a concern: tests transmit at
1 % RF power, except QSO tests." Cost 4 and 5 live tests run without asking when all of
these hold:

- `.harness/deploy/radio-preflight.ps1` has taken the radio lease and set RF power to
  `0003` (1 %, 1.2 % of the control) with read-back before anything keys;
- the test transmits only on 10, 15, 20 or 40 m;
- afterwards it restores the power found and every setting it changed.

QSO tests, their power and their bounds are not covered by this consent (#192).

### Operator role and returns

The operator is asked only for open questions and changes to the product contract, whether
to push past a red test, and items only a person can judge. An installed CR that fails acceptance or is returned gets a row in the
escapes ledger.

### Probe, tests and drill

**After every install** `station-update.ps1` runs the independent probe itself (policy
item 5). Run by hand, `PROBE FAIL` (exit 1) calls for `station-update.ps1 -Rollback`;
`PROBE ERROR` (exit 2) is a wrong argument, not a verdict:

```powershell
<package>\deploy\tools\deploy\station-probe.ps1 -Manifest <package>\manifest.json
```

It is read-only. It asks Windows which process listens on TCP 18081, hashes that
process's executable itself and requires the candidate's commit directory and the digest
of the package's own `wstx-rust.exe` (recomputed, not read from the manifest), then HTTP
200 from `https://192.168.0.37:18081/` over TLS that Windows trusts. In the same
response, the station's `x-wstx-source-commit` header must be the candidate's commit (#33,
CL-033-01). This is the commit the running service itself reports. `make_package.py`
compiles it in as `WSTX_SOURCE_COMMIT`, and a build without one reports `unknown`, which
fails. A build from before #33 sends no header, for example a rollback target. The probe
then says so and keeps the image digest as the identity. Last, it checks that the launcher
receipt agrees with what it observed. Tests of the deploy mechanism, its pins and its drill
are suite `deploy-tooling` (cost 2, `.harness/suites.yaml`):
`python -m unittest discover -s tools/deploy/tests -v`.

The operator can check the result without any agent, from PC Andreas (the only address
the firewall admits). This is not a step of each install (operator decision 2026-11-01):

```powershell
(Invoke-WebRequest -UseBasicParsing https://192.168.0.37:18081/).Headers['x-wstx-source-commit']
```

It prints the commit the station reports. Compare it with the commit announced on the
issue.

**When `station-update.ps1` changes** run the refusal drill and record its output on the
change's issue (suite `deploy-tooling` runs it too, through `test_station_drill.py`):

```powershell
python tools\deploy\station_drill.py
```

It runs a copy of the script against a sandbox station, with `LOCALAPPDATA` in a temporary
directory and the task, firewall, processes, network and git replaced by mocks. Starting
or stopping anything records a sentinel and throws. Before running, it parses the script
and refuses any command (also inside `"$(...)"`), .NET type or call target it has not
classified, `$ExecutionContext`, an environment variable other than `LOCALAPPDATA`, and a
literal absolute path other than the repository and the deploy-authority root. This keeps
the commands the drill knows away from the live station. It is no sandbox against a
script written to escape it: read a changed script's diff before drilling it. Each case damages one thing in a package built as `make_package.py`
builds it and requires the refusal's own message, no sentinel and an unchanged
destination (version folders, `active.json`, profiles, launcher; `logs\` may change).
The cases are: tampered artifact, manifest naming another artifact, changed gate
record, gate record of another commit or artifact or not passed, changed push-gate log,
commit not on GitHub master, master unreachable, abbreviated commit, package paths that
escape or name a stream, gate record outside the package, no executable, wrong firewall
scope, task not on the launcher and a staged copy that differs. Two controls show the
mocks refuse nothing by themselves: the intact package passes `-DryRun`, and without it
the script reaches the station stop. Two `LIMIT` cases are expected to be accepted: a
consistent rewrite of executable and records, and an older commit on master. With the
authority patch applied, two more cases cover an approved and a refused approval.

The drill runs the package's own pinned copy with a scripted clock (10 s polls from
12:00:00) and a sandbox station whose state the package's agent client reports. The idle
cases (#171, TC-171-01) each require the busy reason in the refusal, no stop sentinel and an
unchanged destination: update lock held, a live radio lease, no and two station processes,
transmit armed, PTT keyed, transmitting, a contact replying, a contact replying after a
`device_lost` disarm, an automation run active, and a state that cannot be read. Busy that
clears at 290 s proceeds to the stop; still busy at 300 s gives up. The radio cases
(#196, TC-196-04) add a radio `closed`, `connecting`, `closing`, `unavailable` or whose
reply cannot be read: each waits to `12:05:00 WAITING FOR THE RADIO` with exit 6 and no
stop; a radio `ready` from the first reading, or from 290 s, proceeds to the stop; transmit
armed until 310 s with the radio closed ends with the busy reason and exit 3. A second
update started between the idle check and the stop is refused because the first holds the
lock. The pin cases (TC-196-01, TC-196-02): all pins equal passes `-DryRun`; a working-folder
copy of the script is refused (only the package's copy runs); a package file edited after
the build, a commit without pins and pins in another order each refuse with exit 1 and
their reason before any write; new pins that differ from the running pins, a running commit
without pins and a station launcher that differs from its pin log `deploy mechanism changed:`
and reach the stop; a call naming the removed OK parameter stops at binding before any
step. No case prints a `Deploy OK` line or reads a comment. `-Rollback` with differing pins
or with the radio closed reaches the stop without asking, and `-DryRun` does not read the radio.

### Rules not met yet

Until each issue is done, the [standing deploy policy](#standing-deploy-policy) authorizes
this mechanism in place of an OK per install; it bounds the operator's standing permission
to run `station-update.ps1` (decision 2026-10-31, recorded on #30).

| Rule | State today | Issue |
|---|---|---|
| Credentials outside the agents | Off (today): agents run as the HB9BLA user and can write the version directory, `active.json`, the receipt, the gates record and the package and station-update scripts. Only the task and firewall changes need the operator's elevation. Prepared: the deploy authority below keeps policy, verifier and launcher where only Administrators write and the signing key with the operator. Still not met when on: the launcher and verifier run as HB9BLA, so the agents can alter them while they run (see its limits). | #30 |
| Approval names the candidate | Off (today): the manifest names commit and executable SHA-256, but the agents write it and no approval is bound to it. Prepared: an operator-signed approval of one commit, one digest and one destination. | #31 |
| Verify before writing | Off (today): `station-update.ps1` refuses a changed artifact, package path, gates record, push-gate log, unpublished commit, task or firewall scope before writing, but against an agent-written manifest beside the artifact. Prepared: the protected verifier hashes the executable itself against the signed digest before the switch, and the protected launcher again before it starts it. | #32 |
| Prove the result | `station-update.ps1` checks the launcher receipt and HTTP 200. `station-probe.ps1` then checks, independently of the receipt, that the process listening on 18081 runs the candidate's bytes, answers over trusted TLS and reports the candidate's commit itself (`x-wstx-source-commit`). The operator can read that report from PC Andreas without an agent. Not met in full: an agent runs the probe and the rollback after it. On HB9BLA everything except the operator runs with the agents' rights, so a prober the agents cannot alter needs another account (an operator decision, see the deploy authority's limits). | #33 |
| Show the refusals | `station_drill.py` shows each refusal of `station-update.ps1` before the destination changes (above). Not met in full: the drill shows that a consistent rewrite of artifact and records and an older commit on master are accepted (#32, #31), and a mismatched approval exists only with the deploy authority on. | #34 |

No rule is met in full.

### Deploy authority (prepared, switched off)

`.harness/deploy/authority/` holds an operator approval for each install (#30, #31, #32).
It is **off**: nothing in the install path calls it, the task runs `station\launcher.ps1`,
and agents install with `station-update.ps1` as above. Only the operator switches it on,
because from then on every install needs the operator's signature.

When on, the operator approves a package by signing
`{schema, commit, artifact_sha256, destination, requested_utc}` with an OpenSSH key the
agents never see (on PC Andreas or a hardware key; `ssh-keygen -Y sign`, namespace
`wstx-station-approval`). The root `C:\ProgramData\WstxRust\deploy-authority` is owned by
Administrators and only readable by HB9BLA. It holds `policy.json` (destination and signer),
`allowed_signers` (the operator's public key), `revoked.txt` (digests no longer allowed),
`verify-approval.ps1`, `protected-launcher.ps1` and `authority-lib.ps1`. Both entry
scripts refuse to run from anywhere else or when the root, an ancestor, PowerShell or
`ssh-keygen` can be changed by an account other than SYSTEM, Administrators or
TrustedInstaller. They load modules only from `$PSHOME` and run `ssh-keygen` with an empty
environment. They hash the executable themselves with the file pinned against change and
refuse unless the signed approval names exactly that commit, that digest and the policy's
destination and the digest is not revoked. `verify-approval.ps1` runs inside
`station-update.ps1` before anything is staged. `protected-launcher.ps1`, which the
scheduled task then runs instead of `station\launcher.ps1`, checks again and starts
nothing unapproved; `station-update.ps1` then sees the version not become ready and
switches back.

**To switch it on** (operator, once):

1. Create the signing key on your own machine, e.g. `ssh-keygen -t ed25519 -f %USERPROFILE%\.ssh\wstx_operator`
   (with a passphrase), and copy only `wstx_operator.pub` to HB9BLA.
2. Approve the running version first, so the switch cannot stop the station. The agent runs
   `.harness\deploy\authority\request-approval.ps1 -Manifest <its package>\manifest.json`. You
   check the commit, digest and gate record it prints, then sign
   `ssh-keygen -Y sign -f wstx_operator -n wstx-station-approval <commit>.approval.json`.
   The agent copies `<commit>.approval.json` and `.sig` to
   `%LOCALAPPDATA%\WstxRust\station\approvals\`.
3. As HB9BLA, unelevated, try it:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .harness\deploy\authority\enable-authority.ps1 -OperatorPublicKey <path>\wstx_operator.pub -DryRun`.
   The real run has Administrator rights, so nothing the agents can write may take part:
   not the checkout, not git, not HB9BLA's environment (an elevated shell of HB9BLA still
   reads `HKCU\Environment`, which can load a DLL into it). In an elevated
   `powershell -NoProfile` of a **separate administrator account**:

   ```powershell
   & {
     $ErrorActionPreference = 'Stop'
     # A fresh, unpredictable folder created with its final permissions in one step, so
     # no agent can create it first or drop a file into it before it is locked.
     $sid = (New-Object Security.Principal.NTAccount('HB9BLA')).Translate([Security.Principal.SecurityIdentifier]).Value
     $s = New-Object Security.AccessControl.DirectorySecurity
     $s.SetSecurityDescriptorSddlForm("O:BAG:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;$sid)")
     $d = "C:\ProgramData\WstxRust-install-$([guid]::NewGuid())"
     $null = [IO.Directory]::CreateDirectory($d, $s)
     if (@(Get-ChildItem -Force $d).Count) { throw "$d is not empty" }
     Copy-Item D:\Github\wsjtx-rust\.harness\deploy\authority\* $d
     Get-FileHash $d\* | Format-Table Hash, Path   # must equal the digests in the review record
     if ((Read-Host 'Digests equal the review record? (yes)') -ne 'yes') { throw 'stopped' }
     powershell -NoProfile -ExecutionPolicy Bypass -File $d\enable-authority.ps1 -OperatorPublicKey <path>\wstx_operator.pub
     $d   # keep: disable-authority.ps1 runs from this folder
   }
   ```

   It refuses as HB9BLA, from an unprotected folder, when the task is not the
   `setup-once.ps1` launcher, when the root existed unprotected or when the running version
   is not approved. It prints the digests of the files it installs, points the task at the
   protected launcher and does not restart the station.
4. Apply `.harness/deploy/authority/station-update-authority.patch` to
   `station-update.ps1` (it accepts the protected launcher in `Assert-Setup` and calls
   the verifier after the package checks). Then run
   `python tools/deploy/station_drill.py`: it must show the two approval cases.
   Without the patch, `station-update.ps1` refuses every install and rollback with
   "setup-once.ps1 has not been run".

From then on each install is: `make_package.py`, `request-approval.ps1`, your signature,
copy to `approvals\`, `station-update.ps1`, `station-probe.ps1`. To revoke an approved
build, add its digest to `revoked.txt` (elevated). **To switch it off**:
`$d\disable-authority.ps1`, run the same way as the enable (separate administrator account,
protected copy), points the task back at `station\launcher.ps1`; then reverse the patch.

**Limits when on.** The approval has no expiry and no one-time nonce: the protected side
has no state the agents cannot write. An approved build stays startable (after a reboot
or a rollback) until its digest is revoked. Replay for another commit, digest or
destination is refused. **The checks still run with the agents' rights:** the task's
principal stays HB9BLA (LeastPrivilege), so `protected-launcher.ps1` runs as the agents'
own account. They can alter it while it runs, for example with a profiler DLL from
`HKCU\Environment` or by writing to the memory of a process they own. They can also start
any program themselves, and the firewall rule has no program condition. When on, the
authority makes the approval tamper-evident and stops an unapproved build in the ordinary
path; it is not a boundary against agents that act deliberately. A real boundary needs the
task (and the verifier) under another account whose environment and processes the agents
cannot reach, which is an operator decision. `station-probe.ps1` detects a listener that
is not the expected image. The required checks
(the push gate) still run with the agents' rights. The operator's signature covers the
gate record shown at signing, but no protected configuration re-runs those checks.

**Platform limits.** `execution_mode: local`: the hooks and the push gate run on the
client with the agents' own rights. The repository has no branch protection and no
required remote status check. There is no environment approval. None of these rules is
enforced by the platform.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)

## Product model maintenance

The reusable [SysML authoring instruction](../../harness/core/docs/standards/sysml-v2.md)
explains how to write models without project-specific assumptions. This binding selects the exclusive authority policy below and the local toolchain. The
functional entry point is [Requirements.sysml](../sysml/Requirements.sysml), with the
[architecture](../sysml/Station.sysml) and the model packages it references.
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
python tools/sysml.py status
python tools/sysml.py oracle
python -m unittest discover -s tools/sysml/tests -q
```

`check` admits only canonical SysML, checks canonical identities/states and trace
bindings, loads the complete model set in the pinned Pilot, then compares the resolved
inventory with the architecture oracle file. `fingerprints` prints one hash per model file by key (its
path relative to `docs/sysml`, with forward slashes), sorted by key, for review;
it never renews model approval. No command writes a model.
`traces` requires canonical SysML and checks only authority, catalog and source/model
bindings. It never invokes Java, the mutation suite or application behavior. Source-only
edits select this fast check; model/tool changes retain the full checks as well.

After the architecture comparison, `check` applies the ten structure checks of the
target (CL-014-18) to what is already in target form. What is not yet is listed in the
pending list `tools/sysml/pending-structure.json`:

- `files`: model file keys, each exempt from every rule; `elements`: the qualified name
  of a model element, exempt with its members, mapped to the function whose rewrite
  takes it off. Placeholder item types (rule 3) and outside things without a connection
  (rule 4) are listed under `elements`, also inside `Context.sysml` and `interfaces/`.
- `Context.sysml` and files under `interfaces/internal/` and `interfaces/external/` are
  never listed as files. A new or renamed file is checked unless a reviewed diff lists
  it; a stale entry refuses the whole list. The deployment rules apply once
  `Station.sysml` is off the list; a rewrite takes its entries off, and an empty list
  means the target is reached.
- The names the rules keep (usages `station`, `frontend`, `browsers`, `web`, `ranking`,
  `auto`, `qso`, `transmit`, `operator`; the files `interfaces/internal/StationLink.sysml`,
  `StationCommands.sysml`, `OperatingChain.sysml`, `interfaces/external/Mcp.sysml`,
  `OperatorInteraction.sysml`; the suffix `Control`) and the browser client's allowed
  outside interfaces are fixed in the tool: renaming one is a tool change.
- The Pilot inventory of `check` carries what the rules read: each connection's model
  types (`CONN`), the file and lines of each named element and each definition's model
  features (`ELEM`), the qualified name and file of each part and port (`WHERE`), the
  items of each interface definition (`IITEM`), the members of each part directly in the
  root and of its types (`OUTSIDE`, `MEMBER`) and each requirement's subject (`SUBJECT`).
  Only `check` reads the list; the other commands work without it.
- A check on a pinned model is `check` entered with a commit by a Python-level setting of
  the tool (`CHECK_COMMIT`), set by its caller as the oracle file and the Pilot inventory
  are; there is no command-line option, and without it `check` reads only the working
  tree's list and model and refuses a list that is missing or malformed. Authority,
  catalog, trace bindings and the validation's file keys are read from the working tree;
  the Pilot inventory is what `validate` returns, the commit's as the caller supplies it;
  the oracle file is the tool's `ORACLE`. The pending list is the commit's own
  `tools/sysml/pending-structure.json`, and the key set it is checked against and the model
  files, keys and sources of the structure stage are the commit's `docs/sysml`.
- A commit without the file predates the structure checks: no structure stage runs, and
  `Structure checks not run: <commit> has no pending list` takes the structure line's
  place; the exit code is that of the stages before. A file present there is refused or
  applied with the form rules above, against the commit's key set, its elements resolved
  against the supplied inventory; `{"files": [], "elements": {}}` means the target is
  reached and all ten rules apply, and a zero-byte file is refused as malformed.

`python tools/sysml.py status` prints each FR's status as computed from its clauses
(CL-014-19):

- It needs the authority and the catalog as `traces` does, runs no Java and writes nothing.
- One line per FR in identity order:
  `<FR> <status>: <n> clauses, <i> implemented, <p> partial, <t> target`. Where the FR
  states a different status, `; stated <state>` is added.
- A last line gives `<n> FRs: <count> implemented, <count> partial, <count> target`.
- Exit 0, or 2 with the catalog's message (`SysML check failed: <message>`).

`python tools/sysml.py oracle` writes the architecture oracle file
`tools/sysml/architecture-oracle.json` from the resolved inventory of the working tree
(CL-014-06):

- It needs the canonical authority, runs the Pilot validation of `check` and then the fixed
  rules; on a refusal it exits 2 (`SysML check failed: <message>`) and leaves the file
  unchanged. It runs no catalog check, and the gate never runs it.
- It prints one line per difference to the file it replaces, sorted:
  `added part <path> <type>`, `removed part <path> <type>`, `added port <path> <contract>`,
  `removed port <path> <contract>`, `added connection <owner> <end> <-> <end>`,
  `removed connection <owner> <end> <-> <end>`, and `changed <section> <key>` for any
  other difference (a reference, a binding, a contract's items, a type or a population).
- Then `Architecture oracle written: <counts>`, or `Architecture oracle unchanged` with no
  change line and the file not rewritten.
- The file has the form `check` reads, sections and keys sorted, and keeps the file's
  `about` text, or a fixed sentence when there is no file.

`python tools/sysml.py markers [<Kind> ...]` lists what the model leaves open:

- It needs the canonical authority, as `traces` does. It runs neither the catalog checks
  nor Java, and writes nothing.
- The kinds are the `metadata def` names in the model file whose package is `ModelNotes`.
  A kind added there is listed without a tool change.
- It lists every use outside comments: `@Kind { ... }`, `@Kind;` and
  `metadata <name> : Kind [about <targets>] { ... }`, with or without `ModelNotes::`.
- One line per marker: `<key>:<line>: <Kind>: <text>`, or
  `<key>:<line>: <Kind> about <targets>: <text>`. The line is that of `@` or `metadata`,
  counted from 1. The text is the string values of the body, each with its `+` parts
  joined, several values separated by `; `.
- Lines are sorted by key, then line. The last line is `<n> markers: <count> <Kind>, ...`
  over all kinds in name order; without a `ModelNotes` file it is `0 markers`. Exit code 0.
- Named kinds restrict lines and counts to those kinds. An unknown kind: exit 2,
  `Unknown marker kind: <name>`.

`python tools/sysml.py equivalence <base> [<head>]` shows that a model move changed no
meaning (CL-014-17):

- Each revision is a commit-ish; without `<head>` the head is the working tree. Each side
  is extracted with `git archive` into a temporary folder that is removed afterwards and
  exported once per distinct tree by the pinned Pilot (`Validate.java --export`).
- Lines: `missing|added <relative name> <package> <file>`,
  `changed <relative name> <property> <base file> -> <head file>`,
  `missing|added package-level <class> "<text>" <file>`, `missing|added note "<text>" <file>`,
  `stale-by-change <file>:<line> <citation>`, then `moved <relative name> <base package>
  <base file> -> <head package> <head file>`, `pair <base file> -> <head file>: <count>`,
  `unresolved <file>:<line> <citation>`, `exempt <file>:<line> <citation> (pinned|fixture)`
  and a summary.
- A tracked file below `tools/sysml/tests/` is a pinned reader when one of its lines is
  `PINNED = "<7 to 40 hex>"` and that value names a commit of the repository; it is judged
  by this rule only, even when it also declares a package. A citation in it is exempt from
  `stale-by-change` only if it resolves in the pinned commit's model (a name in that
  commit's export, one more export per distinct pinned commit, or a `docs/sysml/` path in
  its tree); one that does not is judged as before. A pinned commit failing the Pilot
  validation exits 2, as any side.
- A file there without a `PINNED` line is a fixture reader of each `<Top>` its text
  declares as `package <Top> {` or `library package <Top> {`: its name citations whose
  first segment is such a `<Top>` are exempt. Every other citation, in any other file,
  keeps the rule above.
- Each exempt citation that would have been `stale-by-change` prints its `exempt` line, no
  difference and no change of the exit code; the summary then ends with
  `; exempt: <file> <count>, ...`, one entry per file in file order with its number of
  exempt lines, and is unchanged without any. This holds in each commit of `--marked`.
- Exit 0 equivalent, 1 differences, 2 cannot compare (unknown revision, or a side failing
  the Pilot validation).
- `equivalence --marked` checks each commit of `master..HEAD` with the trailer
  `Model-Move: pure` against its first parent and prints `checked`/`skipped` per commit and
  the number of exports; without a marked commit it prints `no marked commit`, exit 0.

`python tools/sysml.py identities <base> [<head>]` lists the identity diff: one line
`<ID> <status> <base file> -> <head file>` per FR/CL/TC identity of either side (status
unchanged, moved, changed, added, removed, or retired with `test <path>` or, for a
superseded retirement, `superseded by <TC>, <TC>`), FR, CL, TC
in order, then `<n> identities: <count> <status>, ...`. It reads `docs/sysml` of each side
without the Pilot or the catalog checks; exit 0, or 2 when a side cannot be read.

The `sysml-documentation` level-2 suite owns these checks. Application outcomes remain
in their existing functional suites and issue evidence; no duplicate application build
is required merely to inspect model syntax. A selected compiler or behavioural gate
remains binding. Missing tools, files or evidence fail rather than becoming a skip/PASS.

## Meaning and limits of semantic validation

`tools/sysml/Validate.java` calls the pinned Pilot's `SysMLInteractive` API, including
its actual parser, name resolution and Xtext semantic validator. `check` passes to the
Pilot `Requirements.sysml` first, then every other model file once, sorted by key. The
order does not change the result (the adapter resolves all files as one graph).
`validate <files>` with an explicit list is unchanged:

```powershell
python tools/sysml.py validate docs/sysml/Requirements.sysml docs/sysml/Station.sysml
```

Syntax/type/reference errors fail. Missing/invalid tools, model libraries or model files,
or missing completion evidence, fail rather than falling back to a lightweight checker.
Self-tests feed legal, malformed and unresolved-reference fixtures to the actual Pilot.
They also exercise authority ambiguity and refusal, missing identities/files, broken traces, archive independence and unavailable tool/library cases.

The `check` command also requests a resolved semantic inventory from the same Pilot
process. The Java adapter traverses actual usage/type/connector objects, inherited
features, conjugated directed items, reference subsetting, binding-versus-ordinary connector kinds
and backend variants.

- **The inventory is complete.** The *deployment* is the one package-level part usage of
  the model files, whatever its name and package, and everything reachable from it; with
  none or several, the inventory lists only the package-level part usages. The inventory holds every part, reference, port with
  its items, connection and binding of the deployment, whatever package declares the
  element or its definition, also a feature a definition inherits from a definition of
  another package. Left out are only the elements of the pinned model library's files; an
  element of a model file is never left out, also in a `library package`. Definitions and
  item types are named by qualified name; paths are dot paths from the deployment's name.
- **The oracle is data.** `check` compares the inventory with the file
  `tools/sysml/architecture-oracle.json`, which only `oracle` writes. It states `root` (the qualified name of the one
  deployment); `parts` (per path below the root: qualified type, population `"1..1"` or
  `"0..*"`, and `variation: true` when it is one); `references` (per path: type,
  population, target path); `contracts` (per port definition: its items as name,
  direction `in`/`out` and qualified item type, and the bindings and connections it
  declares itself); `ports` (per path: the contract, a leading `~` for the conjugate);
  `connections` and `bindings` (per owner path: the pairs of ends as the inventory gives
  them); and `about`, one free text. No other key exists; an empty section means none of
  this kind. A slice that adds a port, part, reference or connection names it there.
- **Nothing unlisted passes, nothing listed may be missing.** Inventory and file agree
  exactly: part by path, type, population and variation (the top-level parts are parts
  like any other); reference by path, type, population and target; port by path,
  definition and conjugation, with its complete item set, each item's direction (reversed
  on a conjugate) and type; connection and binding by owner, kind and both ends. The
  edges a contract declares count at every port typed by it.
- **Refusals and their order.** `check` exits 2 with
  `SysML check failed: Architecture integrity: <message>`, naming the first difference in
  this order: the oracle file; an empty inventory; the fixed rules; each listed
  reference (`invalid endpoint/resource/authority association`); missing, then
  unexpected connections and bindings; the set of ports, then each port's items
  (`semantic exchange signature mismatch`, `wrong exchange direction`, `wrong semantic
  item type`); then `wrong port definition`, `missing part`, `unexpected part`,
  `wrong part type or population`, `unexpected reference` and, last,
  `port joined to no function <path>`.
- **Fixed rules stay in the tool** and hold whatever the file lists: exactly one part
  usage at package level in all model files (the root); no view in any model file adds a
  part or connection; exactly one part typed by `RadioAuthority` (the authority); exactly
  one part typed by `StationProcess` (the station population), variable (`0..*`); directly
  in it exactly one `audioAdapter : AudioDeviceAdapter`, one `catAdapter : RustRadioDriver`
  and one `profile : PersistedProfile`, found by usage name, each `1..1` and no variation,
  and no other part of the two adapter types; and a non-empty inventory. A type is matched
  by the simple name of the part's definition or of a definition it specializes, directly
  or through other definitions, in any package; no rule names a root, a path or a package.
  `check` applies these rules and `oracle` applies them before it writes. Then `check`
  alone: every port of the deployment is an end of at least one connection of the
  deployment; an end reached through a reference resolves to the referenced part's port
  (`authority.requests` to `context.station.backend.radioAuthority.requests`), and a
  binding, also one a contract declares, joins no port. Otherwise the first unjoined port
  in sorted path order is named. The rule cannot tell an outside thing from a function:
  an outside part put back with its connection is refused only while the oracle file does
  not list it. A change to a fixed rule is a tool change with its own issue.
- **The oracle file fails closed.** A missing, unreadable or non-JSON file is refused
  with `Architecture oracle unavailable: <path>`. A missing section, an unknown key, a
  key stated twice, an entry of another shape, a direction other than `in` or `out`, a
  malformed population, a port naming a contract the file lacks, or a pair listed twice
  or as both connection and binding is refused with
  `Invalid architecture oracle: <what>: <key>`. Neither prints a passed line.
- **Generated, independent in the issue.** Only `python tools/sysml.py oracle` writes the
  file, from the resolved inventory of the working tree, after the Pilot validation and
  the fixed rules pass; otherwise it exits 2 and leaves the file unchanged. The gate never
  runs `oracle`; `check` compares inventory and file exactly as before. The independence
  is in the issue: every issue that changes the architecture lists the parts and
  connections it adds or removes, written by the definer before the generator is run and
  never from its output; comparing `oracle`'s change lines with that list is a numbered
  acceptance item and a review step. `check` and `oracle` read the file; `traces`,
  `markers`, `fingerprints`, `status`, `validate` and `setup` work without it.

Identity obligations require binding connectors; ordinary connections between the same
endpoints do not satisfy them. The oracle is deliberately specific to this target
architecture, not a general SysML connectivity theorem; a regenerated file approves
nothing until its change lines are compared with the issue's list of additions and
removals.

TC-DOC-005 fixtures remove connections, bypass authority, split authority, duplicate a
backend, redirect association/context identity, change waveform/provider directions or semantic item kinds, weaken identity bindings, add detached
stations, add runtime structure to a view and put back removed outside things. They judge
the pinned model of commit `1df1ba3a5` against the oracle file of the same commit, both
extracted with `git archive`, so a rewrite of the working tree's model changes no such
test. They run through the real Pilot before
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
   An issue that changes the architecture lists its added and removed parts, ports and
   connections, written before `python tools/sysml.py oracle` runs and never from its
   output; its acceptance compares that list with `oracle`'s change lines.
3. Settle open decisions on behaviour, data, ownership, states, timing, errors and test
   oracles with the operator; unresolved ones block the issue. A device or protocol whose
   behaviour is unknown gets an experiment (`cr:experimenting`) within the
   [limits below](#limits-for-experiments), findings on the issue. The issue then passes the
   ready check of the [CR process](../../harness/core/docs/CR-Process.md): an agent that did not
   write it posts `Ready: PASS`. A model-readiness review is held only on request.
4. Implement against the model and declared normative references. Verification keeps
   independent expected values and does not generate its sole oracle from that code.
5. Test the function, for real where it matters (a few short transmissions need no prior
   review; long or unattended on-air running waits for it). Only when the function is OK,
   independently review the exact candidate to find undesired behaviour; then the gate.
   Keep test existence, actual execution, model readiness and live acceptance separate.
6. Before issue closure reconcile delivered functionality, durable cases and model/source
   bindings. Current issues retain approval, review, deployment and dated execution evidence.

### Limits for experiments

The limits the [CR process](../../harness/core/docs/CR-Process.md) leaves to the project:

- Throwaway scripts live in `D:/wstx-tmp/experiments/<issue>/`, are never committed and may
  hold radio addresses.
- Live runs log under `D:/wstx-tmp/live/<issue>/`, removed when the issue closes.
- The radio is keyed as in any agent test: the radio preflight and its lease first
  ([handoff](HB9BLA-HANDOFF.md)), and short test transmissions only.
- Anything that needs the operator (the Flex switched on) is prepared and dry-run first.
- Three real runs without an answer mean stop and report to the operator.

### Method clauses (Markdown only)

These are HOW bindings, not product requirements and not SysML model elements.

| ID | Subject | Rule | Verification |
|---|---|---|---|
| CL-014-01 | Authority | One declared functional authority applies. Canonical SysML and an active FSD cannot coexist; archived Markdown is never an ongoing input after cutover. | TC-DOC-001; TC-DOC-007 |
| CL-014-02 | Functional scope | Model product requirements, behaviour, architecture/interfaces and verification. Keep harness, skills, process and build documentation Markdown-only. | TC-DOC-001; manual scope review |
| CL-014-03 | Architecture | The architecture model is functional: a part of the deployment is a function of the software, a port is the interface one function offers to another, and every connection joins two functions. An outside thing (hardware, a person, another program, a file or a service) is no function. It is an entry of the context list `OutsideThing` with exactly one owning function in the deployment and the `@FollowsSource` reference of its protocol or format. Where `Context.sysml` exists, it is also a black-box part there (CL-014-18 rule 4), each of its ports joined to a port of its owning function, and its owner is the function its ports join. An outside thing without an interface yet is a black box without a connection, on the pending list under its owner. What an outside thing is made to do is a promise of its owning function, observed at the peer system. Preserve population, identity, ownership and directed semantic exchanges. Views select existing model facts and cannot supply missing architecture. | TC-DOC-005 |
| CL-014-04 | Real validation | Required checks use the pinned full validator/library. Missing tools/files, syntax/name/semantic errors or missing completion evidence fail with no lint fallback. | TC-DOC-003; TC-DOC-004 |
| CL-014-05 | Stable identities and traces | Preserve stable FR/CL/TC identities and declared states; a verification case may instead retire under CL-014-15. Clause ownership and verification links are reciprocal. A clause derived from its FR by a derivation connection of the pinned model library (`#original` the FR, `#derive` the clause) is owned by that FR and verified by the cases whose objective verifies it; no reciprocal `dependency` is written for it. Clause and case keep their declared states; an FR's status is computed (CL-014-19). Delivered declarations name existing implementation/executable or explicit manual bindings; no declared status means a test passed. | TC-DOC-001; TC-DOC-002; TC-DOC-007 |
| CL-014-06 | Structural integrity | Validate the resolved architecture against the independent end-to-end oracle, including identity bindings, exclusive backend and shared authority. A legal but miswired model fails the oracle. The oracle is the data file `tools/sysml/architecture-oracle.json`. Only `python tools/sysml.py oracle` writes it, from the resolved inventory of the working tree, after the Pilot validation and the fixed rules pass; otherwise it exits 2 and leaves the file unchanged. The gate never runs `oracle`; `check` compares inventory and file exactly as before. The independence is in the issue: every issue that changes the architecture lists the parts and connections it adds or removes, written by the definer before the generator is run and never from its output; comparing `oracle`'s change lines with that list is a numbered acceptance item and a review step. `oracle` prints one line per difference to the file it replaces, sorted (`added`/`removed part <path> <type>`, `added`/`removed port <path> <contract>`, `added`/`removed connection <owner> <end> <-> <end>`, and `changed <section> <key>` for any other difference), then `Architecture oracle written: <counts>`, or `Architecture oracle unchanged` with no change line and the file not rewritten; it writes the file's form with sorted keys and keeps its `about` text, or writes a fixed sentence when there is no file. The file lists every part, reference, port with its items, connection and binding of the deployment, whatever package declares them; an unlisted or a missing one is refused, and so is a missing or invalid file. The inventory starts at the one package-level part usage and names every path from it. The fixed rules find the station population as the parts typed by `StationProcess`, the authority as the parts typed by `RadioAuthority`, and `profile : PersistedProfile`, `audioAdapter : AudioDeviceAdapter` and `catAdapter : RustRadioDriver` by usage name directly in the station process; a type is matched by the simple name of its definition or of a definition it specializes, in any package. The rules on the one deployment, views, the one authority, the adapters, the profile and the station population are fixed in the tool and hold in every model file. A port joined to no function is refused. | TC-DOC-005 |
| CL-014-07 | Implementation readiness | Before code, the issue's ready check passes: the selected model slice settles observable behaviour, interfaces/data, ownership, state/timing/error choices and independent oracles. Explicit implementation freedoms do not authorize unresolved functional decisions. | TC-DOC-006 |
| CL-014-08 | Functional sequence and closure | Use the declared canonical artifact first, pass the ready check, implement against it and verify with independent expected results. Reconcile delivered behaviour and durable cases before closing the issue. SysML-only authority requires no maintained/generated Markdown specification. | TC-DOC-006; TC-DOC-007; independent closure review |
| CL-014-09 | Modeling feedback | Correct differences against the declared authority; do not bless code defects by rewriting requirements. Record causes/review on the issue and improve demonstrated reusable/project-specific gaps, with a focused regression where useful. | TC-DOC-006; independent review |
| CL-014-10 | Model file tree | The model is every `*.sysml` file at any depth below `docs/sysml`, named by its path relative to that folder. The required packages are `WstxRequirements` and `WstxArchitecture`, and `WstxContext` whenever the model file `Context.sysml` exists; each is the package of exactly one model file, whatever the file's name and folder, and the entry file stays at the root. `Context.sysml` declares the package `WstxContext` and no identity, and no other model file names `WstxContext` in code. Any other package is accepted without a reference; a lost model file stays noticed through the required identities, name resolution and the `Proves:` tags. Identities and links hold across folders and packages. | TC-DOC-007; TC-DOC-008 |
| CL-014-11 | Stated once | Status and bindings are read as attributes or as `ModelBindings` metadata, once per declaration. A delivered clause without a binding takes the function binding of its model file; a case takes automation from the verification definition of its file that it is typed by. A declaration with an identity in a form the catalog does not read is refused. | TC-DOC-009 |
| CL-014-12 | Marker listing | `markers` lists every `ModelNotes` marker of the model by file key and line, with counts by kind; it checks nothing and writes nothing. | TC-DOC-010 |
| CL-014-13 | Tag and binding agree | Every test that names a verification case, by an attached `Proves:` tag or a JavaScript test name, is in that case's binding, as its file or as `path::symbol`. A `path::symbol` binding of a manual case names an existing test. The gate's model bindings report a revision and do not apply this rule. | TC-DOC-011 |
| CL-014-15 | Retired case | A verification case retires by `@RetiredCase { identity = "<TC>"; test = "<path>"; }` directly in the body whose `@DetailTests` names that path as written; an FR, a clause, another spelling, a path that body's detail tests do not name, an identity retired twice and a retired identity declared again are refused. A case whose checks went to other contract cases retires as superseded by `@RetiredCase { identity = "<TC>"; supersededBy = "<TC>; <TC>"; }` in any model file, at package level or in a definition body, with no `@DetailTests`; each named case is declared and not retired, and both features, neither, a value that is not one literal, a malformed or repeated identity or the case itself are refused. A retired identity counts as present for the stable baseline, is not a catalog entry and is never declared again; tags, test names and clause dependencies naming it are refused as for any undeclared identity. `retired` checks the catalog and lists the retirements; the gate's model bindings list neither the retired identity nor its test file. | TC-DOC-013 |
| CL-014-16 | Model values in tests | A contract test reads a value the model holds as data from the `.sysml` text by its qualified name, through the one reader of its language. It never writes the value again or parses the model with its own patterns. A value with a unit ends its name in a member of `WstxUnits::UnitSuffix`. A missing, duplicate or unreadable value, or a broken unit rule, fails the test; it never skips. | TC-DOC-014 |
| CL-014-17 | Equivalence and identity diff | `equivalence <base> [<head>]` compares two revisions (head omitted: the working tree), each extracted whole with `git archive` into a temporary folder that is removed; nothing in the repository is written. Exit 0 equivalent, 1 differences listed, 2 cannot compare (unknown revision, or a side failing the Pilot validation). Every named element of the model files has exactly one counterpart, matched by qualified name without its top-level package; several of one name on a side pair by equal content, their named members included, the rest is missing or added. Among equal candidates a member of a paired owner pairs first under its owner's counterpart, then a top-level element or a member of an unpaired owner in its own package, then any; file order decides only among candidates neither tells apart. A member keeps its owner: a pair whose owners are not paired with each other is a difference. The counterpart has the same kind, declared and short name, doc and comment texts, literal values, multiplicities and directions, the same relationships (typing, specialization, subsetting, redefinition, satisfy, verify, subject, dependency, connection ends, metadata with its values) to counterparts, and the same unnamed owned elements in declaration order. A difference names the element, the property or relationship kind and both files. Free to differ: the file and top-level package of an element, the set of top-level packages, imports and aliases (an `expose` is compared), and how a reference is spelled. Package-level unnamed elements, package docs and the members outside any package (a file's header comment) compare as a multiset by content, and line notes as a multiset of texts over the model. A qualified name in text is equal when it resolves on each side, by the Pilot's resolution with imports, aliases and public re-exports, to counterparts, and a relative Markdown link when it resolves to the same file or to the model file of the same package. Each element whose file or package changed is listed with both, and a count per file pair. At the head, model citations in the tracked files under `server/`, `client/`, `tests/`, `tools/`, `fixtures/`, `docs/harness/`, `.harness/` and `README.md` (qualified names starting with a top-level package of either side, `docs/sysml/` paths) that resolved on the base and not on the head are differences (stale-by-change); those resolving on neither side are listed. Two kinds of tracked file below `tools/sysml/tests/` read another model. A file with a line `PINNED = "<7 to 40 hex>"` naming a commit of the repository is a pinned reader and is judged by this rule only, even when it also declares a package: a citation in it is exempt only if it resolves in the pinned commit's model (a name in that commit's export, one more Pilot export per distinct pinned commit, or a `docs/sysml/` path in its tree), and one that does not is judged as before; a pinned commit failing the Pilot validation exits 2. A file there without a `PINNED` line is a fixture reader of each `<Top>` it declares as `package <Top> {` or `library package <Top> {`, and its name citations whose first segment is such a `<Top>` are exempt. Every other citation, in any other file, keeps the stale-by-change rule. An exempt citation that would have been stale-by-change prints `exempt <file>:<line> <citation> (pinned\|fixture)`, is no difference and leaves the exit code unchanged; the summary then ends with `; exempt: <file> <count>, ...`, one entry per file in file order with its number of exempt lines, and is unchanged without any, also in each commit of `--marked`. `identities <base> [<head>]` reads the FR/CL/TC declarations of `docs/sysml` of each side without validating the tree and the Pilot, and prints one line per identity with its status (unchanged, moved, changed, added, retired with its test file or the cases superseding it, removed) and both files, then a count per status. Text compares from the keyword to the closing brace with LF line endings, relative Markdown links resolved as `equivalence` resolves them, a leading top-level package dropped from each qualified name and the dependency lines of its `from` identity. `equivalence --marked` checks each commit of `master..HEAD` with the trailer `Model-Move: pure` against its first parent, with one Pilot export per distinct tree, prints the number of exports, and reports "no marked commit" with exit 0 when there is none. | TC-DOC-015 |
| CL-014-18 | Target structure checks | `check` applies the rules below to every model file and element not on the pending list `tools/sysml/pending-structure.json`, and the deployment rules (3 for connections, 4, 5, 6 and 7) to the whole deployment once `Station.sysml` is not on the list; a listed file is exempt from every rule, a listed element with its members. Names: the root is the one package-level part usage; the station is `station` directly in the root; the frontend `frontend` directly in the station; the browser client `browsers` directly in the frontend; the station process the parts typed by `StationProcess`, and in it the station service `station`, `web`, `ranking`, `auto`, `qso` and `transmit`, each directly in it; the operator `operator` directly in the root. A port is typed by an internal interface when its port definition is declared in a file under `interfaces/internal/`, conjugated or not; typed by `StationLink` when declared in `interfaces/internal/StationLink.sysml`, by `OperatorInteraction` when declared in `interfaces/external/OperatorInteraction.sysml`. The control family is every `interface def` whose name ends in `Control`, its files `interfaces/internal/*Control.sysml`. The commanding end of a connection is its first end. A role part or file that is missing while its rule applies is refused, naming it. Rules: (1) a file of a part folder (each folder directly under `backend/` other than `operating/`, each folder directly under `backend/operating/`, and `frontend/`) names, by `import` or by qualified name in code (not in comments or `doc`), only packages of its own part folder, of files under `interfaces/` and `shared/`, of `Requirements.sysml` and of the pinned library; a file under `interfaces/` only packages of its own file, `shared/`, `Requirements.sysml`, the library and other files under `interfaces/`, where a file under `interfaces/external/` names no file under `interfaces/internal/` (except `interfaces/external/Mcp.sysml` naming control interface files), and a control interface file never names `interfaces/internal/StationLink.sysml`, `interfaces/internal/StationCommands.sysml`, `interfaces/external/Mcp.sysml` or `interfaces/internal/OperatingChain.sysml`. (2) `Station.sysml` holds, at package level and inside its part definitions, only its package declaration, part definitions, part usages and reference parts, connections and binding connectors, `satisfy` of an FR by a part, imports, `doc` and comments. (3) Every connection of the deployment (binding connectors excepted) is typed by an `interface def` declared in a file under `interfaces/`; an interface definition under `interfaces/` has at least one item (items in one direction only pass); every item is typed by a definition that has a feature of its own or inherited from a model definition, or by a placeholder on the pending list. (4) An outside part is a part usage directly in the root other than `station`: its type and its own body have ports and attributes only (with `doc` and metadata); no requirement's subject is an outside part or its type; it has at least one port joined to a port of a function, unless it is on the pending list. (5) An interface of the control family has the station service at its commanding end. (6) The browser client has exactly one port typed by an internal interface, typed by `StationLink` and connected to `web` of a station process; its only other port is typed by an outside interface the tool lists (today `interfaces/external/OperatorInteraction.sysml`, connected to `operator`); no connection with an end in `frontend` ends anywhere else. (7) Among `ranking`, `auto`, `qso` and `transmit` only `ranking` to `auto`, `auto` to `qso` and `qso` to `transmit` are connected, first end to second end. (8) An FR states no status (`coverage`, `@Status`), no code or test binding (`implementation`, `@ImplementedIn`, `@TestedBy`, `@DetailTests`) and no issue reference (`#` followed by digits) in its text, its `doc` included. (9) No `dependency` is declared. (10) Every requirement, definition or usage, declares a `subject`. The pending list is JSON: `files`, a list of model file keys, and `elements`, a map from the qualified name of a model element to its owning function, whose rewrite takes the entry off. It is refused whole, `check` exiting 2 with no passed line, when it is missing, unreadable or not JSON, lists a key or a name twice, a key that is no model file or a name that resolves to no element, an element with an empty owner, or lists in `files` `Context.sysml` or a file under `interfaces/internal/` or `interfaces/external/`. `check` prints every structure fault, one line each, `Structure rule <n>: <what>: <key>:<line>` for a file rule or `Structure rule <n>: <what>: <path>` for a deployment rule, sorted by rule, key and line, then exits 2 with `SysML check failed: <k> structure faults`; on a pass it prints `Structure checks passed: <a> files in target form, <b> files and <c> elements pending; deployment rules on\|off`. Only `check` reads the list. A check on a pinned model is `check` entered with a commit by the tool's Python-level setting `CHECK_COMMIT`, set by its caller as the oracle file and the Pilot inventory are; there is no command-line option, and without it `check` reads only the working tree's list and model and refuses the list as above. Authority, catalog, trace bindings and the validation's file keys come from the working tree, the Pilot inventory from `validate` as the caller supplies it, and the oracle file from `ORACLE`; the pending list is the commit's own `tools/sysml/pending-structure.json`, and the key set it is checked against and the model files, keys and sources of the structure stage are the commit's `docs/sysml`. A commit without the file predates the structure checks: it is not refused, no structure stage runs, `Structure checks not run: <commit> has no pending list` takes the structure line's place and the exit code is that of the stages before. A file present there is refused or applied with the form rules above, against the commit's key set and the supplied inventory; `{"files": [], "elements": {}}` means the target is reached and all ten rules apply, the deployment rules among them, and a zero-byte file is refused as malformed. | TC-DOC-016 |
| CL-014-19 | Computed FR status | An FR's status is computed from the clauses derived from it, by derivation or by the clause's `dependency` to the FR: `implemented` when all its clauses are implemented, `target` when all are target or it has none, `partial` in every other case, so two partial clauses give a partial FR. The catalog accepts an FR without a stated status and without a binding; the FR's catalog entry carries the computed status, and an FR that states a status has it checked as any declaration's. `status` prints each FR's computed status with its clause counts and the stated status where it differs; it runs no Java and writes nothing. | TC-DOC-017 |

## Documentation-tool test definitions

These checks prove HOW clauses, not radio functionality. Level 2 means isolated
verification using local fixtures. TC-DOC-014 runs in the Rust and Node suites on the test
machine without the Pilot; the other rows run on the documentation development PC with the
pinned portable Pilot. No radio, live service, Jupyter server or global Java is needed.

| ID | Clauses | Independent actions and expected observations | Method and location |
|---|---|---|---|
| TC-DOC-001 | CL-014-01, CL-014-02, CL-014-05 | Inspect stable IDs, declared states, scope and FR/CL/TC relationships. Tooling reads the canonical model directly, checks bindings and never rewrites it or requires a Markdown view. | Automated local model/tool fixtures; independent scope/meaning review. |
| TC-DOC-002 | CL-014-05 | Mutate declared state/identity/link or remove a required artifact and expect a named nonzero refusal. A clause derived from its FR and verified by a case, with no dependency, is accepted, also with package names on the metadata and the ends, and the pinned Pilot resolves that form; a clause with both dependencies and no derivation is accepted. Refused: a clause with neither a derivation nor a dependency to an FR (`Canonical clause lacks requirement ownership`), a derived clause no case verifies (`Canonical clauses lack verification links`), a clause owned by dependency without its case dependency or a case verifying it without the reciprocal one, a derivation from a missing FR or deriving an FR (`Invalid canonical clause dependency`), and a derivation body other than one `#original` and one or more `#derive` ends (`Invalid canonical derivation: <key>:<line>`). | Automated isolated fixtures on this PC. |
| TC-DOC-003 | CL-014-04 | Feed the actual Pilot a valid model, malformed syntax and unresolved names/types. Accept only the valid model; other cases return diagnostics and nonzero. | Automated pinned Pilot, local fixtures. |
| TC-DOC-004 | CL-014-04 | Remove/corrupt Java, validator/library or model paths. Required validation fails nonzero and never reports semantic PASS. | Automated tool/prerequisite fixtures on this PC. |
| TC-DOC-005 | CL-014-03, CL-014-06 | Load the complete architecture with the actual Pilot, inspect resolved port/item/association/binding inventory and compare with independent endpoint expectations. Remove/delegate/bypass/split/duplicate/redirect a required path or authority, change item type/direction, weaken identity binding or add view-only runtime parts. Each negative fails semantics or integrity; a rendered view cannot repair it. Remove each entry of the oracle file alone, damage or remove the file, declare a port, a part and a bypass connection in a definition of another package, used as a type or inherited, and put a second deployment, a view-made part and a subtype of the authority into a library package or another package: each is refused. A function of another package with its port and connection passes once the oracle file names them. Put back the parent's removed outside things with their ports and connections: refused while unlisted. List a port that no connection joins: refused, naming the first in sorted path order. The context list names exactly the issue's outside things, each with one owner in the deployment and one `@FollowsSource`. Where `Context.sysml` exists, an outside part there without ports and without a connection is refused by `check` with `Structure rule 4: outside part joined to no function: <path>`, and passes when listed under `elements` of the pending list with its owner. The mutation and fixture cases judge the model of commit `1df1ba3a5` against the oracle file of the same commit, both extracted by `git archive`. `oracle` on that model writes a file equal as data to its hand-written oracle and prints no change line. On a fixture tree in the skeleton's form (root `context` in `Context.sysml`, parts and interfaces in packages of their own folders): `oracle` then `check` pass, a second `oracle` prints `unchanged` and leaves the bytes equal, and an added connection is refused by `check` until `oracle` runs again; a part, a port and a connection added and removed and an item type changed, one at a time, each print exactly their one change line; a model the Pilot refuses, a second authority in another package, a second package-level part usage, a duplicate `catAdapter` and a station population `1..1` make `oracle` exit 2 with today's message and the file unchanged, and `traces`, `markers`, `fingerprints`, `status` and `check` neither create nor change it; an outside part joined to its owner's port passes and unjoined is refused with `port joined to no function`. | Automated full-validator mutation fixtures and independent architecture review on this PC. |
| TC-DOC-006 | CL-014-07, CL-014-08, CL-014-09 | An agent that did not write the issue reads it and the canonical contract it names; missing required decisions, missing test cases or a shared-only generated oracle give `Ready: not yet`, and `cr_state.py` refuses `implementing` without a `Ready: PASS`. The independent review of the candidate rechecks exact changes and closure reconciliation. On request, a model-readiness review traces the contract to code boundaries. No syntax/fingerprint result establishes implementation sufficiency. | Manual source/model/meaning reading on this PC; automation cannot establish complete intended meaning. |
| TC-DOC-007 | CL-014-01, CL-014-05, CL-014-08 | Refuse dual/missing authority and an active FSD without the marker, missing/duplicate stable IDs, missing required packages, invalid state, nonreciprocal verification links, missing/escaping source paths and unsupported executable claims. Refuse dangling active references to retired FSD content. Edited/missing archived Markdown does not change canonical checks; no command rewrites the model. A new package needs no reference and is validated in full; a model with or without `WstxProductScope` is accepted. `Context.sysml` with `WstxContext` is accepted; `Context.sysml` with another package or none, `Context.sysml` declaring an identity, and another file importing, naming or declaring `WstxContext` are refused; with `Context.sysml` removed while another file names `WstxContext`, the pinned Pilot refuses. Source edits/deletions invalidate both model suites' evidence; source-only changes select fast traces without the full model suite. Fast traces refuses a deleted binding and never invokes Java. | Automated isolated Python fixtures on this PC; full integrated Pilot validation remains separate. |
| TC-DOC-008 | CL-014-10 | Place a clause and its case in a subfolder file, move, rename and split the file of a required package, remove the package (`WstxRequirements`, `WstxArchitecture`), declare it in two files, move the entry file, verify and link a clause through a package-qualified name, add an additional package referred to by import, by alias and not at all, with and without `WstxProductScope`, and a former library package and a file without a package. The real model is accepted. The tree is accepted, each fault is refused by package or key, fingerprints and the gate's model list name every file by key, and the real model with one file of a required package moved into a folder under another name passes the full validation with the same identities. | Automated isolated Python fixtures and one full Pilot validation on this PC. |
| TC-DOC-009 | CL-014-11 | Write status, bindings and method as metadata, state one twice, leave a clause's binding to none, one and two function bindings, type a case by a definition with and without automation in its file and in another, bind a test on a definition, and declare an identity in an unread form. The new forms give the catalog and gate bindings of the attribute forms, each fault is refused by identity or key, and the real model rewritten to metadata passes the full validation with the same identities. | Automated isolated Python fixtures and full Pilot validations on this PC. |
| TC-DOC-010 | CL-014-12 | List markers in each form across folders, in comments, with joined strings, by kind, with an added kind, an unknown kind, no ModelNotes file, a broken catalog and no authority. | Automated isolated Python fixtures on this PC. |
| TC-DOC-011 | CL-014-13 | Tag a test in a file its case does not bind, and as another symbol of a file bound by symbols; name a case by shorthand, in a tag for two cases, in a JavaScript test name, above a helper, on an ignored test, on a planned and on a manual case, and outside the source roots; bind a manual case to a missing symbol. Each fault is refused naming case, path and test; adding the binding or removing the identity is accepted; the gate's bindings still report such a revision. | Automated isolated Python fixtures on this PC. |
| TC-DOC-013 | CL-014-15 | Remove a baseline case and retire it beside the `@DetailTests` that names its file, with and without package names, two in one body, in a subfolder file and in a comment; retire an FR and a clause, a malformed identity, a missing, repeated or other feature, a value that is not one literal, a test with `;` or `::`, the `metadata` keyword form, a file named only by another body or by no `@DetailTests`, one identity twice in one file and in two, and a retired identity declared again; name the retired identity in a tag, a JavaScript test name and a clause dependency. Each accepted model passes with the declared identities only, each fault is refused with its message, key and line, and the existing messages are unchanged. List three retirements in two files and none with `retired`, on a broken catalog and with no authority. The gate's bindings of a retiring revision equal those of the revision without the case. The pinned Pilot resolves the def text and refuses a misspelt feature. Superseded: with the extended `RetiredCase` definition in the fixture's `shared/ModelBindings.sysml`, TC-A superseded by TC-B and TC-C at package level of a subfolder file, with package names, and directly in a definition body, with TC-B and TC-C declared, counts for the baseline and is no entry, and `retired` prints `TC-A: superseded by TC-B, TC-C: <key>:<line>`, sorted beside a retirement into the detail tests. Refused: TC-C missing and TC-C retired (`Superseding case missing or retired`); naming itself, both `test` and `supersededBy`, neither, a sequence or a `+` join, a malformed, repeated or empty identity and the feature twice (`Invalid retired case`); a `Proves:` tag naming TC-A. The pinned Pilot accepts the extended definition with both forms and refuses a misspelt `supersededBy`. | Automated isolated Python fixtures and full Pilot validations on this PC. |
| TC-DOC-014 | CL-014-16 | Each reader reads the fixture tree `tests/fixtures/model-values/`, with its own `WstxUnits::UnitSuffix`, against the hand-written list of expected values there, in an LF and a CRLF copy: a value two folders deep in a file named other than its package; package-level, definition and usage-redefinition values; a quoted name; integer, negative real, a string holding `\"`, `;`, braces and `//`, `true`, `false`, `null` and an enumeration value; enum members in both forms after a definition `doc` and with a doc body; three usages of a definition, one typed by its qualified name; declarations in comments and `doc` not read; numbers with and without their unit. Each refusal names the qualified name and the reason: a missing and an empty folder, a non-UTF-8 file, a package in no file and in two, a name not declared and declared twice, a value missing, an expression, a `+` join, a list, a unit expression, a feature only the definition states, an empty table, an unlisted suffix, a value with a unit read as a plain number, and the suffix list missing and empty. The six tests that read `WstxOperatingReceive` pass with the parent's assertions, also with its file moved and renamed, and go red on a scratch copy with a changed or removed vector, a changed or removed band entry, a renamed `ft8Hz` and `Hz` removed from the suffix list. | Automated fixtures in the Rust and Node suites on the test machine, without the Pilot; scratch-copy runs on the test machine, quoted on the owning issue. |
| TC-DOC-015 | CL-014-17 | On the real history, the parent of the commit that divided `Requirements.sysml` by part against that commit is equivalent and leaves `git status` unchanged; their identities are 522, 202 moved exactly as that issue's assignment table, among them the two cases with rewritten links, and 320 unchanged; a revision against itself is equivalent. On a small model in a temporary repository each mutation exits 1 naming the element and the kind: a doc character; a dropped attribute and action definition; a dependency, a `verify` and a type target; a value, a multiplicity and a rename (missing plus added); an unqualified reference resolving to another element after a move (qualified: equivalent); kind, short name, direction, specialization, subsetting, redefinition, `satisfy` target, subject type, connection end, a status and a module value; a package-level comment dropped and altered and a package-level `satisfy` dropped; a link retargeted to another file; one of two same-named definitions, both moved, with a changed value; values swapped between two same-named definitions; a member moved from one to the other (changed owner); an `expose` changed and dropped; a comment outside any package altered and dropped. Two same-named definitions with equal own facts, one moved to a file read first, are equivalent, paired by their members. Two equal same-named enumerations in two packages, the file of one renamed to be read after the other's, are equivalent, the renamed one listed as moved within its own package; with a literal added to the renamed one, only it is missing and added, with its new literal added, and no line names the other's file or a typing target. A case moved in the commit that moves the file its link targets, the link updated, is moved; its link retargeted to another file, changed. A move of two elements to a new package and file, with imports, an updated qualified name in text and an updated link, is equivalent and listed with a count of 2; that name pointing to another element, or a dropped line note, is a difference. A code and a suite citation of a moved element or file are stale until updated, a citation unresolved on both sides is listed only, and a citation reached through a public re-export resolves. Readers below `tools/sysml/tests/`, the head moving the cited element: a pinned reader whose `PINNED` names the base, citing the moved name, prints `exempt <file>:<line> Core::Run (pinned)`, exits 0 and the summary ends `; exempt: <file> 1` (E15 a); its `PINNED` naming a commit without that name (E15 b), naming no commit of the repository (E15 c), or naming that commit while the file also declares `package Core {` (E15 f), the citation stays stale-by-change with exit 1 and no exempt entry; a fixture reader declaring `package Core {` prints `exempt ... Core::Limits (fixture)` while its `Extra::Limits` stays stale, exit 1, counting 1 (E15 d); a file outside `tools/sysml/tests/` with both signs and a file below it with neither stay stale with no exempt entry (E15 e). On this repository `test_architecture_integrity.py` is a pinned reader of `1df1ba3a5` and no fixture reader, the names it cites in `tools/sysml/tests/test_architecture_integrity.py` (among them those of R7's "port path twice" and "direction inout" cases) resolving in that commit's export; `test_architecture_oracle.py` is a fixture reader with `WstxArchitecture` among its declared packages, the names at its lines 135-136 starting with it; an ordinary file is neither (R-real). An unknown revision and a head failing the Pilot exit 2. Identities of a pair with one of each status count 1 per status, the retired one with its test file; a case declared in the base and superseded in the head is retired `superseded by TC-B, TC-C`; on two real revisions the lines are the union of both sides. With marked, unmarked and altering commits `--marked` checks the marked ones with 3 exports, names the altering commit with exit 1, and reports no marked commit. | Automated isolated Python fixtures in temporary git repositories and the repository's own history, with the pinned Pilot, on this PC. |
| TC-DOC-016 | CL-014-18, CL-014-03 | Without the Pilot, on small trees: a part file naming its own folder's package, an `interfaces/` package, a `shared/` package, `WstxRequirements` and `ScalarValues` passes, and so do `StationLink` and `Mcp` importing `QsoControl`, `RadioControl` naming `RadioProperties`, `Hearing` naming `PskReporter`, `ReceiveControl` and `OperatingChain` naming `QsoControl`, and a qualified name in `doc`; refused: a part file importing another part's package or naming it in code, `QsoControl` naming `StationLink` or `OperatingChain`, and `Cat` naming `ReceiveControl` (rule 1). `Station.sysml` with its package, part definitions and usages, a reference, a connection, a binding and `satisfy 'FR-001'` passes; refused with key and line: at package level an `attribute def`, a `port def`, a requirement, a `satisfy` of a clause and a `dependency`, in a part definition an attribute and a port; `backend/station/Station.sysml` is not judged (rule 2). An FR with `coverage`, `@Status`, `implementation`, `@ImplementedIn` or `#40` in its `doc` is refused (rule 8); a `dependency` is refused and a derived clause with its case passes (rule 9); a requirement definition and usage without `subject` are refused (rule 10). Each faulty file on the pending list passes. With the pinned Pilot, on a fixture tree in the target form that passes every rule with the deployment rules on, one edit at a time: an untyped connection, one typed by an interface outside `interfaces/`, an interface without items, an untyped item and one typed by a featureless `Empty` (passing with `Empty` under `elements`) are refused, and with `Station.sysml` listed the connection faults pass (rule 3); an outside part whose type has a part, an action or a state, whose body has a part, or that is a requirement's subject is refused (rule 4); a control interface commanded from its second end, `transmit` to `radioControl` and `auto` to `qso` typed by a control interface, and no station service are refused (rule 5); a second internal browser port, the `StationLink` port connected to `receive`, a third port to an outside part, a connection from inside the frontend to `receive` and no operator are refused (rule 6); `auto` to `transmit`, `ranking` to `qso`, `qso` to `auto` and no `ranking` are refused (rule 7); an outside part joined to no function is refused unless listed (rule 4, CL-014-03). The pending list missing, empty, not JSON, with a key or a name twice, an unknown or renamed key, a name resolving to nothing, an empty owner, or `files` naming `Context.sysml` or `interfaces/internal/X.sysml` exits 2 with no passed line; element entries inside `Context.sysml` and `interfaces/` are accepted; two faults of two rules are listed in rule, key and line order before `2 structure faults`. On this tree `check` passes and prints the structure line of its pending list after the architecture line. Pinned checks: on `1df1ba3a5`, which has no list, with the working tree's list carrying `WstxContext::browserOwner`, `check` prints `Structure checks not run: 1df1ba3a5 has no pending list`, runs no rule and exits 0 (P1); on a fixture commit whose list is `{"files": [], "elements": {}}` and whose model declares a `dependency`, `Structure rule 9: dependency declared: <key>:<line>` with exit 2, and without the `dependency` the passed line with 0 files and 0 elements pending and the deployment rules on (P2); a commit's list naming a file key of that commit absent from the working tree is accepted, one naming an element absent from the supplied inventory is refused with `no model element`, and a malformed or zero-byte list there is refused (P3); the architecture integrity tests on `1df1ba3a5` as pinned checks, with a temporary working list carrying `WstxContext::browserOwner`, pass with their oracle and other-command assertions unchanged (P4). | Automated isolated Python fixtures, full Pilot validations of the fixture states and one `check` of this tree on this PC. |
| TC-DOC-017 | CL-014-19 | A synthetic catalog with one FR per case, the FRs stating no status and no binding, the first clause of each FR owned by a dependency and the second by a derivation: (implemented, implemented) gives implemented; (partial, partial), (implemented, target) and (implemented, partial) give partial; (target, target) and no clause give target. Both forms of ownership count. `status` prints the lines and the summary counted by hand, an FR stating another status shows `; stated <state>`, and nothing is written; a broken catalog and a missing authority exit 2. On the working tree `status` exits 0 and prints one line per FR of the catalog in identity order in that form; each line's status and counts agree with its clauses' states as the catalog reads them, and the summary's counts equal the per-line statuses. | Automated isolated Python fixtures and the real model on this PC, without the Pilot. |

Executable companions are `tools/sysml.py`, `tools/sysml/tests/` and the pinned
`tools/sysml/Validate.java` adapter; for TC-DOC-014 they are the two model-value readers
and their tests. Results and independent review
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

The canonical entry point is `docs/sysml/Requirements.sysml`. The model set includes the
required packages `WstxRequirements` and `WstxArchitecture`, and `WstxContext` whenever
the model file `Context.sysml` exists. Additional packages are discovered, scanned and
fully validated without a reference; a model with or without `WstxProductScope` is
accepted. A lost model file stays noticed through the required identities, name
resolution and the `Proves:` tags. A missing required package fails.

A model file is a file `*.sysml` at any depth below `docs/sysml`; its key is its path
relative to `docs/sysml` with forward slashes, and every message that names a model file
names it by its key. No folder is excluded; a file kept out of the model keeps a suffix
other than `.sysml`. The package of a model file is its first package declaration outside
comments; a file without one has no package. A package named only in a comment, nested in
another package or declared after the first package of its file is not the file's package.

- **Required packages.** Each package in the tool's list of required packages
  (`REQUIRED_PACKAGES` in `tools/sysml.py`, the two named above), and `WstxContext` while
  `Context.sysml` exists, is the package of exactly
  one model file, whatever that file's name and folder. The name is compared whole. None:
  `Canonical model packages missing: <names>`, the names sorted and joined by `, `. Two or
  more files: `Duplicate canonical model package: <package>: <keys>`, the keys sorted and
  joined by `, `. The catalog asks for no model file name: two model files of one name in
  different folders are accepted, each judged by its package and named by its key. The
  file of a required package may be moved, renamed or split while one file keeps the
  package. A change that renames or removes a required package changes the name in the
  list in the same change, with this section and the code comments that cite it; there
  is no alias from an old name to a new one. Any other package, and a file without a
  package, is an additional package and needs no reference; the file name decides
  nothing.
- **Entry file.** `Requirements.sysml` with the marker `// Canonical authority: SysML` is
  required directly in `docs/sysml`. Elsewhere or absent, the commands refuse with
  `No declared functional authority`.
- **Context file.** `Context.sysml` directly in `docs/sysml` is the top layer: nothing
  imports it and it holds no identity. While it is absent, two packages are required;
  once it exists, `WstxContext` is required too, with no tool change. Before the
  required-package check, `traces`, `check`, `fingerprints`, `retired` and `status`
  refuse: a `Context.sysml` whose package is not `WstxContext` (another package or none),
  `Context file package is not WstxContext: Context.sysml`; a `Context.sysml` declaring an
  FR, CL or TC identity, `Context file declares an identity: <ID>: Context.sysml`; and any
  other model file naming `WstxContext` outside comments and strings (an import, a
  qualified name or a package declaration),
  `Model file names the context package: WstxContext: <key>`.

Each clause declares `coverage : ImplementationState` as target, partial or implemented;
an FR may declare it too or leave it out, and its status is computed (CL-014-19). Each
verification declares `automation : AutomationState` as planned, partial or implemented.
These are declarations of available companions, not execution or acceptance results.

- **Clause ownership.** A clause is owned by its FR in one of two forms. By dependency:
  `dependency <name> from '<CL>' to '<FR>';` beside `dependency <name> from '<CL>' to
  '<TC>';` for each case whose objective verifies it, reciprocity checked. By
  derivation, the form of the pinned model library (Domain Libraries/Requirement
  Derivation): `#derivation connection { end #original ::> '<FR>'; end #derive ::> '<CL>'; }`,
  with or without package names on the metadata and the ends, verified by the cases
  whose objective verifies it and with no reciprocal dependency. A connection body other
  than one `#original` end and one or more `#derive` ends:
  `Invalid canonical derivation: <key>:<line>`; a derivation from an FR that does not
  exist or deriving anything but a clause: `Invalid canonical clause dependency: <CL> ->
  <FR>`. A clause with neither form: `Canonical clause lacks requirement ownership: <CL>`;
  owned by dependency without a case dependency: `Canonical clause lacks a declared
  verification case: <CL>`; verified by no case: `Canonical clauses lack verification
  links: <CL>`. Reciprocity (`Nonreciprocal canonical verification links: <TC>`) is
  checked for the clauses owned by a dependency only.
- **Computed FR status.** The status of an FR is computed from the clauses it owns in
  either form: `implemented` when all are implemented, `target` when all are target or it
  owns none, `partial` otherwise. An FR without a stated status needs no binding. The
  catalog entry of an FR carries `status` (computed), `stated` (the stated state, or
  none) and `clauses`; its `state` is the stated one, or the computed one when none is
  stated.

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

A *declaration* is a requirement or verification with a stable identity that the catalog
reads. The forms above are the *attribute form*. The *metadata form* uses the names of the
harness template `harness/core/templates/sysml/model-bindings.sysml` with this project's
status names; a metadata name may carry package names (`@ModelBindings::Status`), and so
may an enumeration value. Both forms are read:

```sysml
action def StandardContact {
    @ImplementedIn { module = "server/src/contact.rs"; }
    @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
}
requirement 'CL-010-18' {                      // takes server/src/contact.rs
    subject qso : WstxQsoPart::QsoAndLogging;
    @Status { build = ImplementationState::implemented; }
}
verification def EngineCase {
    subject qso : WstxQsoPart::QsoAndLogging;
    attribute level : Integer = 2;
    attribute location : String = "Windows development PC, isolated, no RF";
    @Automation { run = AutomationState::implemented; }
}
verification 'TC-007-010' : EngineCase {
    objective { verify 'CL-010-02'; }
    @TestedBy { test = "server/src/contact_tests.rs"; }
}
```

- **Status as metadata.** In a requirement body `@Status { build = ImplementationState::<state>; }`
  is read as `attribute coverage`. In a verification body
  `@Automation { run = AutomationState::<state>; }` is read as `attribute automation`, and it
  may also hold `method = "manual";` or `method = "automated";`, read as `attribute method`.
  States and their meaning are unchanged.
- **Bindings as metadata.** In a requirement body `@ImplementedIn { module = "<bindings>"; }`
  is read as `attribute implementation`. In a verification body
  `@TestedBy { test = "<bindings>"; }` is read as `attribute executable`. The value is one
  string literal with the grammar, checks and messages of the attribute form.
- **Once per declaration.** Status, binding and method are each stated at most once per
  declaration, in either form. Status stated twice, or not at all and not taken from a
  definition: `Missing or invalid declared model state: <ID>`. Binding or method stated
  twice, a value that is not one string literal, or a method other than the two:
  `Invalid verification/implementation metadata: <ID>`.
  Nothing is taken over where the declaration names the fact itself. A declaration whose
  own body names status, binding or method in a spelling the tool does not read
  (`attribute implementation`, `attribute automation` or `attribute method` with a value
  that is not the read form, such as a `+` expression or a qualified state; the feature
  redefined in the attribute form, such as `attribute :>> automation = ...`; an own
  `@ImplementedIn`, `@Status` or `@Automation` body with a non-blank statement the tool
  did not read, such as `:>> module = ...`; or the same metadata written with the
  `metadata` keyword, such as `metadata ImplementedIn { ... }`) is refused with the message
  above for that fact wherever a value would otherwise be taken over (a delivered clause
  beside a function binding; the state of a case; the method of a case beside a
  definition that states one); elsewhere the result is that of the attribute form. It
  never gets the value of its function binding or of its definition.
  `@Automation {}` and `@Automation { method = "automated"; }` keep taking the state over.
- **Shared case definition.** `verification '<TC>' : <Definition> {` is read as a case, as
  `verification '<TC>' {` is. A case that states no automation state takes the state of its
  definition, and a case that states no method takes its method, when the definition is a
  `verification def` in the same model file, named without package names, and states them
  in either form. A state or method the case states itself wins. Nothing is taken from a
  definition in another file or from the definition's own supertypes; such a case states
  its own. A `@TestedBy` or `attribute executable` on a verification definition without
  identity is refused: `Verification definition carries a test binding: <name>: <key>`.
- **Function binding.** An `@ImplementedIn` outside the body of every declaration is a
  function binding of its model file. It is checked as a clause binding is, and its
  messages name the file key in place of an identity.
- **A clause takes its module from its function.** A requirement that is `partial` or
  `implemented` and states no binding takes the function binding of its own model file.
  None in the file: `Delivered declaration lacks implementation/test binding: <ID>`. Two or
  more: `Ambiguous function binding: <ID>: <key>`. A requirement that states its own
  binding is not affected by either.
- **Detail tests.** `@DetailTests { tests = "<paths>"; covers = "<text>"; }` anywhere in a
  model file: each path of `tests`, separated by semicolons, must be an existing file
  under the source roots, else the binding messages with the file key. No `Proves:` tag is
  asked, and the gate's bindings do not list it.
- **Retired case.** A verification case whose test shows nothing at a part boundary
  retires into the detail tests of its part: its test stays and loses the case tag, and
  the body that names the test file in `@DetailTests` lists the identity as retired:

  ```sysml
  action def StandardContact {
      @DetailTests { tests = "server/src/contact_tests.rs"; covers = "the engine on a virtual clock"; }
      @RetiredCase { identity = "TC-007-020"; test = "server/src/contact_tests.rs"; }
  }
  ```

  The form is typed by
  `metadata def RetiredCase { attribute identity : String; attribute test : String; }` in
  the `ModelBindings` package, beside `DetailTests`. It is this project's own form, not one
  of the harness template `model-bindings.sysml`. It is read outside comments, with or
  without package names (`@ModelBindings::RetiredCase`); one annotation retires one
  identity and names one file, and a body may hold several. Only verification cases
  retire. `traces`, `check`, `fingerprints`, `retired` and `status` refuse, in this order:
  - per model file, after its `@DetailTests` path check and its declaration checks, each
    `@RetiredCase` in the order of the file: an FR or clause identity,
    `Only a verification case retires: <ID>: <key>`; any other spelling (a missing,
    repeated or other feature, a value that is not one string literal, an identity not of
    the form `TC-ddd-ddd`, a `test` holding `;` or `::`, or the `metadata` keyword form
    `metadata r : RetiredCase { ... }`), `Invalid retired case: <key>:<line>`, the line of
    the `@` or of the word `metadata`; a `test` that no `@DetailTests` directly in the same
    body names as written, `Retired case outside the detail tests: <TC>: <path>: <key>`.
    The retirement has no file check of its own: its file is a `@DetailTests` path of the
    same body, which the binding messages with the key have already judged;
  - after all model files, before the baseline: an identity retired more than once,
    `Duplicate retired case: <TC>: <keys>`, each key once, sorted and joined by `, `; a
    retired identity that is also declared,
    `Retired case declared again: <TC>: <key>`, with the key of the declaration; then each
    case a superseded retirement names that is not a declared case or is retired,
    `Superseding case missing or retired: <TC>: <named TC>: <key>`.

  **Superseded.** A verification case whose checks went to other contract cases, not to
  detail tests, retires as superseded:

  ```sysml
  @RetiredCase { identity = "TC-039-041"; supersededBy = "TC-097-002; TC-097-003"; }
  ```

  The tool reads it against
  `metadata def RetiredCase { attribute identity : String; attribute test : String[0..1]; attribute supersededBy : String[0..1]; }`;
  the model's definition is extended to it in the change that writes the first such
  marker. An annotation has `identity` and exactly one of `test` and `supersededBy`;
  `supersededBy` is one string literal of one or more `TC-ddd-ddd` identities separated by
  `;`. Any other spelling (both features, neither, a value that is not one literal, a
  malformed or repeated identity, the case itself) gives
  `Invalid retired case: <key>:<line>`. A superseded retirement stands in any model file,
  at package level or directly in a definition body, and needs no `@DetailTests`. Each
  named case must be a declared case of the catalog and not retired, checked as above.
  The rest is as for a retired case.

  A retired identity counts as present for the stable baseline. It is not a catalog
  entry: the identity count of `traces` and `check` leaves it out, and a `Proves:` tag, a
  JavaScript test name or a clause dependency naming it is refused by the rules for an
  undeclared identity. A clause whose only case retires loses that dependency and is
  refused (`Canonical clause lacks a declared verification case: <CL>`) until another
  case verifies it. `python tools/sysml.py retired` checks the authority and the catalog
  as `fingerprints` does, then prints one line per retirement sorted by identity,
  `<TC>: <test path>: <key>:<line>` or `<TC>: superseded by <TC>, <TC>: <key>:<line>`,
  and the summary `<n> retired cases`; it writes nothing, and a broken catalog or a
  missing authority gives the existing refusal and exit 2. The gate's bindings list no
  retired identity and no retirement test file.
- **No unread declaration.** A `requirement` or `verification` declaration whose name or
  short name is a stable identity, in a form the catalog does not read (`:>`,
  `<'ID'> name`, a typed `requirement`), is refused:
  `Unreadable canonical declaration: <ID>: <key>`.

The gate's model bindings (`.harness/model_bindings.py --rev REV`) report the effective
values, so a model in the metadata form gives the JSON of the same model in the attribute
form.

Recognized numeric product identities in source `Proves:` comments must exist in the
canonical catalog; same-prefix shorthand is expanded. HOW and fixture-specific names
are not product declarations. A tag's presence still does not establish test execution.
A manual physical case uses `attribute method : String = "manual";` and names its
existing probe/source, without claiming an automated or executed result. A planned case
may lack an executable. Source tags and existing files prove presence, not conformance.

A test *names* a case when an attached `Proves:` tag above it holds the case identity after
shorthand expansion, or when it is a JavaScript test whose name holds the case identity. A
test is *in the binding* of a case when its file is bound as a file, or when
`path::<its name>` is bound; the binding is the effective `attribute executable` or
`@TestedBy` value.

- **Tag and binding agree.** For every case, each test that names it, in a `.rs`, `.js` or
  `.cjs` file below `client/`, `server/` or `tests/`, is in the case's binding. Otherwise
  `traces` and `check` refuse with one message naming every such pair, sorted by case, path
  and test name: `Proves tag outside the verification binding: <TC>: <path>::<test name>;
  <TC>: <path>::<test name>`. It holds for every case: automated, manual or planned, with or
  without a binding, and in either form of the binding. A tag that is not attached to a test
  names no test and is not judged. A test that is ignored or left out by a build
  configuration still names its case: a tag states presence, not execution. Files outside
  the three source roots are not judged. The refusal comes after the existing catalog and
  binding refusals, whose messages are unchanged.
- **A manual case's symbol exists.** A `path::symbol` binding of a case with method
  `manual` must name a test of that file. Otherwise:
  `Missing executable test symbol: <TC>: <binding>`.
- **The gate's bindings report, they do not judge.** `.harness/model_bindings.py --rev REV`
  gives its JSON for a revision whose tags stand outside a binding. Such a test is not
  listed for the case.

Canonical documents link to active model elements or existing repository paths with
correct model-file-relative Markdown links. Retired FSD section dependencies, source-hash
markers and broken file references fail. The minimum stable identity baseline includes
all 23 FRs, 38 clauses and 38 verification identities present in the reviewed application
baseline; a verification identity counts as present when it is declared or retired under
**Retired case**. Additions retain unique identities, and a retired identity is never
declared again. A verification case retires only in that form, in a change of its own;
any other retirement or an authority change requires explicit review rather than deleting
a definition to obtain a green check.

### Model values read by tests

This section is CL-014-16; TC-DOC-014 verifies it.

- **Rule.** Where the model holds an observable value as data (a typed value, an
  enumeration of external names, a table of instances), the contract test that compares the
  product with it reads the value from the model and does not write it again. A value that
  exists only in the prose of a case stays in the test. A test reads the `.sysml` files
  themselves, at run time, through the one reader of its language:
  `server/src/model_values.rs` for tests under `server/`, `tests/model-values.cjs` for tests
  under `tests/`. No file is generated from the model for a test, and no test parses the
  model with its own patterns. The one exception is the test "TC-097-019 the model carries
  no superseded wording" in `tests/ui-operating.test.cjs`: it reads no model value and
  compares nothing with the product, but scans the model text for superseded wording, so it
  reads the model files itself. The model it reads is every model file as defined in
  "Canonical model catalog and source bindings". Transition tables and other behaviour
  (states, transitions, actions) are not read yet; the change that first needs one extends
  this rule and both readers.
- **Naming.** A value is named by its qualified name `Package::Element(::Feature)*`.
  `Package` is the package of a model file. Each further segment names an element or
  feature declared directly in the body of the segment before it; a quoted name keeps its
  quotes (`WstxDecodes::FreeTextFields::'type'`). The file's name and folder are never
  part of the name, so moving, renaming or splitting a model file changes no name while one
  file keeps the package. Renaming an element, or moving it to another package, changes the
  name; the tests that cite it change in the same change, as code comments that cite
  elements do.
- **What is read.**
  - The value of an attribute: `attribute <name> [: <Type>] = <literal>;`, or a
    redefinition `attribute :>> <name> = <literal>;`, in a package, a definition body or a
    usage body.
  - The members of an `enum def`, in declaration order, written `a;` or `enum a;`. A `doc`
    on the definition is skipped. A member may also carry a body that holds only a `doc`
    comment; that is valid SysML, although `WstxUnits::UnitSuffix` does not use it.
  - The attribute usages declared directly in a named package or body and typed by a named
    attribute definition (short or qualified name), in declaration order. Each comes with
    its name and the literal values of its own body.
  - Literals: integer and real, with a sign; string, with its escapes, where `;`, braces
    and `//` inside it belong to the string; `true`, `false`; `null`; an enumeration value
    `Def::member`.
  - Only what the element's own body states is read. Specialization, inherited defaults,
    imports and aliases are not followed: a value stated on a definition is named on the
    definition.
  - Text in `//` and `/* */` comments and in `doc` bodies is not read. A file read with
    CRLF and the same file read with LF give the same values.
- **Units.** The unit suffixes are the members of `WstxUnits::UnitSuffix`. The readers read
  them from the model they read, through "What is read". A value with a unit carries one of
  them as the last part of its name. A name *ends in a suffix* when its last characters are
  the suffix and the character before them is a lowercase letter or a digit (`ft8Hz`,
  `pollMs`, `workerMemoryMaxMiB`). The value is written in the unit its promise is stated
  in, as an integer where one exists. No literal is a unit expression; existing quantity
  types stay, and they type fields without values.

  A test reads a number either *with its unit* or *as a plain number*:
  - Read with its unit, the name must end in a suffix. Otherwise the read fails
    (`unit suffix not on the list`), so a misspelt or unlisted suffix such as
    `ft8WindowMaxSecs` is refused.
  - Read as a plain number, the name must not end in a suffix. Otherwise the read fails
    (`value has a unit; read it with its unit`). A count without a unit (`pageRecords`,
    `candidateCap`, `caseId`) is read this way.
  - `null` is read in either way.
  - Strings, Booleans and enumeration values carry no unit and are not judged by the
    suffixes.

  A suffix is added as a member of `UnitSuffix`, with its sentence in the definition's
  `doc`, in the change that first needs it.
- **Failure: fail, never skip.** The reader returns an error naming the qualified name and
  the reason (Rust), or throws it (JavaScript), and a test that reads a value fails on it.
  The reasons are:
  - the model folder is missing, holds no model file, or holds a file that is unreadable
    or not UTF-8;
  - no file, or more than one file, has the package;
  - the name is not declared, or is declared twice in one body;
  - the value is missing (an attribute declared without `=`), or is not one literal of
    "What is read": an expression, a `+` join, a list, or a unit expression;
  - a unit rule of "Units" is broken, or `WstxUnits::UnitSuffix` is missing or has no
    member;
  - a table has no usage.

  No test that reads a model value skips, returns early, passes with nothing read, or
  reports NOT RUN because a value is missing.
- **What the test still states.** A provenance pin, an expected count, and the order and
  shape checks of a table stay in the test, as independent checks of what it read.
- **Scratch copy.** A test that reads a value is shown to read it by the scratch-copy
  check: in a scratch copy of the model the value is changed or removed, the test goes red,
  and it is green on the real model. Both readers find the model folder from their own
  file (`docs/sysml` beside `server/` and `tests/`), so the scratch copy is a throwaway
  checkout of the candidate (`git worktree add`) whose model files are edited; the tests
  run there unchanged, the Node tests on that checkout's own build (`WSTX_TEST_EXE`). A
  damaged copy inside a test replaces the text of the file of one package
  (`Model::with_package_text`, `withPackageText`), found by package, not by path.
