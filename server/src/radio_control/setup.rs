#![forbid(unsafe_code)]
//! #44 radio detection and IC-7300 setup (CL-044-01..05). Portable rules only: the
//! probe runs over any `Transport`, the topology and endpoint lists are plain data.
//! Probing writes nothing but the frames of `ProbeFrame`; menu writes exist only as
//! `Setting` values the executor sends through the station's CAT owner.
use super::{
    Error, Result,
    codec::{Framer, MAX_READ},
    executor::Transport,
};
use std::{
    sync::atomic::AtomicBool,
    time::{Duration, Instant},
};

/// Rates of the read-only probe, in probe order (CL-044-01).
pub const PROBE_BAUDS: [u32; 4] = [9600, 19200, 38400, 115200];
pub const CONTROLLER: u8 = 0xe0;
const BROADCAST_WINDOW: Duration = Duration::from_millis(250);
const ADDRESSED_WINDOW: Duration = Duration::from_millis(120);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Model {
    /// Transceiver ID returned by 19 00, which is also the radio's default CI-V address.
    pub id: u8,
    pub name: &'static str,
    /// True only where this station has a CAT implementation (CL-022, catalogue).
    pub station_cat: bool,
}
pub const MODELS: [Model; 4] = [
    Model {
        id: 0x94,
        name: "IC-7300",
        station_cat: true,
    },
    Model {
        id: 0xa4,
        name: "IC-705",
        station_cat: false,
    },
    Model {
        id: 0xa2,
        name: "IC-9700",
        station_cat: false,
    },
    Model {
        id: 0x98,
        name: "IC-7610",
        station_cat: false,
    },
];
pub fn model(id: u8) -> Option<Model> {
    MODELS.iter().copied().find(|m| m.id == id)
}
/// Text-CAT families that are listed for manual setup and never probed (CL-044-01).
pub const MANUAL_FAMILIES: [&str; 3] = ["Yaesu", "Kenwood", "Elecraft"];

