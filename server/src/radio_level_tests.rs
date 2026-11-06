#![forbid(unsafe_code)]
// Proves: CL-044-12; CL-044-13; TC-044-013; TC-044-014. The actual router, Recording owner,
// transmit owner thread on the recording hardware double, CAT actor and executor on a
// scripted IC-7300 on COM3 that echoes each frame. Expected bytes and meter scales are
// hand-written from the IC-7300 Full Manual section 19 command table ("15 11 Po":
// 0143 = 50 %, 0213 = 100 %; "15 12 SWR": 0048 = 1.5, 0080 = 2.0, 0120 = 3.0; "15 13 ALC").
use super::*;
use crate::contact_http_tests::{Fixture, fixture};
use axum::http::StatusCode;
use std::collections::VecDeque;
use std::sync::atomic::AtomicBool;
use wstx_rust::radio_control::{self as cat, codec, executor::Transport};

const READ_ALC: [u8; 7] = [0xfe, 0xfe, 0x94, 0xe0, 0x15, 0x13, 0xfd];
const READ_PO: [u8; 7] = [0xfe, 0xfe, 0x94, 0xe0, 0x15, 0x11, 0xfd];
const READ_SWR: [u8; 7] = [0xfe, 0xfe, 0x94, 0xe0, 0x15, 0x12, 0xfd];

type AlcAt = Arc<dyn Fn() -> [u8; 2] + Send + Sync>;
struct Ic7300 {
    /// The 15 13 data; None: the radio refuses the read (FA).
    alc: Option<AlcAt>,
    po: [u8; 2],
    swr: [u8; 2],
    /// Meter reads get no reply until this is cleared (a stalled radio).
    silent: bool,
    transmitting: bool,
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
        let body = &bytes[4..bytes.len() - 1];
        if r.silent && body.first() == Some(&0x15) {
            return Ok(bytes.len());
        }
        let reply: Vec<u8> = match body {
            [3] => [&[3][..], &codec::encode_frequency(7_074_000).unwrap()].concat(),
            [4] => vec![4, 1, 1],
            [0x1a, 6] => vec![0x1a, 6, 1, 1],
            [0x1c, 0] => vec![0x1c, 0, u8::from(r.transmitting)],
            [0x1c, 0, on] => {
                r.transmitting = *on == 1;
                vec![0xfb]
            }
            [0x0f] => vec![0x0f, 0],
            [0x15, 0x13] => match &r.alc {
                Some(alc) => {
                    let data = alc();
                    vec![0x15, 0x13, data[0], data[1]]
                }
                None => vec![0xfa],
            },
            [0x15, 0x11] => vec![0x15, 0x11, r.po[0], r.po[1]],
            [0x15, 0x12] => vec![0x15, 0x12, r.swr[0], r.swr[1]],
            _ => vec![0xfa],
        };
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
fn fixed(data: [u8; 2]) -> Option<AlcAt> {
    Some(Arc::new(move || data))
}
fn radio(alc: Option<AlcAt>) -> Ic7300 {
    Ic7300 {
        alc,
        po: [0x01, 0x43],
        swr: [0x00, 0x00],
        silent: false,
        transmitting: false,
        writes: Vec::new(),
    }
}
/// The fixture station, IC-7300 CAT on COM3, its CAT owner Ready and managed.
fn station(ic7300: Ic7300) -> (Fixture, Arc<Mutex<Ic7300>>) {
    let f = fixture("http://127.0.0.1:18046", true);
    {
        let mut store = f.state.store.lock().unwrap();
        store.document.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some("COM3".into()),
            ptt: "cat".into(),
        };
        store.document.radio = Some(profile::Radio::DEFAULT);
    }
    let ic7300 = Arc::new(Mutex::new(ic7300));
    let shared = ic7300.clone();
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
    ic7300.lock().unwrap().writes.clear();
    (f, ic7300)
}
fn actor(f: &Fixture) -> Arc<cat::actor::Actor> {
    f.state.recording.radio_actor().unwrap()
}
/// Keys through the actor: the transmit hold a Tune holds in the station (the hardware
/// double of the transmit owner does not reach the actor).
fn hold(f: &Fixture) {
    actor(f)
        .ptt(true, Instant::now() + Duration::from_secs(1))
        .unwrap();
}
fn meter_frames(r: &Arc<Mutex<Ic7300>>) -> Vec<Vec<u8>> {
    let r = r.lock().unwrap();
    r.writes.iter().filter(|w| w[4] == 0x15).cloned().collect()
}
fn finished(f: &Fixture) -> &'static str {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if !f.state.recording.tx_level.assistant_running()
            && let Some(result) = f.state.recording.tx_level.result()
        {
            return result;
        }
        assert!(Instant::now() < deadline, "assistant did not finish");
        std::thread::sleep(Duration::from_millis(2));
    }
}
fn stored(f: &Fixture) -> Option<Value> {
    let bytes = std::fs::read(f.dir.join(LEVEL_FILE)).ok()?;
    serde_json::from_slice(&bytes).ok()
}

