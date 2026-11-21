use super::*;
// The test-only model-value reader (Project-Specifics, "Model values read by tests").
use wstx_test_tools::model_values;

/// A launch refusal the model lists: the name is checked against the members of
/// `WstxStartup::StartupOutcome`, written as `WstxStationLink::WireNames` says, so a test
/// fails when the model does not list it.
fn outcome(name: &'static str) -> &'static str {
    let members = model_values::Model::load()
        .enum_members("WstxStartup::StartupOutcome")
        .unwrap_or_else(|e| panic!("model value {e}"))
        .iter()
        .map(|m| {
            m.chars().fold(String::new(), |mut wire, c| {
                if c.is_ascii_uppercase() {
                    wire.push('_');
                }
                wire.push(c.to_ascii_lowercase());
                wire
            })
        })
        .collect::<Vec<_>>();
    assert!(
        members.iter().any(|m| m == name),
        "{name} is not a StartupOutcome of the model {members:?}"
    );
    name
}

/// A step of the file port (`profile::Files`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Step {
    Create,
    Write,
    Flush,
    Replace,
    Remove,
    List,
    Id,
}
/// What an armed fault does at its step.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    /// An `io::Error` before the step.
    Fail,
    /// A panic before the step: the process is interrupted there.
    InterruptBefore,
    /// The real step, then a panic.
    InterruptAfter,
}
/// Whose calls an armed fault meets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum FaultScope {
    /// Only the calls of the thread that armed it.
    ArmingThread,
    /// The calls of every thread.
    EveryThread,
}
/// A fault of [`FaultyFiles`]: its step, how many calls of that step in scope pass first,
/// its kind and its scope.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Fault {
    pub(crate) step: Step,
    pub(crate) passes: usize,
    pub(crate) kind: Kind,
    pub(crate) scope: FaultScope,
}
impl Fault {
    pub(crate) fn fail(step: Step, scope: FaultScope) -> Self {
        Self {
            step,
            passes: 0,
            kind: Kind::Fail,
            scope,
        }
    }
    pub(crate) fn interrupt_before(step: Step, scope: FaultScope) -> Self {
        Self {
            kind: Kind::InterruptBefore,
            ..Self::fail(step, scope)
        }
    }
    pub(crate) fn interrupt_after(step: Step, scope: FaultScope) -> Self {
        Self {
            kind: Kind::InterruptAfter,
            ..Self::fail(step, scope)
        }
    }
    /// The same fault after `passes` calls of its step in scope have gone through.
    pub(crate) fn after(self, passes: usize) -> Self {
        Self { passes, ..self }
    }
}
struct Armed {
    fault: Fault,
    thread: std::thread::ThreadId,
    passed: usize,
}
#[derive(Default)]
struct Switch(std::sync::Mutex<Option<Armed>>);
impl Switch {
    /// The kind of the armed fault when this call of `step` meets it.
    fn meets(&self, step: Step) -> Option<Kind> {
        let mut armed = self.0.lock().unwrap_or_else(|p| p.into_inner());
        let armed = armed.as_mut()?;
        if armed.fault.step != step
            || (armed.fault.scope == FaultScope::ArmingThread
                && armed.thread != std::thread::current().id())
        {
            return None;
        }
        if armed.passed < armed.fault.passes {
            armed.passed += 1;
            return None;
        }
        Some(armed.fault.kind)
    }
    fn run<T>(&self, step: Step, real: impl FnOnce() -> std::io::Result<T>) -> std::io::Result<T> {
        match self.meets(step) {
            None => real(),
            Some(Kind::Fail) => Err(std::io::Error::other("file fake: armed fault")),
            Some(Kind::InterruptBefore) => panic!("simulated process interruption before {step:?}"),
            Some(Kind::InterruptAfter) => {
                let _ = real();
                panic!("simulated process interruption after {step:?}")
            }
        }
    }
}
/// The test fake of the file port: the disk, until a test arms a fault; then the fault acts
/// at its step until the test disarms it.
#[derive(Default)]
pub(crate) struct FaultyFiles {
    switch: Arc<Switch>,
}
impl FaultyFiles {
    pub(crate) fn new() -> Arc<Self> {
        Arc::default()
    }
    pub(crate) fn arm(&self, fault: Fault) {
        *self.switch.0.lock().unwrap_or_else(|p| p.into_inner()) = Some(Armed {
            fault,
            thread: std::thread::current().id(),
            passed: 0,
        });
    }
    pub(crate) fn disarm(&self) {
        *self.switch.0.lock().unwrap_or_else(|p| p.into_inner()) = None;
    }
    /// Runs `action` with `fault` armed, and disarms it after, also when `action` panics.
    pub(crate) fn during<T>(&self, fault: Fault, action: impl FnOnce() -> T) -> T {
        struct Disarm<'a>(&'a FaultyFiles);
        impl Drop for Disarm<'_> {
            fn drop(&mut self) {
                self.0.disarm();
            }
        }
        self.arm(fault);
        let _disarm = Disarm(self);
        action()
    }
}
/// The separate file fakes of a station fixture: a fault armed on one never reaches the
/// files of another.
#[derive(Clone)]
pub(crate) struct StationFiles {
    pub(crate) store: Arc<FaultyFiles>,
    pub(crate) logbook: Arc<FaultyFiles>,
    pub(crate) recording: Arc<FaultyFiles>,
}
impl StationFiles {
    pub(crate) fn new() -> Self {
        Self {
            store: FaultyFiles::new(),
            logbook: FaultyFiles::new(),
            recording: FaultyFiles::new(),
        }
    }
}
struct FaultyWriter {
    file: Box<dyn Writer>,
    switch: Arc<Switch>,
}
impl Writer for FaultyWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<()> {
        let file = &mut self.file;
        self.switch.run(Step::Write, || file.write(bytes))
    }
    fn flush(&mut self) -> std::io::Result<()> {
        let file = &mut self.file;
        self.switch.run(Step::Flush, || file.flush())
    }
}
impl Files for FaultyFiles {
    fn create(&self, path: &Path, open: Open) -> std::io::Result<Box<dyn Writer>> {
        let file = self.switch.run(Step::Create, || Disk.create(path, open))?;
        Ok(Box::new(FaultyWriter {
            file,
            switch: self.switch.clone(),
        }))
    }
    fn replace(&self, from: &Path, to: &Path) -> std::io::Result<()> {
        self.switch.run(Step::Replace, || Disk.replace(from, to))
    }
    fn remove(&self, path: &Path) -> std::io::Result<()> {
        self.switch.run(Step::Remove, || Disk.remove(path))
    }
    fn list(&self, directory: &Path) -> std::io::Result<Vec<std::io::Result<Entry>>> {
        self.switch.run(Step::List, || Disk.list(directory))
    }
    fn id(&self) -> std::io::Result<String> {
        self.switch.run(Step::Id, || Disk.id())
    }
}
fn independent_document() -> ProfileDocument {
    serde_json::from_str(r#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-000000000001","revision":0,"display_name":"Station 1","callsign":"TEST1","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard","audio":{"input_device":"fixture-input-1","output_device":"fixture-output-1"},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}}"#).unwrap()
}

// An expected private authorization record cannot be silently reset.
#[test]
fn expected_authorization_corruption_blocks_profile_startup_without_rewriting_files() {
    for record in [None, Some(b"{corrupt".as_slice())] {
        let directory =
            std::env::temp_dir().join(format!("wstx-auth-startup-{}", new_uuid().unwrap()));
        Store::create(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
        let (store, _) =
            Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
        let profile_id = store.document.profile_id.clone();
        drop(store);
        let original = fs::read(directory.join("profile.json")).unwrap();
        let marker = format!(r#"{{"schema_version":1,"profile_id":"{profile_id}"}}"#);
        fs::write(directory.join(".authorization-initialized.json"), &marker).unwrap();
        if let Some(bytes) = record {
            fs::write(directory.join("authorization.json"), bytes).unwrap();
        }
        let attempted = Store::open(&directory, std::sync::Arc::new(crate::profile::Disk));
        let rejected = matches!(attempted, Err(e) if e == outcome("resource_unavailable"));
        drop(attempted);
        assert_eq!(fs::read(directory.join("profile.json")).unwrap(), original);
        assert_eq!(
            fs::read(directory.join(".authorization-initialized.json")).unwrap(),
            marker.as_bytes()
        );
        if let Some(bytes) = record {
            assert_eq!(
                fs::read(directory.join("authorization.json")).unwrap(),
                bytes
            );
        } else {
            assert!(!directory.join("authorization.json").exists());
        }
        fs::remove_dir_all(directory).unwrap();
        assert!(
            rejected,
            "startup accepted a missing/corrupt expected authorization record"
        );
    }
}

// Proves: TC-022-001
#[test]
fn exact_nullable_schema_rejects_omission_duplicates_and_unknown_keys() {
    let raw = serde_json::to_string(&independent_document()).unwrap();
    for bad in [
        raw.replace("\"origin\":null", "\"extra\":null"),
        raw.replace("\"revision\":0", "\"revision\":0,\"revision\":0"),
        raw.replace("\"mode\":\"disabled\",", ""),
        raw.replace("\"endpoint\":null,", ""),
        raw.replace("\"input_device\":\"fixture-input-1\",", ""),
        raw.replace(
            "\"output_device\":\"fixture-output-1\"",
            "\"unexpected\":null",
        ),
    ] {
        assert!(serde_json::from_str::<ProfileDocument>(&bad).is_err());
    }
}

// Proves: TC-022-001
#[test]
fn settings_validation_uses_utf8_bytes_and_independent_audio_control_domains() {
    let mut settings = independent_document().settings();
    for valid in ["JN47", "AA00AA", "RR99XX99", ""] {
        settings.locator = valid.into();
        assert!(settings.validate().is_ok());
    }
    for invalid in ["SN47", "JN47YY", "JN47AA9", "jn47", "A000"] {
        settings.locator = invalid.into();
        assert_eq!(settings.validate(), Err("locator"));
    }
    settings.locator.clear();
    settings.display_name = "é".repeat(32);
    assert!(settings.validate().is_ok());
    settings.display_name.push('x');
    assert_eq!(settings.validate(), Err("display_name"));
    settings.display_name = "Station 1".into();
    settings.audio.input_device = None;
    settings.audio.output_device = None;
    assert!(
        settings.validate().is_ok(),
        "audio unspecified with CAT disabled is valid"
    );
    settings.control.mode = "cat".into();
    settings.control.endpoint = Some("fixture-cat-1".into());
    settings.control.ptt = "cat".into();
    assert!(
        settings.validate().is_ok(),
        "CAT intent does not require audio selection"
    );
    settings.control.mode = "disabled".into();
    settings.control.endpoint = None;
    assert_eq!(settings.validate(), Err("control.ptt"));
}

// Proves: TC-022-002, TC-022-003
#[test]
fn storage_commit_point_and_os_ownership_survive_reopen() {
    let directory = std::env::temp_dir().join(format!("wstx-profile-unit-{}", new_uuid().unwrap()));
    Store::create(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    let (mut store, _) =
        Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    assert!(
        matches!(Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)), Err(e) if e == outcome("profile_in_use"))
    );
    let old = fs::read(directory.join("profile.json")).unwrap();
    // Stop at the actual production write/flush boundary, before replacement.
    // A complete, synced candidate temp MUST NOT be promoted on restart.
    let mut candidate = store.document.clone();
    candidate.revision = 1;
    candidate.display_name = "Uncommitted".into();
    write_document(&Disk, &directory.join(".interrupted.tmp"), &candidate).unwrap();
    drop(store);
    let (recovered, _) =
        Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    assert_eq!(recovered.document.revision, 0);
    assert_eq!(fs::read(directory.join("profile.json")).unwrap(), old);
    store = recovered;
    let mut edited = independent_document().settings();
    edited.display_name = "Committed".into();
    store.save(edited.clone()).unwrap();
    drop(store);
    let (restored, _) = Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    assert_eq!(restored.document.revision, 1);
    assert_eq!(restored.document.settings(), edited);
    assert_ne!(fs::read(directory.join("profile.json")).unwrap(), old);
    drop(restored);
    fs::remove_dir_all(directory).unwrap();
}

// Proves: TC-022-002
#[test]
fn save_failures_and_interruptions_preserve_the_defined_commit_point() {
    for stage in [
        "write",
        "flush",
        "replace",
        "before_replace",
        "after_replace",
    ] {
        let directory =
            std::env::temp_dir().join(format!("wstx-profile-fault-{}", new_uuid().unwrap()));
        let files = FaultyFiles::new();
        Store::create(&directory, files.clone()).unwrap();
        let (mut store, _) = Store::open(&directory, files.clone()).unwrap();
        let original = fs::read(directory.join("profile.json")).unwrap();
        let original_settings = store.document.settings();
        let mut edit = original_settings.clone();
        edit.display_name = "Committed after replacement".into();
        let scope = FaultScope::ArmingThread;
        files.arm(match stage {
            "write" => Fault::fail(Step::Write, scope),
            "flush" => Fault::fail(Step::Flush, scope),
            "replace" => Fault::fail(Step::Replace, scope),
            "before_replace" => Fault::interrupt_before(Step::Replace, scope),
            _ => Fault::interrupt_after(Step::Replace, scope),
        });
        let result =
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| store.save(edit.clone())));
        files.disarm();
        if matches!(stage, "before_replace" | "after_replace") {
            assert!(result.is_err());
        } else {
            assert!(result.unwrap().is_err());
        }
        assert_eq!(
            store.document.revision, 0,
            "no incomplete save published to memory"
        );
        assert_eq!(store.document.settings(), original_settings);
        drop(store);
        let (recovered, _) =
            Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
        if stage == "after_replace" {
            assert_eq!(recovered.document.revision, 1);
            assert_eq!(recovered.document.settings(), edit);
        } else {
            assert_eq!(fs::read(directory.join("profile.json")).unwrap(), original);
            assert_eq!(recovered.document.revision, 0);
            assert_eq!(recovered.document.settings(), original_settings);
        }
        drop(recovered);
        fs::remove_dir_all(directory).unwrap();
    }
}