/// IC-7300 1A 05 menu items read by the settings check. Item numbers and value
/// encodings: Icom IC-7300 Full Manual, section 19, command table pages 19-4/19-5.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Setting {
    /// 0065 MOD input level from USB, 0000..0255.
    UsbModLevel,
    /// 0066 MOD input connector during DATA OFF (00 MIC, 01 ACC, 02 MIC/ACC, 03 USB, 04 MIC/USB).
    DataOffMod,
    /// 0067 MOD input connector during DATA (same encoding).
    DataMod,
    /// 0071 CI-V transceive (00 OFF, 01 ON).
    CivTransceive,
    /// 0078 transmission control line for USB, "USB SEND" (00 OFF, 01 DTR, 02 RTS).
    UsbSend,
    /// 0079 CW keying line for USB (00 OFF, 01 DTR, 02 RTS).
    UsbKeyingCw,
    /// 0080 RTTY (FSK) keying line for USB (00 OFF, 01 DTR, 02 RTS).
    UsbKeyingRtty,
}
pub const SETTINGS: [Setting; 7] = [
    Setting::DataOffMod,
    Setting::DataMod,
    Setting::UsbModLevel,
    Setting::CivTransceive,
    Setting::UsbSend,
    Setting::UsbKeyingCw,
    Setting::UsbKeyingRtty,
];
/// Apply order: keying lines first, so every step moves towards "cannot key".
pub const APPLY_ORDER: [Setting; 5] = [
    Setting::UsbSend,
    Setting::UsbKeyingCw,
    Setting::UsbKeyingRtty,
    Setting::DataMod,
    Setting::CivTransceive,
];
impl Setting {
    /// The two BCD bytes of the 1A 05 item number.
    pub fn item(self) -> [u8; 2] {
        match self {
            Self::UsbModLevel => [0x00, 0x65],
            Self::DataOffMod => [0x00, 0x66],
            Self::DataMod => [0x00, 0x67],
            Self::CivTransceive => [0x00, 0x71],
            Self::UsbSend => [0x00, 0x78],
            Self::UsbKeyingCw => [0x00, 0x79],
            Self::UsbKeyingRtty => [0x00, 0x80],
        }
    }
    pub fn item_text(self) -> String {
        let [a, b] = self.item();
        format!("{a:02x}{b:02x}")
    }
    pub fn from_item(text: &str) -> Option<Self> {
        SETTINGS.into_iter().find(|s| s.item_text() == text)
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::UsbModLevel => "usb_mod_level",
            Self::DataOffMod => "data_off_mod",
            Self::DataMod => "data_mod",
            Self::CivTransceive => "civ_transceive",
            Self::UsbSend => "usb_send",
            Self::UsbKeyingCw => "usb_keying_cw",
            Self::UsbKeyingRtty => "usb_keying_rtty",
        }
    }
    fn width(self) -> usize {
        if self == Self::UsbModLevel { 2 } else { 1 }
    }
    pub fn maximum(self) -> u16 {
        match self {
            Self::UsbModLevel => 255,
            Self::DataOffMod | Self::DataMod => 4,
            Self::CivTransceive => 1,
            Self::UsbSend | Self::UsbKeyingCw | Self::UsbKeyingRtty => 2,
        }
    }
    /// The value "Apply recommended radio settings" writes (CL-044-04); None: never written.
    pub fn recommended(self) -> Option<u16> {
        match self {
            Self::UsbSend | Self::UsbKeyingCw | Self::UsbKeyingRtty => Some(0),
            Self::DataMod => Some(3),
            Self::CivTransceive => Some(0),
            Self::UsbModLevel | Self::DataOffMod => None,
        }
    }
    pub fn label(self, value: u16) -> String {
        match self {
            Self::UsbModLevel => format!("{}%", (u32::from(value) * 100 + 127) / 255),
            Self::DataOffMod | Self::DataMod => ["MIC", "ACC", "MIC/ACC", "USB", "MIC/USB"]
                .get(usize::from(value))
                .map_or_else(|| format!("{value}"), |s| (*s).into()),
            Self::CivTransceive => if value == 0 { "OFF" } else { "ON" }.into(),
            Self::UsbSend | Self::UsbKeyingCw | Self::UsbKeyingRtty => ["OFF", "DTR", "RTS"]
                .get(usize::from(value))
                .map_or_else(|| format!("{value}"), |s| (*s).into()),
        }
    }
    /// BCD data bytes of a value (CI-V menu data is BCD, two digits per byte).
    pub fn encode(self, value: u16) -> Result<Vec<u8>> {
        if value > self.maximum() {
            return Err(Error::InvalidRequest);
        }
        let bcd = |n: u16| (((n / 10) as u8) << 4) | (n % 10) as u8;
        Ok(if self.width() == 2 {
            vec![bcd(value / 100), bcd(value % 100)]
        } else {
            vec![bcd(value)]
        })
    }
    pub fn decode(self, data: &[u8]) -> Result<u16> {
        if data.len() != self.width() {
            return Err(Error::Protocol);
        }
        let mut value = 0u16;
        for byte in data {
            let (hi, lo) = (byte >> 4, byte & 15);
            if hi > 9 || lo > 9 {
                return Err(Error::Protocol);
            }
            value = value * 100 + u16::from(hi * 10 + lo);
        }
        if value > self.maximum() {
            return Err(Error::Protocol);
        }
        Ok(value)
    }
}

/// #44 CL-044-10/11 IC-7300 AGC, CI-V command 16 sub 12 with one data byte 01 FAST,
/// 02 MID, 03 SLOW; read with the same command without data (Icom IC-7300 Full Manual,
/// section 19 command table, "16 12 AGC"). The JSON names are the radio's labels.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum Agc {
    Fast,
    Mid,
    Slow,
}
impl Agc {
    pub fn code(self) -> u8 {
        match self {
            Self::Fast => 1,
            Self::Mid => 2,
            Self::Slow => 3,
        }
    }
    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            1 => Some(Self::Fast),
            2 => Some(Self::Mid),
            3 => Some(Self::Slow),
            _ => None,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Fast => "FAST",
            Self::Mid => "MID",
            Self::Slow => "SLOW",
        }
    }
}
/// FE FE <address> E0 16 12 FD: read the AGC.
pub fn read_agc_frame(address: u8) -> Vec<u8> {
    vec![0xfe, 0xfe, address, CONTROLLER, 0x16, 0x12, 0xfd]
}
/// FE FE <address> E0 16 12 <01|02|03> FD: set the AGC.
pub fn write_agc_frame(address: u8, agc: Agc) -> Vec<u8> {
    vec![
        0xfe,
        0xfe,
        address,
        CONTROLLER,
        0x16,
        0x12,
        agc.code(),
        0xfd,
    ]
}