// TC-044-013 (a, b)
#[test]
fn meters_are_read_only_under_the_transmit_hold_in_the_manual_frames() {
    let (f, r) = station(radio(fixed([0x01, 0x20])));
    let deadline = || Instant::now() + Duration::from_millis(400);
    // No hold: refused, no byte.
    assert_eq!(actor(&f).read_meters(deadline()), Err(cat::Error::Busy));
    assert!(r.lock().unwrap().writes.is_empty());
    hold(&f);
    r.lock().unwrap().writes.clear();
    let meters = actor(&f).read_meters(deadline()).unwrap();
    assert_eq!(
        meters,
        Meters {
            alc: Some(120),
            po: Some(143),
            swr: Some(0)
        }
    );
    assert_eq!(
        r.lock().unwrap().writes,
        vec![READ_ALC.to_vec(), READ_PO.to_vec(), READ_SWR.to_vec()],
        "exactly the three reads"
    );
    // The hold is untouched: the release works and no ordinary exchange ran.
    actor(&f)
        .ptt(false, Instant::now() + Duration::from_secs(1))
        .unwrap();
    assert!(!r.lock().unwrap().transmitting);
    // A refused ALC read is a missing meter, the other two still read.
    let (f, _) = station(radio(None));
    hold(&f);
    let meters = actor(&f).read_meters(deadline()).unwrap();
    assert_eq!((meters.alc, meters.po), (None, Some(143)));
}

// TC-044-013 (c)
#[test]
fn a_stalled_meter_read_gives_way_to_the_release_and_keeps_the_connection() {
    let (f, r) = station(radio(fixed([0, 0])));
    hold(&f);
    r.lock().unwrap().silent = true;
    // A timeout alone leaves the connection ready.
    assert_eq!(
        actor(&f).read_meters(Instant::now() + Duration::from_millis(60)),
        Err(cat::Error::Timeout)
    );
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
    // A release during a stalled read is served at once, inside the 250 ms halt bound.
    let reader = actor(&f);
    let before = meter_frames(&r).len();
    let read =
        std::thread::spawn(move || reader.read_meters(Instant::now() + Duration::from_secs(3)));
    let deadline = Instant::now() + Duration::from_secs(5);
    while meter_frames(&r).len() == before {
        assert!(Instant::now() < deadline, "the read did not start");
        std::thread::sleep(Duration::from_millis(1));
    }
    let start = Instant::now();
    actor(&f)
        .ptt(false, Instant::now() + Duration::from_secs(1))
        .unwrap();
    assert!(start.elapsed() < Duration::from_millis(250));
    assert_eq!(read.join().unwrap(), Err(cat::Error::Cancelled));
    assert_eq!(actor(&f).snapshot().unwrap().state, cat::State::Ready);
}

