**Layer:** HOW. **Scope:** this project's development environment and procedures.

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
change owners and downstream dependencies in `harness/project/suites/`. The ordinary
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
`harness/project/suites/`; `gate.py --plan` (below) prints the groups a change selects
and why. The selector does not infer changed functions from a file or guess dependencies
from an agent's description. Unmapped inputs select every group that declares them;
entirely unknown paths and selection-policy changes cause a full fallback.

Every test file is registered in a group. A test file that several groups share is
partitioned by the test-name patterns of their `run` commands; each complement includes
future names instead of silently omitting them. No test assertion, budget or test case is
removed by selection.

`python harness/general/core/tools/gate.py --suite NAME --filter "WORDS"` runs selected tests
of one suite with the gate's environment, through the suite's `filter:` form. Only this
command reads `filter:`; the gate's selection, its memos and whole-suite runs use `run`. A
form runs the steps of the suite's `run` through `harness/project/tools/filter_run.py`, each
narrowed to the words: the same build steps, runner targets, test-name filters, `--skip`,
`--test-name-pattern` and `--test-skip-pattern`. A word therefore never reaches a test that a
sibling suite owns through the partition, and where `run` already selects by a name pattern
(`protocol-thin`, `recording-storage`, `recording-thin`) or a test-name filter (`decoder::`,
`receive_http_tests::live_native_`), the words narrow that selection and never widen it.

- Suites with a form: libtest `wstx-rust`, `wstx-rust-decoder`, `decoder-correctness`,
  `live-station-browser` and `live-station-latency` (its two named tests;
  `resource_station_process_delta_and_owner_release` keeps `--ignored`); `node --test`
  `protocol`, `protocol-thin`, `profiles`, `recording-storage`, `recording-display`,
  `recording-thin`, `recording-fixtures`, `model-values`, `test-tools`, `native-flex`,
  `operating-layout` and `mcp`; libtest and node `radio-selection`; unittest
  `sysml-documentation`, `sysml-tools`, `sysml-architecture-context`, `sysml-architecture`,
  `sysml-equivalence-tests`, `deploy-tooling`, `test-bench`, `fortran-reference-tools` and
  `simulator-fixtures`.
- Words: each word of `--filter`, split as a shell splits it, is one selection, and a test
  runs when it matches any word, in every runner step of the suite. In libtest a word is a
  substring of the test path (`module::test_name`); in node a JavaScript regular expression
  on the test name, with `.` for each space of a name (`--filter "deferred.client.download"`);
  in unittest a substring of the dotted name `module.Class.method`, or an fnmatch pattern
  when the word holds `*`.
- No test selected: when no step of the suite runs a test for the words (a skipped test does
  not count), the run prints `filter_run: <suite>: no test selected by --filter <words>`,
  exits 1 and the gate prints `RED <suite>`, although libtest and `node --test` exit 0 and
  unittest exits 5 for an empty run. A step that selects nothing while another step runs a
  test is no failure by itself; a run in which a test ran passes only when every test that
  ran passed.
- Steps left out under `--filter`, because they select no tests: the `python tools/sysml.py
  check` of `sysml-documentation`, the two `--verify-manifest` runs of `simulator-fixtures`
  and `independent-vector-tool/test_cache.py` of `decoder-correctness`. Whole-suite runs
  and the gate run them.
- Suites without a form, each with its reason in its entry; `--filter` on them is refused
  with the gate's "has no filter form" message. `live-receive-integration`,
  `contact-browser` and `radio-selection-thin`: the run is exactly one test, so the whole
  suite is that test. `sysml-equivalence` and `source-model-traces`: the run is a model
  check with no tests to select. `decoder-quality`: `windows_resource_job.py resolve` binds
  every ordinary pass of `decoder_signal` into one artifact, so a partial run cannot be
  resolved. `radio-bounds`: the run is the 14 `realtime_bound_` tests, measured alone; a
  whole run takes seconds, so a part of it saves nothing.

`harness/project/tests/test_filter_forms.py` holds the list of suites with and without a
form and checks that each form runs exactly the steps of its `run`.

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
in `harness/project/suites/`). A timing suite has no `select`; its `timing_inputs` name
the code that sets the measured time, its own test files and helpers, and the toolchain and
dependency pins, and nothing else selects it: no functional owner, unmapped-input or
unowned-path fallback, `harness/project/` edit or dependency
([harness testing standard](../../../general/core/docs/standards/testing.md#timing-suites)).
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
deploy under the [standing deploy policy](deployment-authority.md#standing-deploy-policy) and at live
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
`live-station-latency` (a browser row-latency budget on the busy decoder), and so do the
radio bounds on scripted doubles, `radio-bounds` (the `realtime_bound_` tests of PTT halt
and release, CAT read, close and lease, and the audio stop). The groups
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
([Listener.sysml](../../../../docs/sysml/backend/web/Listener.sysml)).

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
([StationLink.sysml](../../../../docs/sysml/interfaces/internal/StationLink.sysml)), the
counted overhead `WstxListener::LinkTrafficLog`
([Listener.sysml](../../../../docs/sysml/backend/web/Listener.sysml)).

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

Without these, a push that selects any suite whose `needs` in `harness/project/suites/`
names a WSTX_* input is refused red. The merge-queue worker reads the same inputs from
`queue.env` in `harness/project/config.yaml`.

Agent builds use their own `CARGO_TARGET_DIR=D:/wstx-build/<worktree>` (`gate.agent_build_root`)
and `TEMP`/`TMP` set to that same folder, never inside a worktree and never shared: Cargo
creates it before the linker needs it (link.exe fails with LNK1104 on a missing temp
folder). Gate builds go to `D:/harness-cargo-target/wsjtx-rust/<checkout>`
(`gate.cargo_target_root`) and are pruned by the gate itself; agent build folders are pruned
with `python harness/general/core/tools/build_prune.py agent-dirs --root DIR --apply`
([Rust standard, Build folders](../../../general/lang/rust/standard.md#build-folders)).