/// Every frame a probe can emit (CL-044-01). Nothing else is ever written while probing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProbeFrame {
    ReadIdBroadcast,
    ReadId(u8),
    ReadSetting(u8, Setting),
}
impl ProbeFrame {
    pub fn bytes(self) -> Vec<u8> {
        let mut bytes = vec![0xfe, 0xfe];
        match self {
            Self::ReadIdBroadcast => bytes.extend([0x00, CONTROLLER, 0x19, 0x00]),
            Self::ReadId(address) => bytes.extend([address, CONTROLLER, 0x19, 0x00]),
            Self::ReadSetting(address, setting) => {
                bytes.extend([address, CONTROLLER, 0x1a, 0x05]);
                bytes.extend(setting.item());
            }
        }
        bytes.push(0xfd);
        bytes
    }
}
/// Frames of a menu exchange through the station's CAT owner.
pub fn read_setting_frame(address: u8, setting: Setting) -> Vec<u8> {
    ProbeFrame::ReadSetting(address, setting).bytes()
}
pub fn write_setting_frame(address: u8, setting: Setting, value: u16) -> Result<Vec<u8>> {
    let mut bytes = vec![0xfe, 0xfe, address, CONTROLLER, 0x1a, 0x05];
    bytes.extend(setting.item());
    bytes.extend(setting.encode(value)?);
    bytes.push(0xfd);
    Ok(bytes)
}

/// What one CI-V frame means to an exchange with `address` (or the broadcast).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Heard {
    Id {
        address: u8,
        id: u8,
    },
    Setting {
        address: u8,
        setting: Setting,
        data: Vec<u8>,
    },
    Ack {
        address: u8,
    },
    Ng {
        address: u8,
    },
    /// The AGC reply 16 12 <code>; the code is checked by the reader.
    Agc {
        address: u8,
        code: u8,
    },
    /// Echo of our own frame, a collision, traffic for others or an unknown body.
    Other,
}
pub fn hear(frame: &[u8]) -> Heard {
    // Framer frames start FE FE and end FD.
    if frame.len() < 6 || frame[2] != CONTROLLER || frame[3] == CONTROLLER {
        return Heard::Other;
    }
    let address = frame[3];
    if !(1..=0xef).contains(&address) {
        return Heard::Other;
    }
    match &frame[4..frame.len() - 1] {
        [0x19, 0x00, id] => Heard::Id { address, id: *id },
        [0xfb] => Heard::Ack { address },
        [0xfa] => Heard::Ng { address },
        [0x16, 0x12, code] => Heard::Agc {
            address,
            code: *code,
        },
        [0x1a, 0x05, hi, lo, data @ ..] if !data.is_empty() => {
            match SETTINGS.into_iter().find(|s| s.item() == [*hi, *lo]) {
                Some(setting) => Heard::Setting {
                    address,
                    setting,
                    data: data.to_vec(),
                },
                None => Heard::Other,
            }
        }
        _ => Heard::Other,
    }
}