// TC-044-013 (d)
#[test]
fn meter_scales_follow_the_manual_table() {
    assert_eq!(
        wstx_rust::radio_control::setup::decode_bcd([0x02, 0x13]),
        Some(213)
    );
    assert_eq!(
        wstx_rust::radio_control::setup::decode_bcd([0x0a, 0x00]),
        None
    );
    for (raw, pct) in [(0, 0), (143, 50), (213, 100)] {
        assert_eq!(po_percent(raw), pct, "Po {raw}");
    }
    for (raw, x10) in [(0, 10), (48, 15), (80, 20), (120, 30)] {
        assert_eq!(swr_x10(raw), x10, "SWR {raw}");
    }
}

// TC-044-014 (a)
#[test]
fn assistant_decides_from_alc_power_limit_and_swr() {
    let m = |alc, po, swr| Meters {
        alc,
        po: Some(po),
        swr: Some(swr),
    };
    assert_eq!(assistant_step(-30, &m(Some(0), 0, 0), None), Step::Up(-29));
    assert_eq!(
        assistant_step(-20, &m(Some(1), 0, 0), None),
        Step::Done(-21, "stored")
    );
    assert_eq!(
        assistant_step(-40, &m(Some(1), 0, 0), None),
        Step::Done(-40, "stored")
    );
    // Never above the profile power: 0143 is 50 %.
    assert_eq!(
        assistant_step(-10, &m(Some(0), 143, 0), Some(49)),
        Step::Done(-11, "stored")
    );
    assert_eq!(
        assistant_step(-10, &m(Some(0), 143, 0), Some(50)),
        Step::Up(-9)
    );
    assert_eq!(
        assistant_step(0, &m(Some(0), 10, 0), None),
        Step::Done(0, "max_without_alc")
    );
    assert_eq!(
        assistant_step(-5, &m(None, 0, 0), None),
        Step::Stop("no_alc")
    );
    assert_eq!(
        assistant_step(-5, &m(Some(0), 0, 120), None),
        Step::Stop("high_swr")
    );
}

/// The double's level and an ALC that rises from `rise_db` on.
fn rising(f: &Fixture, r: &Arc<Mutex<Ic7300>>, rise_db: i32) {
    let levels = f.bench.levels.clone();
    r.lock().unwrap().alc = Some(Arc::new(move || {
        let level = levels.lock().unwrap().last().copied().unwrap_or(0);
        if level >= rise_db { [0, 5] } else { [0, 0] }
    }));
}

// TC-044-014 (b)
#[test]
fn set_level_steps_up_backs_off_one_step_stores_and_stops_tune() {
    let (f, r) = station(radio(fixed([0, 0])));
    rising(&f, &r, -27);
    hold(&f);
    let revision = f.state.store.lock().unwrap().document.revision;
    start_assistant(&f.state, 1500).unwrap();
    assert_eq!(finished(&f), "stored");
    assert_eq!(*f.bench.levels.lock().unwrap(), vec![-30, -29, -28, -27]);
    assert_eq!(f.state.recording.tx_level.level_db(), -28);
    assert_eq!(stored(&f), Some(json!({"schema_version":1,"level_db":-28})));
    let view = f.state.recording.transmit.get().unwrap().service.view();
    assert!(!view.tune, "Tune stopped");
    assert_eq!(
        view.arm_state,
        ArmState::Disarmed,
        "it armed only for itself"
    );
    assert_eq!(
        f.state.store.lock().unwrap().document.revision,
        revision,
        "a level change is no profile save (that would reconnect CAT)"
    );
    // The next Tune plays at the stored level.
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    assert_eq!(f.bench.levels.lock().unwrap().last(), Some(&-28));
    service.with(|c| c.set_tune(false, 0).unwrap());
    // Every frame of the run was a read or the test's own key: nothing was set.
    let r = r.lock().unwrap();
    assert!(
        r.writes
            .iter()
            .all(|w| w[4] == 0x15 || w[4..6] == [0x1c, 0]),
        "{:02x?}",
        r.writes
    );
}