fn native_document() -> serde_json::Value {
    let mut value = serde_json::to_value(independent_document()).unwrap();
    value["schema_version"] = 2.into();
    value["connection_type"] = "native_flex".into();
    value["audio"] = serde_json::json!({"input_device":null,"output_device":null});
    value["control"] = serde_json::json!({"mode":"disabled","endpoint":null,"ptt":"disabled"});
    value.as_object_mut().unwrap().remove("radio");
    value["native"] =
        serde_json::json!({"client_id":"72e8c7f3-5766-4ade-9286-ebf2f525c77a","rx_antenna":"ANT1"});
    value
}

// The native intent is a separate schema-2 document without a radio
// identity; standard schema-1 bytes, refusals and the absence of a runtime handle are preserved.
// Proves: TC-022-002, TC-023-007
#[test]
fn native_schema_two_document_is_exact_and_standard_schema_one_is_unchanged() {
    let accept = |value: &serde_json::Value| {
        serde_json::from_value::<ProfileDocument>(value.clone())
            .map_err(|_| outcome("invalid_profile"))
            .and_then(|d| d.validate().map(|_| d))
    };
    let native = accept(&native_document()).unwrap();
    let mut located = native_document();
    located["native"]["radio_address"] = "192.0.2.10:4992".into();
    assert_eq!(
        serde_json::to_value(accept(&located).unwrap()).unwrap(),
        located,
        "a saved address round-trips"
    );
    assert_eq!(serde_json::to_value(&native).unwrap(), native_document());
    let standard = serde_json::to_value(independent_document()).unwrap();
    assert!(
        standard.get("native").is_none(),
        "standard bytes gain no key"
    );
    let mut cases = Vec::new();
    let mut with = |change: &dyn Fn(&mut serde_json::Value), expected: &'static str| {
        let mut value = native_document();
        change(&mut value);
        cases.push((value, expected));
    };
    with(
        &|v| v["native"] = serde_json::Value::Null,
        "invalid_profile",
    );
    for transient in ["radio_serial", "slice_index", "stream_id"] {
        let key = transient.to_owned();
        with(&move |v| v["native"][&key] = "1".into(), "invalid_profile");
    }
    with(
        &|v| v["native"]["client_id"] = "00000000-0000-4000-8000-0000000000C1".into(),
        "invalid_profile",
    );
    with(
        &|v| v["native"]["rx_antenna"] = "ant1".into(),
        "invalid_profile",
    );
    with(
        &|v| v["audio"]["input_device"] = "X".into(),
        "invalid_profile",
    );
    with(
        &|v| v["native"]["radio_address"] = serde_json::Value::Null,
        "invalid_profile",
    );
    for bad in [
        "radio.local:4992",
        "192.0.2.10",
        "192.0.2.10:0",
        "[::1]:4992",
    ] {
        with(
            &move |v| v["native"]["radio_address"] = bad.into(),
            "invalid_profile",
        );
    }
    with(&|v| v["control"]["mode"] = "cat".into(), "invalid_profile");
    with(
        &|v| v["connection_type"] = "standard".into(),
        "invalid_profile",
    );
    with(
        &|v| v["schema_version"] = 1.into(),
        "unsupported_connection_type",
    );
    with(&|v| v["schema_version"] = 3.into(), "unsupported_schema");
    with(
        &|v| {
            v.as_object_mut().unwrap().remove("native");
        },
        "unsupported_schema",
    );
    for (value, expected) in cases {
        assert_eq!(accept(&value).err(), Some(outcome(expected)), "{value}");
    }
    let mut legacy = standard.clone();
    legacy["connection_type"] = "native_flex".into();
    assert_eq!(
        accept(&legacy).err(),
        Some(outcome("unsupported_connection_type"))
    );
    let mut extra = standard;
    extra["native"] = native_document()["native"].clone();
    assert_eq!(accept(&extra).err(), Some(outcome("invalid_profile")));
    let settings = native.settings();
    assert_eq!(settings.validate_native(), Ok(()));
    let mut device = settings.clone();
    device.audio.input_device = Some("X".into());
    assert_eq!(device.validate_native(), Err("audio.input_device"));
    let mut cat = settings;
    cat.control.ptt = "cat".into();
    assert_eq!(cat.validate_native(), Err("control.ptt"));
}

