//! #45 WstxRequirements CL-045-01..03: the last started receive choice and the
//! Monitor-off-at-startup setting, persisted next to profile.json, and the one resume
//! of that choice when the station starts. Resuming only receives: it never arms,
//! keys or tunes for transmit.
use super::*;

#[cfg(test)]
#[path = "receive_startup_tests.rs"]
mod tests;

pub(crate) const FILE: &str = "receive-startup.json";
const FILE_LIMIT: u64 = 1024;
/// Bounded wait for configured CAT to become ready before a band resume falls back to
/// receiving on the radio's present dial.
pub(crate) const CAT_WAIT: Duration = Duration::from_secs(20);

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Choice {
    pub mode: String,
    pub band: Option<String>,
    pub input_device: String,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Record {
    schema_version: u8,
    profile_id: String,
    monitor_off_at_startup: bool,
    last_receive: Option<Choice>,
}
pub(crate) struct Startup {
    directory: PathBuf,
    record: Record,
    storage_error: Option<&'static str>,
    resume: &'static str,
    resume_error: Option<&'static str>,
}
fn mode(text: &str) -> Option<&'static str> {
    ["spectrum", "ft4", "ft8"].into_iter().find(|m| *m == text)
}
fn band(text: &str) -> Option<&'static str> {
    selection::BANDS.into_iter().find(|b| *b == text)
}
impl Record {
    fn valid(&self, profile: &str) -> bool {
        self.schema_version == 1
            && self.profile_id == profile
            && self.last_receive.as_ref().is_none_or(|c| {
                mode(&c.mode).is_some()
                    && c.band.as_deref().is_none_or(|b| band(b).is_some())
                    && !c.input_device.is_empty()
                    && c.input_device.len() <= 256
                    && !c.input_device.chars().any(char::is_control)
            })
    }
}
impl Startup {
    pub(crate) fn load(directory: &Path, profile: &str) -> Self {
        let defaults = Record {
            schema_version: 1,
            profile_id: profile.into(),
            monitor_off_at_startup: false,
            last_receive: None,
        };
        let path = directory.join(FILE);
        let (record, storage_error) = match fs::metadata(&path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (defaults, None),
            Err(_) => (defaults, Some("storage_unavailable")),
            Ok(_) => match bounded_json::<Record>(&path, FILE_LIMIT) {
                Ok(record) if record.valid(profile) => (record, None),
                // A corrupt or foreign file resumes nothing; the next write replaces it.
                _ => (defaults, Some("invalid_startup")),
            },
        };
        Self {
            directory: directory.to_path_buf(),
            record,
            storage_error,
            resume: "idle",
            resume_error: None,
        }
    }
    fn write(&mut self, next: Record) -> Result<()> {
        if next == self.record && self.storage_error.is_none() {
            return Ok(());
        }
        match profile::atomic_json(&self.directory, FILE, &next) {
            Ok(()) => {
                self.record = next;
                self.storage_error = None;
                Ok(())
            }
            Err(_) => {
                self.storage_error = Some("storage_unavailable");
                Err("storage_unavailable")
            }
        }
    }
}

