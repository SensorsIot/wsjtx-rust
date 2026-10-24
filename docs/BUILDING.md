# Building on Windows

The project has a minimal, dependency-free Rust executable to verify the compiler, linker, and CI environment before radio functionality is implemented.

The root Cargo workspace contains the station-server package in `server/`. Run Cargo commands from the repository root; the shared lock file and toolchain stay there, and Windows build artifacts remain under `target/x86_64-pc-windows-msvc/`. The `client/` directory is reserved for the browser UI and has no frontend build step yet.

## GitHub Actions

[Windows Rust](https://github.com/SensorsIot/wsjtx-rust/actions/workflows/windows-rust.yml) runs on pushes and pull requests to `master`, and can also be started manually from the Actions page once the workflow is on the default branch.

The workflow uses a GitHub-hosted Windows Server 2022 x64 runner with the MSVC build tools. It installs Rust 1.99.0, matching `rust-toolchain.toml`, and checks formatting, Clippy warnings, tests, release compilation, and execution of the built program. The executable is uploaded as the `wstx-rust-windows-x64` artifact with a 14-day retention period.

No radio, sound device, third-party decoder, repository secrets, or external Rust dependencies are required for the initial build. The test command currently checks the scaffold with zero application tests; decoder acceptance tests will be added with the implementation. A successful initial workflow validates the build environment, not protocol behavior.

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

## Same-machine development

Both applications can be developed on one Windows computer: the station-server process runs locally and the operator client opens in a browser on that computer. The interface between them remains the same when the server is later placed beside a remote radio. The present executable is a build scaffold; it does not yet serve the browser client or implement networking or radio control.

## References

- [GitHub guidance for building and testing Rust](https://docs.github.com/en/actions/tutorials/build-and-test-code/rust)
- [Windows Server 2022 runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)
