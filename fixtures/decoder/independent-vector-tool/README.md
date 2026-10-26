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
