# WSTX Rust

A planned Rust port of the WSJT-X application suite, including WSJT-X, MAP65, QMAP, and supporting tools. WSTX Rust is a working name; final release branding remains undecided.

The project is in the specification phase. No Rust implementation or Cargo workspace has been added yet.

## Documentation

- [Functional specification](docs/WSTX%20Rust%20FSD.md)
- [Upstream baseline and attribution](docs/UPSTREAM.md)

## Branches

- `master`: specifications and development of the Rust port.
- `original`: the imported upstream source and history, preserved as the reference baseline.

The original Fortran, C, C++, Qt, and CMake implementation has been removed from the current `master` tree. It remains available on `original` and in Git history. Browse the [original source](https://github.com/SensorsIot/wsjtx-rust/tree/original) or inspect individual files with `git show original:path/to/file`.

## License and attribution

The Rust port will be distributed under GPLv3. See [COPYING](COPYING), [AUTHORS](AUTHORS), [THANKS](THANKS), and the [upstream reference record](docs/UPSTREAM.md).

WSJT-X, MAP65, QMAP, and their program icons are subject to the upstream [trademark policy](TRADEMARK.md). This is an independent project and does not claim endorsement by the WSJT Development Team. Relevant third-party notices must be retained as components are ported or reused.
