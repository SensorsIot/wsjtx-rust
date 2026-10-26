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

// TC-009-002 query-only probe. The external keying prerequisite is checked before any UART open.
#[test]
#[ignore = "Coordinator requires verified USB SEND/CW/RTTY inhibit before selecting this hardware probe"]
fn inhibited_ic7300_frequency_query_evidence() {
    assert_eq!(
        std::env::var("WSTX_RX_ONLY_INHIBIT_VERIFIED").as_deref(),
        Ok("USB_SEND_CW_RTTY_OFF"),
        "coordinator must independently verify keying inhibit"
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
        let observation = actor.execute(Request {
            authority: ready.authority.clone(),
            request_id: "frequency-probe".into(),
            operation: Operation::ReadFrequency,
            deadline: Instant::now() + Duration::from_secs(2),
            cancelled: Arc::new(AtomicBool::new(false)),
        })?;
        Ok(
            serde_json::json!({"probe":"ic7300_receive_only_frequency","device_id":ready.authority.resource_id,"effective_baud":ready.effective_baud,"frequency_hz":observation.frequency_hz,"requested_operation":"read_frequency","setters_sent":false,"transmit_requested":false}),
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
    assert!(
        result.unwrap()["frequency_hz"]
            .as_u64()
            .is_some_and(|v| v > 0)
    );
}
