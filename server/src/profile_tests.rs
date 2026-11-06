use super::*;
use std::cell::Cell;

thread_local! { static FAULT: Cell<Option<&'static str>> = const { Cell::new(None) }; }

pub(crate) fn with_fault<T>(stage: &'static str, action: impl FnOnce() -> T) -> T {
    struct Restore(Option<&'static str>);
    impl Drop for Restore {
        fn drop(&mut self) {
            FAULT.set(self.0);
        }
    }
    let _restore = Restore(FAULT.replace(Some(stage)));
    action()
}

// Test-only I/O/crash seam: no configuration or fault switch exists in the binary.
pub(super) fn checkpoint(stage: &'static str) -> std::io::Result<()> {
    if FAULT.get() == Some(stage) {
        assert!(
            !matches!(stage, "before_replace" | "after_replace"),
            "simulated process interruption"
        );
        return Err(std::io::Error::other("injected storage failure"));
    }
    Ok(())
}

fn independent_document() -> Document {
    serde_json::from_str(r#"{"schema_version":1,"profile_id":"00000000-0000-4000-8000-000000000001","revision":0,"display_name":"Station 1","callsign":"TEST1","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard","audio":{"input_device":"fixture-input-1","output_device":"fixture-output-1"},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}}"#).unwrap()
}

// CL-022-02: an expected private authorization record cannot be silently reset.
// This uses only the preexisting Store API so the unchanged parent compiles and
// fails on its actual accepted startup, rather than a missing new module/API.
#[test]
fn expected_authorization_corruption_blocks_profile_startup_without_rewriting_files() {
    for record in [None, Some(b"{corrupt".as_slice())] {
        let directory =
            std::env::temp_dir().join(format!("wstx-auth-startup-{}", new_uuid().unwrap()));
        Store::create(&directory).unwrap();
        let (store, _) = Store::open(&directory).unwrap();
        let profile_id = store.document.profile_id.clone();
        drop(store);
        let original = fs::read(directory.join("profile.json")).unwrap();
        let marker = format!(r#"{{"schema_version":1,"profile_id":"{profile_id}"}}"#);
        fs::write(directory.join(".authorization-initialized.json"), &marker).unwrap();
        if let Some(bytes) = record {
            fs::write(directory.join("authorization.json"), bytes).unwrap();
        }
        let attempted = Store::open(&directory);
        let rejected = matches!(attempted, Err("resource_unavailable"));
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

// Proves: FR-001, FR-016; CL-005-02, CL-005-05; TC-022-001, TC-022-002.
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
        assert!(serde_json::from_str::<Document>(&bad).is_err());
    }
}

// Proves: FR-001, FR-022; CL-005-02, CL-005-05; TC-022-001.
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

// Proves: FR-022; CL-005-02, CL-005-04; TC-022-002, TC-022-003.
#[test]
fn storage_commit_point_and_os_ownership_survive_reopen() {
    let directory = std::env::temp_dir().join(format!("wstx-profile-unit-{}", new_uuid().unwrap()));
    Store::create(&directory).unwrap();
    let (mut store, _) = Store::open(&directory).unwrap();
    assert!(matches!(Store::open(&directory), Err("profile_in_use")));
    let old = fs::read(directory.join("profile.json")).unwrap();
    // Stop at the actual production write/flush boundary, before replacement.
    // A complete, synced candidate temp MUST NOT be promoted on restart.
    let mut candidate = store.document.clone();
    candidate.revision = 1;
    candidate.display_name = "Uncommitted".into();
    write_document(&directory.join(".interrupted.tmp"), &candidate).unwrap();
    drop(store);
    let (recovered, _) = Store::open(&directory).unwrap();
    assert_eq!(recovered.document.revision, 0);
    assert_eq!(fs::read(directory.join("profile.json")).unwrap(), old);
    store = recovered;
    let mut edited = independent_document().settings();
    edited.display_name = "Committed".into();
    store.save(edited.clone()).unwrap();
    drop(store);
    let (restored, _) = Store::open(&directory).unwrap();
    assert_eq!(restored.document.revision, 1);
    assert_eq!(restored.document.settings(), edited);
    assert_ne!(fs::read(directory.join("profile.json")).unwrap(), old);
    drop(restored);
    fs::remove_dir_all(directory).unwrap();
}

// Proves: FR-016, FR-022; CL-005-02, CL-005-04; TC-022-002.
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
        Store::create(&directory).unwrap();
        let (mut store, _) = Store::open(&directory).unwrap();
        let original = fs::read(directory.join("profile.json")).unwrap();
        let original_settings = store.document.settings();
        let mut edit = original_settings.clone();
        edit.display_name = "Committed after replacement".into();
        FAULT.set(Some(stage));
        let result =
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| store.save(edit.clone())));
        FAULT.set(None);
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
        let (recovered, _) = Store::open(&directory).unwrap();
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

// Proves: TC-023-002. The native intent is a separate schema-2 document without a radio
// identity; standard schema-1 bytes, refusals and the absence of a runtime handle are preserved.
#[test]
fn native_schema_two_document_is_exact_and_standard_schema_one_is_unchanged() {
    let accept = |value: &serde_json::Value| {
        serde_json::from_value::<Document>(value.clone())
            .map_err(|_| "invalid_profile")
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
        assert_eq!(accept(&value).err(), Some(expected), "{value}");
    }
    let mut legacy = standard.clone();
    legacy["connection_type"] = "native_flex".into();
    assert_eq!(accept(&legacy).err(), Some("unsupported_connection_type"));
    let mut extra = standard;
    extra["native"] = native_document()["native"].clone();
    assert_eq!(accept(&extra).err(), Some("invalid_profile"));
    let settings = native.settings();
    assert_eq!(settings.validate_native(), Ok(()));
    let mut device = settings.clone();
    device.audio.input_device = Some("X".into());
    assert_eq!(device.validate_native(), Err("audio.input_device"));
    let mut cat = settings;
    cat.control.ptt = "cat".into();
    assert_eq!(cat.validate_native(), Err("control.ptt"));
}

// Proves: TC-023-002. Creation persists only the intent and a fresh client identity, and
// no writer can give the native profile a device or CAT selection afterwards.
#[test]
fn native_profile_creation_persists_intent_without_runtime_handles() {
    let directory = std::env::temp_dir().join(format!("wstx-native-{}", new_uuid().unwrap()));
    assert_eq!(
        Store::create_native(&directory, "ant 1", None),
        Err("invalid_runtime_configuration")
    );
    assert!(!directory.exists());
    assert_eq!(
        Store::create_native(&directory, "ANT1", Some("radio.local:4992")),
        Err("invalid_runtime_configuration")
    );
    Store::create_native(&directory, "ANT1", None).unwrap();
    let text = fs::read_to_string(directory.join("profile.json")).unwrap();
    let (mut store, _) = Store::open(&directory).unwrap();
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
    fs::remove_dir_all(directory).unwrap();
}
