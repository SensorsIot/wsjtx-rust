# HTTP response compression dependency notices

Pinned direct additions: tower-http0.7.1 (compression-gzip only) and existing tower0.5.3 util. Exact resolved additions and original license texts are retained below; feature-tree evidence distinguishes active Rust gzip backend from optional lock entries. No runtime body/shared cache/algorithm change is authorized by these notices.

| Crate | Version | Upstream license expression | Source |
|---|---|---|---|
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | https://github.com/oyvindln/adler2 |
| async-compression | 0.4.51 | MIT OR Apache-2.0 | https://github.com/Nullus157/async-compression |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | https://github.com/bitflags/bitflags |
| compression-codecs | 0.4.46 | MIT OR Apache-2.0 | https://github.com/Nullus157/async-compression |
| compression-core | 0.4.34 | MIT OR Apache-2.0 | https://github.com/Nullus157/async-compression |
| crc32fast | 1.5.3 | MIT OR Apache-2.0 | https://github.com/srijs/rust-crc32fast |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | https://github.com/rust-lang/flate2-rs |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 | https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide |
| simd-adler32 | 0.3.10 | MIT | https://github.com/mcountryman/simd-adler32 |
| tower-http | 0.7.1 | MIT | https://github.com/tower-rs/tower-http |
| zlib-rs | 0.6.8 | Zlib | https://github.com/trifectatechfoundation/zlib-rs |

The accompanying files are original upstream license/notice texts for these versions. Existing tower0.5.3 remains under its upstream MIT license; its license is retained as well. For dual/multiple licensing, no upstream choice is removed from the retained texts. These notices do not claim all transitive source code is unsafe-free.

Repository formatting removes trailing whitespace and an extra blank final line in two upstream files; all license and copyright wording is retained. Original-source and retained hashes are recorded in the dependency review evidence.
