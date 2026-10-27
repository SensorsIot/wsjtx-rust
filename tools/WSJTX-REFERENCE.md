# WSJT-X prebuilt differential decoder reference

This test-only runner compares the standard WSJT-X decoder with Rust on identical,
hash-verified 12 kHz mono PCM16. It provides no application file-decoding route,
station service, radio control or transmit operation. No Fortran compiler, source
build or GitHub Actions workflow is needed.

The reference is the official WSJT-X 3.3.0-beta4 Windows jt9 executable, pinned by
SHA256 `a2d0b111d91248bf3fd74be016c5afbb82b37fa11bf0e9563a420623bdd1b6ab`.
The runner refuses a different executable and records its version string, actual
hash, command, raw stdout/stderr and decoded observations. Its reported revision
includes `0f7d59-dirty`; this binary is not claimed to be a reproducible build of
the pristine reference-source commit.

Each run declares decode depth 1 or 3, 200-3500 Hz search, matching the Rust contract, explicitly blank
operator/partner calls (`-c b -x b`), experience flags zero (`-X 0`), QSO progress
zero, no FT8 multithread mode and one FFT thread. Cases use separate working
directories. The pinned release binary emits one completion per case; every
completion count must match that attempt's rows. The parser also has independent
coverage for the newer three-attempt source protocol. Every attempt and emission
is retained; no inferred final-set or hidden deduplication policy is applied.

The standard CLI has no AP-off option. Blank calls and `-X 0` do not disable
AP; reference output is explicitly labeled `upstream-default-on`. Decode depth
changes AP use as well as search effort. Rust's present decoder is unassisted,
so equality of capabilities is not asserted. AP/quality suffixes are retained
verbatim; absent annotations are not proof of an unassisted decode. A GUI capture
with explicitly controlled AP settings would be a separate reference experiment.

The same beta4 release also supplies the standard `wsjt-codec` streaming binary.
`run-codec --ap off` uses its supported configure field `ft8_ap_on: false` with
`multithreaded_ft8: false`, rather than the standalone jt9 WAV CLI. This binary is
pinned to SHA256
`c3263d36e08e012c4a1856c8046564db97af38dfd589374f56c9ad19934a2655`.
It requires no GUI, installation, source modification or compilation. For FT4,
this option selects Fast depth 1, which excludes the AP passes; the FT8 switch
does not disable FT4 AP in Normal/Deep. Requested FT8 depth is preserved.

The stream carries the original PCM bytes in framed 12 kHz mono PCM16, without
gain, trimming, resampling or padding. Exact configure JSON, framed request hash,
raw NDJSON/stderr and all events are retained. The runner requires ready, matching
mode/version and exactly one completion, refusing error or unknown events.
The protocol provides no configure readback or acknowledgment: absence of errors
is recorded without inventing an ACK. Independent source mapping and a negative
control using `ft8_ap_on: "false"` demonstrate key recognition: the actual binary
returns `configure_type_error`, expected bool, got string. Valid boolean false
executes without that error. Equal output with AP on/off for one recording does
not imply that the AP control was ignored or that all recordings behave equally.

`wsjtx_reference.py acquire` downloads the two pinned official recordings and
verifies their existing hashes. `run` executes the hash-verified prebuilt decoder.
`run-rust` calls `reference_decode.rs` after exact PCM16/32768 conversion, without
trimming, padding or gain changes. Build this test-only Rust adapter in an immutable
copy of the candidate using the existing Rust toolchain; it is not an application
binary. Retain the candidate source manifest, adapter hash and executable hash.

```text
python tools/wsjtx_reference.py run --exe PATH/jt9.exe --inputs INPUTS --output REFERENCE --depth 3
python tools/wsjtx_reference.py run-codec --exe PATH/wsjt-codec.exe --inputs INPUTS --output UNASSISTED --depth 3 --ap off
python tools/wsjtx_reference.py compare --reference REFERENCE/reference.json --rust RUST/rust.json --output comparison.json
```

`compare` requires matching input hashes, PCM hashes, frame counts and mode. It
reports one-to-one displayed-message matches within 5 Hz, every missing reference
row and every Rust-only row. Only spacing before signed acknowledged reports is
normalized; order is ignored and repeated observations remain separate. Missing
rows from an AP-enabled reference are diagnostic differences, not automatically
an unassisted-decoder defect or a weakened acceptance threshold.

The reference text does not expose raw77. Displayed DT and Rust waveform-origin
frames use different conventions, and SNR estimators differ. These measurements
are reported side by side without invented equality. Exact payload/timing parity
would require an independently reviewed reference callback and origin tests.

Reference observations complement the independent known-answer fixtures. They
never replace fixture truth or lower numerical, false-positive, cancellation,
memory or runtime acceptance thresholds. Matching this recording alone is not
exhaustive RF ground truth or a completed application acceptance.

## Optional instrumented source diagnostics

The separate manually dispatched `WSJT-X decoder stage diagnostics` workflow is
an explicitly selected investigation, not the ordinary prebuilt comparison or
Rust build. Only its hosted Ubuntu runner installs the Fortran compiler. It builds
the pinned unmodified `wsjt-codec`, then applies the separately reviewed bounded
stderr-only stage logging patch and incrementally builds the instrumented codec.
No GUI or Rust executable is built by that workflow.

The diagnostic runner reuses the same AP-off, 200-3500 Hz, original-PCM controls.
It checks that the instrumented binary with logging disabled AND enabled preserves
exact request hashes, parsed observations, events and raw protocol stdout against
the original source-built binary on both selected recordings. It records compiler,
package and binary hashes, corresponding original source plus exact patch/new
module, licenses, raw stdout and bounded stderr stage records. Source-build binary
hashes are explicit arguments to the private diagnostic runner; ordinary CLI
prebuilt hash pins remain unchanged. This proves sample-specific observation
identity only; it does not establish universal numerical equivalence.