// TC-044-014 (c)
#[test]
fn halt_aborts_set_level_without_storing() {
    let (f, r) = station(radio(fixed([0, 0])));
    hold(&f);
    start_assistant(&f.state, 1500).unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while meter_frames(&r).is_empty() {
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    }
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.halt("00000000-0000-4000-8000-000000000001");
    assert_eq!(finished(&f), "aborted");
    assert_eq!(stored(&f), None);
    assert_eq!(
        f.state.recording.tx_level.level_db(),
        0,
        "the prior level stays"
    );
    let view = service.view();
    assert!(!view.tune);
    assert_eq!(view.arm_state, ArmState::Disarmed);
}

// TC-044-014 (d)
#[test]
fn a_radio_without_alc_stops_the_assistant_and_opens_the_manual_level() {
    let (f, _) = station(radio(fixed([0, 0])));
    // Before a read says otherwise, and with ALC, there is no manual level.
    assert_eq!(set_manual(&f.state, -10), Err("alc_available"));
    let (f, _) = station(radio(None));
    hold(&f);
    start_assistant(&f.state, 1500).unwrap();
    assert_eq!(finished(&f), "no_alc");
    assert_eq!(f.state.recording.tx_level.alc(), Alc::Unavailable);
    assert_eq!(stored(&f), None);
    assert_eq!(set_manual(&f.state, -41), Err("invalid_request"));
    assert_eq!(set_manual(&f.state, 1), Err("invalid_request"));
    assert_eq!(set_manual(&f.state, -10), Ok(()));
    assert_eq!(stored(&f), Some(json!({"schema_version":1,"level_db":-10})));
    // A running Tune follows the manual level at once.
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    assert_eq!(set_manual(&f.state, -12), Ok(()));
    assert_eq!(f.bench.levels.lock().unwrap().last(), Some(&-12));
    service.with(|c| c.set_tune(false, 0).unwrap());
}

// TC-044-014 (e)
#[test]
fn stored_level_is_loaded_at_startup_and_bad_files_are_ignored() {
    let (f, _) = station(radio(fixed([0, 0])));
    let service = &f.state.recording.transmit.get().unwrap().service;
    let level_after_tune = |f: &Fixture| {
        service.with(|c| {
            c.arm(3).unwrap();
            c.set_tune(true, 1500).unwrap();
            c.set_tune(false, 0).unwrap();
        });
        *f.bench.levels.lock().unwrap().last().unwrap()
    };
    for bad in [
        r#"{"schema_version":1,"level_db":5}"#,
        r#"{"schema_version":2,"level_db":-5}"#,
        "not json",
    ] {
        std::fs::write(f.dir.join(LEVEL_FILE), bad).unwrap();
        startup(&f.state);
        assert_eq!(f.state.recording.tx_level.level_db(), 0, "{bad}");
        assert_eq!(level_after_tune(&f), 0, "{bad}");
    }
    std::fs::write(
        f.dir.join(LEVEL_FILE),
        r#"{"schema_version":1,"level_db":-17}"#,
    )
    .unwrap();
    startup(&f.state);
    assert_eq!(f.state.recording.tx_level.level_db(), -17);
    assert_eq!(level_after_tune(&f), -17);
}

