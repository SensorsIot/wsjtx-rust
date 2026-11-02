# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/main/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/main/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

## Machines and roles

Two Windows PCs work on this repository with the same GitHub account. Where a document
says "this PC" without naming one, read it as the machine named below for that task.

| Machine | Role |
|---|---|
| **HB9BLA** (`192.168.0.37`, checkout `D:\Github\wsjtx-rust`) | The station. The product runs here and the transceiver (IC-7300, COM3) is connected here. All operational programming, builds, release packaging, installs and deploy dry runs; all live and hardware tests (cost 3–5) and radio acceptance; by default also harness work. Runtime details: [HB9BLA handover](HB9BLA-HANDOFF.md). |
| **Andreas** (hostname `Andreas`) | SysML model work, in isolated worktrees, and documentation work. It has no radio, so it runs no live or hardware tests and installs nothing on the station. |

- The `windows-rust.yml` artifact (`wstx-rust-windows-x64`) is build evidence only. It
  shows that the build and tests pass on a clean Windows runner and is never installed
  on the station (operator decision, [#26](https://github.com/SensorsIot/wsjtx-rust/issues/26)).
- The machine that currently builds an issue is named by the issue's single
  `owner: HB9BLA` or `owner: Andreas` label. A machine does not start an issue owned
  by the other one; a handoff swaps the label first
  ([harness #23](https://github.com/SensorsIot/harness/issues/23)).

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
| `wstx-rust` | Rust unit and integration tests | Native sources, Cargo inputs and Rust toolchain |
| `protocol` | Status messages, sessions, reconnect and TLS login | Router (`main.rs`), status page client (`app.js`, `index.html`, `style.css`), protocol tests/helpers, runtime dependencies |
| `protocol-thin` | Measurement: TC-021-008 32 kbit/s link and 60-second idle budget, stalled-reader liveness, link simulator | Router/websocket, HTTP compression, status page client, protocol tests and link simulator helpers |
| `profiles` | Saved settings, independent stations, authorization and pending-status behavior | Router, profile and authorization owners, page and recording client (shared controls container), profile tests |
| `recording-storage` | Import, validation, storage, jobs, cancellation and source provenance | Router, recording owners, recording client, recording test file, fixture tool and recording manifests |
| `recording-display` | Spectrum, waterfall, calibrated bins, palette, sliders, readouts and geometry | Router, recording and spectrum owners, recording client, recording test file and manifests |
| `recording-thin` | Measurement: display pacing, bounded subscribers, the full 32 kbit/s display/status regression and the TC-010-005 Detailed peer cadence | Router, recording/spectrum owners, HTTP compression, recording client and test file |
| `operating-layout` | Operating screen, settings drawer, receive races, logbook, strategy, UDP editor, transmit status | Router and the HTTP owners the operating page calls; page, recording, contact and logbook clients; its test file |
| `contact-browser` | Contact engine, QSO sequencing, logging and halt through the browser | Router, contact/logbook/transmit owners, contact/logbook/recording clients, contact test |
| `radio-selection` | H1 compression negotiation, commissioning, browser selection cases | Router, compression, selection/radio/CAT/receive/source owners, recording client, selection test |
| `radio-selection-thin` | Measurement: the 75 s native/CAT/TLS two-browser Thin and Off workload | As `radio-selection` plus spectrum, audio, decoder and library code, which set the real-time load |
| `mcp` | MCP client grant and refusals | Router, MCP/automation/authorization owners, authorization client, MCP test and credential helper |
| `recording-fixtures` | Offline fixture planning, integrity and refusal paths | Fixture tool, plans and tests, plus Node package metadata |
| `sysml-documentation` | Canonical catalog/trace checks, full semantic and architecture validation, model/tool tests | Model and tooling changes; bound source remains a complete fingerprint/dirty-guard input |
| `source-model-traces` | Fast canonical source/model identity and binding checks; no Java or model mutation suite | Client, server and test source, plus model/tool changes |

All existing test files remain registered. The recording test file is partitioned by
names: `^TC-018-` goes to storage, `^TC-010-002` and the TC-010-005 Detailed peer
cadence to thin-link checks, and the complement to display. The communication test
file sends `^TC-021-008` and the link simulator check to `protocol-thin`, the complement
to `protocol`. The radio selection Rust fixture `live_native_selection_tls_thin_and_off`
runs in `radio-selection-thin`, the other selection tests in `radio-selection`. Each
complement includes future names instead of silently omitting them. No test assertion,
budget or test case is removed by selection.

Measurements run only when the change touches time-critical code (harness#28).
Timing promises live in measurement groups (`protocol-thin`, `recording-thin`,
`radio-selection-thin`, `decoder-quality`) selected only by the code that can change
that timing: the router/websocket and its pacing, HTTP compression, the link simulator,
the recording/spectrum producers, the receive/audio/decoder pipeline and the clients
that pace the display. Functional groups do not measure.

The model has an explicit documentation owner. Its edits select full model validation;
runtime oracles are selected by changed implementation and executable tests. Source
edits also select the fast binding check, without a dependency that runs the full Pilot
mutation suite on every code edit. Both model suites fingerprint the model, tool and
complete client/server/test source inputs they read. A source edit or deletion invalidates
old trace evidence and full-model evidence, even when only the fast suite is selected.
Independent contract comparison still checks that tests prove the changed promises.

A file selects the groups whose test cases prove its promises, not every group whose
fixture merely loads it. The router `main.rs` (routes, authentication, websocket and
profile HTTP) selects every browser group. The operating page client files select
`operating-layout`, the operating-page regression, besides their owning groups. A
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

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## Deployment authority

This is the project's binding of the harness
[deployment authority](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/security.md#deployment-authority)
rules (#26).

**Mechanism.** There is one deploy mechanism: the Windows release executable built on
HB9BLA and installed there at user level by the reviewed station-update scripts in
`.git/harness-parallel/resources/station-update/` (operator decision 2026-10-31, see #30).
`make_package.py <commit> <push-gate log>` builds a package of a commit on GitHub master
whose push gate passed; `station-update.ps1 -Manifest <package>\manifest.json [-DryRun]`
verifies it, stops the station gracefully, switches `active.json`, starts the task and
switches back on failure; `station-update.ps1 -Rollback` returns to the previous version.
The operator's one-time `setup-once.ps1` points the scheduled task at
`station\launcher.ps1`, which runs the version named in `active.json`. The manual
`windows-rust.yml` workflow and its `wstx-rust-windows-x64` artifact are build evidence
only (operator decision 2026-10-30): that artifact is never installed on the station.

**After every install** run the independent probe; on `PROBE FAIL` (exit 1) run
`station-update.ps1 -Rollback`; `PROBE ERROR` (exit 2) is a wrong argument, not a verdict:

```powershell
.harness\deploy\station-probe.ps1 -Manifest <package>\manifest.json
```

It is read-only. It asks Windows which process listens on TCP 18081, hashes that
process's executable itself and requires the candidate's commit directory and the digest
of the package's own `wstx-rust.exe` (recomputed, not read from the manifest), then HTTP
200 from `https://192.168.0.37:18081/` over TLS that Windows trusts, and last that the
launcher receipt agrees with what it observed. The service reports only its crate version
(`0.1.0`), not its commit, so the running image's digest is the version identity; a
service-reported commit would be a product change (CR). Tests:
`python -m unittest discover -s .harness/deploy/tests`.

**When `station-update.ps1` changes** run the refusal drill and record its output on the
change's issue:

```powershell
python .harness\deploy\station_drill.py
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

**Rules not met yet.** Until each issue is done, the operator's standing permission to
run `station-update.ps1` (decision 2026-10-31, recorded on #30) authorizes this mechanism
in place of an OK per install.

| Rule | State today | Issue |
|---|---|---|
| Credentials outside the agents | Off (today): agents run as the HB9BLA user and can write the version directory, `active.json`, the receipt, the gates record and the package and station-update scripts. Only the task and firewall changes need the operator's elevation. Prepared: the deploy authority below keeps policy, verifier and launcher where only Administrators write and the signing key with the operator. Still not met when on: the launcher and verifier run as HB9BLA, so the agents can alter them while they run (see its limits). | #30 |
| Approval names the candidate | Off (today): the manifest names commit and executable SHA-256, but the agents write it and no approval is bound to it. Prepared: an operator-signed approval of one commit, one digest and one destination. | #31 |
| Verify before writing | Off (today): `station-update.ps1` refuses a changed artifact, package path, gates record, push-gate log, unpublished commit, task or firewall scope before writing, but against an agent-written manifest beside the artifact. Prepared: the protected verifier hashes the executable itself against the signed digest before the switch, and the protected launcher again before it starts it. | #32 |
| Prove the result | `station-update.ps1` checks the launcher receipt and HTTP 200. `station-probe.ps1` then checks independently of the receipt that the process listening on 18081 runs the candidate's bytes and answers over trusted TLS. Not met in full: an agent runs the probe and the rollback after it (the operator can run the same probe), and the service does not report its own commit. | #33 |
| Show the refusals | `station_drill.py` shows each refusal of `station-update.ps1` before the destination changes (below). Not met in full: the drill shows that a consistent rewrite of artifact and records and an older commit on master are accepted (#32, #31), and a mismatched approval exists only with the deploy authority on. | #34 |

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
   `python .harness/deploy/station_drill.py`: it must show the two approval cases.
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

The reusable [SysML authoring instruction](https://github.com/SensorsIot/harness/blob/main/core/docs/standards/sysml-v2.md)
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
