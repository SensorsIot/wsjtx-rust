#![forbid(unsafe_code)]
// Proves: CL-009-03, CL-009-04; TC-008-003. The actual station transmit owner with the
// automatic CL-022 lifecycle and an independent scripted CI-V peer; wire strictness of
// WstxTransmit::TransmitWire on the actual router.
use super::*;
use crate::cat_lifecycle::{Gate, Key};
use crate::cat_lifecycle_tests::{Device, ENDPOINT, attach_peer};
use axum::body::Body;
use tower::ServiceExt;
use wstx_rust::radio_control as cat;
use wstx_rust::transmit::service::{ArmState, Capability, OutcomeKind};

fn document(id: &str, ptt: &str, output: Option<&str>) -> profile::Document {
    serde_json::from_value(json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Transmit fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":output},"control":{"mode":"cat","endpoint":ENDPOINT,"ptt":ptt}}))
    .unwrap()
}
fn gate(revision: u64) -> Gate {
    Gate::Eligible {
        key: Key {
            radio_id: "00000000-0000-4000-8000-0000000000aa".into(),
            safety_revision: revision,
            profile_revision: 0,
            endpoint: ENDPOINT.into(),
        },
        configuration: cat::Configuration::parse(ENDPOINT).unwrap(),
    }
}
fn ptt_setters(writes: &[Vec<u8>]) -> usize {
    writes
        .iter()
        .filter(|w| w.len() == 8 && w[4] == 0x1c && w[5] == 0)
        .count()
}

#[test]
fn automatic_lifecycle_with_a_transmit_owner_never_emits_ptt_and_no_output_means_no_key() {
    let directory =
        std::env::temp_dir().join(format!("wstx-transmit-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir_all(&directory).unwrap();
    let id = profile::new_uuid().unwrap();
    let recording =
        recording::Recording::open(&directory, id.clone(), profile::new_uuid().unwrap());
    let peer = attach_peer(&recording, Device::Present);
    let station = transmit_http::Station::start().unwrap();
    let _ = recording.transmit.set(station.clone());
    // Receive-only commissioning (PTT disabled) is not transmit capability.
    let receive_only = document(&id, "disabled", Some("fixture-output"));
    let configured = document(
        &id,
        "cat",
        Some("{0.0.0.00000000}.{00000000-0000-0000-0000-000000000000}"),
    );
    let g = gate(3);
    let start = Instant::now();
    let tick = |doc: &profile::Document| {
        recording.cat_maintain(&g, Instant::now());
        station.update(doc, &g, recording.radio_actor());
        std::thread::sleep(Duration::from_millis(50));
    };
    while start.elapsed() < Duration::from_millis(1_500) {
        tick(&receive_only);
    }
    assert_eq!(station.service.view().capability, Capability::Unsupported);
    assert_eq!(
        station.service.with(|c| c.arm(3)),
        Err(wstx_rust::transmit::service::TransmitRefusal::TransmitUnsupported)
    );
    while start.elapsed() < Duration::from_millis(3_000) {
        tick(&configured);
    }
    let v = station.service.view();
    assert_eq!(
        (v.capability, v.arm_state),
        (Capability::Available, ArmState::Disarmed)
    );
    assert_eq!(
        ptt_setters(&peer.lock().unwrap().writes),
        0,
        "lifecycle/disarmed owner keyed"
    );
    // A radio in receive at boot: the safety release is not needed and sends nothing.
    assert_eq!(
        station.service.view().startup_release,
        wstx_rust::transmit::service::StartupRelease::NotNeeded
    );
    assert!(
        peer.lock().unwrap().writes.len() >= 5,
        "the read-only lifecycle polled"
    );
    // Armed with the current safety revision, a request whose output device cannot be
    // opened (or whose clock is not synchronized) never keys PTT.
    station.service.with(|c| c.arm(3)).unwrap();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;
    let period = wstx_rust::transmit::next_period(
        decoder::Mode::Ft8,
        now + 500,
        wstx_rust::transmit::parity(decoder::Mode::Ft8, now - now.rem_euclid(15_000)),
    );
    let outcome = station.service.with(|c| {
        c.submit(wstx_rust::transmit::service::Request {
            contact_id: None,
            request_sequence: 1,
            mode: decoder::Mode::Ft8,
            period_start_utc_ms: period,
            message_text: "CQ HB9BLA JN47".into(),
            tx_offset_hz: 1500,
        })
    });
    if outcome.kind == OutcomeKind::Accepted {
        let deadline = Instant::now() + Duration::from_millis((period - now).max(0) as u64 + 1_500);
        while Instant::now() < deadline && station.service.view().arm_state == ArmState::Armed {
            tick(&configured);
        }
    }
    assert_eq!(station.service.view().arm_state, ArmState::Disarmed);
    assert_eq!(ptt_setters(&peer.lock().unwrap().writes), 0);
    if let Some(actor) = recording.radio_actor() {
        actor.request_close();
    }
    drop(station);
    let _ = std::fs::remove_dir_all(&directory);
}

async fn app() -> (Router, String, String, String, std::path::PathBuf) {
    let dir = std::env::temp_dir().join(format!(
        "wstx-transmit-http-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir(&dir).unwrap();
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"Transmit wire",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard",
        "audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (store, _) = profile::Store::open(&dir).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    let _ = recording
        .transmit
        .set(transmit_http::Station::start().unwrap());
    let origin = "http://127.0.0.1:18001".to_string();
    let app = App {
        origin: origin.clone(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            authorization: Mutex::new(None),
            boot: boot.clone(),
            recording,
        })),
        profile_id: Some(id.clone()),
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    (router(app), origin, id, boot, dir)
}
async fn call(
    router: &Router,
    method: &str,
    path: &str,
    origin: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut request = axum::http::Request::builder().method(method).uri(path);
    if let Some(origin) = origin {
        request = request.header(header::ORIGIN, origin);
    }
    let request = match body {
        Some(b) => request
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(serde_json::to_vec(&b).unwrap())),
        None => request.body(Body::empty()),
    }
    .unwrap();
    let response = router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 65536)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
fn object_keys(v: &Value) -> Vec<String> {
    let mut k = v.as_object().unwrap().keys().cloned().collect::<Vec<_>>();
    k.sort();
    k
}

#[tokio::test]
async fn transmit_wire_is_exact_halt_is_always_admitted_and_plaintext_never_arms() {
    let (router, origin, id, boot, dir) = app().await;
    let (status, view) = call(&router, "GET", "/transmit", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        object_keys(&view),
        [
            "boot_id",
            "clock",
            "outcomes",
            "profile_id",
            "ptt",
            "startup_release",
            "transmit",
            "transmitting",
            "v",
            "watchdog"
        ]
    );
    assert_eq!(
        object_keys(&view["transmit"]),
        [
            "arm_state",
            "capability",
            "halt_state",
            "last_disarm_cause",
            "last_period_utc",
            "last_text",
            "pending_sequence",
            "refusal",
            "tune"
        ]
    );
    assert_eq!(view["transmit"]["arm_state"], "disarmed");
    assert_eq!(view["transmit"]["last_disarm_cause"], "startup");
    assert_eq!(view["transmit"]["capability"], "unsupported");
    assert_eq!(
        view["startup_release"], "pending",
        "no CAT readback, no release"
    );
    let command = "00000000-0000-4000-8000-000000000001";
    let halt = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":command});
    let (status, receipt) = call(
        &router,
        "POST",
        "/transmit/halt",
        Some(&origin),
        Some(halt.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(
        receipt,
        json!({"v":1,"command_id":command,"halt_state":"idle"})
    );
    // A halt from an older boot is still a halt.
    let other_boot = json!({"v":1,"profile_id":id,"boot_id":"00000000-0000-4000-8000-0000000000bb","command_id":"00000000-0000-4000-8000-000000000002"});
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/halt",
            Some(&origin),
            Some(other_boot)
        )
        .await
        .0,
        StatusCode::ACCEPTED
    );
    let mut extra = halt.clone();
    extra["force"] = json!(true);
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/halt",
            Some(&origin),
            Some(extra)
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/halt",
            Some("http://evil.example"),
            Some(halt.clone())
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        call(&router, "POST", "/transmit/halt", None, Some(halt))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    // Arm without a CL-022 grant (plaintext profile) is never transmit authority.
    let arm = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":"00000000-0000-4000-8000-000000000003","action":"arm","safety_revision":1});
    let (status, reply) = call(
        &router,
        "POST",
        "/transmit/command",
        Some(&origin),
        Some(arm.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        reply["result"],
        json!({"accepted":false,"refusal":"not_authorized"})
    );
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/command",
            Some(&origin),
            Some(arm.clone())
        )
        .await
        .1,
        reply,
        "same receipt"
    );
    let mut changed = arm.clone();
    changed["safety_revision"] = json!(2);
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/command",
            Some(&origin),
            Some(changed)
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    let request = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":"00000000-0000-4000-8000-000000000004","action":"request",
        "request_sequence":1,"mode":"ft8","period_start_utc_ms":1_800_000_000_000u64,"message_text":"CQ HB9BLA JN47","tx_offset_hz":1500});
    let (_, reply) = call(
        &router,
        "POST",
        "/transmit/command",
        Some(&origin),
        Some(request.clone()),
    )
    .await;
    assert_eq!(reply["result"]["kind"], "refused");
    assert_eq!(reply["result"]["refusal"], "transmit_unsupported");
    let mut stale = request.clone();
    stale["command_id"] = json!("00000000-0000-4000-8000-000000000005");
    stale["boot_id"] = json!("00000000-0000-4000-8000-0000000000bb");
    assert_eq!(
        call(
            &router,
            "POST",
            "/transmit/command",
            Some(&origin),
            Some(stale)
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    for bad in [
        json!({"raw":[28,0,1]}),
        json!({"action":"ptt","enabled":true}),
    ] {
        let mut b = json!({"v":1,"profile_id":id,"boot_id":boot,"command_id":"00000000-0000-4000-8000-000000000006"});
        for (k, v) in bad.as_object().unwrap() {
            b[k] = v.clone();
        }
        assert_eq!(
            call(&router, "POST", "/transmit/command", Some(&origin), Some(b))
                .await
                .0,
            StatusCode::BAD_REQUEST
        );
    }
    let _ = std::fs::remove_dir_all(dir);
}

// Proves: CL-009-04, CL-022-03; TC-008-003. Startup safety release: a radio found
// transmitting by the first fresh readback after boot gets exactly one off-only switch.
#[test]
fn radio_transmitting_at_boot_gets_exactly_one_off_only_release_with_readback() {
    let directory = std::env::temp_dir().join(format!(
        "wstx-transmit-boot-{}",
        profile::new_uuid().unwrap()
    ));
    std::fs::create_dir_all(&directory).unwrap();
    let id = profile::new_uuid().unwrap();
    let recording =
        recording::Recording::open(&directory, id.clone(), profile::new_uuid().unwrap());
    let peer = attach_peer(&recording, Device::Present);
    peer.lock().unwrap().transmitting = true;
    let station = transmit_http::Station::start().unwrap();
    let _ = recording.transmit.set(station.clone());
    // Even a receive-only profile gets the release: it only ever turns RF off.
    let doc = document(&id, "disabled", None);
    let g = gate(3);
    let start = Instant::now();
    while start.elapsed() < Duration::from_millis(3_500) {
        recording.cat_maintain(&g, Instant::now());
        station.update(&doc, &g, recording.radio_actor());
        std::thread::sleep(Duration::from_millis(50));
    }
    let writes = peer.lock().unwrap().writes.clone();
    let off = [0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0, 0, 0xfd];
    let read = [0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0, 0xfd];
    assert_eq!(
        ptt_setters(&writes),
        1,
        "exactly one switch frame: {writes:02x?}"
    );
    let at = writes
        .iter()
        .position(|w| w[..] == off)
        .expect("off-only release");
    assert_eq!(writes[at + 1], read, "release is read back");
    assert!(!peer.lock().unwrap().transmitting);
    assert_eq!(
        station.service.view().startup_release,
        wstx_rust::transmit::service::StartupRelease::Released
    );
    if let Some(actor) = recording.radio_actor() {
        actor.request_close();
    }
    drop(station);
    let _ = std::fs::remove_dir_all(&directory);
}
