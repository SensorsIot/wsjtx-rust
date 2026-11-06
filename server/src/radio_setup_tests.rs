#![forbid(unsafe_code)]
// Proves: CL-044-01; CL-044-02; CL-044-03; CL-044-04; CL-044-05; CL-044-07; CL-044-11; TC-044-001; TC-044-002; TC-044-003; TC-044-006; TC-044-009.
// The actual router, Recording owner and CAT actor; a scripted IC-7300 behind
// the station's CAT owner, a detection hardware double of ports and audio endpoints.
// Expected bytes are hand-written from the IC-7300 Full Manual section 19 command table.
use super::*;
use crate::contact_http_tests::{Fixture, fixture};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::AtomicBool;
use wstx_rust::radio_control::{
    self as cat,
    executor::Transport,
    setup::{AudioEndpoint, Flow, PortInfo, Topology},
};

#[derive(Default)]
struct Ic7300 {
    id: u8,
    menu: HashMap<[u8; 2], Vec<u8>>,
    transmitting: bool,
    /// A write of this item is answered FA.
    refuse: Option<[u8; 2]>,
    /// A write of this item is acknowledged but the value does not change.
    sticky: Option<[u8; 2]>,
    writes: Vec<Vec<u8>>,
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
            [3] => vec![3, 0, 0x40, 7, 7, 0],
            [4] => vec![4, 1, 1],
            [0x1a, 6] => vec![0x1a, 6, 1, 1],
            [0x1c, 0] => vec![0x1c, 0, u8::from(r.transmitting)],
            [0x0f] => vec![0x0f, 0],
            [0x19, 0] => vec![0x19, 0, r.id],
            [0x1a, 5, hi, lo] => match r.menu.get(&[*hi, *lo]) {
                Some(data) => [&[0x1a, 5, *hi, *lo][..], data].concat(),
                None => vec![0xfa],
            },
            [0x1a, 5, hi, lo, data @ ..] => {
                if r.refuse == Some([*hi, *lo]) {
                    vec![0xfa]
                } else {
                    if r.sticky != Some([*hi, *lo]) {
                        r.menu.insert([*hi, *lo], data.to_vec());
                    }
                    vec![0xfb]
                }
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
fn hb9bla_menu() -> HashMap<[u8; 2], Vec<u8>> {
    HashMap::from([
        ([0x00, 0x78], vec![0x01]),
        ([0x00, 0x79], vec![0x00]),
        ([0x00, 0x80], vec![0x02]),
        ([0x00, 0x66], vec![0x00]),
        ([0x00, 0x67], vec![0x00]),
        ([0x00, 0x65], vec![0x01, 0x28]),
        ([0x00, 0x71], vec![0x01]),
    ])
}
/// The fixture station with its CAT owner Ready on COM3 against the scripted radio.
fn station(radio: Ic7300) -> (Fixture, Arc<Mutex<Ic7300>>) {
    let f = fixture("http://127.0.0.1:18044", true);
    f.state.store.lock().unwrap().document.control = profile::Control {
        mode: "cat".into(),
        endpoint: Some("COM3".into()),
        ptt: "cat".into(),
    };
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
    while f
        .state
        .recording
        .radio_actor()
        .unwrap()
        .snapshot()
        .unwrap()
        .state
        != cat::State::Ready
    {
        assert!(Instant::now() < deadline, "CAT owner not ready");
        std::thread::sleep(Duration::from_millis(5));
    }
    (f, radio)
}
fn generation(f: &Fixture) -> u64 {
    f.state.recording.radio_view()["connection_generation"]
        .as_u64()
        .unwrap()
}
/// Menu writes (1A 05 item data) in order, as (item, value).
fn menu_writes(radio: &Arc<Mutex<Ic7300>>) -> Vec<(String, u8)> {
    radio
        .lock()
        .unwrap()
        .writes
        .iter()
        .filter(|w| w.len() == 10 && w[4..6] == [0x1a, 0x05])
        .map(|w| (format!("{:02x}{:02x}", w[6], w[7]), w[8]))
        .collect()
}
/// No transmit, frequency or mode setter ever reached the radio.
fn assert_never_keyed(radio: &Arc<Mutex<Ic7300>>) {
    for w in &radio.lock().unwrap().writes {
        let body = &w[4..w.len() - 1];
        assert!(
            !(body.starts_with(&[0x1c, 0x00]) && body.len() > 2)
                && body[0] != 0x05
                && body[0] != 0x06
                && !(body.starts_with(&[0x1a, 0x06]) && body.len() > 2),
            "setter frame {w:02x?}"
        );
    }
}
fn undo_file(f: &Fixture) -> Option<Value> {
    std::fs::read(f.dir.join(radio_setup::UNDO_FILE))
        .ok()
        .map(|b| serde_json::from_slice(&b).unwrap())
}

#[test]
fn apply_writes_recommended_items_with_undo_record_then_undo_restores() {
    let (f, radio) = station(Ic7300 {
        id: 0x94,
        menu: hb9bla_menu(),
        ..Default::default()
    });
    let g = generation(&f);
    let v = radio_setup::apply(&f.state, g).unwrap();
    assert_eq!(v["result"], "done", "{v}");
    assert_eq!(
        menu_writes(&radio),
        [
            ("0078".into(), 0x00),
            ("0080".into(), 0x00),
            ("0067".into(), 0x03),
            ("0071".into(), 0x00)
        ],
        "keying lines first, never 0079 (already OFF)"
    );
    // Each write was read back: the item's read follows its write.
    let writes = radio.lock().unwrap().writes.clone();
    let at = writes
        .iter()
        .position(|w| w[4..] == [0x1a, 5, 0, 0x78, 0x00, 0xfd])
        .unwrap();
    assert_eq!(writes[at + 1][4..], [0x1a, 5, 0, 0x78, 0xfd]);
    assert_eq!(
        undo_file(&f).unwrap(),
        json!({"schema_version":1,"profile_id":f.id,"civ_address":"94","items":[
            {"item":"0078","old":1,"new":0},{"item":"0080","old":2,"new":0},
            {"item":"0067","old":0,"new":3},{"item":"0071","old":1,"new":0}]})
    );
    // A second apply finds nothing to change and keeps the record.
    let before = menu_writes(&radio).len();
    let again = radio_setup::apply(&f.state, g).unwrap();
    assert_eq!(
        (
            again["result"].as_str(),
            again["written"].as_array().unwrap().len()
        ),
        (Some("done"), 0)
    );
    assert_eq!(menu_writes(&radio).len(), before);
    assert!(undo_file(&f).is_some());
    // Undo writes the old values in reverse order and removes the record.
    let u = radio_setup::undo(&f.state, g).unwrap();
    assert_eq!(u["result"], "done", "{u}");
    assert_eq!(
        menu_writes(&radio)[before..],
        [
            ("0071".into(), 0x01),
            ("0067".into(), 0x00),
            ("0080".into(), 0x02),
            ("0078".into(), 0x01)
        ]
    );
    assert_eq!(radio.lock().unwrap().menu, hb9bla_menu());
    assert!(undo_file(&f).is_none());
    assert_eq!(radio_setup::undo(&f.state, g), Err("nothing_to_undo"));
    assert_never_keyed(&radio);
    assert!(f.bench.keys.lock().unwrap().is_empty(), "PTT never keyed");
}

#[test]
fn apply_refusals_and_failures_stop_without_keying() {
    // Radio in TX: no menu write at all.
    let (f, radio) = station(Ic7300 {
        id: 0x94,
        menu: hb9bla_menu(),
        transmitting: true,
        ..Default::default()
    });
    let g = generation(&f);
    let v = radio_setup::apply(&f.state, g).unwrap();
    assert_eq!(
        (
            v["result"].as_str(),
            v["error"].as_str(),
            v["failed_item"].as_str()
        ),
        (Some("failed"), Some("busy"), Some("0078"))
    );
    assert!(menu_writes(&radio).is_empty());
    assert!(undo_file(&f).is_none(), "nothing changed, nothing recorded");
    assert_eq!(radio_setup::apply(&f.state, g + 1), Err("state_conflict"));
    // Transmitter armed: refused before any exchange.
    radio.lock().unwrap().transmitting = false;
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.with(|c| c.arm(3).unwrap());
    assert_eq!(radio_setup::apply(&f.state, g), Err("transmit_armed"));
    assert!(menu_writes(&radio).is_empty());
    drop(f);

    // FA to 0080 stops after 0078 with the record kept.
    let (f, radio) = station(Ic7300 {
        id: 0x94,
        menu: hb9bla_menu(),
        refuse: Some([0x00, 0x80]),
        ..Default::default()
    });
    let v = radio_setup::apply(&f.state, generation(&f)).unwrap();
    assert_eq!(
        (
            v["result"].as_str(),
            v["error"].as_str(),
            v["failed_item"].as_str()
        ),
        (Some("failed"), Some("radio_rejected"), Some("0080"))
    );
    assert_eq!(
        menu_writes(&radio),
        [("0078".into(), 0x00), ("0080".into(), 0x00)]
    );
    // Only the item that may have changed stays recorded: 0080 was refused (FA,
    // unchanged), 0067 and 0071 were never written.
    assert_eq!(
        undo_file(&f).unwrap()["items"],
        json!([{"item":"0078","old":1,"new":0}])
    );
    // Undo then restores it and clears the record.
    let u = radio_setup::undo(&f.state, generation(&f)).unwrap();
    assert_eq!(u["result"], "done", "{u}");
    assert_eq!(menu_writes(&radio)[2..], [("0078".into(), 0x01)]);
    assert_eq!(radio.lock().unwrap().menu, hb9bla_menu());
    assert!(undo_file(&f).is_none());
    drop(f);

    // Readback of 0067 stays 00.
    let (f, _radio) = station(Ic7300 {
        id: 0x94,
        menu: hb9bla_menu(),
        sticky: Some([0x00, 0x67]),
        ..Default::default()
    });
    let v = radio_setup::apply(&f.state, generation(&f)).unwrap();
    assert_eq!(
        (v["error"].as_str(), v["failed_item"].as_str()),
        (Some("readback_mismatch"), Some("0067"))
    );
    drop(f);

    // Another model behind the station's CAT owner.
    let (f, radio) = station(Ic7300 {
        id: 0xa4,
        menu: hb9bla_menu(),
        ..Default::default()
    });
    assert_eq!(
        radio_setup::apply(&f.state, generation(&f)),
        Err("unsupported_radio")
    );
    assert!(menu_writes(&radio).is_empty());
    assert_never_keyed(&radio);
}

struct Double {
    ports: Vec<PortInfo>,
    endpoints: Vec<AudioEndpoint>,
    radios: HashMap<u16, (u8, u32)>,
    in_use: Vec<u16>,
    opened: Mutex<Vec<u16>>,
    writes: Arc<Mutex<Vec<Vec<u8>>>>,
}
/// A probe port answering 19 00 for one radio at one rate, recording every write.
struct ProbePort {
    radio: Option<(u8, u32)>,
    baud: u32,
    writes: Arc<Mutex<Vec<Vec<u8>>>>,
    pending: VecDeque<u8>,
}
impl Transport for ProbePort {
    fn configure(&mut self, baud: u32) -> cat::Result<()> {
        self.baud = baud;
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> cat::Result<usize> {
        self.writes.lock().unwrap().push(bytes.to_vec());
        if let Some((address, baud)) = self.radio
            && baud == self.baud
            && (bytes[2] == 0 || bytes[2] == address)
        {
            let body: Vec<u8> = match &bytes[4..bytes.len() - 1] {
                [0x19, 0] => vec![0x19, 0, address],
                [0x1a, 5, hi, lo] => vec![0x1a, 5, *hi, *lo, 0],
                _ => vec![0xfa],
            };
            self.pending.extend([0xfe, 0xfe, 0xe0, address]);
            self.pending.extend(body);
            self.pending.push_back(0xfd);
        }
        Ok(bytes.len())
    }
    fn read(&mut self, bytes: &mut [u8], _: Instant, _: &AtomicBool) -> cat::Result<usize> {
        if self.pending.is_empty() {
            std::thread::sleep(Duration::from_millis(1));
            return Ok(0);
        }
        let n = bytes.len().min(self.pending.len());
        for b in bytes.iter_mut().take(n) {
            *b = self.pending.pop_front().unwrap();
        }
        Ok(n)
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> cat::Result<()> {
        Ok(())
    }
    fn close(&mut self) -> cat::Result<()> {
        Ok(())
    }
}
impl radio_setup::Hardware for Double {
    fn ports(&self) -> Result<Vec<PortInfo>, cat::Error> {
        Ok(self.ports.clone())
    }
    fn endpoints(&self) -> Result<Vec<AudioEndpoint>, cat::Error> {
        Ok(self.endpoints.clone())
    }
    fn open(
        &self,
        port: u16,
        _: Instant,
        _: &AtomicBool,
    ) -> Result<Box<dyn Transport>, cat::Error> {
        self.opened.lock().unwrap().push(port);
        if self.in_use.contains(&port) {
            return Err(cat::Error::ResourceInUse);
        }
        Ok(Box::new(ProbePort {
            radio: self.radios.get(&port).copied(),
            baud: 0,
            writes: self.writes.clone(),
            pending: VecDeque::new(),
        }))
    }
}
const CAPTURE: &str = "{0.0.1.00000000}.{6b9f2c1e-1111-4222-8333-944444444444}";
const RENDER: &str = "{0.0.0.00000000}.{f4069c8a-1111-4222-8333-944444444444}";
fn under(hub: &str) -> Topology {
    Topology {
        container_id: None,
        usb_device: Some(format!("USB\\VID_10C4&PID_EA60\\{hub}")),
        usb_parent: Some(hub.into()),
    }
}
fn port(n: u16, hub: &str) -> PortInfo {
    PortInfo {
        port: n,
        instance_id: format!("USB\\VID_10C4&PID_EA60\\RADIO{n}"),
        friendly_name: Some(format!("Silicon Labs CP210x USB to UART Bridge (COM{n})")),
        topology: under(hub),
    }
}
fn double(ports: Vec<PortInfo>, radios: HashMap<u16, (u8, u32)>, in_use: Vec<u16>) -> Arc<Double> {
    Arc::new(Double {
        ports,
        endpoints: vec![
            AudioEndpoint {
                id: CAPTURE.into(),
                name: "Microphone (USB Audio CODEC )".into(),
                flow: Flow::Capture,
                topology: under("USB\\HUB\\IC7300"),
            },
            AudioEndpoint {
                id: RENDER.into(),
                name: "Speakers (USB Audio CODEC )".into(),
                flow: Flow::Render,
                topology: under("USB\\HUB\\IC7300"),
            },
            AudioEndpoint {
                id: "{0.0.1.00000000}.{00000000-0000-4000-8000-00000000000c}".into(),
                name: "Microphone (Webcam)".into(),
                flow: Flow::Capture,
                topology: under("USB\\HUB\\OTHER"),
            },
        ],
        radios,
        in_use,
        opened: Mutex::new(Vec::new()),
        writes: Arc::new(Mutex::new(Vec::new())),
    })
}

#[test]
fn detection_never_opens_station_port_and_proposes_the_station_radio() {
    let (f, radio) = station(Ic7300 {
        id: 0x94,
        menu: hb9bla_menu(),
        ..Default::default()
    });
    let hw = double(
        vec![
            port(3, "USB\\HUB\\IC7300"),
            port(5, "USB\\HUB\\IC705"),
            port(7, "USB\\HUB\\X"),
            port(8, "USB\\HUB\\Y"),
            // An FTDI microcontroller board: never opened.
            PortInfo {
                port: 9,
                instance_id: "FTDIBUS\\VID_0403+PID_6001+A1\\0000".into(),
                friendly_name: Some("USB Serial Port (COM9)".into()),
                topology: Topology {
                    usb_device: Some("USB\\VID_0403&PID_6001\\A1".into()),
                    ..Default::default()
                },
            },
        ],
        HashMap::from([(5, (0xa4, 115200))]),
        vec![7],
    );
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw.clone());
    let v = radio_setup::detect(&f.state).unwrap();
    assert_eq!(
        *hw.opened.lock().unwrap(),
        vec![5, 7, 8],
        "COM3 is never opened a second time"
    );
    let states: Vec<_> = v["ports"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["state"].as_str().unwrap())
        .collect();
    assert_eq!(
        states,
        [
            "station_cat",
            "identified",
            "in_use",
            "no_reply",
            "not_radio_bridge"
        ]
    );
    let com3 = &v["ports"][0];
    assert_eq!(
        (com3["vid"].as_str(), com3["pid"].as_str()),
        (Some("10C4"), Some("EA60"))
    );
    assert_eq!(com3["radios"][0]["model"], "IC-7300");
    assert_eq!(
        v["ports"][1]["radios"][0],
        json!({"model":"IC-705","id":"A4","civ_address":"A4","baud":115200,"station_cat":false,"unknown_model":false})
    );
    assert_eq!(
        v["proposal"],
        json!({"port":"COM3","model":"IC-7300","civ_address":"94","baud":9600,
            "control":{"mode":"cat","endpoint":"icom7300://COM3?baud=9600&radio=94&controller=e0","ptt":"cat"},
            "radio":{"agc":"SLOW"},
            "audio":{"input_device":CAPTURE,"output_device":RENDER,
                "input_name":"Microphone (USB Audio CODEC)","output_name":"Speakers (USB Audio CODEC)"}})
    );
    // The proposal's endpoint is a valid station CAT configuration.
    assert!(
        cat::Configuration::parse(v["proposal"]["control"]["endpoint"].as_str().unwrap()).is_ok()
    );
    // Settings read through the owner: values and guidance; nothing written.
    assert_eq!(v["settings"]["source"], "station_cat");
    let items: Vec<_> = v["settings"]["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| {
            (
                i["item"].as_str().unwrap().to_owned(),
                i["value"].as_u64(),
                i["severity"].as_str().unwrap().to_owned(),
            )
        })
        .collect();
    assert_eq!(
        items,
        [
            ("0066".into(), Some(0), "information".into()),
            ("0067".into(), Some(0), "blocking".into()),
            ("0065".into(), Some(128), "ok".into()),
            ("0071".into(), Some(1), "advice".into()),
            ("0078".into(), Some(1), "blocking".into()),
            ("0079".into(), Some(0), "ok".into()),
            ("0080".into(), Some(2), "blocking".into()),
        ]
    );
    assert!(
        menu_writes(&radio).is_empty(),
        "detection writes no setting"
    );
    assert_never_keyed(&radio);
    // The probe ports saw only ID and menu reads.
    for w in hw.writes.lock().unwrap().iter() {
        let body = &w[4..w.len() - 1];
        assert!(
            body == [0x19, 0x00] || (body.len() == 4 && body[..2] == [0x1a, 0x05]),
            "{w:02x?}"
        );
    }
    assert!(f.bench.keys.lock().unwrap().is_empty());
}

#[test]
fn detection_of_an_unconfigured_ic7300_probes_it_and_proposes_it() {
    let f = fixture("http://127.0.0.1:18045", false);
    let hw = double(
        vec![port(4, "USB\\HUB\\IC7300")],
        HashMap::from([(4, (0x94, 19200))]),
        vec![],
    );
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw.clone());
    let v = radio_setup::detect(&f.state).unwrap();
    assert_eq!(
        v["proposal"]["control"]["endpoint"],
        "icom7300://COM4?baud=19200&radio=94&controller=e0"
    );
    assert_eq!(v["proposal"]["audio"]["input_device"], CAPTURE);
    assert_eq!(v["settings"]["source"], "probe");
    assert_eq!(v["settings"]["civ_baud"], 19200);
    assert_eq!(v["ports"][0]["audio"]["input"]["state"], "one");
    // Two supported radios: no proposal.
    let hw = double(
        vec![port(4, "USB\\HUB\\IC7300"), port(6, "USB\\HUB\\Z")],
        HashMap::from([(4, (0x94, 19200)), (6, (0x94, 9600))]),
        vec![],
    );
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw);
    let v = radio_setup::detect(&f.state).unwrap();
    assert_eq!(
        (v["supported_radios"].as_u64(), v["proposal"].is_null()),
        (Some(2), true)
    );
}

