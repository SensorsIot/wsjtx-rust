# WSTX Rust

A planned, simplified Rust implementation of WSJT-family radio functionality. Requirements will be extracted from documented and observable behavior, with WSJT-X v3.3.0-beta4 as the initial experimental reference. The existing implementation will not be translated line by line or copied into the Rust project. WSTX Rust is a working name; final release branding remains undecided.

The project has a minimal Rust executable and a Windows/MSVC build workflow. Radio functionality is still in the specification phase; no decoder has been implemented or imported.

## Documentation

- [Functional specification](docs/WSTX%20Rust%20FSD.md)
- [Upstream baseline and attribution](docs/UPSTREAM.md)
- [Windows build environment](docs/BUILDING.md)
- [Sample recordings and provenance](docs/SAMPLES.md)

## Branches

- `master`: specifications and development of the Rust port.
- `original`: the imported upstream source and history, preserved as the reference baseline.

The original Fortran, C, C++, Qt, and CMake implementation has been removed from the current `master` tree. It remains available on `original` and in Git history. Browse the [original source](https://github.com/SensorsIot/wsjtx-rust/tree/original) or inspect individual files with `git show original:path/to/file`.

## License and attribution

The Rust port will be distributed under GPLv3. See [COPYING](COPYING), [AUTHORS](AUTHORS), [THANKS](THANKS), and the [upstream reference record](docs/UPSTREAM.md).

WSJT-X, MAP65, QMAP, and their program icons are subject to the upstream [trademark policy](TRADEMARK.md). This is an independent project and does not claim endorsement by the WSJT Development Team. Relevant third-party notices must be retained as components are ported or reused.