/// Reads what arrives until `until`; framing garbage restarts the framer, it is never fatal.
fn listen<T: Transport + ?Sized>(
    transport: &mut T,
    until: Instant,
    cancel: &AtomicBool,
    mut done: impl FnMut(Heard) -> bool,
) -> Result<()> {
    let mut framer = Framer::default();
    let mut buffer = [0u8; MAX_READ];
    while Instant::now() < until {
        let count = match transport.read(&mut buffer, until, cancel) {
            Ok(count) => count,
            Err(Error::Timeout) => return Ok(()),
            Err(error) => return Err(error),
        };
        if count == 0 {
            std::thread::sleep(Duration::from_millis(2));
            continue;
        }
        match framer.feed(&buffer[..count.min(MAX_READ)]) {
            Ok(frames) => {
                for frame in frames {
                    if done(hear(&frame)) {
                        return Ok(());
                    }
                }
            }
            Err(_) => framer = Framer::default(),
        }
    }
    Ok(())
}
fn send<T: Transport + ?Sized>(
    transport: &mut T,
    frame: ProbeFrame,
    deadline: Instant,
    cancel: &AtomicBool,
) -> Result<()> {
    let bytes = frame.bytes();
    if transport.write(&bytes, deadline, cancel)? != bytes.len() {
        return Err(Error::PartialWrite);
    }
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Identity {
    pub baud: u32,
    pub address: u8,
    pub id: u8,
}
/// Read-only probe of one opened port (CL-044-01): per rate the broadcast ID read,
/// then the addressed ID read of each model address. Returns every radio heard at the
/// first rate any radio answered, or none.
pub fn probe<T: Transport + ?Sized>(
    transport: &mut T,
    deadline: Instant,
    cancel: &AtomicBool,
) -> Result<Vec<Identity>> {
    for baud in PROBE_BAUDS {
        transport.configure(baud)?;
        let _ = transport.quiet(
            std::cmp::min(deadline, Instant::now() + Duration::from_millis(30)),
            cancel,
        );
        let mut found: Vec<Identity> = Vec::new();
        // True ends the window: an addressed read is answered once.
        fn heard(found: &mut Vec<Identity>, baud: u32, h: Heard, wanted: Option<u8>) -> bool {
            if let Heard::Id { address, id } = h
                && wanted.is_none_or(|w| w == address)
                && !found.iter().any(|f| f.address == address)
            {
                found.push(Identity { baud, address, id });
                return wanted.is_some();
            }
            false
        }
        send(transport, ProbeFrame::ReadIdBroadcast, deadline, cancel)?;
        listen(
            transport,
            std::cmp::min(deadline, Instant::now() + BROADCAST_WINDOW),
            cancel,
            |h| heard(&mut found, baud, h, None),
        )?;
        if found.is_empty() {
            for model in MODELS {
                send(transport, ProbeFrame::ReadId(model.id), deadline, cancel)?;
                listen(
                    transport,
                    std::cmp::min(deadline, Instant::now() + ADDRESSED_WINDOW),
                    cancel,
                    |h| heard(&mut found, baud, h, Some(model.id)),
                )?;
            }
        }
        if !found.is_empty() {
            return Ok(found);
        }
        if Instant::now() >= deadline {
            return Err(Error::Timeout);
        }
    }
    Ok(Vec::new())
}
/// One menu read on an opened probe port, at the rate the radio answered at.
/// None: the radio refused it (FA) or did not answer within the window.
pub fn probe_setting<T: Transport + ?Sized>(
    transport: &mut T,
    address: u8,
    setting: Setting,
    deadline: Instant,
    cancel: &AtomicBool,
) -> Result<Option<u16>> {
    send(
        transport,
        ProbeFrame::ReadSetting(address, setting),
        deadline,
        cancel,
    )?;
    let mut value = None;
    listen(
        transport,
        std::cmp::min(deadline, Instant::now() + Duration::from_millis(300)),
        cancel,
        |h| match h {
            Heard::Setting {
                address: a,
                setting: s,
                data,
            } if a == address && s == setting => {
                value = setting.decode(&data).ok();
                true
            }
            Heard::Ng { address: a } => a == address,
            _ => false,
        },
    )?;
    Ok(value)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    pub setting: Setting,
    pub value: Option<u16>,
    /// ok, information, advice, blocking or unreadable.
    pub severity: &'static str,
    pub message: &'static str,
}
/// Guidance of the read-only settings check (CL-044-03).
pub fn guidance(setting: Setting, value: Option<u16>) -> Finding {
    let (severity, message) = match (setting, value) {
        (_, None) => ("unreadable", "The radio did not report this item."),
        (Setting::UsbSend, Some(0)) => ("ok", "USB SEND is OFF; the station keys by CI-V."),
        (Setting::UsbSend, Some(_)) => (
            "blocking",
            "USB SEND on DTR/RTS can key the transmitter when a program raises that line; set it OFF (the station keys by CI-V).",
        ),
        (Setting::UsbKeyingCw | Setting::UsbKeyingRtty, Some(0)) => ("ok", "USB keying is OFF."),
        (Setting::UsbKeyingCw | Setting::UsbKeyingRtty, Some(_)) => (
            "blocking",
            "USB keying on DTR/RTS can key the transmitter when a program raises that line; set it OFF.",
        ),
        (Setting::DataMod, Some(3)) => ("ok", "DATA MOD takes transmit audio from USB."),
        (Setting::DataMod, Some(4)) => (
            "advice",
            "DATA MOD MIC/USB also mixes the microphone into FT8 transmit audio; USB alone is recommended.",
        ),
        (Setting::DataMod, Some(_)) => (
            "blocking",
            "DATA MOD does not take audio from USB: FT8 transmit would carry no station audio; set it to USB.",
        ),
        (Setting::UsbModLevel, Some(0)) => (
            "blocking",
            "USB MOD level is 0%: transmit audio from USB is muted; raise it in the radio's menu.",
        ),
        (Setting::UsbModLevel, Some(_)) => ("ok", "USB MOD level as set in the radio."),
        (Setting::CivTransceive, Some(0)) => ("ok", "CI-V transceive is OFF."),
        (Setting::CivTransceive, Some(_)) => (
            "advice",
            "CI-V transceive ON sends unsolicited frames; OFF is recommended.",
        ),
        (Setting::DataOffMod, Some(_)) => (
            "information",
            "DATA OFF MOD applies outside data mode; the station transmits in USB-D.",
        ),
    };
    Finding {
        setting,
        value,
        severity,
        message,
    }
}
/// Items "Apply recommended radio settings" writes for these readings, in apply order.
/// An unreadable item is never written.
pub fn plan(readings: &[(Setting, Option<u16>)]) -> Vec<(Setting, u16, u16)> {
    APPLY_ORDER
        .into_iter()
        .filter_map(|setting| {
            let current = readings.iter().find(|(s, _)| *s == setting)?.1?;
            let target = setting.recommended()?;
            (current != target).then_some((setting, current, target))
        })
        .collect()
}

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Topology {
    /// Windows container ID in braces, lower case; the null container is dropped.
    pub container_id: Option<String>,
    /// Instance ID of the nearest USB device node (not an interface `&MI_`) of the device.
    pub usb_device: Option<String>,
    /// Instance ID of that USB device's parent hub.
    pub usb_parent: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PortInfo {
    pub port: u16,
    pub instance_id: String,
    pub friendly_name: Option<String>,
    pub topology: Topology,
}
impl PortInfo {
    /// USB VID and PID from the USB device's instance ID (USB\VID_xxxx&PID_xxxx\...).
    pub fn vid_pid(&self) -> Option<(String, String)> {
        let id = self
            .topology
            .usb_device
            .as_deref()
            .unwrap_or(&self.instance_id)
            .to_ascii_uppercase();
        let vid = id.split_once("VID_")?.1.get(..4)?.to_owned();
        let pid = id.split_once("PID_")?.1.get(..4)?.to_owned();
        (vid.bytes().all(|b| b.is_ascii_hexdigit()) && pid.bytes().all(|b| b.is_ascii_hexdigit()))
            .then_some((vid, pid))
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flow {
    Capture,
    Render,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AudioEndpoint {
    pub id: String,
    pub name: String,
    pub flow: Flow,
    pub topology: Topology,
}
const NULL_CONTAINER: &str = "{00000000-0000-0000-ffff-ffffffffffff}";
pub fn container(text: &str) -> Option<String> {
    let text = text.to_ascii_lowercase();
    (text != NULL_CONTAINER && text != "{00000000-0000-0000-0000-000000000000}").then_some(text)
}
/// CL-044-02 shared USB parent: same container, or same non-root parent hub.
pub fn same_usb_parent(a: &Topology, b: &Topology) -> bool {
    if let (Some(x), Some(y)) = (&a.container_id, &b.container_id)
        && x == y
    {
        return true;
    }
    match (&a.usb_parent, &b.usb_parent) {
        (Some(x), Some(y)) => {
            x.eq_ignore_ascii_case(y) && !x.to_ascii_uppercase().contains("ROOT_HUB")
        }
        _ => false,
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Match {
    One(AudioEndpoint),
    None,
    Ambiguous(usize),
}
pub fn match_audio(port: &PortInfo, endpoints: &[AudioEndpoint], flow: Flow) -> Match {
    let found: Vec<_> = endpoints
        .iter()
        .filter(|e| e.flow == flow && same_usb_parent(&port.topology, &e.topology))
        .collect();
    match found.as_slice() {
        [] => Match::None,
        [one] => Match::One((*one).clone()),
        many => Match::Ambiguous(many.len()),
    }
}

/// CL-044-07: the operator's name of an endpoint: the Windows friendly name with
/// whitespace runs collapsed, trimmed and no space inside its parentheses.
pub fn display_name(name: &str) -> String {
    name.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace("( ", "(")
        .replace(" )", ")")
}
/// One entry of a picker (CL-044-07): the endpoint ID is the value, `label` the text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EndpointChoice {
    pub id: String,
    pub name: Option<String>,
    pub label: String,
    pub present: bool,
    pub radio: Option<&'static str>,
}
/// CL-044-07: the choices of one flow. `radio` is the selected radio's port and model
/// name; `saved` the profile's endpoint of this flow with its last known name.
pub fn endpoint_choices(
    endpoints: &[AudioEndpoint],
    flow: Flow,
    radio: Option<(&PortInfo, &'static str)>,
    saved: Option<(&str, Option<&str>)>,
) -> Vec<EndpointChoice> {
    let present: Vec<_> = endpoints.iter().filter(|e| e.flow == flow).collect();
    let radio_id = radio.and_then(|(port, model)| match match_audio(port, endpoints, flow) {
        Match::One(e) => Some((e.id, model)),
        _ => None,
    });
    let mut choices: Vec<EndpointChoice> = present
        .iter()
        .map(|e| {
            let name = display_name(&e.name);
            let mut same: Vec<&str> = present
                .iter()
                .filter(|o| display_name(&o.name) == name)
                .map(|o| o.id.as_str())
                .collect();
            same.sort_unstable();
            let mut label = name.clone();
            if same.len() > 1 {
                let n = same.iter().position(|id| *id == e.id).unwrap_or(0) + 1;
                label.push_str(&format!(" #{n}"));
            }
            let radio = radio_id
                .as_ref()
                .filter(|(id, _)| *id == e.id)
                .map(|(_, model)| *model);
            if let Some(model) = radio {
                label.push_str(&format!(" — {model}"));
            }
            EndpointChoice {
                id: e.id.clone(),
                name: Some(name),
                label,
                present: true,
                radio,
            }
        })
        .collect();
    if let Some((id, known)) = saved
        && !choices.iter().any(|c| c.id == id)
    {
        let name = known.map(display_name);
        choices.push(EndpointChoice {
            id: id.to_owned(),
            label: format!(
                "{} · not present",
                name.as_deref().unwrap_or("Unknown device")
            ),
            name,
            present: false,
            radio: None,
        });
    }
    choices
}

/// CL-044-05: a WASAPI endpoint ID of this flow, {0.0.F.00000000}.{GUID}.
pub fn endpoint_id(text: &str, flow: Flow) -> bool {
    let prefix = match flow {
        Flow::Capture => "{0.0.1.00000000}.{",
        Flow::Render => "{0.0.0.00000000}.{",
    };
    let Some(rest) = text.strip_prefix(prefix).and_then(|r| r.strip_suffix('}')) else {
        return false;
    };
    let groups: Vec<_> = rest.split('-').collect();
    groups.len() == 5
        && groups
            .iter()
            .zip([8, 4, 4, 4, 12])
            .all(|(g, n)| g.len() == n && g.bytes().all(|b| b.is_ascii_hexdigit()))
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Migration {
    Unchanged,
    Migrated(String),
    NotFound,
    Ambiguous,
}
/// CL-044-05: replace a friendly-name device entry by the one endpoint of that flow with
/// exactly that friendly name.
pub fn migrate(value: &str, endpoints: &[AudioEndpoint], flow: Flow) -> Migration {
    if endpoint_id(value, flow) {
        return Migration::Unchanged;
    }
    let found: Vec<_> = endpoints
        .iter()
        .filter(|e| e.flow == flow && e.name == value)
        .collect();
    match found.as_slice() {
        [] => Migration::NotFound,
        [one] => Migration::Migrated(one.id.clone()),
        _ => Migration::Ambiguous,
    }
}

#[cfg(test)]
#[path = "setup_tests.rs"]
mod tests;
