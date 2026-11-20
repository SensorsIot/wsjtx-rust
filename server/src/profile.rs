//! The profile of a station (WstxProfileDocument).
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    net::SocketAddr,
    path::{Path, PathBuf},
    sync::Arc,
};

#[cfg(test)]
#[path = "profile_tests.rs"]
pub(crate) mod tests;

pub const MAX_REVISION: u64 = 9_007_199_254_740_991;
pub const MAX_FILE: u64 = profile_limits::PROFILE_FILE_MAX_BYTES;
const MAX_RESPONSE: usize = profile_limits::PROFILE_HTTP_MAX_BYTES;

/// The bounds of a saved profile (WstxProfileAccess::ProfileLimits).
pub mod profile_limits {
    pub const PROFILE_FILE_MAX_BYTES: u64 = 16_384;
    pub const PROFILE_HTTP_MAX_BYTES: usize = 8192;
    pub const DISPLAY_NAME_MAX_BYTES: usize = 64;
}
/// A new profile's own configuration (WstxProfileAccess::ProfileConfig).
mod profile_config {
    pub const DISPLAY_NAME: &str = "New station";
    pub const CONNECTION_TYPE: &str = "standard";
}
/// A new profile's call sign and locator (WstxProfileAccess::ShackConfig).
mod shack_config {
    pub const CALLSIGN: &str = "";
    pub const LOCATOR: &str = "";
}

fn nullable<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    Option::<String>::deserialize(d)
}

