use super::*;
use std::cell::Cell;

thread_local! { static FAULT: Cell<Option<&'static str>> = const { Cell::new(None) }; }

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