// TC-044-014 (f)
#[test]
fn tune_meters_are_read_once_a_second_and_pushed_as_one_event() {
    let (f, r) = station(radio(fixed([0, 7])));
    let recording = &f.state.recording;
    let settings = Some(profile::Radio {
        agc: wstx_rust::radio_control::setup::Agc::Slow,
        power_limit_pct: Some(40),
    });
    let now = Instant::now();
    tick(recording, settings, now);
    assert!(meter_frames(&r).is_empty(), "no Tune, no read");
    let (revision, text) = event(recording);
    assert!(revision > 0);
    let v: Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["type"], "radio.tx_level");
    let mut keys: Vec<_> = v["data"].as_object().unwrap().keys().cloned().collect();
    keys.sort();
    assert_eq!(
        keys,
        [
            "alc",
            "assistant",
            "boot_id",
            "keying_confirmed",
            "level_db",
            "managed",
            "meters",
            "power_limit_pct",
            "profile_id",
            "result",
            "stored",
            "warnings"
        ]
    );
    assert_eq!(
        (
            &v["data"]["managed"],
            &v["data"]["power_limit_pct"],
            &v["data"]["alc"]
        ),
        (&json!(true), &json!(40), &json!("unknown"))
    );
    hold(&f);
    let service = &recording.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    tick(recording, settings, now);
    let deadline = Instant::now() + Duration::from_secs(5);
    while meter_frames(&r).len() < 3 || recording.tx_level.alc() != Alc::Available {
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    }
    let v: Value = serde_json::from_str(&event(recording).1).unwrap();
    assert_eq!(
        v["data"]["meters"],
        json!({"alc":7,"po_pct":50,"swr_x10":10})
    );
    // Within the second: nothing; after it: one more read.
    tick(recording, settings, now + Duration::from_millis(900));
    std::thread::sleep(Duration::from_millis(30));
    assert_eq!(meter_frames(&r).len(), 3);
    // A tick while the first read is still finishing passes; the next one reads.
    while meter_frames(&r).len() < 6 {
        tick(recording, settings, now + Duration::from_millis(1000));
        assert!(Instant::now() < deadline);
        std::thread::sleep(Duration::from_millis(1));
    }
    service.with(|c| c.set_tune(false, 0).unwrap());
}

// TC-044-014 (g)
#[tokio::test]
async fn the_route_refuses_bad_requests_and_a_station_without_a_grant() {
    let (f, _) = station(radio(fixed([0, 0])));
    let body = |extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
            "command_id":"00000000-0000-4000-8000-000000000002"});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        b
    };
    for bad in [
        json!({"action":"tune"}),
        json!({"action":"set_level"}),
        json!({"action":"set_level","tx_offset_hz":"1500"}),
        json!({"action":"set_level","tx_offset_hz":1500,"more":1}),
        json!({"action":"manual"}),
        json!({"action":"manual","level_db":"x"}),
    ] {
        let (s, v, _, _) = f
            .call("POST", "/radio/tx-level", Some(body(bad.clone())))
            .await;
        assert_eq!(s, StatusCode::BAD_REQUEST, "{bad} {v}");
    }
    let (s, _, _, _) = f
        .call(
            "POST",
            "/radio/tx-level",
            Some(body(json!({"action":"set_level","tx_offset_hz":1500}))),
        )
        .await;
    assert_eq!(
        s,
        StatusCode::UNAUTHORIZED,
        "transmit authority needs a grant"
    );
    let view = f.state.recording.transmit.get().unwrap().service.view();
    assert!(!view.tune);
}

// CL-044-12 profile field.
#[tokio::test]
async fn profile_power_limit_is_saved_kept_absent_by_default_and_validated() {
    let (f, _) = station(radio(fixed([0, 0])));
    let (_, v, _, _) = f.call("GET", "/profile", None).await;
    assert_eq!(v["settings"]["radio"], json!({"agc":"SLOW"}), "{v}");
    let edit = |revision: u64, radio: Value| {
        json!({"profile_id":f.id,"revision":revision,"settings":{"display_name":"Level",
            "callsign":"HB9BLA","locator":"JN37VL","audio":{"input_device":null,"output_device":null},
            "control":{"mode":"cat","endpoint":"COM3","ptt":"cat"},"radio":radio}})
    };
    let r0 = v["revision"].as_u64().unwrap();
    let (s, v, _, _) = f
        .call(
            "PUT",
            "/profile",
            Some(edit(r0, json!({"agc":"SLOW","power_limit_pct":10}))),
        )
        .await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(
        v["settings"]["radio"],
        json!({"agc":"SLOW","power_limit_pct":10})
    );
    let r1 = v["revision"].as_u64().unwrap();
    for bad in [0, 101] {
        let (s, v, _, _) = f
            .call(
                "PUT",
                "/profile",
                Some(edit(r1, json!({"agc":"SLOW","power_limit_pct":bad}))),
            )
            .await;
        assert_eq!(s, StatusCode::BAD_REQUEST, "{bad} {v}");
    }
}

