#![forbid(unsafe_code)]
// Proves: CL-044-09; CL-044-10; CL-044-11; TC-044-008; TC-044-009.
// The actual router, Recording owner, CAT lifecycle AGC tick and CAT actor/executor on a
// disposable profile; a scripted IC-7300 on COM3 that echoes each frame. Expected bytes
// are hand-written from the IC-7300 Full Manual section 19 command table ("16 12 AGC":
// 01 FAST, 02 MID, 03 SLOW; the read is the command without data).
use super::*;
use crate::contact_http_tests::{Fixture, fixture};
use crate::profile;
use axum::http::StatusCode;
use std::collections::VecDeque;
use std::sync::atomic::AtomicBool;
use wstx_rust::radio_control::{self as cat, codec, executor::Transport, setup};

const READ_AGC: [u8; 7] = [0xfe, 0xfe, 0x94, 0xe0, 0x16, 0x12, 0xfd];
const READ_RX_TX: [u8; 7] = [0xfe, 0xfe, 0x94, 0xe0, 0x1c, 0x00, 0xfd];
const SET_SLOW: [u8; 8] = [0xfe, 0xfe, 0x94, 0xe0, 0x16, 0x12, 0x03, 0xfd];

struct Ic7300 {
    agc: u8,
    transmitting: bool,
    dial: u64,
    mode: [u8; 2],
    data: [u8; 2],
    /// The AGC read is answered FA.
    refuse_read: bool,
    /// The AGC write is answered FA.
    refuse_write: bool,
    /// The AGC write is acknowledged but the AGC does not change.
    sticky: bool,
    writes: Vec<Vec<u8>>,
}
impl Ic7300 {
    fn at(agc: u8) -> Self {
        Self {
            agc,
            transmitting: false,
            dial: 7_074_000,
            mode: [1, 1],
            data: [1, 1],
            refuse_read: false,
            refuse_write: false,
            sticky: false,
            writes: Vec::new(),
        }
    }
}
struct Port {
    radio: Arc<Mutex<Ic7300>>,
    pending: VecDeque<u8>,
}
impl Transport for Port {
    fn configure(&mut self, _: u32) -> cat::Result<()> {
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> cat::Result<usize> {
        let mut r = self.radio.lock().unwrap();
        r.writes.push(bytes.to_vec());
        assert_eq!(&bytes[..4], &[0xfe, 0xfe, 0x94, 0xe0], "{bytes:02x?}");
        let body = &bytes[4..bytes.len() - 1];
        let reply: Vec<u8> = match body {
            [3] => [&[3][..], &codec::encode_frequency(r.dial).unwrap()].concat(),
            [5, f @ ..] => {
                r.dial = codec::decode_frequency(f).unwrap();
                vec![0xfb]
            }
            [4] => vec![4, r.mode[0], r.mode[1]],
            [6, m, f] => {
                r.mode = [*m, *f];
                vec![0xfb]
            }
            [0x1a, 6] => vec![0x1a, 6, r.data[0], r.data[1]],
            [0x1a, 6, d, f] => {
                r.data = [*d, *f];
                vec![0xfb]
            }
            [0x1c, 0] => vec![0x1c, 0, u8::from(r.transmitting)],
            [0x0f] => vec![0x0f, 0],
            [0x19, 0] => vec![0x19, 0, 0x94],
            [0x16, 0x12] if r.refuse_read => vec![0xfa],
            [0x16, 0x12] => vec![0x16, 0x12, r.agc],
            [0x16, 0x12, _] if r.refuse_write => vec![0xfa],
            [0x16, 0x12, code] => {
                if !r.sticky {
                    r.agc = *code;
                }
                vec![0xfb]
            }
            _ => vec![0xfa],
        };
        // CI-V echo of our own frame precedes the reply on the bus.
        self.pending.extend(bytes);
        self.pending.extend([0xfe, 0xfe, 0xe0, 0x94]);
        self.pending.extend(reply);
        self.pending.push_back(0xfd);
        Ok(bytes.len())
    }
    fn read(&mut self, bytes: &mut [u8], _: Instant, _: &AtomicBool) -> cat::Result<usize> {
        let n = bytes.len().min(self.pending.len());
        for b in bytes.iter_mut().take(n) {
            *b = self.pending.pop_front().unwrap();
        }
        Ok(n)
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> cat::Result<()> {
        self.pending.clear();
        Ok(())
    }
    fn close(&mut self) -> cat::Result<()> {
        Ok(())
    }
}

/// The fixture station, IC-7300 CAT on COM3 with AGC SLOW saved, its CAT owner Ready.
fn station(radio: Ic7300) -> (Fixture, Arc<Mutex<Ic7300>>) {
    let f = fixture("http://127.0.0.1:18045", true);
    {
        let mut store = f.state.store.lock().unwrap();
        store.document.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some("COM3".into()),
            ptt: "cat".into(),
        };
        store.document.radio = Some(profile::Radio::DEFAULT);
    }
    let radio = Arc::new(Mutex::new(radio));
    let shared = radio.clone();
    f.state
        .recording
        .fixture_cat_transport(Arc::new(move |_, _, _| {
            Ok(Box::new(Port {
                radio: shared.clone(),
                pending: VecDeque::new(),
            }) as Box<dyn Transport>)
        }));
    f.state
        .recording
        .radio_connect(cat::Configuration::parse("COM3").unwrap(), 0)
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while actor(&f).snapshot().unwrap().state != cat::State::Ready {
        assert!(Instant::now() < deadline, "CAT owner not ready");
        std::thread::sleep(Duration::from_millis(5));
    }
    // Connection-phase queries are not the AGC exchange under test.
    radio.lock().unwrap().writes.clear();
    (f, radio)
}
fn actor(f: &Fixture) -> Arc<cat::actor::Actor> {
    f.state.recording.radio_actor().unwrap()
}
fn ensure(f: &Fixture) -> cat::Result<cat::SetupReply> {
    actor(f).setup(
        cat::SetupCommand::EnsureAgc(setup::Agc::Slow),
        Instant::now() + Duration::from_secs(3),
    )
}
fn agc_frames(radio: &Arc<Mutex<Ic7300>>) -> Vec<Vec<u8>> {
    radio
        .lock()
        .unwrap()
        .writes
        .iter()
        .filter(|w| w[4..6] == [0x16, 0x12])
        .cloned()
        .collect()
}
fn writes(radio: &Arc<Mutex<Ic7300>>) -> Vec<Vec<u8>> {
    radio.lock().unwrap().writes.clone()
}
/// Waits for the background connect apply to finish and returns its status.
fn settled(f: &Fixture) -> Status {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(s) = f.state.recording.agc.status() {
            return s;
        }
        assert!(Instant::now() < deadline, "AGC apply did not finish");
        std::thread::sleep(Duration::from_millis(5));
    }
}
fn tick(f: &Fixture, now: Instant) {
    super::tick(&f.state.recording, Some(setup::Agc::Slow), now);
}