impl Recording {
    /// Records a receive the operator (or a band/mode selection) started. A failed
    /// write leaves receive running and is reported in the startup view.
    pub(super) fn remember_receive(&self, mode: &str, band: Option<&str>, device: &str) {
        let mut startup = self.startup.lock().unwrap();
        let mut next = startup.record.clone();
        next.last_receive = Some(Choice {
            mode: mode.into(),
            band: band.map(str::to_owned),
            input_device: device.into(),
        });
        let _ = startup.write(next);
    }
    /// The operator stopped receive: the next start resumes nothing.
    pub(super) fn forget_receive(&self) {
        let mut startup = self.startup.lock().unwrap();
        let mut next = startup.record.clone();
        next.last_receive = None;
        let _ = startup.write(next);
    }
    pub(crate) fn startup_view(&self) -> Value {
        let s = self.startup.lock().unwrap();
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,
            "monitor_off_at_startup":s.record.monitor_off_at_startup,
            "last_receive":s.record.last_receive,"storage_error":s.storage_error,
            "resume":{"state":s.resume,"error":s.resume_error}})
    }
    pub(crate) fn set_monitor_off(&self, profile: &str, boot: &str, off: bool) -> Result<Value> {
        if profile != self.profile {
            return Err("wrong_profile");
        }
        if boot != self.boot {
            return Err("state_conflict");
        }
        {
            let mut startup = self.startup.lock().unwrap();
            let mut next = startup.record.clone();
            next.monitor_off_at_startup = off;
            startup.write(next)?;
        }
        Ok(self.startup_view())
    }
    fn resume_state(&self, state: &'static str, error: Option<&'static str>) {
        let mut startup = self.startup.lock().unwrap();
        startup.resume = state;
        startup.resume_error = error;
    }
    /// Any receive, selection or import other than the resume's own selection `own`
    /// came from an operator (or MCP client) after boot; the resume never replaces it.
    fn resume_superseded(s: &State, own: Option<&str>) -> bool {
        let own_job = own
            .and_then(|c| s.operating.operation.as_ref().filter(|o| o.command_id == c))
            .and_then(|o| o.new_job_id.as_deref());
        s.import.is_some()
            || s.operating
                .operation
                .as_ref()
                .is_some_and(|o| Some(o.command_id.as_str()) != own)
            || s.job
                .as_ref()
                .is_some_and(|j| Some(j.id.as_str()) != own_job)
    }
    /// Starts the one startup resume on its own thread. `device` and `cat` are the
    /// loaded profile's audio input and control mode.
    pub(crate) fn resume_receive(
        self: &Arc<Self>,
        device: Option<String>,
        cat: bool,
        wait: Duration,
    ) -> std::io::Result<std::thread::JoinHandle<()>> {
        let this = self.clone();
        std::thread::Builder::new()
            .name("station-resume".into())
            .spawn(move || this.resume_run(device, cat, wait))
    }
    fn resume_run(self: Arc<Self>, device: Option<String>, cat: bool, wait: Duration) {
        let choice = {
            let startup = self.startup.lock().unwrap();
            if startup.record.monitor_off_at_startup {
                drop(startup);
                return self.resume_state("off", None);
            }
            startup.record.last_receive.clone()
        };
        let Some(choice) = choice else {
            return self.resume_state("idle", None);
        };
        let Some(device) = device else {
            return self.resume_state("failed", Some("audio_unconfigured"));
        };
        let mode = mode(&choice.mode).unwrap_or("ft8");
        self.resume_state("waiting", None);
        let tune = choice
            .band
            .as_deref()
            .and_then(band)
            .filter(|_| mode != "spectrum");
        let mut own = None;
        if let Some(band) = tune {
            match self.resume_selection(mode, band, &device, cat, wait, &mut own) {
                Ok(()) => return self.resume_state("started", None),
                Err("superseded") => return self.resume_state("skipped", None),
                // The radio's dial is not confirmed; receive on it rather than not at all.
                Err(_) => {}
            }
        }
        // FR-023: a native session still has discovery and its slice ahead of it.
        if let Some(session) = self.flex.get() {
            let deadline = Instant::now() + wait;
            while !session.ready() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(100));
            }
        }
        let start = {
            let s = self.state.lock().unwrap();
            if Self::resume_superseded(&s, own.as_deref()) {
                drop(s);
                return self.resume_state("skipped", None);
            }
            (s.generation, s.operating.profile_revision)
        };
        match self.receive_start_selected(
            &self.profile,
            &self.boot,
            start.0,
            device,
            mode,
            StartGuard::Profile(start.1),
        ) {
            Ok(_) => self.resume_state(
                if tune.is_some() {
                    "started_untuned"
                } else {
                    "started"
                },
                None,
            ),
            Err(e) => self.resume_state("failed", Some(e)),
        }
    }
    /// The same band/mode selection the band button makes (receive-only CAT setup,
    /// refused while the radio reports TX), retried while configured CAT is not ready.
    fn resume_selection(
        self: &Arc<Self>,
        mode: &'static str,
        band: &'static str,
        device: &str,
        cat: bool,
        wait: Duration,
        own: &mut Option<String>,
    ) -> Result<()> {
        let deadline = Instant::now() + wait;
        let command = loop {
            let intent = {
                let s = self.state.lock().unwrap();
                if Self::resume_superseded(&s, None) {
                    return Err("superseded");
                }
                selection::Intent {
                    command_id: profile::new_uuid().map_err(|_| "storage_unavailable")?,
                    profile_id: self.profile.clone(),
                    boot_id: self.boot.clone(),
                    profile_revision: s.operating.profile_revision,
                    generation: s.generation,
                    revision: s.operating.revision,
                    action: "band",
                    mode: Some(mode),
                    band: Some(band.into()),
                }
            };
            let command = intent.command_id.clone();
            #[cfg(test)]
            let refused = self.resources.lock().unwrap().resume_refusals.pop_front();
            #[cfg(not(test))]
            let refused: Option<&'static str> = None;
            let begun = match refused {
                Some(e) => Err(e),
                None => self.selection_begin(intent, Some(device.into()), cat),
            };
            match begun {
                Ok(_) => {
                    *own = Some(command.clone());
                    break command;
                }
                // CAT not ready yet, the actor's background poll holding its lease, or the
                // connection/snapshot changing between the two preflights: all transient
                // while the CAT lifecycle brings the radio up.
                Err("radio_unavailable" | "busy" | "state_conflict")
                    if Instant::now() < deadline =>
                {
                    std::thread::sleep(Duration::from_millis(250));
                }
                Err(e) => return Err(e),
            }
        };
        loop {
            {
                let s = self.state.lock().unwrap();
                let op = s
                    .operating
                    .operation
                    .as_ref()
                    .filter(|o| o.command_id == command);
                match op.map(|o| (o.result, o.error)) {
                    Some(("pending", _)) => {}
                    Some(("success", _)) => return Ok(()),
                    Some(("failed", error)) => return Err(error.unwrap_or("selection_failed")),
                    // Cancelled by the operator, or replaced by a newer selection.
                    _ => return Err("superseded"),
                }
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}