// Proves: CL-044-13; TC-044-014 (b). The pushed level is the one playing at every step.
#[test]
fn set_level_pushes_the_level_it_is_playing_at_every_step() {
    let (f, r) = station(radio(fixed([0, 0])));
    let seen = Arc::new(Mutex::new(Vec::new()));
    let (levels, rec, log) = (
        f.bench.levels.clone(),
        f.state.recording.clone(),
        seen.clone(),
    );
    r.lock().unwrap().alc = Some(Arc::new(move || {
        let v: Value = serde_json::from_str(&event(&rec).1).unwrap();
        let played = *levels.lock().unwrap().last().unwrap();
        log.lock()
            .unwrap()
            .push((played, v["data"]["level_db"].as_i64().unwrap() as i32));
        if played >= -27 { [0, 5] } else { [0, 0] }
    }));
    hold(&f);
    start_assistant(&f.state, 1500).unwrap();
    assert_eq!(finished(&f), "stored");
    let seen = seen.lock().unwrap();
    assert!(!seen.is_empty());
    for (played, pushed) in seen.iter() {
        assert_eq!(played, pushed);
    }
}

// Proves: CL-044-12; TC-044-014 (c). A level that cannot be stored is not kept.
#[test]
fn set_level_that_cannot_be_stored_leaves_the_prior_level() {
    let (f, r) = station(radio(fixed([0, 0])));
    rising(&f, &r, -27);
    std::fs::create_dir(f.dir.join(LEVEL_FILE)).unwrap();
    hold(&f);
    start_assistant(&f.state, 1500).unwrap();
    assert_eq!(finished(&f), "storage_unavailable");
    assert_eq!(f.state.recording.tx_level.level_db(), 0);
    let v: Value = serde_json::from_str(&event(&f.state.recording).1).unwrap();
    assert_eq!(v["data"]["stored"], json!(false));
    let service = &f.state.recording.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    assert_eq!(f.bench.levels.lock().unwrap().last(), Some(&0));
    service.with(|c| c.set_tune(false, 0).unwrap());
}

// TC-044-017 (a)
#[test]
fn monitor_decides_one_bounded_step_and_warns_only_when_persistent() {
    let m = |alc: Option<u16>, po: u16, swr: u16| Meters {
        alc,
        po: Some(po),
        swr: Some(swr),
    };
    let step =
        |level, meters: &Meters, limit| monitor_step(level, meters, limit, &mut Counts::default());
    // 0143 is 50 % Po. In the window: nothing.
    assert_eq!(step(-10, &m(Some(10), 143, 0), Some(50)).level_db, -10);
    // ALC too high: one down, at the floor it stays.
    assert_eq!(step(-10, &m(Some(60), 143, 0), Some(50)).level_db, -11);
    assert_eq!(step(-10, &m(Some(59), 143, 0), Some(50)).level_db, -10);
    assert_eq!(step(-40, &m(Some(60), 143, 0), None).level_db, -40);
    // ALC zero and power low (below 80 % of the profile power): one up, never past 0 dB.
    assert_eq!(step(-10, &m(Some(0), 143, 0), Some(63)).level_db, -9);
    assert_eq!(step(-10, &m(Some(0), 143, 0), Some(62)).level_db, -10);
    assert_eq!(step(0, &m(Some(0), 143, 0), Some(100)).level_db, 0);
    // ALC not zero, or no profile power: no step up.
    assert_eq!(step(-10, &m(Some(1), 0, 0), Some(50)).level_db, -10);
    assert_eq!(step(-10, &m(Some(0), 0, 0), None).level_db, -10);
    // Above the profile power: one down.
    assert_eq!(step(-10, &m(Some(0), 143, 0), Some(49)).level_db, -11);
    // A radio without ALC is never stepped up.
    assert_eq!(step(-10, &m(None, 0, 0), Some(50)).level_db, -10);
    // SWR 3.0 is the clear fault, 2.0 only counts.
    assert!(step(-10, &m(Some(0), 143, 120), None).fault);
    assert!(!step(-10, &m(Some(0), 143, 119), None).fault);
    // Persistent means three transmissions in a row; one good reading clears it.
    let mut counts = Counts::default();
    for expected in [vec![], vec![], vec!["swr_high"]] {
        let v = monitor_step(-10, &m(Some(0), 143, 80), None, &mut counts);
        assert_eq!(v.warnings, expected);
    }
    assert!(
        monitor_step(-10, &m(Some(0), 143, 0), None, &mut counts)
            .warnings
            .is_empty()
    );
    let mut counts = Counts::default();
    for _ in 0..2 {
        monitor_step(-10, &m(Some(60), 143, 0), None, &mut counts);
    }
    assert_eq!(
        monitor_step(-10, &m(Some(60), 143, 0), None, &mut counts).warnings,
        ["alc_high"]
    );
    // Low Po warns below half the profile power: 0143 is 50 %.
    let mut counts = Counts::default();
    for _ in 0..2 {
        monitor_step(-10, &m(Some(0), 143, 0), Some(101), &mut counts);
    }
    assert_eq!(
        monitor_step(-10, &m(Some(0), 143, 0), Some(101), &mut counts).warnings,
        ["po_low"]
    );
}