// TC-044-008 (h)
// Proves: TC-044-008.
#[test]
fn agc_frames_and_replies_follow_the_ic7300_command_table() {
    assert_eq!(setup::read_agc_frame(0x94), READ_AGC);
    for (agc, code) in [
        (setup::Agc::Fast, 1),
        (setup::Agc::Mid, 2),
        (setup::Agc::Slow, 3),
    ] {
        assert_eq!(
            setup::write_agc_frame(0x94, agc),
            [0xfe, 0xfe, 0x94, 0xe0, 0x16, 0x12, code, 0xfd]
        );
        assert_eq!(setup::Agc::from_code(code), Some(agc));
        assert_eq!(
            setup::hear(&[0xfe, 0xfe, 0xe0, 0x94, 0x16, 0x12, code, 0xfd]),
            setup::Heard::Agc {
                address: 0x94,
                code
            }
        );
    }
    assert_eq!(setup::Agc::from_code(4), None);
    assert_eq!(setup::Agc::from_code(0), None);
    // Our own echo (addressed to the radio) is not a reply.
    assert_eq!(setup::hear(&READ_AGC), setup::Heard::Other);
    assert_eq!(serde_json::to_value(setup::Agc::Slow).unwrap(), "SLOW");
    assert_eq!(
        serde_json::from_value::<setup::Agc>(json!("MID")).unwrap(),
        setup::Agc::Mid
    );
    assert!(serde_json::from_value::<setup::Agc>(json!("LOW")).is_err());
}

