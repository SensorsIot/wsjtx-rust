# Upstream baseline and attribution

This project is based on [WSJTX/wsjtx](https://github.com/WSJTX/wsjtx). The imported baseline is commit `967c85a6119110788b0df3782cf796485b2cee14`, preserved on this repository's `original` branch.

## Repository preparation

On 2026-10-24, the upstream application source, assets, utilities, packaging, and build configuration were removed from the current `master` tree to prepare for a Rust port. The upstream README and Git configuration files were replaced with project-specific versions. The upstream implementation has not yet been translated into Rust.

The original license, authors list, acknowledgments, and trademark policy are retained unchanged in the repository root as `COPYING`, `AUTHORS`, `THANKS`, and `TRADEMARK.md`.

## Upstream credits

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

## License and branding

The upstream application is licensed under GNU GPLv3; see [COPYING](../COPYING). Translation into Rust does not remove applicable copyright or license obligations. Distributed binaries must be accompanied by access to their complete corresponding source under the applicable GPL requirements.

The upstream [trademark policy](../TRADEMARK.md) governs use of its program names and icons separately from the software license. WSTX Rust is a working name, not a cleared public product name. This independent port does not claim upstream endorsement.
