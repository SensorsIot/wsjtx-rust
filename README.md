# WSTX Rust

A planned, simplified Rust implementation of WSJT-family radio functionality. Requirements will be extracted from documented and observable behavior, with WSJT-X v3.3.0-beta4 as the initial experimental reference. The existing implementation will not be translated line by line or copied into the Rust project. WSTX Rust is a working name; final release branding remains undecided.

The project has a Rust station server, a browser status/settings interface and a Windows/MSVC build workflow. Saved profiles support independently configured server processes and browser windows on distinct ports. Radio functionality is still in the specification phase; no decoder has been implemented or imported.

Create a profile with `wstx-rust --create-profile <directory>`, then start it with
`wstx-rust --profile <directory>` and open the reported URL. Each simultaneous server
uses its own profile directory and port. The [profile contract](docs/WSTX%20Rust%20FSD.md#42-concurrent-persisted-station-profiles--target-fr-022)
defines configuration, locking, recovery and access; device selections are saved intent
and do not activate hardware. No-argument startup retains the original status mode.

Selected-profile pages import one mono 12 kHz PCM16 WAV of up to 120 seconds and
preserve its original bytes. Choose a file, import it, then explicitly replay its
measured spectrum/waterfall. The upper display and lower station controls share a
draggable, keyboard-accessible separator. Replay uses one worker per station and
does not play audio or decode messages. Cancel stops the current import or replay;
reconnection refreshes state without retrying operations.

Recording tests use an explicit, separate prerequisite step. In PowerShell:

```powershell
$env:WSTX_SAMPLE_DIR = Join-Path $env:LOCALAPPDATA 'WstxRust/recording-fixtures'
node tools/recording-fixtures.cjs --directory "$env:WSTX_SAMPLE_DIR"
cargo build --workspace --locked
npm run test:recording
```

The setup command downloads the 25 pinned WAVs and applicable license/provenance
files from the two tracked decoder manifests, verifies size, SHA256 and WAV headers,
and promotes each file atomically into the selected cache. It refuses Git working
trees, symlinked directories, unsafe manifest paths and changed existing files.
`--verify` checks an already provisioned cache without downloading. Downloads have
bounded time/size limits and acquisition errors fail explicitly. Audio stays out of Git.
The manifests preserve their sample-specific licensing/provenance limitations; a
software license is not a new claim about a recording's origin or decoder truth.

`npm run test:recording` is offline: it uses disposable Windows servers/Chromium,
independent byte/DFT fixtures, the acquired read-only recordings and the shared TLS
link simulator. Missing recordings fail with the setup command. The current parallel
Windows clone can also discover its pre-existing `resources/issue-7/downloads` inputs;
other clones should set `WSTX_SAMPLE_DIR` explicitly. Upload/page-load metrics are
separate from steady display traffic. The manual-only Windows workflow explicitly
runs setup and both `npm test` and `npm run test:recording` against the same release
executable. The local harness gate remains the selected authoritative execution mode;
editing the workflow does not execute it or establish a hosted passing result.

The first release targets Windows desktop. macOS and Linux are planned afterward. The desktop design will use multicore CPUs and evaluate SIMD and optional GPU acceleration where measured benefits justify them, with a usable CPU-only path. A microcontroller edition is a possible secondary product with separately defined capabilities.

## Repository layout

The [FSD](docs/WSTX%20Rust%20FSD.md#35-station-server-and-operator-client) defines the product
requirements. The [target architecture](docs/WSTX%20Rust%20FSD.md#11-target-product-architecture) defines component boundaries,
internal contract ownership and how the queued functional CRs fit together.

| Path | Contents |
| --- | --- |
| `server/` | Rust station server, persisted profiles, WebSocket/HTTP settings and optional native TLS. |
| `client/` | HTML/CSS/JavaScript status/settings interface, embedded into the server executable. |
| `docs/` | One functional specification document and its synchronized SysML model. |
| `docs/harness/` | Project-specific harness bindings and development instructions. |
| `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml` | Shared Rust workspace, dependency lock file, and compiler selection. |
| `harness/`, `.harness/` | Pinned development harness and project bindings. |

Build, test and packaging instructions are in the [project-specific harness](docs/harness/Project-Specifics.md). A packaged desktop webview is an optional future client distribution, not a requirement for using the browser interface.

## Documentation

- [Functional specification](docs/WSTX%20Rust%20FSD.md)
- [Functional behavior baseline](docs/WSTX%20Rust%20FSD.md#behavior-reference)
- [Project-specific harness: Windows builds and model validation](docs/harness/Project-Specifics.md)
- [Reusable SysML authoring instruction](https://github.com/SensorsIot/harness/blob/V2/core/docs/standards/sysml-v2.md)

## Branches

- `master`: specifications and development of the Rust port.
- `original`: the imported upstream source and history, preserved as the reference baseline.

The original Fortran, C, C++, Qt, and CMake implementation has been removed from the current `master` tree. It remains available on `original` and in Git history. Browse the [original source](https://github.com/SensorsIot/wsjtx-rust/tree/original) or inspect individual files with `git show original:path/to/file`.

## License and attribution

The Rust port will be distributed under GPLv3. See [COPYING](COPYING), [AUTHORS](AUTHORS), [THANKS](THANKS), and the retained notices below.

WSJT-X, MAP65, QMAP, and their program icons are subject to the upstream [trademark policy](TRADEMARK.md). This is an independent project and does not claim endorsement by the WSJT Development Team. Relevant third-party notices must be retained as components are ported or reused.

### Retained upstream credits

The original license, authors list, acknowledgments and trademark policy are retained
unchanged as `COPYING`, `AUTHORS`, `THANKS` and `TRADEMARK.md`. These credits describe
the archived upstream project; they do not identify authors of new Rust code.

The WSJT-X About dialog at the baseline credits copyright 2001-2026 to:

- Joe Taylor, K1JT
- Bill Somerville, G4WJS
- Steve Franke, K9AN
- Nico Palermo, IV3NWV
- Uwe Risse, DG2YCB
- Brian Moran, N9ADG
- Roger Rehr, W3SZ
- John Nelson, G4KLA
- Charlie Suckling, DL3WDG
- Terrell Deppe, KJ5HST

It acknowledges contributions from AC6SL, AE4JY, DF2ET, DJ0OT, DL3WDG, EA4AC, G4KLA, IW3RAB, JA7UDE, K3WYC, KA1GT, KA6MAL, KA9Q, KB1ZMX, KD6EKQ, KG4IYS, KI7MT, KK1D, ND0B, PY1ZRJ, PY2SDR, VE1SKY, VK3ACF, VK4BDJ, VK7MO, VR2UPU, W3DJS, W4TI, W4TV, and W9MDB.

The MAP65 and QMAP About dialogs credit copyright 2001-2026 to Joe Taylor, K1JT, and the WSJT Development Group.

The reference to `about.cpp` in the retained `AUTHORS` file refers to the original application source. See the pinned baseline files:

- [WSJT-X credits](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/widgets/about.cpp)
- [MAP65 credits](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/map65/about.cpp)
- [QMAP credits](https://github.com/WSJTX/wsjtx/blob/967c85a6119110788b0df3782cf796485b2cee14/qmap/about.cpp)

These summary credits are not an exhaustive inventory of file-level copyrights or third-party licenses. Record component provenance and carry forward the applicable notices as implementation proceeds.

Translation into Rust does not remove applicable copyright or license obligations.
Distributed binaries must provide access to complete corresponding source under the
applicable GPL requirements. Bundled components and assets may have separate terms;
record their provenance and retain applicable notices. The initial license check
was not a complete dependency audit. Licensing and trademarks remain separate.

### Candidate recording notices

The shared FFT provider is [RustFFT 6.4.1](https://crates.io/crates/rustfft/6.4.1),
by Allen Welkie and Elliott Mahler, under MIT OR Apache-2.0. Its complete notices are
retained in [server/third-party/rustfft](server/third-party/rustfft). The application
owns FFT scaling, scratch storage and the independent dBFS definition; no upstream
WSJT-X transform/decoder implementation was copied.

- Obtain candidate fixtures directly from the pinned ft8_lib revision and keep its MIT license and attribution with any imported material. The root license names copyright 2018 Karlis Goba; no separate sample-specific license was found in the reviewed tree.
- [ft8_lib MIT license](https://github.com/kgoba/ft8_lib/blob/9fec6ca39886edbf96f4f5e71edc76da5074e871/LICENSE)