// TC-044-008 (a)-(g)
// Proves: TC-044-008.
#[test]
fn ensure_agc_reads_first_and_writes_only_a_differing_value_with_readback() {
    // (a) already SLOW: the read is the only frame.
    let (f, radio) = station(Ic7300::at(3));
    assert_eq!(
        ensure(&f),
        Ok(cat::SetupReply::Agc {
            value: setup::Agc::Slow,
            written: false
        })
    );
    assert_eq!(writes(&radio), [READ_AGC.to_vec()]);
    drop(f);
    // (b) MID: read, RX check, write SLOW, read back.
    let (f, radio) = station(Ic7300::at(2));
    assert_eq!(
        ensure(&f),
        Ok(cat::SetupReply::Agc {
            value: setup::Agc::Slow,
            written: true
        })
    );
    assert_eq!(
        writes(&radio),
        [
            READ_AGC.to_vec(),
            READ_RX_TX.to_vec(),
            SET_SLOW.to_vec(),
            READ_AGC.to_vec()
        ]
    );
    assert_eq!(radio.lock().unwrap().agc, 3);
    drop(f);
    // (c) TX: refused busy after the read and the RX check, no set frame.
    let mut tx = Ic7300::at(2);
    tx.transmitting = true;
    let (f, radio) = station(tx);
    assert_eq!(ensure(&f), Err(cat::Error::Busy));
    assert_eq!(writes(&radio), [READ_AGC.to_vec(), READ_RX_TX.to_vec()]);
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
    drop(f);
    // (d) FA to the write.
    let mut refused = Ic7300::at(2);
    refused.refuse_write = true;
    let (f, radio) = station(refused);
    assert_eq!(ensure(&f), Err(cat::Error::Rejected));
    assert_eq!(radio.lock().unwrap().agc, 2);
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
    drop(f);
    // (e) acknowledged but unchanged.
    let mut sticky = Ic7300::at(2);
    sticky.sticky = true;
    let (f, _) = station(sticky);
    assert_eq!(ensure(&f), Err(cat::Error::ReadbackMismatch));
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
    drop(f);
    // (f) FA to the read: nothing written.
    let mut unreadable = Ic7300::at(2);
    unreadable.refuse_read = true;
    let (f, radio) = station(unreadable);
    assert_eq!(ensure(&f), Err(cat::Error::Rejected));
    assert_eq!(writes(&radio), [READ_AGC.to_vec()]);
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
}

// TC-044-009 (a), (b), (g)
// Proves: TC-044-009.
#[test]
fn connect_applies_the_saved_agc_once_and_pushes_the_read_back() {
    let (f, radio) = station(Ic7300::at(2));
    let (before, _) = super::event(&f.state.recording);
    assert_eq!(before, 0, "no event before the station has an AGC target");
    tick(&f, Instant::now());
    let s = settled(&f);
    assert_eq!(
        (s.target, s.value, s.result, s.trigger),
        (
            setup::Agc::Slow,
            Some(setup::Agc::Slow),
            "written",
            "connect"
        )
    );
    assert_eq!(
        agc_frames(&radio),
        [READ_AGC.to_vec(), SET_SLOW.to_vec(), READ_AGC.to_vec()]
    );
    let (revision, text) = super::event(&f.state.recording);
    assert!(revision > 0);
    let v: Value = serde_json::from_str(&text).unwrap();
    let generation = actor(&f)
        .snapshot()
        .unwrap()
        .authority
        .connection_generation;
    assert_eq!(
        v,
        json!({"v":1,"type":"radio.agc","data":{"profile_id":f.id,"boot_id":f.boot,"target":"SLOW",
            "connection_generation":generation,"value":"SLOW","result":"written","trigger":"connect"}})
    );
    // Once per connection: further ticks send nothing.
    let count = writes(&radio).len();
    tick(&f, Instant::now());
    std::thread::sleep(Duration::from_millis(50));
    assert_eq!(writes(&radio).len(), count);
    drop(f);
    // (b) already SLOW: read only, unchanged.
    let (f, radio) = station(Ic7300::at(3));
    tick(&f, Instant::now());
    assert_eq!(settled(&f).result, "unchanged");
    assert_eq!(
        writes(&radio),
        [READ_AGC.to_vec()],
        "a matching read writes nothing"
    );
}

