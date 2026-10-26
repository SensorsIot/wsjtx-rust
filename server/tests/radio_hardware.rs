#![deny(unsafe_code)]
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
    let (actor, authority_basis, keying_configuration) =
        open_authorized_radio("typed read queries only; no setters or transmit request");
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

fn open_authorized_radio(plan: &str) -> (Actor, &'static str, &'static str) {
    let inhibit = std::env::var("WSTX_RX_ONLY_INHIBIT_VERIFIED").ok();
    let operator = std::env::var("WSTX_OPERATOR_AUTHORIZED_TRANSCEIVER").ok();
    let (authority_basis, keying_configuration) =
        receive_test_authority(inhibit.as_deref(), operator.as_deref()).expect(
            "standalone receive test requires verified inhibit or explicit operator authorization",
        );
    println!(
        "{}",
        serde_json::json!({"probe":"ic7300_receive_only_frequency","authority":authority_basis,"keying_configuration":keying_configuration,"planned_operations":plan})
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
    (actor, authority_basis, keying_configuration)
}

fn receive_phase(restore: bool) -> Operation {
    Operation::ReceiveSetup {
        frequency_hz: 7_074_000,
        mode: if restore {
            Sideband::Lsb
        } else {
            Sideband::Usb
        },
        filter: 1,
        data: !restore,
        data_filter: if restore { 0 } else { 1 },
    }
}
fn radio_request(authority: Authority, operation: Operation) -> Request {
    let seconds = if matches!(operation, Operation::ReceiveSetup { .. }) {
        5
    } else {
        2
    };
    Request {
        authority,
        request_id: "receive-configuration-phase".into(),
        operation,
        deadline: Instant::now() + Duration::from_secs(seconds),
        cancelled: Arc::new(AtomicBool::new(false)),
    }
}
#[test]
#[ignore = "Coordinator prepares USB-D before capture; leaves state until explicit restoration"]
fn authorized_ic7300_prepare_usb_data() {
    receive_configuration_evidence(false)
}
#[test]
#[ignore = "Coordinator restores exact baseline only after audio capture has completed"]
fn authorized_ic7300_restore_lsb_data_off() {
    receive_configuration_evidence(true)
}
fn receive_configuration_evidence(restore: bool) {
    let (actor, authority, keying) = open_authorized_radio(if restore {
        "Restore7074000Hz LSB FIL1 DATAoff0; no PTT/split/audio output"
    } else {
        "Prepare7074000Hz USB FIL1 DATAon1 for audio capture; no PTT/split/audio output; restoration is separate after capture"
    });
    let result = (|| -> Result<serde_json::Value> {
        let limit = Instant::now() + Duration::from_secs(6);
        let ready = loop {
            let snapshot = actor.snapshot()?;
            if snapshot.state == State::Ready {
                break snapshot;
            }
            if snapshot.state != State::Connecting || Instant::now() >= limit {
                return Err(snapshot.last_error.unwrap_or(Error::Timeout));
            }
            thread::sleep(Duration::from_millis(2));
        };
        let mut baseline = Observation::default();
        for operation in [
            Operation::ReadFrequency,
            Operation::ReadMode,
            Operation::ReadData,
            Operation::ReadRxTx,
            Operation::ReadSplit,
        ] {
            baseline = actor.execute(radio_request(ready.authority.clone(), operation))?;
        }
        println!(
            "{}",
            serde_json::json!({"baseline_frequency":baseline.frequency_hz,"baseline_mode":baseline.mode.map(|v|v.code),"baseline_filter":baseline.mode.map(|v|v.filter),"baseline_data":baseline.data.map(|v|v.enabled),"baseline_data_filter":baseline.data.map(|v|v.filter),"baseline_tx":baseline.transmitting,"baseline_split":baseline.split})
        );
        if baseline.frequency_hz != Some(7_074_000)
            || baseline.mode
                != Some(ModeValue {
                    code: u8::from(restore),
                    filter: 1,
                })
            || baseline.data
                != Some(DataValue {
                    enabled: restore,
                    filter: if restore { 1 } else { 0 },
                })
            || baseline.transmitting != Some(false)
            || baseline.split != Some(false)
        {
            return Err(Error::InvalidRequest);
        }
        let measured = actor.execute(radio_request(ready.authority, receive_phase(restore)))?;
        Ok(
            serde_json::json!({"phase":if restore{"restore"}else{"prepare_usb_data"},"authority":authority,"keying_configuration":keying,"frequency_hz":measured.frequency_hz,"mode_code":measured.mode.map(|v|v.code),"filter":measured.mode.map(|v|v.filter),"data":measured.data.map(|v|v.enabled),"data_filter":measured.data.map(|v|v.filter),"ptt_or_split_write":false,"restore_baseline":{"frequency_hz":7074000,"mode":"LSB","filter":1,"data":false,"data_filter":0}}),
        )
    })();
    actor.request_close();
    let limit = Instant::now() + Duration::from_millis(500);
    while !actor.close_complete() && Instant::now() < limit {
        thread::sleep(Duration::from_millis(1));
    }
    println!(
        "{}",
        serde_json::json!({"result":result.as_ref().ok(),"error":result.as_ref().err().map(|e|format!("{e:?}")),"closed":actor.close_complete(),"operator_restoration_needed_if_mutation_unconfirmed":result.is_err(),"automatic_retry":false})
    );
    assert!(actor.close_complete());
    result.unwrap();
}

#[test]
fn usb_data_prepare_and_restore_have_independent_icom_bytes_and_readbacks() {
    use radio_control::executor::{Executor, Transport};
    use std::{collections::VecDeque, sync::Mutex};
    struct Script {
        responses: VecDeque<Vec<u8>>,
        pending: Vec<u8>,
        writes: Arc<Mutex<Vec<Vec<u8>>>>,
    }
    impl Transport for Script {
        fn configure(&mut self, _: u32) -> Result<()> {
            Ok(())
        }
        fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> Result<usize> {
            self.writes.lock().unwrap().push(bytes.to_vec());
            self.pending = self.responses.pop_front().ok_or(Error::Protocol)?;
            Ok(bytes.len())
        }
        fn read(&mut self, bytes: &mut [u8], _: Instant, _: &AtomicBool) -> Result<usize> {
            let count = bytes.len().min(self.pending.len());
            bytes[..count].copy_from_slice(&self.pending[..count]);
            self.pending.drain(..count);
            Ok(count)
        }
        fn quiet(&mut self, _: Instant, _: &AtomicBool) -> Result<()> {
            Ok(())
        }
        fn close(&mut self) -> Result<()> {
            Ok(())
        }
    }
    let frequency = vec![0xfe, 0xfe, 0xe0, 0x94, 3, 0, 0x40, 7, 7, 0, 0xfd];
    let ack = vec![0xfe, 0xfe, 0xe0, 0x94, 0xfb, 0xfd];
    let usb = vec![0xfe, 0xfe, 0xe0, 0x94, 4, 1, 1, 0xfd];
    let lsb = vec![0xfe, 0xfe, 0xe0, 0x94, 4, 0, 1, 0xfd];
    let on = vec![0xfe, 0xfe, 0xe0, 0x94, 0x1a, 6, 1, 1, 0xfd];
    let off = vec![0xfe, 0xfe, 0xe0, 0x94, 0x1a, 6, 0, 0, 0xfd];
    let responses = [
        frequency.clone(),
        ack.clone(),
        usb.clone(),
        ack.clone(),
        on.clone(),
        ack.clone(),
        frequency.clone(),
        usb,
        on,
        frequency.clone(),
        ack.clone(),
        lsb.clone(),
        ack.clone(),
        off.clone(),
        ack,
        frequency.clone(),
        lsb,
        off,
        frequency,
    ];
    let writes = Arc::new(Mutex::new(Vec::new()));
    let authority = Authority {
        profile_id: "fixture".into(),
        boot_id: "fixture".into(),
        profile_revision: 0,
        resource_id: "fixture".into(),
        connection_generation: 1,
    };
    let executor = Executor::connect(
        Script {
            responses: responses.into(),
            pending: Vec::new(),
            writes: writes.clone(),
        },
        Configuration::parse("icom7300://COM3?baud=9600&radio=94&controller=E0").unwrap(),
        authority.clone(),
        Catalogue::builtin().unwrap(),
        &AtomicBool::new(false),
    )
    .unwrap();
    for restore in [false, true] {
        let measured = executor
            .execute(radio_request(authority.clone(), receive_phase(restore)))
            .unwrap();
        assert_eq!(
            measured.mode,
            Some(ModeValue {
                code: u8::from(!restore),
                filter: 1
            })
        );
        assert_eq!(
            measured.data,
            Some(DataValue {
                enabled: !restore,
                filter: if restore { 0 } else { 1 }
            })
        );
        assert_eq!(measured.frequency_hz, Some(7074000));
    }
    let writes = writes.lock().unwrap();
    assert_eq!(writes.len(), 19);
    for (index, body) in [
        (1, vec![6, 1, 1]),
        (3, vec![0x1a, 6, 1, 1]),
        (5, vec![5, 0, 0x40, 7, 7, 0]),
        (10, vec![6, 0, 1]),
        (12, vec![0x1a, 6, 0, 0]),
        (14, vec![5, 0, 0x40, 7, 7, 0]),
    ] {
        assert_eq!(&writes[index][4..writes[index].len() - 1], body);
    }
}
