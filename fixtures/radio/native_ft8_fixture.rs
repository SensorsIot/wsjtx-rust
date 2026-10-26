#![forbid(unsafe_code)]
//! Test input only: independently verified FT8 CQ audio represented as native stereo.
use std::{fs, path::PathBuf, process::Command};

pub const NATIVE_FRAMES: usize = 720_000;
pub const TRAILING_SILENT_FRAMES: usize = 480;

pub struct NativeFt8Fixture {
    pub expected: serde_json::Value,
    samples: Vec<f32>,
}

impl NativeFt8Fixture {
    pub fn load() -> Self {
        let root = PathBuf::from(
            std::env::var_os("WSTX_DECODER_VECTORS").expect("explicit verified vector cache"),
        );
        let tool = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../fixtures/decoder/independent-vector-tool/cache.py");
        // Existing independent fixture authority verifies pinned original hashes.
        // No network, candidate encoder, waveform reconstruction or new golden.
        let verified = Command::new(if cfg!(windows) { "python" } else { "python3" })
            .arg(tool)
            .args(["--kind", "frozen", "--output"])
            .arg(&root)
            .arg("--verify-only")
            .output()
            .expect("independent fixture verification executes");
        assert!(
            verified.status.success(),
            "{}",
            String::from_utf8_lossy(&verified.stderr)
        );
        let manifest: serde_json::Value =
            serde_json::from_str(include_str!("../decoder/independent-vectors/manifest.json"))
                .unwrap();
        let expected = manifest["vectors"]
            .as_array()
            .unwrap()
            .iter()
            .find(|v| v["mode"] == "ft8" && v["id"] == "cq")
            .unwrap()
            .clone();
        let wav = fs::read(root.join("ft8-cq/000000_000000.wav")).unwrap();
        assert_eq!(wav.len(), 360_044);
        assert_eq!(&wav[..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(&wav[20..24], &[1, 0, 1, 0]); // PCM16, mono
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 12_000);
        assert_eq!(u16::from_le_bytes(wav[34..36].try_into().unwrap()), 16);
        assert_eq!(&wav[36..40], b"data");
        let samples = wav[44..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|bytes| f32::from(i16::from_le_bytes(*bytes)) / 32768.0)
            .collect();
        Self { expected, samples }
    }

    /// Explicit test-only zero-order hold to48kHz. Negating channel1 makes
    /// accidental channel summation erase the known signal instead of passing.
    pub fn native_stereo(&self, first: usize, frames: usize) -> Vec<u8> {
        assert!((1..=8192).contains(&frames));
        let end = first.checked_add(frames).unwrap();
        assert!(end <= NATIVE_FRAMES);
        let mut bytes = Vec::with_capacity(frames * 8);
        for n in first..end {
            let value = self.samples[n / 4];
            bytes.extend_from_slice(&value.to_le_bytes());
            bytes.extend_from_slice(&(-value).to_le_bytes());
        }
        bytes
    }
}