/// The input device of a new profile: none.
const INPUT_DEVICE: Option<String> = None;
/// The output device of a new profile: none.
const OUTPUT_DEVICE: Option<String> = None;
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Audio {
    #[serde(deserialize_with = "nullable")]
    pub input_device: Option<String>,
    #[serde(deserialize_with = "nullable")]
    pub output_device: Option<String>,
}
impl Audio {
    /// CL-044-05: a saved device is a WASAPI endpoint ID of its flow, or null. Only
    /// PUT /profile applies it; loading keeps older entries for the startup migration.
    pub fn validate_endpoints(&self) -> Result<(), &'static str> {
        use wstx_rust::radio_control::setup::{Flow, endpoint_id};
        for (field, value, flow) in [
            (
                "settings.audio.input_device",
                &self.input_device,
                Flow::Capture,
            ),
            (
                "settings.audio.output_device",
                &self.output_device,
                Flow::Render,
            ),
        ] {
            if value.as_deref().is_some_and(|v| !endpoint_id(v, flow)) {
                return Err(field);
            }
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct ControlSelection {
    pub mode: String,
    #[serde(deserialize_with = "nullable")]
    pub endpoint: Option<String>,
    pub ptt: String,
}
/// CL-044-10 radio settings the station manages over CAT. Present exactly when the
/// control names a radio with a known CI-V AGC command (`manages_radio`); kept apart
/// from `control`, which is the receive-only authorization's checked identity.
#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Radio {
    pub agc: wstx_rust::radio_control::setup::Agc,
    /// CL-044-12 the profile power: the Po (percent of the radio's full scale) the Tx
    /// level never drives above. None: only the radio's own RF power setting limits it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub power_limit_pct: Option<u8>,
}
impl Radio {
    /// FT8/FT4 default on the IC-7300.
    pub const DEFAULT: Self = Self {
        agc: wstx_rust::radio_control::setup::Agc::Slow,
        power_limit_pct: None,
    };
}
/// True when the control is CAT on a radio whose CI-V AGC command is known: every
/// station CAT endpoint is an IC-7300 CI-V configuration (CL-022, catalogue).
/// The live receive input of a profile: its native session stream or its audio device.
pub fn receive_device(document: &ProfileDocument) -> Option<String> {
    if document.native.is_some() {
        Some(NATIVE_DEVICE.to_owned())
    } else {
        document.audio.input_device.clone()
    }
}
pub const NATIVE_DEVICE: &str = "native_flex";
pub fn manages_radio(control: &ControlSelection) -> bool {
    control.mode == "cat"
        && control
            .endpoint
            .as_deref()
            .is_some_and(|e| wstx_rust::radio_control::Configuration::parse(e).is_ok())
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Settings {
    pub display_name: String,
    pub callsign: String,
    pub locator: String,
    pub audio: Audio,
    pub control: ControlSelection,
    /// Omitted in an edit: the saved value is kept (or the default for a newly managed
    /// radio); omitted in a representation when the radio has no managed settings.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub radio: Option<Radio>,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Endpoint {
    pub bind: String,
    #[serde(deserialize_with = "nullable")]
    pub origin: Option<String>,
}
impl Endpoint {
    const BIND: &str = "127.0.0.1:8080";
    const ORIGIN: Option<&str> = None;
}
/// FR-023 persisted native intent (schema 2 only). A radio identity, slice indices,
/// stream IDs and client handles are never stored (NativeProfileDocument).
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Native {
    pub client_id: String,
    pub rx_antenna: String,
    /// Where to connect when discovery cannot cross to the radio: a locator, no identity.
    /// Absent means discovery; an explicit null is refused like the native object's.
    #[serde(
        default,
        deserialize_with = "present_address",
        skip_serializing_if = "Option::is_none"
    )]
    pub radio_address: Option<String>,
}
impl Native {
    pub fn intent(&self) -> wstx_rust::flex::Intent {
        wstx_rust::flex::Intent {
            client_id: self.client_id.clone(),
            rx_antenna: self.rx_antenna.clone(),
            radio_address: self.radio_address.as_deref().and_then(|a| a.parse().ok()),
        }
    }
    fn valid(&self) -> bool {
        self.intent().valid()
            && valid_uuid(&self.client_id)
            && self.radio_address.as_deref().is_none_or(|a| {
                a.parse::<std::net::SocketAddrV4>()
                    .is_ok_and(|a| a.port() != 0)
            })
    }
}
fn present_address<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    String::deserialize(d).map(Some)
}
// Present means an object: an explicit null is refused, absence is the standard path.
fn present<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<Native>, D::Error> {
    Native::deserialize(d).map(Some)
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct ProfileDocument {
    pub schema_version: i64,
    pub profile_id: String,
    pub revision: u64,
    pub display_name: String,
    pub callsign: String,
    pub locator: String,
    pub endpoint: Endpoint,
    pub connection_type: String,
    pub audio: Audio,
    pub control: ControlSelection,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub radio: Option<Radio>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub native: Option<Native>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Edit {
    pub profile_id: String,
    pub revision: u64,
    pub settings: Settings,
}

impl Settings {
    pub fn validate(&self) -> Result<(), &'static str> {
        let text = |s: &str, maximum| {
            !s.is_empty() && s.len() <= maximum && !s.chars().any(char::is_control)
        };
        if !text(&self.display_name, profile_limits::DISPLAY_NAME_MAX_BYTES)
            || self.display_name.trim() != self.display_name
        {
            return Err("display_name");
        }
        let c = self.callsign.as_bytes();
        if !c.is_empty()
            && (!(3..=12).contains(&c.len())
                || !c
                    .iter()
                    .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || *b == b'/')
                || !c.iter().any(u8::is_ascii_uppercase)
                || !c.iter().any(u8::is_ascii_digit))
        {
            return Err("callsign");
        }
        let l = self.locator.as_bytes();
        if !l.is_empty()
            && (![4, 6, 8].contains(&l.len())
                || !l.iter().enumerate().all(|(i, b)| match i {
                    0 | 1 => (b'A'..=b'R').contains(b),
                    4 | 5 => (b'A'..=b'X').contains(b),
                    _ => b.is_ascii_digit(),
                }))
        {
            return Err("locator");
        }
        for (field, value) in [
            ("audio.input_device", &self.audio.input_device),
            ("audio.output_device", &self.audio.output_device),
        ] {
            if value.as_ref().is_some_and(|s| !text(s, 256)) {
                return Err(field);
            }
        }
        self.control.validate()?;
        if self.radio.is_some() != manages_radio(&self.control) {
            return Err("radio");
        }
        if self
            .radio
            .and_then(|r| r.power_limit_pct)
            .is_some_and(|p| !(1..=100).contains(&p))
        {
            return Err("radio.power_limit_pct");
        }
        Ok(())
    }
    /// CL-044-10 an edit without `radio` keeps the saved radio settings, or takes the
    /// default for a radio that becomes managed; an unmanaged control has none.
    pub fn complete_radio(&mut self, saved: Option<Radio>) {
        if self.radio.is_none() && manages_radio(&self.control) {
            self.radio = Some(saved.unwrap_or(Radio::DEFAULT));
        }
    }
}