// TC-044-009 (c), (d)
// Proves: TC-044-009.
#[test]
fn connect_apply_never_writes_while_transmitting_or_armed() {
    // (c) the radio reports TX: busy, retried after the delay once it is RX.
    let mut tx = Ic7300::at(2);
    tx.transmitting = true;
    let (f, radio) = station(tx);
    let t0 = Instant::now();
    tick(&f, t0);
    assert_eq!(settled(&f).result, "busy");
    assert!(!agc_frames(&radio).contains(&SET_SLOW.to_vec()));
    radio.lock().unwrap().transmitting = false;
    tick(&f, t0 + Duration::from_millis(100));
    std::thread::sleep(Duration::from_millis(100));
    assert!(
        !agc_frames(&radio).contains(&SET_SLOW.to_vec()),
        "not before the retry delay"
    );
    tick(&f, Instant::now() + RETRY);
    let deadline = Instant::now() + Duration::from_secs(5);
    while f.state.recording.agc.status().unwrap().result != "written" {
        assert!(Instant::now() < deadline, "retry did not write");
        std::thread::sleep(Duration::from_millis(5));
    }
    drop(f);
    // (d) the transmitter armed: no AGC frame at all.
    let (f, radio) = station(Ic7300::at(2));
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.with(|c| c.arm(3).unwrap());
    tick(&f, Instant::now());
    std::thread::sleep(Duration::from_millis(100));
    assert!(agc_frames(&radio).is_empty(), "nothing sent while armed");
    assert!(f.state.recording.agc.status().is_none());
}

/// An operator selection (RF work) on the station's connection.
fn begin(f: &Fixture, action: &'static str, mode: &'static str, band: Option<&str>) {
    let r = &f.state.recording;
    let v = r.selection_snapshot(true).unwrap();
    let intent = crate::selection::Intent {
        command_id: profile::new_uuid().unwrap(),
        profile_id: v["profile_id"].as_str().unwrap().into(),
        boot_id: v["boot_id"].as_str().unwrap().into(),
        profile_revision: v["profile_revision"].as_u64().unwrap(),
        generation: v["generation"].as_u64().unwrap(),
        revision: v["operating_revision"].as_u64().unwrap(),
        action,
        mode: Some(mode),
        band: band.map(Into::into),
    };
    r.selection_begin(intent, None, true).unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while r.selection_snapshot(true).unwrap()["operation"]["result"] == "pending" {
        assert!(Instant::now() < deadline, "selection did not finish");
        std::thread::sleep(Duration::from_millis(5));
    }
}

// TC-044-009 (e), (f)
// Proves: TC-044-009.
#[test]
fn ft8_and_ft4_selections_apply_the_agc_inside_the_selection() {
    let (f, radio) = station(Ic7300::at(3));
    tick(&f, Instant::now());
    assert_eq!(settled(&f).result, "unchanged");
    // The operator turned the radio to FAST meanwhile.
    radio.lock().unwrap().agc = 1;
    radio.lock().unwrap().writes.clear();
    begin(&f, "band", "ft8", Some("20m"));
    let s = f.state.recording.agc.status().unwrap();
    assert_eq!(
        (s.value, s.result, s.trigger),
        (Some(setup::Agc::Slow), "written", "selection")
    );
    let all = writes(&radio);
    let set = all
        .iter()
        .position(|w| *w == SET_SLOW)
        .expect("AGC set in the selection");
    let dial = all
        .iter()
        .position(|w| w[4] == 5)
        .expect("dial set in the selection");
    assert!(dial < set, "after the receive setup: {all:02x?}");
    assert_eq!(radio.lock().unwrap().agc, 3);
    // (f) an FT4 selection with the radio already at SLOW: only the AGC read.
    radio.lock().unwrap().writes.clear();
    begin(&f, "mode", "ft4", None);
    let s = f.state.recording.agc.status().unwrap();
    assert_eq!((s.result, s.trigger), ("unchanged", "selection"));
    assert_eq!(
        agc_frames(&radio),
        [READ_AGC.to_vec()],
        "a matching read writes nothing"
    );
}

