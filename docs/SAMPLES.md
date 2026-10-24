# FT8 sample recordings and provenance

Investigated: 2026-10-24. No third-party sample files or decoder source have been copied into this Rust project as part of this investigation.

## Source identified by rust-ft8

The `siuze/rust-ft8` README and benchmark guide identify `kgoba/ft8_lib` as the source of the recordings used for their 22-recording comparison:

| Recording group | Files used in the comparison | Description in rust-ft8 |
| --- | --- | --- |
| WebSDR | `websdr_test1.wav` through `websdr_test13.wav` | Public WebSDR recordings of busy on-air FT8 activity. |
| Timestamped recordings | `191111_110115.wav`, `191111_110130.wav`, `191111_110145.wav`, `191111_110200.wav`, `191111_110215.wav`, `191111_110615.wav`, `191111_110630.wav`, `191111_110645.wav`, `191111_110700.wav` | Baseline recordings supplied with ft8_lib. |

Each recording has a corresponding `.txt` expected-decode file. The benchmark guide describes those texts as decoder output from `wsjtx-lib` or `ft8_lib`, without a per-file decoder version and configuration record.

## Independent identity check

Git tree blob identifiers were compared between:

- `siuze/rust-ft8` commit `42d77990188b3af78d72e7eee0f1d1c983aaddf4`, under `tests/wav/`.
- `kgoba/ft8_lib` commit `9fec6ca39886edbf96f4f5e71edc76da5074e871`, under `test/wav/`.

All 22 benchmark WAV files and all 22 matching text files have identical Git blob identifiers: 44 of 44 files are byte-identical. The text fixtures are therefore inherited too, rather than newly generated for rust-ft8's current Rust implementation or the WSJT-X experimental beta.

For example, `websdr_test1.wav` has blob ID `b4299f33dd98e430533817932e30e121a1d47fd2` in both trees. `191111_110115.wav` has blob ID `b34b35892d93186a392d51034b4f546d74ae111e` in both trees.

## Earlier history

The ft8_lib history credits Karlis Goba with adding `tests/websdr_test1.wav` and its expected-decode text on 2019-01-16, in commit `a31733448d79d7e12cd9dc50198ee9f241829da8`, described as adding test cases with corresponding WSJT-X decodes.

The timestamped example `tests/191111_110115.wav` was added on 2019-11-11 in commit `82da02f7ade8bcaa750016625ddd69a2703938d1`, also by Karlis Goba. The files were moved to `test/wav/` in 2022 in commit `a05dbae957a9aef3b3d72cf18aab9c7087dee346`.

This establishes repository provenance. It does not establish the particular WebSDR receiver, original recorder, antenna, band, or recording conditions for every file; those details were not identified in the material reviewed. A file added by a contributor does not by itself establish who recorded it.

## Use in this project

- Obtain candidate fixtures directly from the pinned ft8_lib revision and keep its MIT license and attribution with any imported material. The root license names copyright 2018 Karlis Goba; no separate sample-specific license was found in the reviewed tree.
- Keep original WAV files and expected-output texts unchanged, with hashes and source URLs recorded in a fixture manifest when imported.
- Treat existing text files as historical reference output, not exhaustive independently verified ground truth.
- For the selected WSJT-X `v3.3.0-beta4` behavior reference, generate a separate output set and record the exact binary, settings, command, and audio input. Do not overwrite the historical references.
- Add synthetic and noise-only inputs alongside the live recordings to measure sensitivity, false decodes, frequency/time error, and crowded-band behavior.
- Sample data can support an independently designed implementation without importing the C or Fortran decoder code.
- The recordings are useful independently of ft8_lib's microcontroller focus. Our primary implementation targets desktop resources and performance, with Windows first and macOS/Linux afterward. Evaluate any codec reference on interoperability, decoder quality, and end-to-end latency rather than adopting its embedded resource limits. A possible secondary microcontroller edition may make different tradeoffs.

## Sources

- [rust-ft8 benchmark guide](https://github.com/siuze/rust-ft8/blob/42d77990188b3af78d72e7eee0f1d1c983aaddf4/docs/BENCHMARK_AND_COMPARISON_GUIDE.md)
- [rust-ft8 audit and reference-data limitations](https://github.com/siuze/rust-ft8/blob/42d77990188b3af78d72e7eee0f1d1c983aaddf4/docs/DECODE_AND_SPEED_AUDIT_2026-10-03.md)
- [Original ft8_lib sample directory](https://github.com/kgoba/ft8_lib/tree/9fec6ca39886edbf96f4f5e71edc76da5074e871/test/wav)
- [ft8_lib MIT license](https://github.com/kgoba/ft8_lib/blob/9fec6ca39886edbf96f4f5e71edc76da5074e871/LICENSE)
- [2019 WebSDR example introduction](https://github.com/kgoba/ft8_lib/commit/a31733448d79d7e12cd9dc50198ee9f241829da8)
- [2019 timestamped example introduction](https://github.com/kgoba/ft8_lib/commit/82da02f7ade8bcaa750016625ddd69a2703938d1)
- [WSJT-X v3.3.0-beta4 release](https://github.com/WSJTX/wsjtx/releases/tag/v3.3.0-beta4)
