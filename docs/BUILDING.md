# Building on Windows

The Rust executable serves an embedded browser status client and a versioned WebSocket interface. Radio functionality is not implemented.

The root Cargo workspace contains the station-server package in `server/`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` files are embedded at Rust compile time, without a frontend build step.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml) runs on pushes and pull requests to `master`, and can also be started manually from the Actions page once the workflow is on the default branch.

The workflow uses a GitHub-hosted Windows Server 2022 x64 runner with the MSVC build tools. It installs Rust 1.99.0, matching `rust-toolchain.toml`, and checks formatting, Clippy warnings, tests, release compilation, and execution of the built program. The executable is uploaded as the `wstx-rust-windows-x64` artifact with a 14-day retention period.

No radio, sound device, third-party decoder or repository secrets are required. Rust dependencies implement HTTP/WebSockets, asynchronous networking, JSON and TLS. Node 24 test dependencies provide a real Chromium browser, independent WebSocket peer and disposable TLS certificates. The workflow runs browser tests against the compiled release executable. These checks validate status communication, not FT4/FT8 behavior.

The workflow has read-only repository permissions and pins its checkout and artifact actions to specific commits. It does not publish GitHub releases or packages.

## Local Windows development

Install Rust through [rustup](https://rustup.rs/) and the Visual Studio C++ Build Tools with the Desktop development with C++ workload and a Windows SDK. The toolchain file selects the compiler version automatically.

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
[communication contract](COMMUNICATION.md#connection-and-security).

For routine local browser checks, install Node 24 and run from the repository root:

```powershell
npm ci --ignore-scripts
npx playwright install chromium
cargo build --locked
npm run test:local
```

This fast profile runs protocol validation, the real browser interface,
disconnect/silent-loss recovery, slow-reader isolation, authentication and simulator
sanity against the debug server. It intentionally excludes the 60-second
TC-021-008 bandwidth-budget measurement and does not certify that budget.
GitHub Actions runs the full `npm test` suite against the packaged release server,
including the bandwidth measurement. To run that full suite on this PC on demand,
use `npm test` after building the executable to test.

`WSTX_TEST_EXE` optionally selects an exact packaged executable. Otherwise tests use
the debug executable under `CARGO_TARGET_DIR` when set, or `target/`.
Screenshots and the thin-link measurement report are written to ignored `test-results/`.
The portable link simulator uses modelled network overhead, not packet capture;
see the [measurement limits](COMMUNICATION.md#thin-link-budget-and-test-model).

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The current page reports server version, connection status and an unconfigured radio; it reconnects after connection loss.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)