impl Settings {
    /// A native profile takes audio and control from its session, not from the
    /// standard device/CAT selections, which therefore stay empty.
    pub fn validate_native(&self) -> Result<(), &'static str> {
        if self.audio.input_device.is_some() {
            return Err("audio.input_device");
        }
        if self.audio.output_device.is_some() {
            return Err("audio.output_device");
        }
        if self.control.mode != "disabled" {
            return Err("control.mode");
        }
        if self.control.endpoint.is_some() {
            return Err("control.endpoint");
        }
        if self.control.ptt != "disabled" {
            return Err("control.ptt");
        }
        Ok(())
    }
}
impl ControlSelection {
    const MODE: &str = "disabled";
    const PTT: &str = "disabled";
    pub fn validate(&self) -> Result<(), &'static str> {
        let text = |s: &str, maximum| {
            !s.is_empty() && s.len() <= maximum && !s.chars().any(char::is_control)
        };
        if !["disabled", "cat"].contains(&self.mode.as_str()) {
            return Err("control.mode");
        }
        if (self.mode == "disabled" && self.endpoint.is_some())
            || (self.mode == "cat" && self.endpoint.as_ref().is_none_or(|s| !text(s, 256)))
        {
            return Err("control.endpoint");
        }
        if !["disabled", "cat"].contains(&self.ptt.as_str())
            || (self.ptt == "cat" && self.mode != "cat")
        {
            return Err("control.ptt");
        }
        Ok(())
    }
}

pub fn valid_uuid(id: &str) -> bool {
    let bytes = id.as_bytes();
    bytes.len() == 36
        && bytes.iter().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                *b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(b)
            }
        })
        && bytes.get(14) == Some(&b'4')
        && bytes.get(19).is_some_and(|b| b"89ab".contains(b))
}
pub fn new_uuid() -> std::io::Result<String> {
    let mut bytes = [0u8; 16];
    rustls::crypto::ring::default_provider()
        .secure_random
        .fill(&mut bytes)
        .map_err(|_| std::io::Error::other("randomness unavailable"))?;
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    Ok(format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    ))
}