/// Starts the burst of one transmission and waits for its reading to be judged.
fn one_transmission(f: &Fixture, r: &Arc<Mutex<Ic7300>>) {
    let before = meter_frames(r).len();
    on_meter_due(&f.state).unwrap().join().unwrap();
    assert_eq!(meter_frames(r).len(), before + 3, "one burst");
}

// TC-044-017 (c, d)
#[test]
fn one_burst_corrects_for_the_next_transmission_only_and_warns_when_persistent() {
    let (f, r) = station(radio(fixed([0, 0x60])));
    let recording = &f.state.recording;
    recording.tx_level.update(|i| i.level_db = -10);
    // No hold, no transmission: refused without a byte and nothing judged.
    on_meter_due(&f.state).unwrap().join().unwrap();
    assert!(r.lock().unwrap().writes.is_empty());
    assert_eq!(recording.tx_level.level_db(), -10);
    hold(&f);
    r.lock().unwrap().writes.clear();
    one_transmission(&f, &r);
    assert_eq!(
        r.lock().unwrap().writes,
        vec![READ_ALC.to_vec(), READ_PO.to_vec(), READ_SWR.to_vec()],
        "one burst, nothing else"
    );
    assert_eq!(recording.tx_level.level_db(), -11);
    assert_eq!(stored(&f), Some(json!({"schema_version":1,"level_db":-11})));
    assert!(
        f.bench.levels.lock().unwrap().is_empty(),
        "nothing reaches the running audio"
    );
    assert!(recording.tx_level.warnings().is_empty());
    one_transmission(&f, &r);
    assert!(recording.tx_level.warnings().is_empty());
    one_transmission(&f, &r);
    assert_eq!(recording.tx_level.warnings(), ["alc_high"]);
    assert_eq!(recording.tx_level.level_db(), -13);
    let v: Value = serde_json::from_str(&event(recording).1).unwrap();
    assert_eq!(v["data"]["warnings"], json!(["alc_high"]));
    // A good transmission clears the entry and the level stays.
    r.lock().unwrap().alc = fixed([0, 0x10]);
    one_transmission(&f, &r);
    assert!(recording.tx_level.warnings().is_empty());
    assert_eq!(recording.tx_level.level_db(), -13);
    // Nothing but reads and the test's own key in all of this.
    assert!(r.lock().unwrap().writes.iter().all(|w| w[4] == 0x15));
}