#[tokio::test]
async fn http_detect_and_settings_routes_refuse_like_operating_mutations() {
    let f = fixture("http://127.0.0.1:18046", false);
    let hw = double(vec![], HashMap::new(), vec![]);
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw);
    let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"keying_inhibit_confirmed":true});
    let (s, v, _, _) = f.call("POST", "/radio/detect", Some(body.clone())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(
        (v["ports"].as_array().map(Vec::len), v["proposal"].is_null()),
        (Some(0), true)
    );
    let other = profile::new_uuid().unwrap();
    let cases = [
        (
            json!({"v":1,"profile_id":other,"boot_id":f.boot,"keying_inhibit_confirmed":true}),
            StatusCode::FORBIDDEN,
            "wrong_profile",
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":other,"keying_inhibit_confirmed":true}),
            StatusCode::CONFLICT,
            "state_conflict",
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"keying_inhibit_confirmed":true,"x":1}),
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({"v":2,"profile_id":f.id,"boot_id":f.boot,"keying_inhibit_confirmed":true}),
            StatusCode::BAD_REQUEST,
            "unsupported_version",
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot}),
            StatusCode::BAD_REQUEST,
            "invalid_request",
        ),
        (
            json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"keying_inhibit_confirmed":false}),
            StatusCode::CONFLICT,
            "confirmation_required",
        ),
    ];
    for (b, status, code) in cases {
        let (s, v, _, _) = f.call("POST", "/radio/detect", Some(b)).await;
        assert_eq!((s, v["error"]["code"].as_str()), (status, Some(code)));
    }
    let bytes = serde_json::to_vec(&body).unwrap();
    let (s, v, _, _) = f
        .raw(
            "POST",
            "/radio/detect",
            Some("http://evil.example"),
            Some(bytes.clone()),
            &[],
        )
        .await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (StatusCode::FORBIDDEN, Some("forbidden_origin"))
    );
    let (s, _, _, _) = f
        .raw(
            "POST",
            "/radio/detect?x=1",
            Some(&f.origin),
            Some(bytes.clone()),
            &[],
        )
        .await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    f.state
        .recording
        .radio_setup
        .busy
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let (s, v, _, _) = f.call("POST", "/radio/detect", Some(body.clone())).await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (StatusCode::CONFLICT, Some("busy"))
    );
    f.state
        .recording
        .radio_setup
        .busy
        .store(false, std::sync::atomic::Ordering::SeqCst);
    let settings = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"connection_generation":0});
    for path in ["/radio/settings/apply", "/radio/settings/undo"] {
        let (s, v, _, _) = f.call("POST", path, Some(settings.clone())).await;
        assert_eq!(s, StatusCode::CONFLICT, "{path} {v}");
        let (s, v, _, _) = f
            .call(
                "POST",
                path,
                Some(json!({"v":1,"profile_id":other,"boot_id":f.boot,"connection_generation":0})),
            )
            .await;
        assert_eq!(
            (s, v["error"]["code"].as_str()),
            (StatusCode::FORBIDDEN, Some("wrong_profile"))
        );
        let (s, _, _, _) = f
            .raw(
                "POST",
                path,
                Some("http://evil.example"),
                Some(serde_json::to_vec(&settings).unwrap()),
                &[],
            )
            .await;
        assert_eq!(s, StatusCode::FORBIDDEN);
    }
    let (_, v, _, _) = f.call("POST", "/radio/settings/undo", Some(settings)).await;
    assert_eq!(v["error"]["code"], "nothing_to_undo");
}

