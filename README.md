# WSTX Rust

A Rust implementation of WSJT-family radio functionality, compared with WSJT-X v3.3.0-beta4.
Selected decoder stages adapt the pinned WSJT-X numerical routines into Rust, retaining their
GPL notices and source provenance. WSTX Rust is a working name.

What the station does is stated in its model, `docs/sysml/`, and only there: the
[functional requirements](docs/sysml/Requirements.sysml), the shack, its stations and
their parts ([Shack.sysml](docs/sysml/Shack.sysml)), the link between a browser and its
station ([StationLink.sysml](docs/sysml/interfaces/internal/StationLink.sysml),
[Listener.sysml](docs/sysml/backend/web/Listener.sysml)). This README gives orientation,
setup and licensing.

Of the station's 24 functional requirements, 7 are built and tested, 16 are built in part
and one is not built yet; `python tools/sysml.py status` lists each requirement with its
clauses. Where the code does not yet do what the model states, the model says so in the
clause's status or in a `CodeDiffers` marker (`python tools/sysml.py markers CodeDiffers`).
The first release targets Windows desktop.

## Repository layout

| Path | Contents |
| --- | --- |
| `server/` | Rust station server. |
| `client/` | Browser client, embedded into the server executable. |
| `docs/sysml/` | The model: requirements, parts, interfaces, behaviour and verification. |
| `tools/` | The model tool (`tools/sysml.py`, [its contract](tools/sysml/README.md)) and other tools. |
| `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml` | Shared Rust workspace, dependency lock file, and compiler selection. |
| `harness/` | The development harness: the pinned general harness (`harness/general/`) and the project harness (`harness/project/`) with its development instructions. |

Build, test and packaging instructions are in the [project-specific harness](harness/project/docs/Project-Specifics.md).

## Branches

- `master`: the Rust implementation and its model.

The upstream WSJT-X source (Fortran, C, C++, Qt, CMake) is master's history up to commit
`967c85a61`; read a file of it with `git show 967c85a61:<path>`.

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
owns FFT scaling, scratch storage and the independent display dBFS definition. Selected
modem synchronization, metrics and subtraction routines adapt WSJT-X revision
`0f7d5928449ec747c3d1f6da1306f8c94404c3a9` under GPL-3.0-only, with source paths and
notices in the adapted files. The project retains its [COPYING](COPYING) and
[AUTHORS](AUTHORS) attribution.

- Obtain candidate fixtures directly from the pinned ft8_lib revision and keep its MIT license and attribution with any imported material. The root license names copyright 2018 Karlis Goba; no separate sample-specific license was found in the reviewed tree.
- [ft8_lib MIT license](https://github.com/kgoba/ft8_lib/blob/9fec6ca39886edbf96f4f5e71edc76da5074e871/LICENSE)