// TC-044-009 (h)
// Proves: TC-044-009.
#[test]
fn profile_radio_settings_default_migrate_and_validate() {
    use profile::{Control, Radio};
    let cat = Control {
        mode: "cat".into(),
        endpoint: Some("icom7300://COM3?baud=19200&radio=94&controller=e0".into()),
        ptt: "cat".into(),
    };
    let off = Control {
        mode: "disabled".into(),
        endpoint: None,
        ptt: "disabled".into(),
    };
    assert!(profile::manages_radio(&cat));
    assert!(!profile::manages_radio(&off));
    // Profile files written before the field existed.
    for (control, expected) in [(&cat, Some(json!({"agc":"SLOW"}))), (&off, None)] {
        let dir = std::env::temp_dir().join(format!("wstx-agc-{}", profile::new_uuid().unwrap()));
        std::fs::create_dir(&dir).unwrap();
        let doc = json!({"schema_version":1,"profile_id":profile::new_uuid().unwrap(),"revision":4,"display_name":"AGC",
            "callsign":"HB9BLA","locator":"JN37VL","endpoint":{"bind":"127.0.0.1:18046","origin":null},"connection_type":"standard",
            "audio":{"input_device":null,"output_device":null},"control":control});
        let bytes = serde_json::to_vec(&doc).unwrap();
        std::fs::write(dir.join("profile.json"), &bytes).unwrap();
        let (store, _) = profile::Store::open(&dir).unwrap();
        let settings = serde_json::to_value(store.document.settings()).unwrap();
        assert_eq!(settings.get("radio").cloned(), expected, "{settings}");
        assert_eq!(store.document.revision, 4);
        assert_eq!(
            std::fs::read(dir.join("profile.json")).unwrap(),
            bytes,
            "file unchanged"
        );
    }
    // Edits: omitted keeps the saved value; a managed radio defaults to SLOW.
    let mut s = profile::Settings {
        display_name: "AGC".into(),
        callsign: String::new(),
        locator: String::new(),
        audio: profile::Audio {
            input_device: None,
            output_device: None,
        },
        control: cat.clone(),
        radio: None,
    };
    let mid = Radio {
        agc: setup::Agc::Mid,
        power_limit_pct: None,
    };
    let mut kept = s.clone();
    kept.complete_radio(Some(mid));
    assert_eq!(kept.radio, Some(mid));
    s.complete_radio(None);
    assert_eq!(s.radio, Some(Radio::DEFAULT));
    assert_eq!(s.validate(), Ok(()));
    let mut unmanaged = s.clone();
    unmanaged.control = off.clone();
    assert_eq!(unmanaged.validate(), Err("radio"));
    unmanaged.radio = None;
    unmanaged.complete_radio(Some(mid));
    assert_eq!((unmanaged.radio, unmanaged.validate()), (None, Ok(())));
    let mut managed_without = s.clone();
    managed_without.radio = None;
    assert_eq!(managed_without.validate(), Err("radio"));
}

// TC-044-009 (h) over HTTP
// Proves: TC-044-009.
#[tokio::test]
async fn profile_put_keeps_saves_and_refuses_radio_settings() {
    let (f, _) = station(Ic7300::at(3));
    let (_, v, _, _) = f.call("GET", "/profile", None).await;
    assert_eq!(v["settings"]["radio"], json!({"agc":"SLOW"}), "{v}");
    let edit = |revision: u64, radio: Option<Value>, control: Value| {
        let mut settings = json!({"display_name":"AGC","callsign":"HB9BLA","locator":"JN37VL",
            "audio":{"input_device":null,"output_device":null},"control":control});
        if let Some(radio) = radio {
            settings["radio"] = radio;
        }
        json!({"profile_id":f.id,"revision":revision,"settings":settings})
    };
    let cat = json!({"mode":"cat","endpoint":"COM3","ptt":"cat"});
    let r0 = v["revision"].as_u64().unwrap();
    let (s, v, _, _) = f
        .call("PUT", "/profile", Some(edit(r0, None, cat.clone())))
        .await;
    assert_eq!(
        (s, v["settings"]["radio"].clone()),
        (StatusCode::OK, json!({"agc":"SLOW"})),
        "{v}"
    );
    let (s, v, _, _) = f
        .call(
            "PUT",
            "/profile",
            Some(edit(r0 + 1, Some(json!({"agc":"MID"})), cat.clone())),
        )
        .await;
    assert_eq!(
        (s, v["settings"]["radio"].clone()),
        (StatusCode::OK, json!({"agc":"MID"})),
        "{v}"
    );
    let (s, v, _, _) = f
        .call(
            "PUT",
            "/profile",
            Some(edit(r0 + 2, Some(json!({"agc":"LOW"})), cat.clone())),
        )
        .await;
    assert_eq!(
        (s, v["error"]["field"].clone()),
        (StatusCode::BAD_REQUEST, json!("settings.radio.agc")),
        "{v}"
    );
    let off = json!({"mode":"disabled","endpoint":null,"ptt":"disabled"});
    let (s, v, _, _) = f
        .call(
            "PUT",
            "/profile",
            Some(edit(r0 + 2, Some(json!({"agc":"SLOW"})), off.clone())),
        )
        .await;
    assert_eq!(
        (s, v["error"]["field"].clone()),
        (StatusCode::BAD_REQUEST, json!("radio")),
        "{v}"
    );
    let (s, v, _, _) = f
        .call("PUT", "/profile", Some(edit(r0 + 2, None, off)))
        .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert!(v["settings"].get("radio").is_none(), "{v}");
    assert_eq!(
        f.state.store.lock().unwrap().document.radio,
        None,
        "an unmanaged control keeps no radio settings"
    );
}
