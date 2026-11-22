use super::*;

// One page kept open while a second page, in its own browser context and on its own socket,
// selects the band the station already receives on, as the live page check does. The driver
// tests/frontend/receive-page-follow.test.cjs holds the oracle. Four inputs: the driver starts
// receive twice (page A starts 20m, page B selects 20m), so two are left to spare.
#[test]
fn live_native_page_follows_another_selection() {
    let dir = std::env::temp_dir().join(format!("wstx-follow-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let listener = wstx_test_tools::ports::first_allowed(
        || std::net::TcpListener::bind("127.0.0.1:0").unwrap(),
        |l| l.local_addr().unwrap().port(),
    );
    let address = listener.local_addr().unwrap();
    let origin = format!("http://{address}");
    let profile_id = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":profile_id,"revision":0,"display_name":"Followed page fixture",
        "callsign":"HB9BLA","locator":"JN37VL","endpoint":{"bind":address.to_string(),"origin":null},"connection_type":"standard",
        "audio":{"input_device":"explicit-test-native-input","output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let boot = KeptPageBoot::start(listener, &dir, &origin, &profile_id, 4);
    let control = dir.join("page-control");
    std::fs::create_dir(&control).unwrap();
    let output = std::fs::File::create(control.join("node.log")).unwrap();
    let status = std::process::Command::new("node")
        .args(["--test", "tests/frontend/receive-page-follow.test.cjs"])
        .current_dir(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap(),
        )
        .env("WSTX_PAGE_ORIGIN", &origin)
        .env("WSTX_PAGE_CONTROL", &control)
        .stdout(output.try_clone().unwrap())
        .stderr(output)
        .status()
        .unwrap();
    let log = std::fs::read_to_string(control.join("node.log")).unwrap();
    boot.stop();
    std::fs::remove_dir_all(dir).unwrap();
    assert!(status.success(), "{log}");
    println!("{log}");
}