/// How [`Files::create`] opens a file for writing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Open {
    /// A new file; an existing one is an error.
    New,
    /// A created or truncated file.
    Truncate,
    /// A file opened for append, created when absent if `create` is set.
    Append { create: bool },
}
/// One entry of a directory listing: its name and whether it is a file.
#[derive(Clone, Debug)]
pub struct Entry {
    pub name: std::ffi::OsString,
    pub is_file: bool,
}
/// A file opened by [`Files::create`]; dropping it closes the file.
pub trait Writer: Send {
    /// Writes all the bytes.
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<()>;
    /// Flushes the file to the disk.
    fn flush(&mut self) -> std::io::Result<()>;
}
/// The file port of the station: every write, replacement, removal and listing of the
/// saved files and the source ids of the live receive. The entry point fills it with
/// [`Disk`].
pub trait Files: Send + Sync {
    /// Opens a file for writing.
    fn create(&self, path: &Path, open: Open) -> std::io::Result<Box<dyn Writer>>;
    /// Renames `from` to `to`, replacing `to`.
    fn replace(&self, from: &Path, to: &Path) -> std::io::Result<()>;
    /// Removes a file.
    fn remove(&self, path: &Path) -> std::io::Result<()>;
    /// The entries of a directory, one result per entry, in the order the system gives.
    fn list(&self, directory: &Path) -> std::io::Result<Vec<std::io::Result<Entry>>>;
    /// A new UUID v4 text.
    fn id(&self) -> std::io::Result<String>;
}
/// The real file adapter: the `std::fs` call of each step.
pub struct Disk;
impl Writer for File {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<()> {
        self.write_all(bytes)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.sync_all()
    }
}
impl Files for Disk {
    fn create(&self, path: &Path, open: Open) -> std::io::Result<Box<dyn Writer>> {
        let file = match open {
            Open::New => OpenOptions::new().create_new(true).write(true).open(path)?,
            Open::Truncate => File::create(path)?,
            Open::Append { create } => OpenOptions::new().create(create).append(true).open(path)?,
        };
        Ok(Box::new(file))
    }
    fn replace(&self, from: &Path, to: &Path) -> std::io::Result<()> {
        fs::rename(from, to)
    }
    fn remove(&self, path: &Path) -> std::io::Result<()> {
        fs::remove_file(path)
    }
    fn list(&self, directory: &Path) -> std::io::Result<Vec<std::io::Result<Entry>>> {
        Ok(fs::read_dir(directory)?
            .map(|entry| {
                let entry = entry?;
                Ok(Entry {
                    name: entry.file_name(),
                    is_file: entry.file_type()?.is_file(),
                })
            })
            .collect())
    }
    fn id(&self) -> std::io::Result<String> {
        new_uuid()
    }
}
impl ProfileDocument {
    pub const SCHEMA_VERSION: i64 = 1;
    fn defaults() -> std::io::Result<Self> {
        Ok(Self {
            schema_version: Self::SCHEMA_VERSION,
            profile_id: new_uuid()?,
            revision: 0,
            display_name: profile_config::DISPLAY_NAME.into(),
            callsign: shack_config::CALLSIGN.into(),
            locator: shack_config::LOCATOR.into(),
            endpoint: Endpoint {
                bind: Endpoint::BIND.into(),
                origin: Endpoint::ORIGIN.map(Into::into),
            },
            connection_type: profile_config::CONNECTION_TYPE.into(),
            audio: Audio {
                input_device: INPUT_DEVICE,
                output_device: OUTPUT_DEVICE,
            },
            control: ControlSelection {
                mode: ControlSelection::MODE.into(),
                endpoint: None,
                ptt: ControlSelection::PTT.into(),
            },
            radio: None,
            native: None,
        })
    }
    pub fn settings(&self) -> Settings {
        Settings {
            display_name: self.display_name.clone(),
            callsign: self.callsign.clone(),
            locator: self.locator.clone(),
            audio: self.audio.clone(),
            control: self.control.clone(),
            radio: self.radio,
        }
    }
    pub fn set_settings(&mut self, s: Settings) {
        self.display_name = s.display_name;
        self.callsign = s.callsign;
        self.locator = s.locator;
        self.audio = s.audio;
        self.control = s.control;
        self.radio = s.radio;
    }
    pub fn admit_response_budget(&self, origin: &str) -> Result<(), &'static str> {
        let mut maximum = self.clone();
        maximum.revision = MAX_REVISION;
        // Quotes/backslashes cost two JSON bytes per permitted UTF-8 byte. Reserve
        // every editable maximum plus the longest valid control/PTT combination.
        maximum.set_settings(Settings {
            display_name: "\\".repeat(profile_limits::DISPLAY_NAME_MAX_BYTES),
            callsign: "A12345678901".into(),
            locator: "RR99XX99".into(),
            audio: Audio {
                input_device: Some("\\".repeat(256)),
                output_device: Some("\\".repeat(256)),
            },
            control: ControlSelection {
                mode: "cat".into(),
                endpoint: Some("\\".repeat(256)),
                ptt: "disabled".into(),
            },
            // No `radio`: it needs a parsable endpoint (`manages_radio`), which holds no
            // JSON-escaped byte, so a managed control is always the shorter of the two.
            radio: None,
        });
        let body = representation(&maximum, "00000000-0000-4000-8000-000000000000", origin);
        let bytes = serde_json::to_vec(&body).map_err(|_| "invalid_profile")?;
        if bytes.len() > MAX_RESPONSE {
            Err("invalid_profile")
        } else {
            Ok(())
        }
    }
    fn validate(&self) -> Result<SocketAddr, &'static str> {
        match (self.schema_version, &self.native) {
            // Schema 1 refuses the reserved spelling without an intent.
            (1, _) if self.connection_type == "native_flex" => {
                return Err("unsupported_connection_type");
            }
            (1, None) if self.connection_type == "standard" => {}
            (2, Some(native))
                if self.connection_type == "native_flex"
                    && native.valid()
                    && self.settings().validate_native().is_ok() => {}
            // Schema 2 defines only the native document; anything else stays unsupported.
            (2, None) => return Err("unsupported_schema"),
            (1 | 2, _) => return Err("invalid_profile"),
            _ => return Err("unsupported_schema"),
        }
        if !valid_uuid(&self.profile_id)
            || self.revision > MAX_REVISION
            || self.settings().validate().is_err()
        {
            return Err("invalid_profile");
        }
        let addr: SocketAddr = self.endpoint.bind.parse().map_err(|_| "invalid_profile")?;
        if addr.port() == 0 {
            return Err("invalid_profile");
        }
        if let Some(origin) = &self.endpoint.origin {
            let uri = parse_origin(origin).ok_or("invalid_profile")?;
            let port = uri
                .port_u16()
                .unwrap_or(if uri.scheme_str() == Some("https") {
                    443
                } else {
                    80
                });
            if port != addr.port() {
                return Err("invalid_profile");
            }
        }
        Ok(addr)
    }
}
pub fn representation(doc: &ProfileDocument, boot: &str, origin: &str) -> serde_json::Value {
    serde_json::json!({"profile_id":doc.profile_id,"boot_id":boot,"revision":doc.revision,"endpoint":origin,"connection_type":doc.connection_type,"settings":doc.settings()})
}
pub fn parse_origin(origin: &str) -> Option<axum::http::Uri> {
    let uri: axum::http::Uri = origin.parse().ok()?;
    if !matches!(uri.scheme_str(), Some("http" | "https"))
        || uri.authority().is_none_or(|a| a.as_str().contains('@'))
        || uri.path_and_query().is_some_and(|p| p.as_str() != "/")
        || origin.ends_with('/')
        || origin.contains(['\r', '\n', '#'])
    {
        None
    } else {
        Some(uri)
    }
}