// Creation persists only the intent and a fresh client identity, and
// no writer can give the native profile a device or CAT selection afterwards.
// Proves: TC-023-007
#[test]
fn native_profile_creation_persists_intent_without_runtime_handles() {
    let directory = std::env::temp_dir().join(format!("wstx-native-{}", new_uuid().unwrap()));
    assert_eq!(
        Store::create_native(
            &directory,
            "ant 1",
            None,
            std::sync::Arc::new(crate::profile::Disk)
        ),
        Err(outcome("invalid_runtime_configuration"))
    );
    assert!(!directory.exists());
    assert_eq!(
        Store::create_native(
            &directory,
            "ANT1",
            Some("radio.local:4992"),
            std::sync::Arc::new(crate::profile::Disk)
        ),
        Err(outcome("invalid_runtime_configuration"))
    );
    Store::create_native(
        &directory,
        "ANT1",
        None,
        std::sync::Arc::new(crate::profile::Disk),
    )
    .unwrap();
    let text = fs::read_to_string(directory.join("profile.json")).unwrap();
    let (mut store, _) =
        Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    let native = store.document.native.clone().unwrap();
    assert_eq!(native.rx_antenna, "ANT1");
    assert!(valid_uuid(&native.client_id));
    for transient in ["serial", "slice", "stream", "handle", "dax", "frequency"] {
        assert!(!text.contains(transient), "{transient} persisted");
    }
    let mut settings = store.document.settings();
    settings.audio.output_device = Some("X".into());
    assert!(store.save(settings).is_err());
    assert_eq!(
        fs::read_to_string(directory.join("profile.json")).unwrap(),
        text
    );
    drop(store);
    fs::remove_dir_all(&directory).unwrap();
    // The one supported way to set the address reaches the session's intent.
    Store::create_native(
        &directory,
        "ANT1",
        Some("192.0.2.10:4992"),
        std::sync::Arc::new(crate::profile::Disk),
    )
    .unwrap();
    let (store, _) = Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    let located = store.document.native.clone().unwrap();
    assert_eq!(located.radio_address.as_deref(), Some("192.0.2.10:4992"));
    assert_eq!(
        located.intent().radio_address,
        Some("192.0.2.10:4992".parse().unwrap())
    );
    drop(store);
    fs::remove_dir_all(directory).unwrap();
}

