# Project-specific harness bindings

**Layer:** HOW. **Scope:** this project's development environment and procedures.

The [general harness](https://github.com/SensorsIot/harness/tree/main/core) defines the
development process. The [Rust harness](https://github.com/SensorsIot/harness/tree/main/lang/rust)
defines reusable Rust rules and checks. This document binds those reusable instructions
to this repository's toolchain, paths, test prerequisites and selected execution mode.
Run the commands below from the repository root.

## Machine

The factory runs on one Windows PC, **HB9BLA** (`192.168.0.37`), with the checkout
`D:\Github\wsjtx-rust`. The transceiver (IC-7300, COM3), the station, the test inputs that
are not in the repository, the timing baseline, the gate and the merge queue are there.
`machines:` in `harness/project/config.yaml` names it, so a gate and the queue worker start
only there. Heavy builds and gates share it with the live station: do not operate the radio
during a heavy gate.

On HB9BLA:

- **Station:** `https://192.168.0.37:18081`, scheduled task `WSTX Rust Station HB9BLA`,
  receipt `%LOCALAPPDATA%\WstxRust\station\station-running.json`. The deployed source is the
  one the issue checkpoint and this receipt name.
- **Station log:** `%LOCALAPPDATA%\WstxRust\station\profiles\ic7300\contacts.adi`, imported
  from the operator's Log4OM export; a rerun of Update logbook with the same export adds
  nothing.
- **IC-7300:** COM3 and the USB Audio CODEC. The operator runs it on 20 m FT8
  (14.074 MHz USB-D) with AGC SLOW for FT8 and FT4 (it removes the AGC line between periods).
  Agents key it as [Keying the radio](#keying-the-radio) says. The camera microphone belongs
  to Dictate, not the radio.
- **Comparison:** the official WSJT-X 3.3.0-beta4 runs alongside as `WSTX-Comparison`,
  Rig=None, no CAT/PTT, Fast/AP-off. A connected Edge frontend runs here too.
- **Credentials:** `%LOCALAPPDATA%\WstxMigration\credential-tools\PRIVATE-CREDENTIAL-HANDOFF.md`;
  readiness is checked without reading a value. Scoped Infisical authentication and secret
  reading work with normal TLS validation; native CLI use needs standard Windows CA trust.
  TLS is never bypassed.
- **Model toolchain:** the JDK and the Pilot are in `%USERPROFILE%\.cache\wsjtx-rust\sysml-tools`.
- **Fortran** is never installed on HB9BLA.

The `windows-rust.yml` artifact (`wstx-rust-windows-x64`) is build evidence only. It shows
that the build and tests pass on a clean Windows runner and is never installed on the
station.

## Windows build and packaging

The Rust executable serves the embedded browser, versioned station interfaces and implemented receive services. Native Windows audio, typed CAT adapters and the pure FT4/FT8 decoder are separate modules. Their presence does not establish complete mode parity or live acceptance; current implementation and verification declarations belong to the functional model and issue evidence.

### Crates that need `unsafe`

The [Rust standard](../../general/lang/rust/standard.md#security) forbids `unsafe` in a crate
the project harness does not list. The listed crate is `wstx-rust` (`server/`): its library
calls the Windows API in the modules below, and only these allow `unsafe`, each by
`#[allow(unsafe_code)]` on its module declaration under the library root's
`#![deny(unsafe_code)]` (`server/src/lib.rs`):

- `server/src/audio/windows.rs`: WASAPI capture, declared in `server/src/audio.rs`;
- `server/src/modes/playback/windows.rs`: WASAPI render, declared in `server/src/transmit/playback.rs`;
- `server/src/radioControl/windows.rs`: the CAT port's serial I/O, declared in `server/src/radio_control/mod.rs`;
- `server/src/transmit/windows_time.rs`: the read-only Windows Time service query, declared in
  `server/src/modes/transmit/mod.rs`.

The binary root `server/src/main.rs` keeps `#![forbid(unsafe_code)]`. Each `unsafe` block of
these modules carries a `// SAFETY:` comment and is covered by a test, as the Rust standard
requires; Miri is not wired, since the blocks call the Windows API.

### Workspace

The root Cargo workspace contains the station-server package in `server/` and the test-tools
crate `wstx-test-tools` in `tools/test/rust/`, a dev-dependency of the station server only;
the versions both crates use stand once in `[workspace.dependencies]`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` files are embedded at Rust compile time, without a frontend build step.

### Test tools

The test-tool folders of the [harness testing standard](../../general/core/docs/standards/testing.md#test-tools):
`tools/test/rust/` (the crate `wstx-test-tools`, its tests in its modules and its `tests/`),
`tools/test/node/` (CommonJS tool modules, each with its `<tool>.test.cjs` beside it),
`tools/test/python/` (the Python test tools, each with its `test_<tool>.py`, and
`WSJTX-REFERENCE.md`) and `tools/test/powershell/` (the test bench's PowerShell scripts with
their Python tests, suite `test-bench`); files several tools use stand in `tools/test/` (`blocked-ports.json`,
`fixtures/model-values/`). A test tool depends on no product package: `wstx-test-tools` has no
`wstx-rust` dependency, and a Node tool module requires no file below `client/` or `server/`.
Product code names a tool only in a test file (`use wstx_test_tools::…`, `require` in a
`*.test.cjs`); the decoder's test-only resource observer hooks, which name the observer by full
path, are the one exception until a port replaces them. Fixture generators and their test data
stand under `fixtures/<area>/` and write the reference vectors where the Rust tests read them.
The suite `test-tools` runs the Node tools' tests; the Rust tools' tests run in `wstx-rust`.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml)
is a manual alternative, started explicitly from the Actions page. Pushes and pull
requests do not trigger it. Normal development, the full test suite and release packaging
run on HB9BLA; a local pass is not automatically repeated on GitHub.

The workflow uses a GitHub-hosted Windows Server 2022 x64 runner with the MSVC build tools. It installs the pinned Rust toolchain (`rust-toolchain.toml`) and checks formatting, Clippy warnings, tests, release compilation, and execution of the built program. The executable is uploaded as the `wstx-rust-windows-x64` artifact with a 14-day retention period.

No radio, sound device, third-party decoder or repository secrets are required. Rust dependencies implement HTTP/WebSockets, asynchronous networking, JSON and TLS. Node 24 test dependencies provide a real Chromium browser, independent WebSocket peer and disposable TLS certificates. The workflow runs browser tests against the compiled release executable. The selected suites state which communication, receive and modem promises they exercise; an unexecuted hardware case is not a passed check.

The workflow has read-only repository permissions and pins its checkout and artifact actions to specific commits. It does not publish GitHub releases or packages.

## Local Windows development

Install Rust through [rustup](https://rustup.rs/) and the Visual Studio C++ Build Tools with the Desktop development with C++ workload and a Windows SDK. The toolchain file selects the compiler version automatically.

Once per clone, the operator runs `git submodule update --init`, then
`python3 harness/general/core/tools/install_hooks.py`, and the same inside the submodule
(`cd harness/general && python3 core/tools/install_hooks.py`) for its commit hook. The roles' hooks
refuse `install_hooks.py`: it is the operator's.

The local pre-push gate is the authoritative check:

```powershell
python harness/general/core/tools/gate.py
```

It selects affected compiler checks and functional test groups from the declared
change owners and downstream dependencies in `harness/project/suites.yaml`. The ordinary
push hook uses the same gate and its valid memoized results. Do not repeat the checks
below when the gate has already supplied their evidence for the same candidate.
Release packaging also runs on this PC; start the packaged candidate for the dry run.

### Functional test selection

`paths` lists a group's complete inputs for evidence fingerprints and dirty-input
checks. `select` lists the files whose edits directly select it; only `select` decides
selection. No group declares `depends_on`, which the harness follows transitively: a group
names in its own `select` the files whose behaviour its test cases prove, not every file its
fixture merely loads, and Cargo and Node dependency inputs select every group that compiles
or runs them. A group's coverage is its `needs` and its change owners are its `select` in
`harness/project/suites.yaml`; `gate.py --plan` (below) prints the groups a change selects
and why. The selector does not infer changed functions from a file or guess dependencies
from an agent's description. Unmapped inputs select every group that declares them;
entirely unknown paths and selection-policy changes cause a full fallback.

Every test file is registered in a group. A test file that several groups share is
partitioned by the test-name patterns of their `run` commands; each complement includes
future names instead of silently omitting them. No test assertion, budget or test case is
removed by selection.

Runtime oracles are selected by changed implementation and executable tests. Source edits
also select the fast binding check `source-model-traces`, without a dependency that runs the
full Pilot suites on every code edit. A source edit or deletion invalidates the trace,
full-model and validator-test evidence whose `paths` hold it, even when only the fast suite
is selected. Independent contract comparison still checks that tests prove the changed
promises.

### Model values read by tests

A group that holds a test reading a model value names, in
`paths` and `select`, every model file those readers read: each file holding a value they
read, and `docs/sysml/shared/Units.sysml` when they read a value by its unit. `docs/sysml/`
covers them all. The change that adds the first such test to another functional group adds
these files there, as additive wiring of its new coverage. A timing test that reads
its bound from the model has the same files in its suite's `timing_inputs` and `paths`.

### Timing suites

Measurements run only when the change touches time-critical code. Every
timing, latency, cadence or throughput promise lives in a **timing suite** (`timing: true`
in `harness/project/suites.yaml`). A timing suite has no `select`; its `timing_inputs` name
the code that sets the measured time, its own test files and helpers, and the toolchain and
dependency pins, and nothing else selects it: no functional owner, unmapped-input or
unowned-path fallback, `harness/project/` edit or dependency
([harness testing standard](../../general/core/docs/standards/testing.md#timing-suites)).
A change to files that no timing suite names runs functional groups only. The gate lists a
timing suite the change reads but does not time as `TIMING ... not run`.

A CR that changes the measured behaviour through another path (a client timer or poll
cadence outside those files, a heavier asset, a new background task) asks for the
measurements with the commit trailer `Harness-Timing: yes`; the review checks that such
a CR carries it. `HARNESS_TIMING_REQUEST=1 git push` or `gate.py --timing` does the same for one
run; `gate.py --full` runs every timing suite. Functional groups assert behaviour; a
residual liveness deadline in a functional case (for example the 2 s status refresh and
10 s recovery bounds of the profile tests) is a known follow-up, not a measurement
promise: a mixed group would declare `timing_inputs` and guard those assertions with
`HARNESS_TIMING` (`0` skips them).

The resource matrix of `decoder-quality` re-measures a configuration whose 50 ms CPU quantum
stayed unmeasured, at most three attempts, and the runtime (including the four-worker 2x
bound), cold-start and 64 MiB budgets of `WstxModemDecode::DecodeBudgets` bind every attempt:
any exceedance in any attempt is a failure.

### Live page check

The **live page check** (`tools/deploy/live-page-check.ps1`) is in no
suite: it needs the installed station and one real restart. It runs on HB9BLA after every
deploy under the [standing deploy policy](#standing-deploy-policy) and at live
acceptance (CR step 6) of a change to `client/`, the receive, recording or logbook owners or
`tools/test/node/page-watch.cjs`. It keys nothing and restarts the station only while nothing is armed,
keyed, in a contact or an automation run. Before the restart it makes one band selection of the
band the station receives on, keeping its mode, so that the old boot's receive job stands at
generation 2 or more: only while receive runs FT8 or FT4 on a selected band,
Monitor off at startup is not set and the saved receive choice is that mode and band, so that the
selection tunes the radio as the resume after the restart does and saves the same choice.
Otherwise, or when the selection is refused or does not take, the result is NOT-EXERCISED naming
why. The station keeps one session per grant, so on the old boot the page and the script share
one session: the page holds the one the script reads and selects with, and gets the new one after
any new login of the script. `live-station-browser` gates the same oracle in-process.

### Parallel groups and shared resources

The gate runs up to three groups at a time (`gate.parallel: 3` in
`harness/project/config.yaml`), longest first, and prints each group's output whole in name
order. `protocol-thin`, `recording-thin` and `radio-selection-thin` run beside other groups
(`gate.timing_alone: false`). The bounds of the first two are wall-clock bounds on the
simulated 32 kbit/s link (byte budgets are judged from the link byte log, not tested); besides those, `recording-thin` holds two local 250 ms TC-018
cancellation bounds (one while four stations replay a recording) and
`radio-selection-thin` the 4230-5000 ms native setup and 2 s Off-acknowledgement bounds.
All were measured stable beside other groups on HB9BLA, with the suite times of their alone
runs. That evidence does not cover the CPU-heavy decoder groups as neighbours, so
`decoder-correctness` (12-thread busy-period decode) and `wstx-rust-decoder` hold
`exclusive: [link-measurement]`, which the three share (`radio-selection-thin`'s socket
qualification fails beside `decoder-quality`). The CPU
measurements run alone (`exclusive: ["*"]`): `decoder-quality` and
`live-station-latency` (a browser row-latency budget on the busy decoder). The groups
declare what they must not share:

- the browser groups run `target/debug/wstx-rust.exe`, which `cargo test` relinks with
  the dev-dependency features, and Windows refuses to replace a running executable. So
  `wstx-rust` builds and runs in its own Cargo output directory
  (`$CARGO_TARGET_DIR/unit`) and `wstx-rust-decoder` in its own profile directory
  (`unit-opt`); neither touches the browser groups' executable, and both run beside them;
- `radio-selection-evidence`: both radio-selection groups write
  `test-results/radio-selection/`;
- `decoder-quality` runs alone (`exclusive: ["*"]`): its owned-Job CPU matrix measures
  50 ms quanta that concurrent groups would disturb.

Each group names its Cargo build (`build`); the gate runs each distinct build once,
serially, before the groups start, so that the groups share one up-to-date build in the
checkout's own `CARGO_TARGET_DIR` instead of queuing on Cargo's lock. The groups' `run`
still repeats its build, which is then up to date. Ports are chosen free per test
(`tools/test/node/support.cjs`), and each browser test station gets its own `LOCALAPPDATA`
(`stationEnv`), so the profile and radio-ownership locks of concurrent groups do not
meet.

### Gate preview and manual runs

Preview the selected commands and reasons without running checks or recording a pass:

```powershell
python harness/general/core/tools/gate.py --plan --base <base-commit>
```

Run all eligible groups and compiler checks without memo reuse when a full validation
is required:

```powershell
python harness/general/core/tools/gate.py --full
```

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
with Ctrl+C. Remote TLS and access settings are `WstxListener::ListenRule`
([Listener.sysml](../../../docs/sysml/backend/web/Listener.sysml)).

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
Isolated tests may start disposable loopback servers, browsers, TLS endpoints and link
simulators: test networking is cost 2. Live station or external-service access is cost 3–5;
the test selection authorizes no hardware or external-service test. The link simulator
counts the actual encrypted-stream bytes plus modelled transport overhead; it is no on-wire
packet capture or physical-network certification. It disconnects a peer whose pending
delivery bytes plus destination write buffer exceed 128 KiB and emulates no other
congestion queue. The link budget is `WstxStationLink::ThinLinkBudget`
([StationLink.sysml](../../../docs/sysml/interfaces/internal/StationLink.sysml)), the
counted overhead `WstxListener::LinkTrafficLog`
([Listener.sysml](../../../docs/sysml/backend/web/Listener.sysml)).

### Inputs

The test inputs are in `.git\migration-data\`; configure each development shell:

```powershell
$data = Join-Path (git rev-parse --path-format=absolute --git-common-dir) 'migration-data'
$env:WSTX_SAMPLE_DIR = Join-Path $data 'recordings'
$env:WSTX_DECODER_CACHE = Join-Path $data 'quality'
$env:WSTX_DECODER_VECTORS = Join-Path $data 'frozen'
$env:WSTX_DECODER_SYNCHRONIZATION = Join-Path $data 'synchronization'
$env:WSTX_DECODER_OFFICIAL_FT8 = Join-Path $data 'official-ft8\210703_133430.wav'
$env:WSTX_SIMULATOR_SAMPLE_DIR = Join-Path $data 'CR18-simulated-samples-v2-03aef7cde-toold06cee63463b\ft4'
$env:WSTX_SIMULATOR_ORACLE_DIR = Join-Path (git rev-parse --show-toplevel) 'fixtures\decoder'
$env:CARGO_BUILD_JOBS = '2'
```

Without these, a push that selects any suite whose `needs` in `harness/project/suites.yaml`
names a WSTX_* input is refused red. The merge-queue worker reads the same inputs from
`queue.env` in `harness/project/config.yaml`.

Agent builds use their own `CARGO_TARGET_DIR=D:/wstx-build/<worktree>` (`gate.agent_build_root`)
and `TEMP`/`TMP` set to that same folder, never inside a worktree and never shared: Cargo
creates it before the linker needs it (link.exe fails with LNK1104 on a missing temp
folder). Gate builds go to `D:/harness-cargo-target/wsjtx-rust/<checkout>`
(`gate.cargo_target_root`) and are pruned by the gate itself; agent build folders are pruned
with `python harness/general/core/tools/build_prune.py agent-dirs --root DIR --apply`
([Rust standard, Build folders](../../general/lang/rust/standard.md#build-folders)).

## Merge queue

A reviewed CR reaches master through the harness
[merge queue](../../general/core/docs/Merge-Queue.md),
whose worker runs on HB9BLA ([machine](#machine)): the coordinator hands in the reviewed tip
(`python harness/general/core/tools/merge_queue.py submit <issue> <tip>`) and builds no merge
itself. The queue's records are local to HB9BLA.
The `queue:` section of `harness/project/config.yaml` names the tools the gate needs (Node 24
or later, npm, Cargo, rustc, `gh`, the MSVC linker), 20 GB free on every drive the gate uses, the
input environment of [Inputs](#inputs) and the `npm ci` setup of
the queue's worktree. The worker runs as a background job from the main checkout
`D:\Github\wsjtx-rust`, with the pinned harness:

```bash
python harness/general/core/tools/merge_queue.py worker
```

Priorities on HB9BLA ([heavy runs](Agent-Working-Rules.md#who-changes-what)): the
station task `WSTX Rust Station HB9BLA` runs at High, above the gate; the gate runs at
ABOVE_NORMAL with unbounded build parallelism; agent builds and tests outside the gate
run at BelowNormal with a bounded `CARGO_BUILD_JOBS` (2, as
[Inputs](#inputs) sets it).

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## Deployment authority

This is the project's binding of the harness
[deployment authority](../../general/core/docs/standards/security.md#deployment-authority)
rules.

**Mechanism.** There is one deploy mechanism: the Windows release executable built on
HB9BLA and installed there at user level by the reviewed, versioned deploy scripts under
`tools/deploy/`.
`tools/deploy/` is a product path: a change to it is a CR with review and the merge
queue's gate, and suite `deploy-tooling` tests it. The **mechanism paths** are every file
under `tools/deploy/station-update/` (`station-update.ps1`, `make_package.py`,
`launcher.ps1`) plus `tools/deploy/agent-client.ps1`, `tools/deploy/station-probe.ps1`
and `tools/deploy/live-page-check.ps1`. Every step of the
[standing deploy policy](#standing-deploy-policy) lives in those files. `.gitattributes`
marks them `-text`, so their bytes in git, in a checkout and in a package are the same.
The live page check's checker `tools/test/node/live-page-check.cjs` is a test tool, gated by
CRs, and is not pinned: the deploy runs it from the repository root it passes (`-Repo`, the main
checkout `D:\Github\wsjtx-rust`) with that checkout's `node_modules`, not from the package.

A deploy is one line in Git Bash on HB9BLA, given only the commit, which runs
`make_package.py` as extracted from the commit it installs, so no working folder is read:

```bash
set -o pipefail; git -C D:/Github/wsjtx-rust show <commit>:tools/deploy/station-update/make_package.py | python - <commit> [--dry-run]
```

The commit is the one the merge queue pushed; Alex runs the same line (`alex.install` in
`harness/project/config.yaml`).

It refuses (exit 1, before any step) any other argument list, a commit not on GitHub master,
and a commit for which not exactly one merge-queue log under `.git\harness-parallel\queue\logs\`
shows a green gate and the push of that commit to master (the commit the queue pushed when
it landed a batch). It builds the package in
`.git\harness-parallel\resources\station-update\packages\<ver>\`, never in a working tree,
or reuses one there whose manifest names the commit (a folder holding anything else is
refused); it copies the mechanism files from the commit's `git archive` export into the
package's `deploy\` folder and lists their SHA-256 in the manifest. It then runs the
package's own copy,
`<package>\deploy\tools\deploy\station-update\station-update.ps1 -Manifest <package>\manifest.json [-DryRun]`,
which refuses to run from anywhere else, and exits with its exit. It verifies the package, checks the pins, waits for
an idle station, stops it gracefully, switches `active.json`, starts the task, switches
back on failure, runs the probe and the live page check from the package, returns to the
previous version when either fails and posts the install record (a stop it has to force:
[Standing deploy policy](#standing-deploy-policy) item 5). Exit 0: installed (or the
dry run passed); 1: refused, failed or returned, or a forced stop whose PTT release was not
confirmed; 3: the station stayed busy, nothing
changed; 6: the radio did not answer, nothing changed. A parameter the script does not
declare stops the call at binding, before any step.
`station-update.ps1 -Rollback` returns to the previous version and never asks. The
operator's one-time `setup-once.ps1` (in `.git\harness-parallel\resources\station-update\`,
not used by deploys) points the scheduled task at `station\launcher.ps1`, which runs the
version named in `active.json`; the task names no repository path and no deploy changes it.
The manual `windows-rust.yml` workflow and its `wstx-rust-windows-x64` artifact are build
evidence only: that artifact is never installed on the station.

### Standing deploy policy

The operator's policy, verbatim: "The operator is kept out of the loop, with one exception:
when a decision is needed." It binds the deploy part of the harness rule
[standing deploy and consent policies](../../general/core/docs/CR-Process.md#standing-deploy-and-consent-policies). A deploy
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
     repeats the whole check, and exit 6 is reported to the operator. `-DryRun`, `-Rollback` and the switch-back after a failed
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
   commit's own `harness/project/docs/Project-Specifics.md` (read with `git show`), and
   compares the launcher in the station folder with its pin (item 4). A commit without that
   file, or whose file has no Deploy pins section, has no pins. This holds for the commit to
   install and for the running commit. The install record's `cr_state.py installed` runs
   `harness\general\core\tools\cr_state.py` of the repository.
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
   **A forced stop.** Every stop (the switch, a switch-back, a return, `-Rollback`) sends
   Ctrl+C, then Ctrl+Break after 8 s, and logs whether each signal was delivered; a signal
   that was not names the helper's failed call and its Windows error
   (`AttachConsole error <n>` or `GenerateConsoleCtrlEvent error <n>`, or `error unknown`). A
   station still running 8 s later is force-stopped, after one line with the transmit state
   one GET /transmit reads just before it (`-Rollback` reads none). The next start that
   becomes ready reads GET /transmit every 2 s for at most 30 s until `startup_release` is no
   longer `pending`: PTT is confirmed when it is `not_needed` or `released`, `ptt` is
   `released` and `transmitting` false; anything else, and every forced stop under
   `-Rollback`, is not confirmed and logged with `check the radio`. A forced stop without that
   confirmation ends the update with exit 1 and starts no further stop: no switch-back and no
   return; a failed probe or page check then gives the record `not returned`, not a return,
   and the record goes to the issues a return's record would go to. The install record has
   one `Station stop:` line per stop (`graceful`, or `forced` with the Ctrl+C delivery and
   the PTT result after it).
6. **Install record.** Every install posts its record on each CR issue it moves to
   installed (`cr_state.py installed <commit> --since <previous>` finds them); after a
   return, on each issue the subjects of `<previous>..<commit>` name that is open and carries
   `cr:landed` or `cr:installed` (the deploy reads each with `gh issue view`; for any other
   issue it logs `record not posted on #<n>: <closed | at <label> | no cr state | state
   cannot be read>` and posts nothing). The record holds the
   commit, the previous version, the SHA-256 of the package executable, the SHA-256 of each
   mechanism file, the probe result line, the page check result line, and any return to the
   previous version. It holds no quote, dollar sign or backtick.
7. **Accepted limit** (operator, verbatim): "I accept knowingly that this guards against
   accidents and shortcuts, not against a deliberate swap by a session running under my
   account."

   The rules of the table under [rules not met](#rules-not-met) stay not met.

### Deploy pins

The SHA-256 of each mechanism file's blob at this commit, then its path, in the order
`station-update.ps1` reads them. A change to a mechanism file changes its pin in the same
CR (policy item 4). Suite `deploy-tooling`
(`test_deploy_pins.py`) recomputes every pin from git.

```text
ef106effe4e5b85a9c02a21dd8808d04281b239feecc5f54a5fe932eb2827c09  tools/deploy/station-update/station-update.ps1
b611766f68a987b450c15d38233c3c9eab5eb2eef58d9cc93db56fdce62fef07  tools/deploy/station-update/make_package.py
8579d535aa68596bd466b0fc400e4d8a8ca25c50e42291b3a09648ab01455509  tools/deploy/station-update/launcher.ps1
9d0524dfc1dc536f5d54e3a1b956b737f5b2b8a5a1ccfebaa896b97241c89dd2  tools/deploy/agent-client.ps1
506cc03746fb8bce42cd20bbafbe83715cf21bf502acb7ab558a5513a9b1f770  tools/deploy/station-probe.ps1
639f288c5b18f992e50f6d435a05dc47c890826a6de48b5b39407467eee4ee9f  tools/deploy/live-page-check.ps1
```

### Standing consent at 1 %

The operator's consent, verbatim: "Transmitting is not a concern: tests transmit at 1 % RF
power, except QSO tests." It covers the real IC-7300 once the operator has decided #239;
until then live tests key the simulator ([Simulator live tests](#simulator-live-tests)).
Cost 4 and 5 live tests run without asking when all of these hold:

- `tools/test/powershell/radio-preflight.ps1` has taken the radio lease and set RF power to
  `0003` (1 %, 1.2 % of the control) with read-back before anything keys;
- the test transmits only on 10, 15, 20 or 40 m;
- afterwards it restores the power found and every setting it changed.

A QSO test keys under this consent with the two exceptions, power and bounds of
[QSO tests](#qso-tests).

### Keying the radio

How an agent keys the real IC-7300; when it may, the [standing consent](#standing-consent-at-1-)
says.

- **RF power** is whatever the radio reads: each test sets the level it needs, and nothing
  keys at an assumed one. The value of CI-V `14 0A` is the radio's RF POWER control from
  `0000` to `0255`, not watts, and Po also follows the Tx level and the profile's limit.
  Measured on 20 m at -19 dB, without a wattmeter: `0128` gave Po 34–43 %; `0003`, `0013`
  and `0026` gave Po 0 to 1 %. Short keying without a QSO uses `0003`; a QSO test keys its
  SWR check at `0128` and its QSO at `0255` ([QSO tests](#qso-tests), items 4 and 7). CI-V
  reads first and writes only on a difference.
- **Preflight.** Before keying, an agent runs
  `tools/test/powershell/radio-preflight.ps1 -Holder <run> -PowerBcd <value>` and keys only
  on exit 0, under its lease (`-Status`, `-Release`). `-Port COM<n> -Baud <n>`, both or
  neither, name the CAT port (the simulator profile's: `-Port COM4 -Baud 115200`); without
  them it is `radio-port.json`'s (COM3, the real IC-7300). The lease and each record of
  `preflight.jsonl` hold the port and baud; `-Restore`, a renewal and `-NoWrite` use the live
  lease's port, and a call naming another one while that lease is live exits 2 and opens no
  port. It stops an idle station gracefully,
  because the station holds the port, reads the power, writes it only if different, reads it
  back, starts the station again and records the old value. It refuses to key only when the
  power cannot be read, written or confirmed by the read-back: exit 2, nothing keys, and the
  agent reports it to the coordinator. Afterwards `radio-preflight.ps1 -Restore -Holder <run>`
  puts the old value back and ends the lease; when that fails the lease stays for another
  try. With no live lease (it expired, a renewal failed, or `-Release` gave up the old value,
  which it prints), run `-PowerBcd <old value from preflight.jsonl>`, then `-Release`.
  Because it restarts the station, it does not run while the operator is operating, unless
  agreed: it sees only PTT and a contact, not someone watching Band Activity.
- **Contacts.** A contact you did not start, seen while another run's lease is live, is that
  run's; the station itself does not check this. A stop a test triggers never aborts a
  contact at or after RR73 or 73: that contact ends on its own.
- **Set back.** A cost-4/5 live test sets back what it changed
  ([testing](../../general/core/docs/standards/testing.md#cost-levels)): band, frequency,
  mode, strategy, Auto, Hold Tx, Tx/Rx, theme and power. A CAT setting change resets the
  receive-only setup confirmation ([CAT confirmation](#simulator-live-tests)), which the
  operator then gives again.

### Simulator live tests

Live tests run against the FT-8 Band Simulator instead of the transceiver
(handoff: SensorsIot/FT-8-Band-Simulator
`docs/ImplementerPackage/README.md`). Transmitting into the simulator, QSOs included, needs
no consent: nothing reaches an antenna. The tester uses FT4 unless a case needs FT8.

- **Profile.** `%LOCALAPPDATA%\WstxRust\station\profiles\SIM-IC7300`: CAT and PTT on COM4
  (`icom7300://COM4?baud=115200&radio=94&controller=e0`), the VB-Audio cables of the
  handoff, its own `contacts.adi`, `udp.json` with one target `127.0.0.1:22370` (`qso_logged`,
  `logged_adif`), `pskr.json` disabled. The
  operator profile `ic7300` and its logbook are never touched; their hashes are taken before
  and compared after.
- **Switch.** The real IC-7300 may be on or off: with `WSTX_RADIO_DISCOVERY=off` the station
  opens only COM4. `tools/test/powershell/station-switch.ps1 -To simulator` (the tester or
  the coordinator) backs up `station\launcher.ps1` once, points its profile line at `profiles\SIM-IC7300` and sets
  `WSTX_RADIO_DISCOVERY=off` and `WSTX_PSKR=off` (without discovery off, a silent COM4 makes
  the station adopt the real radio on COM3), and `WSTX_UDP=off` unless every target of the
  profile's `udp.json` is on `127.0.0.1` and none on the operator logger's port 2237 (it says
  which, and why UDP stays off), stops the station gracefully
  (Ctrl+C, `station-control.ps1`, as `radio-preflight.ps1` does), restarts the task, reads
  the profile back (`GET /radio`, `station-running.json`) and compares the hashes of the
  operator profile and its logbook; any difference exits non-zero. Return:
  `station-switch.ps1 -To back`, the last step of the tester's run, or the coordinator: the
  backed-up launcher (without one, the pinned launcher), the same restart. `-DryRun` prints
  every step and changes nothing.
- **CAT confirmation.** A new profile, and any change of its CAT setup, needs the operator's
  receive-only confirmation in the browser (Settings, "CAT receive-only confirmation");
  until then CAT stays closed. Agents never change the CAT endpoint during a simulator run.
- **Emulator.** Each run starts its own IC-7300 emulator on COM5 at 115200 baud and stops it:
  `tools/test/powershell/emulator.ps1 -Start` refuses while any process runs the emulator on
  COM5 or its record names a live one, starts `simulator.py --serial COM5 --baud 115200` of
  `D:/Github/IC-7300 simulator` as its own hidden process with stdin held open, waits until its
  new run folder starts the serial transport and records it (pid, creation time, command) in
  `<git common dir>/harness-parallel/radio/emulator.json` beside the radio lease; `-Stop` ends
  exactly the recorded process and its descendants, never another; `-Status` reads it. The
  run's order: `station-switch.ps1 -To simulator`, `emulator.ps1 -Start` once the station runs
  (the station opens COM4 before the emulator's transport), test, halt, `emulator.ps1 -Stop`,
  `station-switch.ps1 -To back`; the station is not restarted while the emulator runs, with
  one exception: the radio preflight of a QSO test stops and restarts it on SIM-IC7300 while
  the emulator runs ([QSO tests](#qso-tests), item 7).
- **Band simulator.** Operated as its project describes it: the tester skill
  `skills/wsjtx-simulator-testing/SKILL.md` and the handoff package of
  SensorsIot/FT-8-Band-Simulator. Agents here do not change the simulator projects.
  `GET /radio` reads `ready` when CAT works.
- **Deploys.** A deploy writes the pinned launcher, so the station returns to `ic7300`;
  switch back to the simulator afterwards if the run continues.
- **Keying the emulator** is not a transmission. Before every keying the agent confirms
  that the active profile is SIM-IC7300; no simulated contact reaches the real logbook, the
  operator's logger, Club Log or PSK Reporter; a loopback listener the test run starts in its
  run folder may receive the station's UDP messages (WSJT-X QSO Logged and Logged ADIF) and
  count the records of each QSO, and the run stops it at its end; an agent returns the
  station to the `ic7300` profile only with `station-switch.ps1 -To back`, after the emulator
  is stopped. Live tests key the simulator: the IC-7300 emulator and the band simulator. The
  real IC-7300 is keyed once the operator has decided so in #239 (`alex.restrictions`).
- **Administrator rights.** Agents have none. A step that needs them is a script the
  operator runs in an elevated shell, restoring what it changed in a `finally` block.

### QSO tests

A CR whose acceptance names a QSO is tested by an agent with the QSO test driver
`tools/test/powershell/qso-test.ps1`, run as `powershell -NoProfile -ExecutionPolicy Bypass
-File tools/test/powershell/qso-test.ps1 -Holder <run> -Issue <n> -Item <k>`; its tests are
`test_qso_test.py` beside it (suite test-bench). The operator's bounds, approved on
2026-11-12, 2026-11-13 and 2026-11-14 and bound by #192 (its decision comments quote them),
are its items 3 to 11; the numbers follow #192:

3. **Profile guard** (2026-11-14). It keys only while `GET /transmit` `profile_id` is the
   one of `profiles\SIM-IC7300\profile.json`, and takes the preflight's `-Port` and `-Baud`
   from that profile's `control.endpoint`; an endpoint naming COM3, or one that does not
   parse, exits 2 before any preflight call. It checks the profile before the preflight,
   before Tune and before every own transmission, and every command it sends carries that
   `profile_id`, so a station running another profile refuses it (`wrong_profile`); any other
   profile ends the run under the stop order, naming #239. It never switches the profile; the
   bench is the tester's.
4. **Use** (2026-11-12). Only where an acceptance item names a QSO, under this consent, with
   two exceptions to `0003`: the SWR key at `0128` and the QSO at `0255`. It answers a CQ;
   the CQ path or Auto only where the item names it.
5. **Target** (2026-11-13), from the decode data, never the text: a general CQ (`fields.type`
   standard, `fields.to.kind` token, `fields.to.text` exactly CQ; a nonstandard call is
   skipped); his newest decoded message is that CQ; not field_day, rtty, vhf or dxpedition;
   `worked_status` present and not worked_this_band_and_mode; fewer than 2 other stations
   sent to his call in the two most recent decoded periods that each follow one of his CQs.
   While fewer than two such periods are decoded it waits without keying. He is dropped when
   he does not call CQ again within two of his cycles (his Tx period plus the next: 30 s FT8,
   15 s FT4) or his newest message is no longer a CQ. Waiting does not count.
6. **Tx frequency** (2026-11-13). Before its first command the driver records Hold Tx Freq,
   `rx_hz` and `tx_hz`; before the first call it sets Hold Tx Freq on and `tx_hz` by
   `set_frequency`; at the end it sets all three back. `tx_hz` is an f with lo ≤ f ≤ hi −
   width in an open range of the newest `free_tx_slots` build whose `rx_parity` is his Tx
   parity: the f nearest his frequency that is `split_clear` of his signal, with none the lo of
   the nearest range. While the build is null, has the other parity or has no such f, it
   does not call.
7. **Power and SWR** (2026-11-12, 2026-11-13). The preflight sets `0128` with read-back
   (`-Holder <run> -Minutes 90` on the port of item 3); after each preflight call the driver
   waits up to 60 s for `GET /radio` ready, else not tested before keying. It subscribes to
   `radio.tx_level`, runs Tune for 3 s and reads the pushes received between the Tune-on reply
   and the Tune-off command with `meters`, `po_pct` and `swr_x10` not null; the SWR is their
   highest `swr_x10`. No such push, `po_pct` 0 in every one, `swr_x10` 30 or more (SWR 3.0) or
   `swr_fault`: not tested, no `0255` write, the reading reported to the operator. Otherwise
   the preflight sets `0255` with read-back, which renews the lease.
8. **Counting and time** (2026-11-13). A transmission is a distinct non-null
   `last_period_utc`; Tune is not counted. `watchdog.tx_calls` 6 or below is accepted, 7 or
   above ends the run before keying; the driver never sets it. No call within 30 minutes of
   the `0255` read-back: not tested. Phase 1, before the first answer: at most 4 calls to one
   station, then another target; at most 10 transmissions, then not tested. A limit counts
   whole sends: the send that reaches it ends before the abort, which comes before the next
   own period. Phase 2 starts
   at a decoded message from the target to the own call; the QSO runs to the 73 under the
   station's rules and is logged normally; a silent partner, or an end by the station's
   watchdog or leave rule, is not tested with the observation. The backstop is 30 minutes from
   the first call; reaching it is a fail.
9. **Stop order**, at every end: Auto off; abort the contact the driver started unless it is
   at rogers, signoff or completed (it ends on its own and the driver waits; one aborted at
   the backstop stays unlogged, and the test fails); Halt only if PTT is still keyed; the
   item 6 values set back; `-Restore` with read-back, a BUSY restore retried every 10 s.
   Without a live lease the value restored is `rf_power_old_bcd` of this holder's first
   `preflight.jsonl` record with verdict PASS and restore false, set on that record's port,
   then the lease is released. A contact the driver did not start is never aborted.
10. **Verdicts** (2026-11-13). Failed: the backstop or a wrong action, whatever else happens:
    (a) a new `last_period_utc` while the transmit state is off (no accepted start since the
    last stop, judged on the state read before it appeared), outside Tune, or after the stop
    order released PTT; a send on the air when a stop arrives may finish; (b) a keyed CQ or a
    message to another call than the target; (c) in a manual test QSO with Hold Tx Freq on, a
    `tx_hz` other than the driver's, except the busy move (while `busy_with` is set or in the
    step that cleared it) until #109 or #314 lands, and not checked in Auto; (d) one message
    keyed more than `tx_calls` times, or twice that with busy pauses; (e) a completed contact
    with outcome unsaved or an error; (f) the previous message keyed again in the second own
    period after a decode that moved `contact.state` forward. Passed: the target's contact
    completed with `last_disarm_cause` contact_completed, its dialogue with his message to the
    own call, a report each way and RR73 or 73, the log saved without error. Not tested beats
    passed: the cases of items 3, 5, 7 and 8, and every `last_disarm_cause` other than
    contact_completed and the driver's own abort, with the cause and the newest outcomes
    failure recorded.
11. **Records and retries.** Each verdict is appended to `qso-tests.jsonl` beside
    `preflight.jsonl` under the issue and item. Not tested leaves the item open, with no
    revert and no escapes row, retried at another time or band; at most 3 attempts per item,
    a 4th is refused and names the operator. Beyond C of #171 the operator is asked only for
    a high SWR, no Po or no fresh reading, and for an item left not tested 3 times.

**Stated limits.** The decode data does not mark a Fox's own plain CQ or the contests with
the standard exchange (ARRL Digi, WW Digi); the driver cannot recognise either, and the
pile-up and newest-message rules skip them often, not always.

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
response, the station's `x-wstx-source-commit` header must be the candidate's commit
(CL-033-01). This is the commit the running service itself reports. `make_package.py`
compiles it in as `WSTX_SOURCE_COMMIT`, and a build without one reports `unknown`, which
fails. An older build sends no header, for example a rollback target. The probe
then says so and keeps the image digest as the identity. Last, it checks that the launcher
receipt agrees with what it observed. Tests of the deploy mechanism, its pins and its drill
are suite `deploy-tooling` (cost 2, `harness/project/suites.yaml`):
`python -m unittest discover -s tools/deploy/tests -v`.

The operator can check the result without any agent; this is not a step of each install:

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
consistent rewrite of executable and records, and an older commit on master. Its two
approval cases apply only with a deploy authority, which this project does not use; the
drill reports them not applicable.

The drill runs the package's own pinned copy with a scripted clock (10 s polls from
12:00:00) and a sandbox station whose state the package's agent client reports. The idle
cases (TC-171-01) each require the busy reason in the refusal, no stop sentinel and an
unchanged destination: update lock held, a live radio lease, no and two station processes,
transmit armed, PTT keyed, transmitting, a contact replying, a contact replying after a
`device_lost` disarm, an automation run active, and a state that cannot be read. Busy that
clears at 290 s proceeds to the stop; still busy at 300 s gives up. The radio cases
(TC-196-04) add a radio `closed`, `connecting`, `closing`, `unavailable` or whose
reply cannot be read: each waits to `12:05:00 WAITING FOR THE RADIO` with exit 6 and no
stop; a radio `ready` from the first reading, or from 290 s, proceeds to the stop; transmit
armed until 310 s with the radio closed ends with the busy reason and exit 3. A second
update started between the idle check and the stop is refused because the first holds the
lock. The pin cases (TC-196-01, TC-196-02): all pins equal passes `-DryRun`; a working-folder
copy of the script is refused (only the package's copy runs); a package file edited after
the build, a commit without pins and pins in another order each refuse with exit 1 and
their reason before any write; new pins that differ from the running pins, a running commit
without pins and a station launcher that differs from its pin log `deploy mechanism changed:`
and reach the stop; a call naming an operator's-OK parameter stops at binding before any
step. No case prints a `Deploy OK` line or reads a comment. `-Rollback` with differing pins
or with the radio closed reaches the stop without asking, and `-DryRun` does not read the radio.

### Rules not met

These rules of the harness's deployment authority stay not met, by the operator's decision:
the deploy authority stays off, and the gate, the package checks, the
idle check, the probe, the automatic return and the pinned, versioned deploy scripts take its
place. The [standing deploy policy](#standing-deploy-policy) authorizes this mechanism in place
of an OK per install:

| Rule | State |
|---|---|
| Credentials outside the agents | Not met: agents run as the HB9BLA user and can write the version directory, `active.json`, the receipt, the gates record and the package and station-update scripts. Only the task and firewall changes need the operator's elevation. |
| Approval names the candidate | Not met: the manifest names commit and executable SHA-256, but the agents write it and no approval is bound to it. |
| Verify before writing | Not met in full: `station-update.ps1` refuses a changed artifact, package path, gates record, push-gate log, unpublished commit, task or firewall scope before writing, but against an agent-written manifest beside the artifact. |
| Prove the result | Not met in full: `station-update.ps1` checks the launcher receipt and HTTP 200, and `station-probe.ps1` checks, independently of the receipt, that the process listening on 18081 runs the candidate's bytes, answers over trusted TLS and reports the candidate's commit itself (`x-wstx-source-commit`); the operator can read that report without an agent. But an agent runs the probe and the rollback after it, and on HB9BLA everything except the operator runs with the agents' rights. |
| Show the refusals | Not met in full: `station_drill.py` shows each refusal of `station-update.ps1` before the destination changes (above), and that a consistent rewrite of artifact and records and an older commit on master are accepted. |

**Platform limits.** `execution_mode: local`: the hooks and the push gate run on the
client with the agents' own rights. The repository has no branch protection and no
required remote status check. There is no environment approval. None of these rules is
enforced by the platform.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)

## Product model maintenance

The reusable [SysML authoring instruction](../../general/core/docs/standards/sysml-v2.md)
explains how to write models without project-specific assumptions. The project harness
selects the exclusive authority policy below and the local toolchain. The rules of this
project's model are the [finished model](Finished-Model.md) (M0 to M8 and its authoring
rules); where they differ from the general skill and standard, they win. The
functional entry point is [Requirements.sysml](../../../docs/sysml/Requirements.sysml), with the
[architecture](../../../docs/sysml/Shack.sysml) and the model packages it references.
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

The model tools' contract (toolchain pins, commands, validation limits, the rules TR-nn and their tests TV-nnn, the catalog and source bindings) is in [tools/sysml/README.md](../../../tools/sysml/README.md).

## Project model documentation contract

### Required sequence for functional issues

1. Identify the current canonical contract, implemented baseline and affected owners.
2. Settle the changed promises in the issue, in the model's wording: each clause with the
   FR it derives from and the use-case step that carries it (M6.2, M6.11), each test case
   by identity and title (M6.5), and a negative test for each clause that prevents
   something. The coder writes them into the model with the code. An issue that changes the architecture lists its added and removed parts, ports and
   connections, written before `python tools/sysml.py oracle` runs and never from its
   output; its acceptance compares that list with `oracle`'s change lines.
3. Settle open decisions on behaviour, data, ownership, states, timing, errors and test
   oracles with the operator; unresolved ones block the issue. A device or protocol whose
   behaviour is unknown gets an experiment (`cr:experimenting`) within the
   [limits below](#limits-for-experiments), findings on the issue. The issue then passes the
   ready check of the [CR process](../../general/core/docs/CR-Process.md): an agent that did not
   write it posts `Ready: PASS`. A model-readiness review is held only on request.
4. Implement against the model and declared normative references. Verification keeps
   independent expected values and does not generate its sole oracle from that code.
5. Test the function, for real where it matters (a few short transmissions need no prior
   review; long or unattended on-air running waits for it). Only when the function is OK,
   independently review the exact candidate to find undesired behaviour; then the gate.
   Keep test existence, actual execution, model readiness and live acceptance separate.
6. Before issue closure reconcile delivered functionality, test cases and model/source
   bindings, and the `@CodeDiffers` markers the change resolves (M6.13). Current issues retain approval, review, deployment and dated execution evidence.

### Limits for experiments

The limits the [CR process](../../general/core/docs/CR-Process.md) leaves to the project:

- Throwaway scripts live in `D:/wstx-tmp/experiments/<issue>/`, are never committed and may
  hold radio addresses.
- Live runs log under `D:/wstx-tmp/live/<issue>/`, removed when the issue closes.
- The radio is keyed as in any agent test: the radio preflight and its lease first
  ([Keying the radio](#keying-the-radio)), and short test transmissions only.
- Anything that needs the operator (the Flex switched on) is prepared and dry-run first.
- Three real runs without an answer mean stop and report to the operator.
