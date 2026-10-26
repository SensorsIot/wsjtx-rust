# Independent decoder inputs

This independently authored fixture composer does not import production functions or upstream decoder implementation. Input is a fixed payload77, not a production encoder's output. It uses Python's standard library and the published, hash-pinned generator/parity matrices. The ordered source message and exact received fields remain distinct: unresolved hashes retain their numeric identity.

Protocol: [Franke/Somerville/Taylor, QEX July/August 2020](https://wsjt.sourceforge.io/FT4_FT8_QEX.pdf), sections 3–5 and Appendix A. The utility is project work under the repository license when adopted; protocol publication/data retain their own notices and conditions. WSJT-X binaries retain their own license. Preserve existing fixture attribution before adoption.

Example, using absolute paths:

```powershell
python generate.py --case CASE.json --out OUTPUT --protocol-data PROTOCOL_DATA
```

Numerics: 12000 Hz; symbol lengths 1920/576; Gaussian BT 2/1; pulse support ±2T; sample-center evaluation; pulse centers j*N+N/2. Phase increments by instantaneous frequency per sample with explicit initial phase. FT8 taper length 240, FT4 576: rise[i]=(1-cos(pi*i/ramp))/2 for i=0..ramp-1; trailing taper reverses these exact values. Outside waveform is zero. PCM uses ties-to-even round(real*32767), signed16 LE, and clipping fails. CR6 maps imported PCM/32768; that distinction is explicit.

Noise uses the source's exact unsigned 64-bit SplitMix64 transitions, top53 midpoint uniforms and two fresh uniforms per Box-Muller sample. No library RNG defaults/cache. Python/libm may differ at final rounding; allow at most 1 PCM LSB between independently computed mathematical waveforms, record runtime/source hashes, and use pinned generated data hashes for byte identity. SNR2500 uses steady signal power A²/2 and one-sided noise PSD 2*variance/12000.

`../independent-vectors/manifest.json` contains 38 frozen channel/waveform vectors, 19 per mode. `../payload-boundary-cases.json` contains 103 fixed field-boundary cases for both modes. `../protocol-data/provenance.json` pins these inputs, the composer and all published tables with their source terms. No external runtime log or machine-specific path defines an expected decoder result.

`../quality-cases.json` specifies 2286 cases: 2000 noise-only, 160 AWGN, 80 overlap, 40 offset, and six silence/wrong-mode/CRC cases. Modes, payloads, seeds, timing, amplitude/noise and aggregate acceptance counts are fixed. These are expected inputs, not successful candidate outcomes. Generated audio belongs in an ignored cache, never beside the frozen corpus; the utility opens no audio device or transmitter.

For a fixed vector, create a case with its waveform `frames`, `start_frame`, `frequency_hz`, `amplitude`, `phase_radians` and zero noise, using that payload/mode as its sole `signals` entry. The generated WAV matches the pinned SHA-256 on the reference math runtime. Another libm may differ by at most one PCM LSB and records its own hash; discrete payload/CRC/parity/tone values must match exactly on every platform. Invoke `generate.py --case CASE.json --out OUTPUT --protocol-data fixtures/decoder/protocol-data` without network access.

`cache.py --kind quality --output CACHE` composes and verifies all2286cases with bounded
workers; `--kind frozen` prepares the38fixedwaveforms. `--verify-only` checks every
recipe, actual WAV SHA256, composer SHA256 and header without generating replacements.
The tracked `../quality-audio-hashes.json` pins all2286independent WAV digests; changing
a PCM file and its adjacent generated hash together is refused. `test_cache.py` proves
that refusal, along with changed-recipe/composer refusal, against a positive fixture.
Generated audio is published from per-case temporary directories into an external cache.
An existing changed input fails instead of being accepted as new truth.

`../synchronization-cases.json` specifies14additional fixed phase/drift/dynamic-range
and quantization-residual cases. `regressions.py --output CACHE` composes mono12kHz
little-endian canonical floats and refuses a changed source/composer/sample hash.
The independent base composer supplies channel tones and real/90degree quadratures;
linear drift adds phase pi*drift*(time since waveform start)^2. PCM16 cases use the
same round(real*32767)/32768 conversion; gain is applied to canonical samples afterward.
Residual cases independently solve the full-support2x2Gram system for unit real/90degree
GFSK templates and subtract the best-fit reconstruction from the quantized source.
Their two inner products satisfy the FSD's double/float orthogonality bounds before
and after canonical gain/storage; no production fitting helper supplies the residual.
The `--pin-hashes` preparation command writes independently computed input hashes before
candidate execution. It is never part of candidate tests, decoder runtime or an oracle
update based on decoder output. All original2286cases and thresholds remain separate.