// A missing folder, a settings value outside its rule in the file, a managed radio without its
// radio settings and a lock that cannot be taken refuse the open; the open makes and changes no
// file.
// Proves: TC-022-002
#[test]
fn an_open_it_cannot_carry_out_is_refused_and_changes_no_file() {
    let missing =
        std::env::temp_dir().join(format!("wstx-profile-missing-{}", new_uuid().unwrap()));
    assert!(
        matches!(Store::open(&missing, std::sync::Arc::new(crate::profile::Disk)), Err(e) if e == outcome("resource_unavailable"))
    );
    assert!(!missing.exists(), "an open makes no folder");
    let directory =
        std::env::temp_dir().join(format!("wstx-profile-refused-{}", new_uuid().unwrap()));
    fs::create_dir(&directory).unwrap();
    let file = directory.join("profile.json");
    let mut nameless = serde_json::to_value(independent_document()).unwrap();
    nameless["display_name"] = "".into();
    let bytes = serde_json::to_vec(&nameless).unwrap();
    fs::write(&file, &bytes).unwrap();
    assert!(
        matches!(Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)), Err(e) if e == outcome("invalid_profile"))
    );
    assert_eq!(fs::read(&file).unwrap(), bytes);
    let mut managed = serde_json::to_value(independent_document()).unwrap();
    managed["control"] = serde_json::json!({"mode":"cat","endpoint":"COM3","ptt":"cat"});
    let bytes = serde_json::to_vec(&managed).unwrap();
    fs::write(&file, &bytes).unwrap();
    assert!(
        matches!(Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)), Err(e) if e == outcome("invalid_profile")),
        "a managed radio without radio"
    );
    assert_eq!(fs::read(&file).unwrap(), bytes);
    let valid = serde_json::to_vec(&independent_document()).unwrap();
    fs::write(&file, &valid).unwrap();
    fs::create_dir(directory.join(".profile.lock")).unwrap();
    assert!(
        matches!(Store::open(&directory, std::sync::Arc::new(crate::profile::Disk)), Err(e) if e == outcome("resource_unavailable"))
    );
    assert_eq!(fs::read(&file).unwrap(), valid);
    fs::remove_dir_all(directory).unwrap();
    // The same document with control disabled opens without radio.
    let unmanaged =
        std::env::temp_dir().join(format!("wstx-profile-unmanaged-{}", new_uuid().unwrap()));
    fs::create_dir(&unmanaged).unwrap();
    fs::write(unmanaged.join("profile.json"), &valid).unwrap();
    let (store, _) = Store::open(&unmanaged, std::sync::Arc::new(crate::profile::Disk)).unwrap();
    assert!(store.document.radio.is_none());
    drop(store);
    assert_eq!(fs::read(unmanaged.join("profile.json")).unwrap(), valid);
    fs::remove_dir_all(unmanaged).unwrap();
}