#[tokio::test]
async fn profile_put_refuses_friendly_names_and_accepts_endpoint_ids() {
    let f = fixture("http://127.0.0.1:18047", false);
    let put = |revision: u64, input: Value, output: Value| {
        json!({"profile_id":f.id,"revision":revision,"settings":{"display_name":"Contact fixture","callsign":"HB9BLA",
            "locator":"JN47AA","audio":{"input_device":input,"output_device":output},
            "control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}}})
    };
    for (input, output, field) in [
        (
            json!(null),
            json!("Speakers (USB Audio CODEC )"),
            "settings.audio.output_device",
        ),
        (json!(null), json!(CAPTURE), "settings.audio.output_device"),
        (json!(RENDER), json!(null), "settings.audio.input_device"),
    ] {
        let (s, v, _, _) = f.call("PUT", "/profile", Some(put(0, input, output))).await;
        assert_eq!(
            (s, v["error"]["code"].as_str(), v["error"]["field"].as_str()),
            (
                StatusCode::BAD_REQUEST,
                Some("audio_device_not_endpoint"),
                Some(field)
            )
        );
    }
    assert_eq!(
        f.state.store.lock().unwrap().document.revision,
        0,
        "nothing saved"
    );
    let (s, v, _, _) = f
        .call(
            "PUT",
            "/profile",
            Some(put(0, json!(CAPTURE), json!(RENDER))),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let (s, _, _, _) = f
        .call("PUT", "/profile", Some(put(1, json!(null), json!(null))))
        .await;
    assert_eq!(s, StatusCode::OK);
}

#[test]
fn startup_migration_replaces_unique_friendly_names_only() {
    let dir = std::env::temp_dir().join(format!("wstx-migrate-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let id = profile::new_uuid().unwrap();
    let write = |input: Value, output: Value| {
        let doc = json!({"schema_version":1,"profile_id":id,"revision":4,"display_name":"Migration","callsign":"HB9BLA",
            "locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18048","origin":null},"connection_type":"standard",
            "audio":{"input_device":input,"output_device":output},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
        std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    };
    let endpoints = double(vec![], HashMap::new(), vec![]).endpoints.clone();
    let mut duplicated = endpoints.clone();
    duplicated.push(AudioEndpoint {
        id: "{0.0.1.00000000}.{00000000-0000-4000-8000-0000000000dd}".into(),
        name: "Microphone (USB Audio CODEC )".into(),
        flow: Flow::Capture,
        topology: Topology::default(),
    });
    // Unique render name migrates; the friendly name loads without failing first.
    write(json!(CAPTURE), json!("Speakers (USB Audio CODEC )"));
    {
        let (mut store, _) = profile::Store::open(&dir).unwrap();
        assert!(radio_setup::needs_migration(&store.document));
        let log = radio_setup::migrate_devices(&mut store, &endpoints);
        assert_eq!(
            log,
            [format!(
                "profile: audio.output_device migrated to endpoint {RENDER}"
            )]
        );
        assert_eq!(store.document.revision, 5);
    }
    let saved: Value =
        serde_json::from_slice(&std::fs::read(dir.join("profile.json")).unwrap()).unwrap();
    assert_eq!(
        (
            saved["audio"]["output_device"].as_str(),
            saved["revision"].as_u64()
        ),
        (Some(RENDER), Some(5))
    );
    // Ambiguous and unknown names stay, with their reasons; nothing saved.
    write(
        json!("Microphone (USB Audio CODEC )"),
        json!("Speakers (Gone)"),
    );
    let (mut store, _) = profile::Store::open(&dir).unwrap();
    let log = radio_setup::migrate_devices(&mut store, &duplicated);
    assert_eq!(
        log,
        [
            "profile: audio.input_device is not an endpoint ID (ambiguous)",
            "profile: audio.output_device is not an endpoint ID (not_found)"
        ]
    );
    assert_eq!(store.document.revision, 4);
    assert_eq!(
        store.document.audio.input_device.as_deref(),
        Some("Microphone (USB Audio CODEC )")
    );
    drop(store);
    let _ = std::fs::remove_dir_all(&dir);
}

/// CL-044-07: a listing double whose endpoints can be unplugged or fail.
struct Listing {
    ports: Vec<PortInfo>,
    endpoints: Mutex<Option<Vec<AudioEndpoint>>>,
}
impl radio_setup::Hardware for Listing {
    fn ports(&self) -> Result<Vec<PortInfo>, cat::Error> {
        Ok(self.ports.clone())
    }
    fn endpoints(&self) -> Result<Vec<AudioEndpoint>, cat::Error> {
        self.endpoints
            .lock()
            .unwrap()
            .clone()
            .ok_or(cat::Error::Unavailable)
    }
    fn open(&self, _: u16, _: Instant, _: &AtomicBool) -> Result<Box<dyn Transport>, cat::Error> {
        panic!("listing endpoints never opens a port")
    }
}

// Proves: CL-044-07; TC-044-006 (d)-(e). Hand-written endpoint list; expected labels by hand.
#[tokio::test]
async fn audio_endpoints_list_names_remember_saved_names_and_name_the_receive_input() {
    let f = fixture("http://127.0.0.1:18049", false);
    {
        let mut store = f.state.store.lock().unwrap();
        store.document.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some("COM3".into()),
            ptt: "cat".into(),
        };
        store.document.audio.input_device = Some(CAPTURE.into());
    }
    let hw = Arc::new(Listing {
        ports: vec![port(3, "USB\\HUB\\IC7300")],
        endpoints: Mutex::new(Some(
            double(vec![], HashMap::new(), vec![]).endpoints.clone(),
        )),
    });
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw.clone());
    let (s, v, _, _) = f.call("GET", "/audio/endpoints", None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let mut keys: Vec<_> = v.as_object().unwrap().keys().cloned().collect();
    keys.sort();
    assert_eq!(keys, ["boot_id", "inputs", "outputs", "profile_id", "v"]);
    assert_eq!(
        (v["profile_id"].as_str(), v["boot_id"].as_str()),
        (Some(f.id.as_str()), Some(f.boot.as_str()))
    );
    let mut entry: Vec<_> = v["inputs"][0]
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect();
    entry.sort();
    assert_eq!(entry, ["id", "label", "name", "present", "radio"]);
    assert_eq!(
        v["inputs"],
        json!([
            {"id":CAPTURE,"name":"Microphone (USB Audio CODEC)","label":"Microphone (USB Audio CODEC) — IC-7300","present":true,"radio":"IC-7300"},
            {"id":"{0.0.1.00000000}.{00000000-0000-4000-8000-00000000000c}","name":"Microphone (Webcam)","label":"Microphone (Webcam)","present":true,"radio":null}
        ])
    );
    assert_eq!(
        v["outputs"],
        json!([{"id":RENDER,"name":"Speakers (USB Audio CODEC)","label":"Speakers (USB Audio CODEC) — IC-7300","present":true,"radio":"IC-7300"}])
    );
    // Only the saved endpoint is remembered.
    let file = || -> Value {
        serde_json::from_slice(&std::fs::read(f.dir.join(radio_setup::NAMES_FILE)).unwrap())
            .unwrap()
    };
    assert_eq!(
        file(),
        json!({"schema_version":1,"names":{CAPTURE:"Microphone (USB Audio CODEC)"}})
    );
    // GET /receive names the live input.
    f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_live_device(CAPTURE);
    let (s, v, _, _) = f.call("GET", "/receive", None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(
        (
            v["audio"]["device_id"].as_str(),
            v["audio"]["device_name"].as_str()
        ),
        (Some(CAPTURE), Some("Microphone (USB Audio CODEC)"))
    );
    // The CODEC unplugged: listed not present by its last known name.
    hw.endpoints
        .lock()
        .unwrap()
        .as_mut()
        .unwrap()
        .retain(|e| e.id != CAPTURE);
    let (s, v, _, _) = f.call("GET", "/audio/endpoints", None).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(
        v["inputs"][1],
        json!({"id":CAPTURE,"name":"Microphone (USB Audio CODEC)","label":"Microphone (USB Audio CODEC) · not present","present":false,"radio":null})
    );
    assert_eq!(v["inputs"][0]["label"], "Microphone (Webcam)");
    // A restarted station reads the remembered names without any listing.
    *hw.endpoints.lock().unwrap() = None;
    let other = "{0.0.0.00000000}.{0d0d0d0d-1111-4222-8333-944444444444}";
    f.state.store.lock().unwrap().document.audio.output_device = Some(other.into());
    std::fs::write(
        f.dir.join(radio_setup::NAMES_FILE),
        serde_json::to_vec(&json!({"schema_version":1,"names":{other:"Speakers (Old radio)"}}))
            .unwrap(),
    )
    .unwrap();
    radio_setup::startup_names(&f.state);
    assert_eq!(
        f.state.recording.radio_setup.name(other).as_deref(),
        Some("Speakers (Old radio)")
    );
    assert_eq!(
        f.state.recording.radio_setup.name(RENDER),
        None,
        "names come only from the record"
    );
    // (e) refusals: a query, an enumeration failure.
    let (s, v, _, _) = f.call("GET", "/audio/endpoints?x=1", None).await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (StatusCode::BAD_REQUEST, Some("invalid_request"))
    );
    let (s, v, _, _) = f.call("GET", "/audio/endpoints", None).await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (StatusCode::CONFLICT, Some("audio_unavailable"))
    );
}

/// The saved control of a fixture: IC-7300 CAT on `port`, saved once.
fn saved_on(f: &Fixture, port: u16) {
    let mut store = f.state.store.lock().unwrap();
    let mut settings = store.document.settings();
    settings.control = profile::Control {
        mode: "cat".into(),
        endpoint: Some(format!("COM{port}")),
        ptt: "cat".into(),
    };
    settings.radio = Some(profile::Radio {
        agc: wstx_rust::radio_control::setup::Agc::Mid,
        power_limit_pct: Some(10),
    });
    store.save(settings).unwrap();
}
fn hardware_of(f: &Fixture, hw: &Arc<Double>) {
    *f.state.recording.radio_setup.hardware.lock().unwrap() = Some(hw.clone());
}
fn saved_control(f: &Fixture) -> (profile::Control, u64) {
    let store = f.state.store.lock().unwrap();
    (store.document.control.clone(), store.document.revision)
}
fn only_id_reads(hw: &Double) {
    for write in hw.writes.lock().unwrap().iter() {
        assert_eq!(&write[4..write.len() - 1], &[0x19, 0], "{write:02x?}");
    }
}

// Proves: CL-044-15; TC-044-020.
#[test]
fn discovery_keeps_a_saved_radio_that_answers() {
    let f = fixture("http://127.0.0.1:18047", false);
    saved_on(&f, 3);
    let before = saved_control(&f);
    let hw = double(
        vec![port(3, "USB\\HUB\\A"), port(5, "USB\\HUB\\IC7300")],
        HashMap::from([(3, (0x94, 19200)), (5, (0x94, 19200))]),
        vec![],
    );
    hardware_of(&f, &hw);
    assert_eq!(radio_setup::discover_on_start(&f.state), None);
    assert_eq!(saved_control(&f), before);
    assert_eq!(
        *hw.opened.lock().unwrap(),
        vec![3],
        "no other port is touched"
    );
    only_id_reads(&hw);
}

// Proves: CL-044-15; TC-044-020. Two transceivers on one PC: the second station process
// takes the next free one; its audio follows; the confirmation is not carried over.
#[test]
fn discovery_takes_the_next_free_radio_with_its_audio_when_the_saved_one_is_held() {
    let f = fixture("http://127.0.0.1:18048", false);
    saved_on(&f, 3);
    std::fs::write(f.dir.join(crate::radio_level::LEVEL_FILE), "{}").unwrap();
    let revision = saved_control(&f).1;
    let hw = double(
        vec![
            port(3, "USB\\HUB\\A"),
            port(4, "USB\\HUB\\B"),
            port(5, "USB\\HUB\\C"),
            port(6, "USB\\HUB\\IC7300"),
        ],
        // COM3 is the saved one, held; COM4 another station's; COM5 silent; COM6 free.
        HashMap::from([(6, (0x94, 19200))]),
        vec![3, 4],
    );
    hardware_of(&f, &hw);
    let line = radio_setup::discover_on_start(&f.state).unwrap();
    assert_eq!(
        line,
        "radio discovery: COM6 (IC-7300) is this station's radio"
    );
    let (control, after) = saved_control(&f);
    assert_eq!(after, revision + 1);
    assert_eq!(
        control,
        profile::Control {
            mode: "cat".into(),
            endpoint: Some("icom7300://COM6?baud=19200&radio=94&controller=e0".into()),
            ptt: "cat".into(),
        }
    );
    let store = f.state.store.lock().unwrap();
    assert_eq!(store.document.audio.input_device.as_deref(), Some(CAPTURE));
    assert_eq!(store.document.audio.output_device.as_deref(), Some(RENDER));
    assert_eq!(
        store.document.radio.map(|r| r.power_limit_pct),
        Some(Some(10)),
        "the radio settings stay"
    );
    assert!(
        !f.dir.join(crate::radio_level::LEVEL_FILE).exists(),
        "the Tx level belonged to the other radio"
    );
    assert!(
        !matches!(
            crate::authorization_http::cat_gate(
                &store,
                f.state.authorization.lock().unwrap().as_ref()
            ),
            crate::cat_lifecycle::Gate::Eligible { .. }
        ),
        "no CAT before the operator confirms this radio"
    );
    drop(store);
    assert_eq!(*hw.opened.lock().unwrap(), vec![3, 4, 5, 6]);
    only_id_reads(&hw);
}

// Proves: CL-044-15; TC-044-020.
#[test]
fn discovery_changes_nothing_without_a_free_radio_or_against_a_saved_disabled() {
    // Nothing else free: the saved radio stays for the lifecycle's retries.
    let f = fixture("http://127.0.0.1:18049", false);
    saved_on(&f, 3);
    let before = saved_control(&f);
    let hw = double(
        vec![port(3, "USB\\HUB\\A"), port(4, "USB\\HUB\\B")],
        HashMap::new(),
        vec![4],
    );
    hardware_of(&f, &hw);
    assert_eq!(radio_setup::discover_on_start(&f.state), None);
    assert_eq!(saved_control(&f), before);
    // An operator's saved Disabled opens nothing.
    let f = fixture("http://127.0.0.1:18050", false);
    {
        let mut store = f.state.store.lock().unwrap();
        let settings = store.document.settings();
        store.save(settings).unwrap();
    }
    let hw = double(
        vec![port(3, "USB\\HUB\\A")],
        HashMap::from([(3, (0x94, 19200))]),
        vec![],
    );
    hardware_of(&f, &hw);
    assert_eq!(radio_setup::discover_on_start(&f.state), None);
    assert!(hw.opened.lock().unwrap().is_empty());
}

// Proves: CL-044-15; TC-044-020. A profile never saved takes the first radio this station
// supports; a radio without station CAT and a port without a radio bridge are passed over.
#[test]
fn discovery_sets_up_a_profile_never_saved() {
    let f = fixture("http://127.0.0.1:18051", false);
    assert_eq!(saved_control(&f).1, 0);
    let hw = double(
        vec![
            PortInfo {
                port: 2,
                instance_id: "FTDIBUS\\VID_0403+PID_6001+A1\\0000".into(),
                friendly_name: None,
                topology: Topology {
                    usb_device: Some("USB\\VID_0403&PID_6001\\A1".into()),
                    ..Default::default()
                },
            },
            port(5, "USB\\HUB\\IC705"),
            port(6, "USB\\HUB\\IC7300"),
        ],
        HashMap::from([(5, (0xa4, 115200)), (6, (0x94, 9600))]),
        vec![],
    );
    hardware_of(&f, &hw);
    assert!(radio_setup::discover_on_start(&f.state).is_some());
    let (control, revision) = saved_control(&f);
    assert_eq!(revision, 1);
    assert_eq!(
        control.endpoint.as_deref(),
        Some("icom7300://COM6?baud=9600&radio=94&controller=e0")
    );
    assert_eq!(control.ptt, "cat");
    assert_eq!(*hw.opened.lock().unwrap(), vec![5, 6], "no FTDI board");
    only_id_reads(&hw);
}
