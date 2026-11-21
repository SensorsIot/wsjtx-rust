**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Windows build and packaging

The Rust executable serves the embedded browser, versioned station interfaces and implemented receive services. Native Windows audio, typed CAT adapters and the pure FT4/FT8 decoder are separate modules. Their presence does not establish complete mode parity or live acceptance; current implementation and verification declarations belong to the functional model and issue evidence.

### Crates that need `unsafe`

The [Rust standard](../../../general/lang/rust/standard.md#security) forbids `unsafe` in a crate
the project harness does not list. The listed crate is `wstx-rust` (`server/`): its library
calls the Windows API in the modules below, and only these allow `unsafe`, each by
`#[allow(unsafe_code)]` on its module declaration under the library root's
`#![deny(unsafe_code)]` (`server/src/lib.rs`):

- `server/src/audio/windows.rs`: WASAPI capture, declared in `server/src/audio.rs`;
- `server/src/modes/playback/windows.rs`: WASAPI render, declared in `server/src/transmit/playback.rs`;
- `server/src/radioControl/windows.rs`: the CAT port's serial I/O, declared in `server/src/radioControl/mod.rs`;
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

The test-tool folders of the [harness testing standard](../../../general/core/docs/standards/testing.md#test-tools):
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
