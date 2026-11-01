// Proves: CL-044-01; CL-044-02; CL-044-03; CL-044-05; TC-044-001; TC-044-002.
// Independent hand-written CI-V scripts (IC-7300 Full Manual section 19 command table)
// drive the probe over a scripted serial port that records every configure and write.
use super::*;
use std::collections::{HashMap, VecDeque};

#[derive(Clone, Debug, PartialEq, Eq)]
enum Event {
    Configure(u32),
    Write(Vec<u8>),
}
#[derive(Clone)]
struct Radio {
    address: u8,
    id: u8,
    baud: u32,
    broadcast: bool,
}
#[derive(Default)]
struct Port {
    radios: Vec<Radio>,
    baud: u32,
    echo: bool,
    /// Bytes delivered before each reply: collisions and line noise.
    noise: Vec<u8>,
    /// Reads fail with Timeout instead of returning nothing.
    timeouts: bool,
    menu: HashMap<[u8; 2], Vec<u8>>,
    events: Vec<Event>,
    pending: VecDeque<u8>,
}
impl Port {
    fn reply(&mut self, from: u8, body: &[u8]) {
        let noise = self.noise.clone();
        self.pending.extend(noise);
        self.pending.extend([0xfe, 0xfe, 0xe0, from]);
        self.pending.extend(body);
        self.pending.push_back(0xfd);
    }
}
impl Transport for Port {
    fn configure(&mut self, baud: u32) -> Result<()> {
        self.baud = baud;
        self.events.push(Event::Configure(baud));
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> Result<usize> {
        assert!(
            self.events.iter().any(|e| matches!(e, Event::Configure(_))),
            "a byte was written before the line-safe configuration"
        );
        self.events.push(Event::Write(bytes.to_vec()));
        if self.echo {
            self.pending.extend(bytes);
        }
        let to = bytes[2];
        for radio in self.radios.clone() {
            if radio.baud != self.baud || !(to == radio.address || (to == 0 && radio.broadcast)) {
                continue;
            }
            match &bytes[4..bytes.len() - 1] {
                [0x19, 0x00] => self.reply(radio.address, &[0x19, 0x00, radio.id]),
                [0x1a, 0x05, hi, lo] => match self.menu.get(&[*hi, *lo]).cloned() {
                    Some(data) => {
                        let mut body = vec![0x1a, 0x05, *hi, *lo];
                        body.extend(data);
                        self.reply(radio.address, &body);
                    }
                    None => self.reply(radio.address, &[0xfa]),
                },
                _ => self.reply(radio.address, &[0xfa]),
            }
        }
        Ok(bytes.len())
    }
    fn read(&mut self, bytes: &mut [u8], deadline: Instant, _: &AtomicBool) -> Result<usize> {
        if self.pending.is_empty() {
            if self.timeouts {
                std::thread::sleep(Duration::from_millis(5));
                return Err(Error::Timeout);
            }
            std::thread::sleep(
                Duration::from_millis(1).min(deadline - Instant::now().min(deadline)),
            );
            return Ok(0);
        }
        let n = bytes.len().min(self.pending.len());
        for b in bytes.iter_mut().take(n) {
            *b = self.pending.pop_front().unwrap();
        }
        Ok(n)
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> Result<()> {
        self.pending.clear();
        Ok(())
    }
    fn close(&mut self) -> Result<()> {
        Ok(())
    }
}
fn ic7300(baud: u32, broadcast: bool) -> Radio {
    Radio {
        address: 0x94,
        id: 0x94,
        baud,
        broadcast,
    }
}
fn run(port: &mut Port) -> Vec<Identity> {
    probe(
        port,
        Instant::now() + Duration::from_secs(10),
        &AtomicBool::new(false),
    )
    .unwrap()
}
/// Every frame a probe wrote is an ID read (broadcast or a model-table address) or a
/// 1A 05 menu read of a checked item with no data: never a setting, frequency, mode
/// or transmit command.
fn assert_read_only(port: &Port) {
    let addresses: Vec<u8> = vec![0x00, 0x94, 0xa4, 0xa2, 0x98];
    let items: Vec<[u8; 2]> = vec![
        [0x00, 0x65],
        [0x00, 0x66],
        [0x00, 0x67],
        [0x00, 0x71],
        [0x00, 0x78],
        [0x00, 0x79],
        [0x00, 0x80],
    ];
    for event in &port.events {
        let Event::Write(w) = event else { continue };
        assert_eq!(&w[..2], &[0xfe, 0xfe], "{w:02x?}");
        assert!(addresses.contains(&w[2]) && w[3] == 0xe0, "{w:02x?}");
        assert_eq!(w.last(), Some(&0xfd));
        let body = &w[4..w.len() - 1];
        let id_read = body == [0x19, 0x00];
        let menu_read =
            body.len() == 4 && body[..2] == [0x1a, 0x05] && items.contains(&[body[2], body[3]]);
        assert!(
            id_read || menu_read,
            "probe wrote a non-read frame {w:02x?}"
        );
    }
}

#[test]
fn ic7300_answers_broadcast_at_19200_with_echo() {
    let mut port = Port {
        radios: vec![ic7300(19200, true)],
        echo: true,
        ..Default::default()
    };
    let found = run(&mut port);
    assert_eq!(
        found,
        vec![Identity {
            baud: 19200,
            address: 0x94,
            id: 0x94
        }]
    );
    assert_eq!(model(0x94).unwrap().name, "IC-7300");
    assert!(model(0x94).unwrap().station_cat);
    assert_eq!(port.events[0], Event::Configure(9600));
    assert!(port.events.contains(&Event::Write(vec![
        0xfe, 0xfe, 0x00, 0xe0, 0x19, 0x00, 0xfd
    ])));
    assert!(
        !port.events.contains(&Event::Configure(38400)),
        "stops at the first answering rate"
    );
    assert_read_only(&port);
}

#[test]
fn ic705_answers_only_addressed_read_at_115200() {
    let mut port = Port {
        radios: vec![Radio {
            address: 0xa4,
            id: 0xa4,
            baud: 115200,
            broadcast: false,
        }],
        ..Default::default()
    };
    let found = run(&mut port);
    assert_eq!(
        found,
        vec![Identity {
            baud: 115200,
            address: 0xa4,
            id: 0xa4
        }]
    );
    let m = model(0xa4).unwrap();
    assert_eq!((m.name, m.station_cat), ("IC-705", false));
    assert!(port.events.contains(&Event::Write(vec![
        0xfe, 0xfe, 0xa4, 0xe0, 0x19, 0x00, 0xfd
    ])));
    let configured: Vec<_> = port
        .events
        .iter()
        .filter_map(|e| match e {
            Event::Configure(b) => Some(*b),
            _ => None,
        })
        .collect();
    assert_eq!(configured, vec![9600, 19200, 38400, 115200]);
    assert_read_only(&port);
}

#[test]
fn collisions_and_garbage_before_reply_are_not_replies() {
    let mut port = Port {
        radios: vec![ic7300(9600, true)],
        echo: true,
        noise: vec![
            0xfe, 0xfe, 0xfc, 0xfc, 0xfc, 0xfd, 0x00, 0x13, 0xfe, 0x55, 0xfd, 0xff,
        ],
        ..Default::default()
    };
    let found = run(&mut port);
    assert_eq!(found.len(), 1);
    assert_eq!(
        (found[0].address, found[0].id, found[0].baud),
        (0x94, 0x94, 9600)
    );
    assert_read_only(&port);
}

#[test]
fn silent_and_timing_out_ports_report_no_reply_after_all_rates() {
    for timeouts in [false, true] {
        let mut port = Port {
            timeouts,
            echo: true,
            ..Default::default()
        };
        assert!(run(&mut port).is_empty());
        let rates = port
            .events
            .iter()
            .filter(|e| matches!(e, Event::Configure(_)))
            .count();
        assert_eq!(rates, 4);
        // Per rate: one broadcast and the four model addresses.
        let writes = port
            .events
            .iter()
            .filter(|e| matches!(e, Event::Write(_)))
            .count();
        assert_eq!(writes, 4 * 5);
        assert_read_only(&port);
    }
}

#[test]
fn unknown_id_is_reported_with_its_id() {
    let mut port = Port {
        radios: vec![Radio {
            address: 0x70,
            id: 0x99,
            baud: 9600,
            broadcast: true,
        }],
        ..Default::default()
    };
    let found = run(&mut port);
    assert_eq!((found[0].address, found[0].id), (0x70, 0x99));
    assert!(model(0x99).is_none());
}

#[test]
fn ic7300_menu_read_and_guidance() {
    let mut port = Port {
        radios: vec![ic7300(19200, true)],
        echo: true,
        baud: 19200,
        ..Default::default()
    };
    port.events.push(Event::Configure(19200));
    for (item, data) in [
        ([0x00, 0x78], vec![0x01]),
        ([0x00, 0x79], vec![0x00]),
        ([0x00, 0x80], vec![0x02]),
        ([0x00, 0x66], vec![0x00]),
        ([0x00, 0x67], vec![0x03]),
        ([0x00, 0x71], vec![0x01]),
    ] {
        port.menu.insert(item, data);
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    let cancel = AtomicBool::new(false);
    let mut read = |s| probe_setting(&mut port, 0x94, s, deadline, &cancel).unwrap();
    let expected = [
        (Setting::UsbSend, Some(1), "blocking", "DTR"),
        (Setting::UsbKeyingCw, Some(0), "ok", "OFF"),
        (Setting::UsbKeyingRtty, Some(2), "blocking", "RTS"),
        (Setting::DataOffMod, Some(0), "information", "MIC"),
        (Setting::DataMod, Some(3), "ok", "USB"),
        (Setting::CivTransceive, Some(1), "advice", "ON"),
        // 0065 is refused (FA) by this radio script.
        (Setting::UsbModLevel, None, "unreadable", ""),
    ];
    for (setting, value, severity, label) in expected {
        let got = read(setting);
        assert_eq!(got, value, "{setting:?}");
        assert_eq!(guidance(setting, got).severity, severity, "{setting:?}");
        if let Some(v) = got {
            assert_eq!(setting.label(v), label);
        }
    }
    assert!(port.events.contains(&Event::Write(vec![
        0xfe, 0xfe, 0x94, 0xe0, 0x1a, 0x05, 0x00, 0x78, 0xfd
    ])));
    assert_read_only(&port);
}

#[test]
fn menu_values_are_bcd_with_hand_table() {
    assert_eq!(Setting::UsbModLevel.decode(&[0x01, 0x28]).unwrap(), 128);
    assert_eq!(Setting::UsbModLevel.encode(255).unwrap(), vec![0x02, 0x55]);
    assert_eq!(Setting::UsbModLevel.label(128), "50%");
    assert_eq!(guidance(Setting::UsbModLevel, Some(0)).severity, "blocking");
    assert_eq!(guidance(Setting::DataMod, Some(4)).severity, "advice");
    assert_eq!(guidance(Setting::DataMod, Some(0)).severity, "blocking");
    assert!(
        Setting::UsbSend.decode(&[0x03]).is_err(),
        "out of the 00..02 domain"
    );
    assert!(Setting::DataMod.decode(&[0x0a]).is_err(), "not BCD");
    assert!(Setting::UsbSend.encode(3).is_err());
    assert_eq!(
        write_setting_frame(0x94, Setting::DataMod, 3).unwrap(),
        vec![0xfe, 0xfe, 0x94, 0xe0, 0x1a, 0x05, 0x00, 0x67, 0x03, 0xfd]
    );
    let item_numbers: Vec<_> = SETTINGS.iter().map(|s| s.item_text()).collect();
    assert_eq!(
        item_numbers,
        ["0066", "0067", "0065", "0071", "0078", "0079", "0080"]
    );
}

#[test]
fn plan_writes_only_differing_readable_items_in_safe_order() {
    let readings = [
        (Setting::UsbSend, Some(1)),
        (Setting::UsbKeyingCw, Some(0)),
        (Setting::UsbKeyingRtty, Some(2)),
        (Setting::DataMod, Some(0)),
        (Setting::CivTransceive, None),
        (Setting::UsbModLevel, Some(0)),
        (Setting::DataOffMod, Some(1)),
    ];
    assert_eq!(
        plan(&readings),
        vec![
            (Setting::UsbSend, 1, 0),
            (Setting::UsbKeyingRtty, 2, 0),
            (Setting::DataMod, 0, 3),
        ]
    );
}

fn topology(container: Option<&str>, parent: &str) -> Topology {
    Topology {
        container_id: container.map(Into::into),
        usb_device: Some(format!("USB\\VID_10C4&PID_EA60\\{parent}-dev")),
        usb_parent: Some(parent.into()),
    }
}
fn endpoint(id: &str, name: &str, flow: Flow, topology: Topology) -> AudioEndpoint {
    AudioEndpoint {
        id: id.into(),
        name: name.into(),
        flow,
        topology,
    }
}
const CAPTURE: &str = "{0.0.1.00000000}.{11111111-2222-3333-4444-555555555555}";
const RENDER: &str = "{0.0.0.00000000}.{f4069c8a-0000-4000-8000-000000000001}";

#[test]
fn audio_endpoints_match_by_shared_usb_parent() {
    let hub = "USB\\VID_0424&PID_2512\\6&1";
    let port = PortInfo {
        port: 3,
        instance_id: "USB\\VID_10C4&PID_EA60\\IC-7300".into(),
        friendly_name: Some("Silicon Labs CP210x USB to UART Bridge (COM3)".into()),
        topology: topology(None, hub),
    };
    assert_eq!(port.vid_pid(), Some(("10C4".into(), "EA60".into())));
    let codec_in = endpoint(
        CAPTURE,
        "Microphone (USB Audio CODEC )",
        Flow::Capture,
        topology(None, hub),
    );
    let codec_out = endpoint(
        RENDER,
        "Speakers (USB Audio CODEC )",
        Flow::Render,
        topology(None, hub),
    );
    let webcam = endpoint(
        "{0.0.1.00000000}.{99999999-2222-3333-4444-555555555555}",
        "Microphone (Webcam)",
        Flow::Capture,
        topology(None, "USB\\VID_8086&PID_0001\\other"),
    );
    // (a) the CODEC under the radio's hub; the webcam elsewhere.
    let all = [codec_in.clone(), codec_out.clone(), webcam];
    assert_eq!(
        match_audio(&port, &all, Flow::Capture),
        Match::One(codec_in.clone())
    );
    assert_eq!(
        match_audio(&port, &all, Flow::Render),
        Match::One(codec_out.clone())
    );
    // (b) two captures under the hub: ambiguous, render still proposed.
    let mut second = codec_in.clone();
    second.id = "{0.0.1.00000000}.{22222222-2222-3333-4444-555555555555}".into();
    let two = [codec_in.clone(), second, codec_out.clone()];
    assert_eq!(match_audio(&port, &two, Flow::Capture), Match::Ambiguous(2));
    assert_eq!(
        match_audio(&port, &two, Flow::Render),
        Match::One(codec_out)
    );
    // (c) same container, different parents.
    let shared = "{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}";
    let mut port_c = port.clone();
    port_c.topology = topology(Some(shared), "USB\\HUB\\x");
    let in_c = endpoint(
        CAPTURE,
        "c",
        Flow::Capture,
        topology(Some(shared), "USB\\HUB\\y"),
    );
    assert_eq!(
        match_audio(&port_c, std::slice::from_ref(&in_c), Flow::Capture),
        Match::One(in_c)
    );
    // (d) only a root hub parent in common, the null container is no container.
    let root = "USB\\ROOT_HUB30\\4&2";
    let mut port_d = port.clone();
    port_d.topology = topology(
        container("{00000000-0000-0000-FFFF-FFFFFFFFFFFF}").as_deref(),
        root,
    );
    let in_d = endpoint(CAPTURE, "d", Flow::Capture, topology(None, root));
    assert_eq!(match_audio(&port_d, &[in_d], Flow::Capture), Match::None);
}

#[test]
fn endpoint_id_syntax_and_friendly_name_migration() {
    assert!(endpoint_id(CAPTURE, Flow::Capture));
    assert!(endpoint_id(RENDER, Flow::Render));
    assert!(endpoint_id(&RENDER.to_ascii_uppercase(), Flow::Render));
    assert!(
        !endpoint_id(CAPTURE, Flow::Render),
        "capture ID is no output device"
    );
    assert!(!endpoint_id(RENDER, Flow::Capture));
    for bad in [
        "Speakers (USB Audio CODEC )",
        "",
        "{0.0.0.00000000}.{f4069c8a-0000-4000-8000-00000000000}",
        "{0.0.0.00000000}.{f4069c8a-0000-4000-8000-000000000001}x",
        "{0.0.0.00000000}.{g4069c8a-0000-4000-8000-000000000001}",
    ] {
        assert!(!endpoint_id(bad, Flow::Render), "{bad}");
    }
    let hub = topology(None, "h");
    let list = [
        endpoint(
            RENDER,
            "Speakers (USB Audio CODEC )",
            Flow::Render,
            hub.clone(),
        ),
        endpoint(
            CAPTURE,
            "Speakers (USB Audio CODEC )",
            Flow::Capture,
            hub.clone(),
        ),
        endpoint(
            "{0.0.0.00000000}.{00000000-0000-4000-8000-000000000002}",
            "Speakers (Realtek)",
            Flow::Render,
            hub.clone(),
        ),
        endpoint(
            "{0.0.0.00000000}.{00000000-0000-4000-8000-000000000003}",
            "Speakers (Realtek)",
            Flow::Render,
            hub,
        ),
    ];
    assert_eq!(
        migrate("Speakers (USB Audio CODEC )", &list, Flow::Render),
        Migration::Migrated(RENDER.into())
    );
    assert_eq!(
        migrate("Speakers (Realtek)", &list, Flow::Render),
        Migration::Ambiguous
    );
    assert_eq!(
        migrate("Speakers (USB Audio CODEC)", &list, Flow::Render),
        Migration::NotFound
    );
    assert_eq!(migrate(RENDER, &list, Flow::Render), Migration::Unchanged);
}