// TC-044-017 (e)
#[test]
fn a_clear_swr_fault_stops_transmitting_and_keeps_automation_off() {
    let (f, r) = station(radio(fixed([0, 0])));
    let recording = &f.state.recording;
    let service = &recording.transmit.get().unwrap().service;
    service.with(|c| {
        c.arm(3).unwrap();
        c.activity();
    });
    assert!(!service.with(|c| c.watchdog_spent()));
    hold(&f);
    r.lock().unwrap().swr = [0x01, 0x20];
    let halts = service.halt_requests();
    one_transmission(&f, &r);
    assert_eq!(service.halt_requests(), halts + 1);
    let view = service.view();
    assert_eq!(view.arm_state, ArmState::Disarmed);
    assert_eq!(view.last_disarm_cause, DisarmCause::Halt);
    assert!(
        service.with(|c| c.watchdog_spent()),
        "automation may not arm again"
    );
    assert!(recording.tx_level.swr_fault());
    let v: Value = serde_json::from_str(&event(recording).1).unwrap();
    assert_eq!(v["data"]["warnings"], json!(["swr_fault"]));
    // The operator arms again and a clear reading ends the entry.
    service.with(|c| c.arm(3).unwrap());
    r.lock().unwrap().swr = [0, 0x10];
    one_transmission(&f, &r);
    assert!(!recording.tx_level.swr_fault());
    assert_eq!(service.view().arm_state, ArmState::Armed);
    service.with(|c| c.disarm(DisarmCause::Operator));
}

// TC-044-017 (f)
#[test]
fn nothing_is_read_for_a_transmission_while_set_level_runs() {
    let (f, r) = station(radio(fixed([0, 0])));
    f.state.recording.tx_level.update(|i| i.assistant = true);
    hold(&f);
    r.lock().unwrap().writes.clear();
    assert!(on_meter_due(&f.state).is_none());
    assert!(r.lock().unwrap().writes.is_empty());
}

// TC-044-017 (g): startup connects the transmit step's call to the burst.
#[test]
fn startup_connects_the_meter_call_to_one_burst() {
    let (f, r) = station(radio(fixed([0, 0x10])));
    startup(&f.state);
    hold(&f);
    r.lock().unwrap().writes.clear();
    let sink = f.state.recording.transmit.get().unwrap().meter_sink();
    sink.expect("startup installs the sink")();
    let deadline = Instant::now() + Duration::from_secs(5);
    while meter_frames(&r).len() < 3 {
        assert!(Instant::now() < deadline, "no burst");
        std::thread::sleep(Duration::from_millis(1));
    }
}

// TC-044-017 (h): a level that cannot be stored is not applied.
#[test]
fn a_correction_that_cannot_be_stored_leaves_the_level() {
    let (f, r) = station(radio(fixed([0, 0x60])));
    let recording = &f.state.recording;
    let service = &recording.transmit.get().unwrap().service;
    recording.tx_level.update(|i| i.level_db = -10);
    service.with(|c| c.set_tx_level(-10));
    std::fs::create_dir(f.dir.join(LEVEL_FILE)).unwrap();
    hold(&f);
    one_transmission(&f, &r);
    assert_eq!(recording.tx_level.level_db(), -10);
    let v: Value = serde_json::from_str(&event(recording).1).unwrap();
    assert_eq!(v["data"]["stored"], json!(false));
    service.with(|c| {
        c.arm(3).unwrap();
        c.set_tune(true, 1500).unwrap();
    });
    assert_eq!(f.bench.levels.lock().unwrap().last(), Some(&-10));
    service.with(|c| c.set_tune(false, 0).unwrap());
}

// TC-044-017 (e): a reading without SWR does not clear the fault.
#[test]
fn a_reading_without_swr_keeps_the_fault_entry() {
    let (f, r) = station(radio(fixed([0, 0])));
    let recording = &f.state.recording;
    hold(&f);
    r.lock().unwrap().swr = [0x01, 0x20];
    one_transmission(&f, &r);
    assert!(recording.tx_level.swr_fault());
    monitor(
        &f.state,
        &Meters {
            alc: Some(0),
            po: Some(143),
            swr: None,
        },
    );
    assert!(recording.tx_level.swr_fault());
}