pub struct Store {
    pub document: ProfileDocument,
    directory: PathBuf,
    files: Arc<dyn Files>,
    // Retained handles are the OS ownership claims. Never delete lock files: unlinking
    // them would let another process lock a different inode for the same profile.
    _directory_lock: File,
    _identity_lock: File,
}
fn lock(path: &Path) -> Result<File, &'static str> {
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path)
        .map_err(|_| "resource_unavailable")?;
    file.try_lock().map_err(|e| match e {
        std::fs::TryLockError::WouldBlock => "profile_in_use",
        std::fs::TryLockError::Error(_) => "resource_unavailable",
    })?;
    Ok(file)
}
impl Store {
    /// The existing profile lock is also the only private authorization writer lock.
    pub fn load_authorization(
        &mut self,
        initial: crate::authorization::Scope,
    ) -> std::io::Result<crate::authorization::Record> {
        if let Some(saved) = read_authorization(&self.directory, &self.document.profile_id)? {
            return Ok(saved);
        }
        let mut initial = crate::authorization::Record::initial(initial)
            .map_err(|_| std::io::Error::other("invalid authorization scope"))?;
        initial.checked_control = self.document.control.clone();
        initial
            .validate(&self.document.profile_id)
            .map_err(|_| std::io::Error::other("invalid authorization scope"))?;
        // Marker first: interruption cannot turn an expected record into a new profile.
        atomic_json(
            &*self.files,
            &self.directory,
            ".authorization-initialized.json",
            &AuthorizationMarker {
                schema_version: 1,
                profile_id: self.document.profile_id.clone(),
            },
        )?;
        atomic_json(
            &*self.files,
            &self.directory,
            "authorization.json",
            &initial,
        )?;
        Ok(initial)
    }
    pub fn save_authorization(
        &mut self,
        record: &crate::authorization::Record,
    ) -> std::io::Result<()> {
        record
            .validate(&self.document.profile_id)
            .map_err(|_| std::io::Error::other("invalid authorization record"))?;
        if read_authorization(&self.directory, &self.document.profile_id)?.is_none() {
            return Err(std::io::Error::other(
                "authorization initialization missing",
            ));
        }
        atomic_json(&*self.files, &self.directory, "authorization.json", record)
    }
    pub fn create(directory: &Path, files: Arc<dyn Files>) -> Result<(), &'static str> {
        fs::create_dir(directory).map_err(|_| "resource_unavailable")?;
        let document = ProfileDocument::defaults().map_err(|_| "resource_unavailable")?;
        atomic_write(&*files, directory, &document).map_err(|_| "resource_unavailable")
    }
    /// FR-023: the connection type is chosen once, when the profile is created.
    pub fn create_native(
        directory: &Path,
        rx_antenna: &str,
        radio_address: Option<&str>,
        files: Arc<dyn Files>,
    ) -> Result<(), &'static str> {
        let mut document = ProfileDocument::defaults().map_err(|_| "resource_unavailable")?;
        document.schema_version = 2;
        document.connection_type = "native_flex".into();
        document.native = Some(Native {
            client_id: new_uuid().map_err(|_| "resource_unavailable")?,
            rx_antenna: rx_antenna.into(),
            radio_address: radio_address.map(Into::into),
        });
        document
            .validate()
            .map_err(|_| "invalid_runtime_configuration")?;
        fs::create_dir(directory).map_err(|_| "resource_unavailable")?;
        atomic_write(&*files, directory, &document).map_err(|_| "resource_unavailable")
    }
    pub fn open(
        directory: &Path,
        files: Arc<dyn Files>,
    ) -> Result<(Self, SocketAddr), &'static str> {
        let directory = directory
            .canonicalize()
            .map_err(|_| "resource_unavailable")?;
        let (document, _) = read_document(&directory)?;
        let directory_lock = lock(&directory.join(".profile.lock"))?;
        // Re-read after ownership: a preceding owner could save during validation.
        let (current, address) = read_document(&directory)?;
        if current.profile_id != document.profile_id {
            return Err("invalid_profile");
        }
        let document = current;
        // Account-local identity claims also exclude copied profile directories.
        let identity_directory = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join("wstx-rust-profile-locks");
        fs::create_dir_all(&identity_directory).map_err(|_| "resource_unavailable")?;
        let identity_lock =
            lock(&identity_directory.join(format!("{}.lock", document.profile_id)))?;
        read_authorization(&directory, &document.profile_id).map_err(|_| "resource_unavailable")?;
        Ok((
            Self {
                document,
                directory,
                files,
                _directory_lock: directory_lock,
                _identity_lock: identity_lock,
            },
            address,
        ))
    }
    /// Another JSON document of this profile directory (WstxUdpControl::UdpConfiguration): None
    /// when absent; larger than `maximum` bytes is an error.
    pub fn read_document_file(
        &self,
        filename: &str,
        maximum: u64,
    ) -> std::io::Result<Option<Vec<u8>>> {
        let file = match File::open(self.directory.join(filename)) {
            Ok(f) => f,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e),
        };
        let mut bytes = Vec::new();
        file.take(maximum + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > maximum {
            return Err(std::io::Error::other("document too large"));
        }
        Ok(Some(bytes))
    }
    /// Atomically replaces another JSON document of this profile directory, under the
    /// profile's own lock (the caller holds this Store).
    pub fn write_document_file(
        &mut self,
        filename: &str,
        document: &impl Serialize,
    ) -> std::io::Result<()> {
        atomic_json(&*self.files, &self.directory, filename, document)
    }
    /// Appends one line to a log file of this profile directory (the caller holds this
    /// Store); at `rotate_bytes` the file first moves to `<stem>.1.<ext>`, replacing the
    /// older one, so the log keeps at most about twice that size.
    pub fn append_log_line(
        &mut self,
        filename: &str,
        line: &str,
        rotate_bytes: u64,
    ) -> std::io::Result<()> {
        let path = self.directory.join(filename);
        if fs::metadata(&path).is_ok_and(|m| m.len() >= rotate_bytes) {
            let older = match filename.rsplit_once('.') {
                Some((stem, ext)) => format!("{stem}.1.{ext}"),
                None => format!("{filename}.1"),
            };
            self.files.replace(&path, &self.directory.join(older))?;
        }
        let mut file = self.files.create(&path, Open::Append { create: true })?;
        file.write(format!("{line}\n").as_bytes())
    }
    /// Removes another document of this profile directory; absent is success.
    pub fn remove_document_file(&mut self, filename: &str) -> std::io::Result<()> {
        match self.files.remove(&self.directory.join(filename)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
            _ => Ok(()),
        }
    }
    pub fn save(&mut self, settings: Settings) -> std::io::Result<()> {
        // No writer can give a native profile a device or CAT selection.
        if self.document.native.is_some() && settings.validate_native().is_err() {
            return Err(std::io::Error::other("native profile selection"));
        }
        let mut next = self.document.clone();
        next.revision = next
            .revision
            .checked_add(1)
            .filter(|n| *n <= MAX_REVISION)
            .ok_or_else(|| std::io::Error::other("revision exhausted"))?;
        next.set_settings(settings);
        atomic_write(&*self.files, &self.directory, &next)?;
        self.document = next;
        Ok(())
    }
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct AuthorizationMarker {
    schema_version: u8,
    profile_id: String,
}
fn read_authorization(
    directory: &Path,
    profile_id: &str,
) -> std::io::Result<Option<crate::authorization::Record>> {
    use std::io::ErrorKind;
    let marker = match fs::read(directory.join(".authorization-initialized.json")) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == ErrorKind::NotFound => {
            return match fs::metadata(directory.join("authorization.json")) {
                Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
                _ => Err(std::io::Error::other(
                    "authorization initialization missing",
                )),
            };
        }
        Err(e) => return Err(e),
    };
    let marker: AuthorizationMarker = serde_json::from_slice(&marker)?;
    if marker.schema_version != 1 || marker.profile_id != profile_id {
        return Err(std::io::Error::other(
            "invalid authorization initialization",
        ));
    }
    let file = File::open(directory.join("authorization.json"))?;
    let mut bytes = Vec::new();
    file.take(4 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > 4 * 1024 * 1024 {
        return Err(std::io::Error::other("invalid authorization record"));
    }
    let saved: crate::authorization::Record = serde_json::from_slice(&bytes)?;
    saved
        .validate(profile_id)
        .map_err(|_| std::io::Error::other("invalid authorization record"))?;
    Ok(Some(saved))
}
fn read_document(directory: &Path) -> Result<(ProfileDocument, SocketAddr), &'static str> {
    let file = File::open(directory.join("profile.json")).map_err(|_| "resource_unavailable")?;
    let mut bytes = Vec::new();
    file.take(MAX_FILE + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "resource_unavailable")?;
    if bytes.len() > usize::try_from(MAX_FILE).map_err(|_| "resource_unavailable")? {
        return Err("invalid_profile");
    }
    let document: ProfileDocument =
        serde_json::from_slice(&bytes).map_err(|_| "invalid_profile")?;
    let address = document.validate()?;
    Ok((document, address))
}
fn write_document(
    files: &dyn Files,
    path: &Path,
    document: &impl Serialize,
) -> std::io::Result<()> {
    let mut file = files.create(path, Open::New)?;
    let mut bytes = serde_json::to_vec(document)?;
    bytes.push(b'\n');
    file.write(&bytes)?;
    file.flush()
}
fn atomic_write(
    files: &dyn Files,
    directory: &Path,
    document: &ProfileDocument,
) -> std::io::Result<()> {
    atomic_json(files, directory, "profile.json", document)
}
pub(crate) fn atomic_json(
    files: &dyn Files,
    directory: &Path,
    filename: &str,
    document: &impl Serialize,
) -> std::io::Result<()> {
    let temporary = directory.join(format!(".{}.tmp", new_uuid()?));
    let result = (|| {
        write_document(files, &temporary, document)?;
        files.replace(&temporary, &directory.join(filename))
    })();
    if result.is_err() {
        let _ = files.remove(&temporary);
    }
    result
}