// A creation whose file cannot be written ends with resourceUnavailable and leaves no
// profile.json.
// Proves: TC-022-002
#[test]
fn a_creation_whose_file_cannot_be_written_is_resource_unavailable() {
    for native in [false, true] {
        let directory =
            std::env::temp_dir().join(format!("wstx-profile-unwritten-{}", new_uuid().unwrap()));
        let files = FaultyFiles::new();
        let created = files.during(Fault::fail(Step::Write, FaultScope::ArmingThread), || {
            if native {
                Store::create_native(&directory, "ANT1", None, files.clone())
            } else {
                Store::create(&directory, files.clone())
            }
        });
        assert_eq!(
            created,
            Err(outcome("resource_unavailable")),
            "native {native}"
        );
        assert!(!directory.join("profile.json").exists(), "native {native}");
        let _ = fs::remove_dir_all(&directory);
    }
}

// A document whose write fails leaves no temporary file beside it and no document.
#[test]
fn a_failed_write_of_a_document_leaves_no_temporary_file() {
    let directory = std::env::temp_dir().join(format!("wstx-profile-tmp-{}", new_uuid().unwrap()));
    fs::create_dir(&directory).unwrap();
    let files = FaultyFiles::new();
    let written = files.during(Fault::fail(Step::Write, FaultScope::ArmingThread), || {
        atomic_json(
            &*files,
            &directory,
            "document.json",
            &serde_json::json!({"v":1}),
        )
    });
    assert!(written.is_err());
    let temporary: Vec<String> = fs::read_dir(&directory)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".tmp"))
        .collect();
    assert!(temporary.is_empty(), "temporary files left: {temporary:?}");
    assert!(!directory.join("document.json").exists());
    fs::remove_dir_all(&directory).unwrap();
}

// A save of a native profile is refused with the first device or radio control value it holds.
// Proves: TC-023-007
#[test]
fn a_native_save_names_each_device_and_radio_control_value() {
    let native = serde_json::from_value::<ProfileDocument>(native_document())
        .unwrap()
        .settings();
    type Change = (&'static str, fn(&mut Settings));
    let cases: [Change; 5] = [
        ("audio.input_device", |s: &mut Settings| {
            s.audio.input_device = Some("X".into())
        }),
        ("audio.output_device", |s: &mut Settings| {
            s.audio.output_device = Some("X".into())
        }),
        ("control.mode", |s: &mut Settings| {
            s.control.mode = "cat".into()
        }),
        ("control.endpoint", |s: &mut Settings| {
            s.control.endpoint = Some("COM3".into())
        }),
        ("control.ptt", |s: &mut Settings| {
            s.control.ptt = "cat".into()
        }),
    ];
    for (field, edit) in cases {
        let mut settings = native.clone();
        edit(&mut settings);
        assert_eq!(settings.validate_native(), Err(field));
    }
}
