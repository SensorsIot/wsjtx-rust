//! #52 WstxRequirements CL-052-01: per-window receive diagnostics and the optional dump of
//! FT8 prompt windows. The dump setting is persisted next to profile.json and is off by
//! default; the window counters are kept in memory and read on demand, never in the
//! GET /receive snapshot.
use super::*;

#[cfg(test)]
#[path = "receive_diagnostics_tests.rs"]
mod tests;

pub(crate) const FILE: &str = "receive-diagnostics.json";
const FILE_LIMIT: u64 = 1024;
/// The dump folder inside the profile directory.
pub(crate) const DUMP_DIR: &str = "diagnostic-windows";
/// The dump keeps the newest windows, at most this many and this many bytes.
pub(crate) const DUMP_KEEP: usize = 20;
pub(crate) const DUMP_BYTES: u64 = 16 * 1024 * 1024;
/// Counters of the latest analysis windows kept for the read.
pub(crate) const WINDOWS: usize = 20;
/// WSJT-X's first FT8 decoding sees the first 41*3456 frames of the period (#52).
const EARLY_FRAMES: u64 = 41 * 3456;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema_version: u8,
    profile_id: String,
    window_dump: bool,
}
pub(crate) struct Diagnostics {
    directory: PathBuf,
    record: Record,
    storage_error: Option<&'static str>,
    dumped_windows: u64,
    windows: VecDeque<Value>,
}
impl Diagnostics {
    pub(crate) fn load(directory: &Path, profile: &str) -> Self {
        let defaults = Record {
            schema_version: 1,
            profile_id: profile.into(),
            window_dump: false,
        };
        let path = directory.join(FILE);
        let (record, storage_error) = match fs::metadata(&path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (defaults, None),
            Err(_) => (defaults, Some("storage_unavailable")),
            Ok(_) => match bounded_json::<Record>(&path, FILE_LIMIT) {
                Ok(r) if r.schema_version == 1 && r.profile_id == profile => (r, None),
                // A corrupt or foreign file never turns the dump on.
                _ => (defaults, Some("invalid_diagnostics")),
            },
        };
        Self {
            directory: directory.to_path_buf(),
            record,
            storage_error,
            dumped_windows: 0,
            windows: VecDeque::new(),
        }
    }
}

/// Exact-zero samples of a window, its longest run of them, and those inside the FT8
/// early buffer `[period, period + 41*3456)` when the period start is known.
pub(crate) fn zero_counts(
    samples: &[f32],
    origin: u64,
    period: Option<u64>,
) -> (u64, u64, Option<u64>) {
    let (mut zeros, mut run, mut longest, mut early) = (0, 0, 0, 0);
    for (i, &x) in samples.iter().enumerate() {
        if x == 0.0 {
            zeros += 1;
            run += 1;
            longest = longest.max(run);
            let frame = origin + i as u64;
            if period.is_some_and(|p| frame >= p && frame < p + EARLY_FRAMES) {
                early += 1;
            }
        } else {
            run = 0;
        }
    }
    (zeros, longest, period.map(|_| early))
}

/// 12 kHz mono PCM16 WAV of the window samples, as jt9 reads them.
pub(crate) fn wav_bytes(samples: &[f32]) -> Vec<u8> {
    let data = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&12000u32.to_le_bytes());
    out.extend_from_slice(&24000u32.to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data.to_le_bytes());
    for &x in samples {
        let v = (f64::from(x) * 32768.0).round().clamp(-32768.0, 32767.0) as i16;
        out.extend_from_slice(&v.to_le_bytes());
    }
    out
}

/// Keeps the newest DUMP_KEEP windows (WAV with its JSON sidecar) within DUMP_BYTES.
pub(crate) fn rotate(dir: &Path) -> std::io::Result<()> {
    let mut wavs = vec![];
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if let Some(stem) = name.strip_suffix(".wav") {
            let meta = entry.metadata()?;
            let sidecar = dir.join(format!("{stem}.json"));
            let bytes = meta.len() + fs::metadata(&sidecar).map_or(0, |m| m.len());
            wavs.push((meta.modified()?, name.clone(), bytes, stem.to_owned()));
        }
    }
    // Newest first; equal times by name, which starts with the window origin.
    wavs.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    let mut total = 0;
    for (index, (_, name, bytes, stem)) in wavs.into_iter().enumerate() {
        total += bytes;
        if index >= DUMP_KEEP || total > DUMP_BYTES {
            let _ = fs::remove_file(dir.join(&name));
            let _ = fs::remove_file(dir.join(format!("{stem}.json")));
        }
    }
    Ok(())
}

impl Recording {
    pub(crate) fn diagnostics_view(&self) -> Value {
        let d = self.diagnostics.lock().unwrap();
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,
            "window_dump":d.record.window_dump,"storage_error":d.storage_error,
            "dump_error":self.diagnostics_error.load(Ordering::Acquire).then_some("dump_failed"),
            "dumped_windows":d.dumped_windows,
            "windows":d.windows})
    }
    pub(crate) fn set_window_dump(&self, profile: &str, boot: &str, on: bool) -> Result<Value> {
        if profile != self.profile {
            return Err("wrong_profile");
        }
        if boot != self.boot {
            return Err("state_conflict");
        }
        {
            let mut d = self.diagnostics.lock().unwrap();
            let next = Record {
                window_dump: on,
                ..d.record.clone()
            };
            if next != d.record || d.storage_error.is_some() {
                match profile::atomic_json(&d.directory, FILE, &next) {
                    Ok(()) => {
                        d.record = next;
                        d.storage_error = None;
                    }
                    Err(_) => {
                        d.storage_error = Some("storage_unavailable");
                        return Err("storage_unavailable");
                    }
                }
            }
        }
        Ok(self.diagnostics_view())
    }
    /// Keeps the counters of one analysis window and, for an FT8 prompt window with the
    /// dump on, writes its samples and sidecar on a separate thread.
    pub(super) fn note_window(&self, mut record: Value, samples: &[f32], dumpable: bool) {
        let (dump, dir) = {
            let d = self.diagnostics.lock().unwrap();
            (dumpable && d.record.window_dump, d.directory.join(DUMP_DIR))
        };
        if dump {
            let utc = record["period_start_utc"]
                .as_str()
                .map(|u| u.replace([':', '-', '.'], ""))
                .unwrap_or_else(|| "unknown".into());
            let stem = format!("{:015}-{utc}", record["origin"].as_u64().unwrap_or(0));
            record["dump"] = json!(format!("{stem}.wav"));
            let wav = wav_bytes(samples);
            let sidecar = json!({"v":1,"rate_hz":12000,"sample_format":"pcm16_mono",
                "window":record.clone()});
            let failed = self.diagnostics_error.clone();
            let spawned = std::thread::Builder::new()
                .name("window-dump".into())
                .spawn(move || {
                    let result = fs::create_dir_all(&dir)
                        .and_then(|()| fs::write(dir.join(format!("{stem}.wav")), &wav))
                        .and_then(|()| {
                            fs::write(
                                dir.join(format!("{stem}.json")),
                                serde_json::to_vec(&sidecar).unwrap_or_default(),
                            )
                        })
                        .and_then(|()| rotate(&dir));
                    failed.store(result.is_err(), Ordering::Release);
                });
            if spawned.is_err() {
                self.diagnostics_error.store(true, Ordering::Release);
            }
        }
        let mut d = self.diagnostics.lock().unwrap();
        d.dumped_windows += u64::from(dump);
        if d.windows.len() == WINDOWS {
            d.windows.pop_front();
        }
        d.windows.push_back(record);
    }
}
