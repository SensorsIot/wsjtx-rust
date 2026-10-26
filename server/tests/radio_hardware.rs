#![cfg(windows)]
#[path = "../src/radio_control/mod.rs"]
pub mod radio_control;
use radio_control::{
    actor::Actor,
    catalogue::Catalogue,
    windows::{SerialTransport, resolve_endpoint},
    *,
};
use std::{
    sync::{Arc, atomic::AtomicBool},
    thread,
    time::{Duration, Instant},
};

fn receive_test_authority(
    inhibit: Option<&str>,
    operator: Option<&str>,
) -> Option<(&'static str, &'static str)> {
    if inhibit == Some("USB_SEND_CW_RTTY_OFF") {
        Some(("verified_keying_inhibit", "USB_SEND_CW_RTTY_OFF"))
    } else if operator == Some("UNRESTRICTED_RECEIVE_TEST") {
        Some(("user_explicit_unrestricted", "unverified"))
    } else {
        None
    }
}

#[test]
fn standalone_query_authority_preserves_truthful_keying_evidence() {
    assert_eq!(receive_test_authority(None, None), None);
    assert_eq!(receive_test_authority(None, Some("yes")), None);
    assert_eq!(receive_test_authority(Some("unknown"), None), None);
    assert_eq!(
        receive_test_authority(Some("USB_SEND_CW_RTTY_OFF"), None),
        Some(("verified_keying_inhibit", "USB_SEND_CW_RTTY_OFF"))
    );
    assert_eq!(
        receive_test_authority(None, Some("UNRESTRICTED_RECEIVE_TEST")),
        Some(("user_explicit_unrestricted", "unverified"))
    );
}

// TC-009-002 standalone query-only probe. Test authority is checked before any UART open.
#[test]
#[ignore = "Coordinator explicitly selects operator-authorized receive-only hardware test"]
fn authorized_ic7300_frequency_query_evidence() {
    radio_query_evidence(&[("read_frequency", Operation::ReadFrequency)]);
}
#[test]
#[ignore = "Explicit coordinator-selected sequential receive-only hardware checks"]
fn authorized_ic7300_readonly_inventory_evidence() {
    radio_query_evidence(&[
        ("read_frequency", Operation::ReadFrequency),
        ("read_mode", Operation::ReadMode),
        ("read_data", Operation::ReadData),
        ("read_rx_tx", Operation::ReadRxTx),
        ("read_split", Operation::ReadSplit),
    ]);
}
fn radio_query_evidence(operations: &[(&str, Operation)]) {
    let inhibit = std::env::var("WSTX_RX_ONLY_INHIBIT_VERIFIED").ok();
    let operator = std::env::var("WSTX_OPERATOR_AUTHORIZED_TRANSCEIVER").ok();
    let (authority_basis, keying_configuration) =
        receive_test_authority(inhibit.as_deref(), operator.as_deref()).expect(
            "standalone receive test requires verified inhibit or explicit operator authorization",
        );
    println!(
        "{}",
        serde_json::json!({"probe":"ic7300_receive_only_frequency","authority":authority_basis,"keying_configuration":keying_configuration,"planned_operations":"typed read queries only; no frequency/mode/DATA/PTT setter or audio output"})
    );
    let selected = resolve_endpoint(3).expect("exact COM3 discovery");
    assert_eq!(
        selected.instance_id.to_ascii_uppercase(),
        "USB\\VID_10C4&PID_EA60\\IC-7300_03018727"
    );
    let configuration =
        Configuration::parse("icom7300://COM3?baud=auto&radio=94&controller=E0").unwrap();
    let native_configuration = configuration.clone();
    let lock_root = std::env::temp_dir().join("wstx-radio-probe-ownership");
    let authority = Authority {
        profile_id: "hardware-probe".into(),
        boot_id: format!("probe-{}", std::process::id()),
        profile_revision: 0,
        resource_id: selected.instance_id,
        connection_generation: 1,
    };
    let actor = Actor::begin(
        configuration,
        authority,
        Catalogue::builtin().unwrap(),
        move |deadline, cancel| {
            SerialTransport::open(&native_configuration, &lock_root, deadline, cancel)
        },
    )
    .expect("CAT I/O owner begins");
    let result = (|| -> Result<serde_json::Value> {
        let limit = Instant::now() + Duration::from_secs(6);
        let ready = loop {
            let snapshot = actor.snapshot()?;
            match snapshot.state {
                State::Ready => break snapshot,
                State::Connecting if Instant::now() < limit => {
                    thread::sleep(Duration::from_millis(2))
                }
                _ => return Err(snapshot.last_error.unwrap_or(Error::Timeout)),
            }
        };
        let mut rows = Vec::new();
        for (name, operation) in operations {
            println!("CAT_QUERY_START {name}");
            let measured = actor.execute(Request {
                authority: ready.authority.clone(),
                request_id: format!("probe-{name}"),
                operation: operation.clone(),
                deadline: Instant::now() + Duration::from_secs(2),
                cancelled: Arc::new(AtomicBool::new(false)),
            })?;
            let value = match operation {
                Operation::ReadFrequency => {
                    serde_json::json!({"frequency_hz":measured.frequency_hz})
                }
                Operation::ReadMode => {
                    serde_json::json!({"mode_code":measured.mode.map(|v|format!("{:02X}",v.code)),"filter":measured.mode.map(|v|v.filter)})
                }
                Operation::ReadData => {
                    serde_json::json!({"data":measured.data.map(|v|v.enabled),"data_filter":measured.data.map(|v|v.filter)})
                }
                Operation::ReadRxTx => serde_json::json!({"transmitting":measured.transmitting}),
                Operation::ReadSplit => serde_json::json!({"split":measured.split}),
                _ => return Err(Error::InvalidRequest),
            };
            let row = serde_json::json!({"operation":name,"measured":value});
            println!("{row}");
            rows.push(row);
        }
        Ok(
            serde_json::json!({"probe":"ic7300_receive_only_queries","authority":authority_basis,"keying_configuration":keying_configuration,"device_id":ready.authority.resource_id,"effective_baud":ready.effective_baud,"queries":rows,"setters_sent":false,"transmit_requested":false}),
        )
    })();
    actor.request_close();
    let close_began = Instant::now();
    while !actor.close_complete() && close_began.elapsed() < Duration::from_millis(500) {
        thread::sleep(Duration::from_millis(1));
    }
    let closed = actor.snapshot().unwrap();
    println!(
        "{}",
        serde_json::json!({"result":result.as_ref().ok(),"error":result.as_ref().err().map(|v|format!("{v:?}")),"close_state":format!("{:?}",closed.state),"close_error":closed.last_error.map(|v|format!("{v:?}")),"close_ms":close_began.elapsed().as_millis()})
    );
    assert!(
        actor.close_complete(),
        "native serial ownership release not acknowledged"
    );
    assert_eq!(
        result.unwrap()["queries"].as_array().unwrap().len(),
        operations.len()
    );
}
