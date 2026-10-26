#[path = "../src/radio_control/mod.rs"]
pub mod radio_control;
use radio_control::{
    catalogue::Catalogue,
    codec::{self, Framer, Reply},
    executor::{Executor, Transport},
    *,
};
use std::{
    collections::VecDeque,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

const FREQUENCY: &[u8] = &[0xfe, 0xfe, 0xe0, 0x94, 3, 0, 0x40, 7, 0x14, 0, 0xfd];
const MODE: &[u8] = &[0xfe, 0xfe, 0xe0, 0x94, 4, 1, 2, 0xfd];
const DATA: &[u8] = &[0xfe, 0xfe, 0xe0, 0x94, 0x1a, 6, 1, 2, 0xfd];
const ACK: &[u8] = &[0xfe, 0xfe, 0xe0, 0x94, 0xfb, 0xfd];
enum Action {
    Bytes(Vec<u8>),
    Timeout,
    Partial,
    Cancel(Vec<u8>),
    Block(Vec<u8>, Arc<AtomicBool>, Arc<AtomicBool>),
}
#[derive(Default)]
struct Script {
    actions: VecDeque<Action>,
    pending: VecDeque<u8>,
    writes: Vec<Vec<u8>>,
    rates: Vec<u32>,
    deadlines: Vec<Instant>,
    closed: usize,
    quiet: usize,
    cancel_read: bool,
    fragment: usize,
    close_error: bool,
    block: Option<(Arc<AtomicBool>, Arc<AtomicBool>)>,
}
struct Fake(Arc<Mutex<Script>>);
impl Transport for Fake {
    fn configure(&mut self, baud: u32) -> Result<()> {
        self.0.lock().unwrap().rates.push(baud);
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], deadline: Instant, _: &AtomicBool) -> Result<usize> {
        let mut s = self.0.lock().unwrap();
        s.writes.push(bytes.to_vec());
        s.deadlines.push(deadline);
        match s.actions.pop_front().unwrap_or(Action::Timeout) {
            Action::Bytes(bytes) => s.pending.extend(bytes),
            Action::Cancel(bytes) => {
                s.pending.extend(bytes);
                s.cancel_read = true;
            }
            Action::Timeout => return Err(Error::Timeout),
            Action::Partial => return Ok(1),
            Action::Block(bytes, entered, release) => {
                s.pending.extend(bytes);
                s.block = Some((entered, release));
            }
        }
        Ok(bytes.len())
    }
    fn read(&mut self, bytes: &mut [u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        let block = self.0.lock().unwrap().block.take();
        if let Some((entered, release)) = block {
            entered.store(true, Ordering::Release);
            while !release.load(Ordering::Acquire) {
                if cancel.load(Ordering::Acquire) {
                    return Err(Error::Cancelled);
                }
                if Instant::now() >= deadline {
                    return Err(Error::Timeout);
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
        let mut s = self.0.lock().unwrap();
        s.deadlines.push(deadline);
        if s.cancel_read {
            cancel.store(true, Ordering::Release);
            s.cancel_read = false;
        }
        if s.pending.is_empty() {
            return Err(Error::Timeout);
        }
        let max = if s.fragment == 0 {
            bytes.len()
        } else {
            s.fragment.min(bytes.len())
        };
        let count = max.min(s.pending.len());
        for dest in bytes.iter_mut().take(count) {
            *dest = s.pending.pop_front().unwrap();
        }
        Ok(count)
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> Result<()> {
        let mut s = self.0.lock().unwrap();
        s.quiet += 1;
        s.pending.clear();
        Ok(())
    }
    fn close(&mut self) -> Result<()> {
        let mut s = self.0.lock().unwrap();
        s.closed += 1;
        if s.close_error {
            Err(Error::FailedClose)
        } else {
            Ok(())
        }
    }
}

// Proves: CL-008-03, CL-008-05; TC-009-001, TC-009-003, TC-009-004.
#[test]
fn actor_has_one_io_owner_no_pending_operation_and_bounded_close() {
    use radio_control::actor::Actor;
    let entered = Arc::new(AtomicBool::new(false));
    let release = Arc::new(AtomicBool::new(false));
    let state = Arc::new(Mutex::new(Script {
        actions: VecDeque::from([
            Action::Bytes(FREQUENCY.to_vec()),
            Action::Block(MODE.to_vec(), entered.clone(), release),
        ]),
        ..Script::default()
    }));
    let owned = state.clone();
    let actor = Arc::new(
        Actor::begin(
            Configuration::parse("COM3").unwrap(),
            authority(),
            Catalogue::builtin().unwrap(),
            move |_, _| Ok(Fake(owned)),
        )
        .unwrap(),
    );
    let limit = Instant::now() + Duration::from_secs(2);
    while actor.snapshot().unwrap().state == State::Connecting && Instant::now() < limit {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(actor.snapshot().unwrap().state, State::Ready);
    let operation = actor.clone();
    let worker = std::thread::spawn(move || operation.execute(req(Operation::ReadMode)));
    while !entered.load(Ordering::Acquire) && Instant::now() < limit {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert!(entered.load(Ordering::Acquire));
    assert_eq!(actor.execute(req(Operation::ReadMode)), Err(Error::Busy));
    assert_eq!(state.lock().unwrap().writes.len(), 2);
    let before = Instant::now();
    actor.request_close();
    assert_eq!(worker.join().unwrap(), Err(Error::Cancelled));
    while !actor.close_complete() && before.elapsed() < Duration::from_millis(250) {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert!(actor.close_complete());
    assert!(before.elapsed() < Duration::from_millis(250));
    assert!(state.lock().unwrap().closed >= 1);
}

// Proves: CL-008-03, CL-008-05; TC-009-001, TC-009-003.
#[test]
fn actor_constructs_non_send_native_values_inside_its_io_thread() {
    use radio_control::actor::Actor;
    struct ThreadOnly(Fake, std::rc::Rc<()>);
    impl Transport for ThreadOnly {
        fn configure(&mut self, baud: u32) -> Result<()> {
            assert_eq!(std::rc::Rc::strong_count(&self.1), 1);
            self.0.configure(baud)
        }
        fn write(&mut self, b: &[u8], d: Instant, c: &AtomicBool) -> Result<usize> {
            self.0.write(b, d, c)
        }
        fn read(&mut self, b: &mut [u8], d: Instant, c: &AtomicBool) -> Result<usize> {
            self.0.read(b, d, c)
        }
        fn quiet(&mut self, d: Instant, c: &AtomicBool) -> Result<()> {
            self.0.quiet(d, c)
        }
        fn close(&mut self) -> Result<()> {
            self.0.close()
        }
    }
    let state = Arc::new(Mutex::new(Script {
        actions: VecDeque::from([Action::Bytes(FREQUENCY.to_vec())]),
        ..Script::default()
    }));
    let actor = Actor::begin(
        Configuration::parse("COM3").unwrap(),
        authority(),
        Catalogue::builtin().unwrap(),
        move |_, _| Ok(ThreadOnly(Fake(state), std::rc::Rc::new(()))),
    )
    .unwrap();
    let limit = Instant::now() + Duration::from_secs(2);
    while actor.snapshot().unwrap().state == State::Connecting && Instant::now() < limit {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(actor.snapshot().unwrap().state, State::Ready);
    actor.request_close();
}
fn authority() -> Authority {
    Authority {
        profile_id: "p".into(),
        boot_id: "b".into(),
        profile_revision: 3,
        resource_id: "physical-radio".into(),
        connection_generation: 2,
    }
}
fn req(operation: Operation) -> Request {
    Request {
        authority: authority(),
        request_id: "request".into(),
        operation,
        deadline: Instant::now() + Duration::from_secs(5),
        cancelled: Arc::new(AtomicBool::new(false)),
    }
}
// Proves: CL-008-06; TC-009-001. Invalid authority cannot even activate a native transport.
#[test]
fn actor_rejects_invalid_authority_before_native_factory() {
    let mut invalid = authority();
    invalid.profile_id.clear();
    let activated = Arc::new(AtomicBool::new(false));
    let called = activated.clone();
    let result = radio_control::actor::Actor::begin(
        Configuration::parse("COM3").unwrap(),
        invalid,
        Catalogue::builtin().unwrap(),
        move |_, _| {
            called.store(true, Ordering::Release);
            Ok(Fake(Arc::new(Mutex::new(Script::default()))))
        },
    );
    assert!(matches!(result, Err(Error::InvalidRequest)));
    assert!(!activated.load(Ordering::Acquire));
}
fn service(actions: Vec<Action>) -> (Executor<Fake>, Arc<Mutex<Script>>) {
    let state = Arc::new(Mutex::new(Script {
        actions: std::iter::once(Action::Bytes(FREQUENCY.to_vec()))
            .chain(actions)
            .collect(),
        ..Script::default()
    }));
    let executor = Executor::connect(
        Fake(state.clone()),
        Configuration::parse("icom7300://COM3?baud=9600&radio=94&controller=E0").unwrap(),
        authority(),
        Catalogue::builtin().unwrap(),
        &AtomicBool::new(false),
    )
    .unwrap();
    (executor, state)
}

// Proves: CL-008-06; TC-009-001. A workflow retains one lease and truthfully reports radio intervention.
#[test]
fn receive_setup_reads_every_setter_and_checks_final_measured_state() {
    let operation = Operation::ReceiveSetup {
        frequency_hz: 14_074_000,
        mode: Sideband::Usb,
        filter: 2,
        data: true,
        data_filter: 2,
    };
    let replies = [ACK, MODE, ACK, DATA, ACK, FREQUENCY, MODE, DATA, FREQUENCY];
    let (executor, state) = service(
        replies
            .into_iter()
            .map(|v| Action::Bytes(v.to_vec()))
            .collect(),
    );
    let observed = executor.execute(req(operation.clone())).unwrap();
    assert_eq!(observed.frequency_hz, Some(14_074_000));
    let bodies: Vec<Vec<u8>> = state
        .lock()
        .unwrap()
        .writes
        .iter()
        .skip(1)
        .map(|v| v[4..v.len() - 1].to_vec())
        .collect();
    assert_eq!(
        bodies,
        vec![
            vec![6, 1, 2],
            vec![4],
            vec![0x1a, 6, 1, 2],
            vec![0x1a, 6],
            vec![5, 0, 0x40, 7, 0x14, 0],
            vec![3],
            vec![4],
            vec![0x1a, 6],
            vec![3]
        ]
    );
    let mut changed = FREQUENCY.to_vec();
    changed[5] = 1; // Manual intervention by one Hz before final verification.
    let mut actions: Vec<_> = replies[..8]
        .iter()
        .map(|v| Action::Bytes(v.to_vec()))
        .collect();
    actions.push(Action::Bytes(changed));
    let (executor, state) = service(actions);
    assert_eq!(
        executor.execute(req(operation)),
        Err(Error::ReadbackMismatch)
    );
    assert_eq!(
        executor.snapshot().unwrap().observation.frequency_hz,
        Some(14_074_001)
    );
    assert_eq!(state.lock().unwrap().writes.len(), 10); // No rollback or retry.
    let (executor, state) = service(vec![Action::Bytes(vec![
        0xfe, 0xfe, 0xe0, 0x94, 0xfa, 0xfd,
    ])]);
    assert_eq!(
        executor.execute(req(Operation::SetMode {
            mode: Sideband::Usb,
            filter: 2
        })),
        Err(Error::Rejected)
    );
    assert_eq!(state.lock().unwrap().writes.len(), 2);
    let (executor, _) = service(vec![
        Action::Bytes(ACK.to_vec()),
        Action::Bytes(vec![0xfe, 0xfe, 0xe0, 0x94, 0xfa, 0xfd]),
    ]);
    assert_eq!(
        executor.execute(req(Operation::SetFrequency {
            frequency_hz: 14_074_000
        })),
        Err(Error::Indeterminate)
    );
}

// Proves: CL-008-01, CL-008-06; TC-009-001.
#[test]
fn configuration_and_catalogue_cannot_admit_raw_or_transmit_operations() {
    assert_eq!(
        Configuration::parse("com3").unwrap(),
        Configuration {
            port: 3,
            baud: Baud::Auto,
            radio_address: 0x94,
            controller_address: 0xe0
        }
    );
    for input in [
        "COM0",
        "COM257",
        "COM03",
        "COM3/other",
        "icom7300://COM3?radio=94&baud=auto&controller=E0",
        "icom7300://COM3?baud=9600&radio=FF&controller=E0",
        "icom7300://COM3?baud=9600&radio=94&controller=94",
        "icom7300://COM3?baud=9600&radio=94&controller=E0&raw=1",
        "icom7300://COM3?baud=9600&radio=94&controller=E0#x",
    ] {
        assert_eq!(
            Configuration::parse(input),
            Err(Error::InvalidConfiguration),
            "{input}"
        );
    }
    let cat = Catalogue::builtin().unwrap();
    assert_eq!(cat.revision(), "icom7300-civ-receive-1");
    assert!(cat.supports(&Operation::ReadFrequency));
    assert!(serde_json::from_str::<Operation>(r#"{"operation":"ptt","enabled":true}"#).is_err());
    assert!(
        serde_json::from_str::<Operation>(r#"{"operation":"read_frequency","raw":[28,0,1]}"#)
            .is_err()
    );
    let mut doc: serde_json::Value =
        serde_json::from_slice(include_bytes!("../../fixtures/radio/ic7300-catalogue.json"))
            .unwrap();
    doc["commands"][0]["request_prefix"] = serde_json::json!([28, 0, 1]);
    assert!(Catalogue::parse(&serde_json::to_vec(&doc).unwrap()).is_err());
    assert!(Catalogue::parse(&vec![b' '; 262145]).is_err());
}

// Proves: CL-008-04, CL-008-06; TC-009-001, TC-009-003.
#[test]
fn civ_frames_match_independently_recorded_icom_bytes() {
    let cfg = Configuration::parse("COM3").unwrap();
    for (operation, body) in [
        (Operation::ReadFrequency, vec![3]),
        (Operation::ReadMode, vec![4]),
        (Operation::ReadData, vec![0x1a, 6]),
        (Operation::ReadRxTx, vec![0x1c, 0]),
        (Operation::ReadSplit, vec![0x0f]),
        (
            Operation::SetMode {
                mode: Sideband::Usb,
                filter: 3,
            },
            vec![6, 1, 3],
        ),
        (
            Operation::SetData {
                data: true,
                filter: 1,
            },
            vec![0x1a, 6, 1, 1],
        ),
    ] {
        let mut expected = vec![0xfe, 0xfe, 0x94, 0xe0];
        expected.extend(body);
        expected.push(0xfd);
        assert_eq!(codec::request(&cfg, &operation).unwrap(), expected);
    }
    for operation in [
        Operation::SetFrequency {
            frequency_hz: 29999,
        },
        Operation::SetFrequency {
            frequency_hz: 74800001,
        },
        Operation::SetMode {
            mode: Sideband::Usb,
            filter: 0,
        },
        Operation::SetMode {
            mode: Sideband::Lsb,
            filter: 4,
        },
        Operation::SetData {
            data: false,
            filter: 1,
        },
        Operation::SetData {
            data: true,
            filter: 0,
        },
        Operation::SetData {
            data: true,
            filter: 4,
        },
    ] {
        assert_eq!(codec::request(&cfg, &operation), Err(Error::InvalidRequest));
    }
    assert_eq!(
        codec::encode_frequency(14_074_000).unwrap(),
        [0, 0x40, 7, 0x14, 0]
    );
    assert_eq!(codec::encode_frequency(30_000).unwrap(), [0, 0, 3, 0, 0]);
    assert_eq!(
        codec::encode_frequency(74_800_000).unwrap(),
        [0, 0, 0x80, 0x74, 0]
    );
    assert_eq!(
        codec::request(&cfg, &Operation::ReadFrequency).unwrap(),
        [0xfe, 0xfe, 0x94, 0xe0, 3, 0xfd]
    );
    assert_eq!(
        codec::request(
            &cfg,
            &Operation::SetFrequency {
                frequency_hz: 14_074_000
            }
        )
        .unwrap(),
        [0xfe, 0xfe, 0x94, 0xe0, 5, 0, 0x40, 7, 0x14, 0, 0xfd]
    );
    assert_eq!(
        codec::request(
            &cfg,
            &Operation::SetData {
                data: false,
                filter: 0
            }
        )
        .unwrap(),
        [0xfe, 0xfe, 0x94, 0xe0, 0x1a, 6, 0, 0, 0xfd]
    );
    assert_eq!(
        codec::reply(&cfg, FREQUENCY, &Operation::ReadFrequency).unwrap(),
        Some(Reply::Frequency(14_074_000))
    );
    assert_eq!(
        codec::decode_frequency(&[0xfa, 0, 0, 0, 0]),
        Err(Error::Protocol)
    );
    assert_eq!(
        codec::reply(
            &cfg,
            &[0xfe, 0xfe, 0xe0, 0x94, 4, 0x77, 1, 0xfd],
            &Operation::ReadMode
        )
        .unwrap(),
        Some(Reply::Mode(ModeValue {
            code: 0x77,
            filter: 1
        }))
    );
    assert_eq!(
        codec::reply(
            &cfg,
            &[0xfe, 0xfe, 0x94, 0xe0, 3, 0xfd],
            &Operation::ReadFrequency
        )
        .unwrap(),
        None
    );
    assert_eq!(
        codec::reply(&cfg, ACK, &Operation::ReadFrequency).unwrap(),
        None
    );
}

// Proves: CL-008-03, CL-008-06; TC-009-001.
#[test]
fn fragmented_parser_preserves_exact_frame_byte_and_count_limits() {
    let mut parser = Framer::default();
    let mut result = Vec::new();
    for byte in FREQUENCY {
        result.extend(parser.feed(&[*byte]).unwrap());
    }
    assert_eq!(result, [FREQUENCY.to_vec()]);
    let mut parser = Framer::default();
    let frame = [0xfe, 0xfe, 0xe0, 0x94, 0xfb, 0xfd];
    let bytes = frame.repeat(64);
    let mut count = 0;
    for chunk in bytes.chunks(256) {
        count += parser.feed(chunk).unwrap().len();
    }
    assert_eq!(count, 64);
    assert_eq!(parser.feed(&frame), Err(Error::Limit));
    let mut parser = Framer::default();
    for _ in 0..16 {
        assert!(parser.feed(&[0; 256]).unwrap().is_empty());
    }
    assert_eq!(parser.feed(&[0]), Err(Error::Limit));
    let mut max = vec![0xfe, 0xfe, 0xe0, 0x94];
    max.extend([0; 27]);
    max.push(0xfd);
    assert_eq!(Framer::default().feed(&max).unwrap()[0].len(), 32);
    max.insert(5, 0);
    assert_eq!(Framer::default().feed(&max), Err(Error::Limit));
}

// Proves: CL-008-03, CL-008-05, CL-008-06; TC-009-001, TC-009-003.
#[test]
fn setters_need_ack_and_independent_readback_and_preserve_actual_mismatch() {
    let (executor, state) = service(vec![
        Action::Bytes(ACK.to_vec()),
        Action::Bytes(FREQUENCY.to_vec()),
    ]);
    assert_eq!(
        executor
            .execute(req(Operation::SetFrequency {
                frequency_hz: 14_074_000
            }))
            .unwrap()
            .frequency_hz,
        Some(14_074_000)
    );
    assert_eq!(
        state.lock().unwrap().writes[2],
        [0xfe, 0xfe, 0x94, 0xe0, 3, 0xfd]
    );
    let (executor, _) = service(vec![
        Action::Bytes(ACK.to_vec()),
        Action::Bytes(MODE.to_vec()),
    ]);
    assert_eq!(
        executor.execute(req(Operation::SetMode {
            mode: Sideband::Lsb,
            filter: 2
        })),
        Err(Error::ReadbackMismatch)
    );
    assert_eq!(
        executor
            .snapshot()
            .unwrap()
            .observation
            .mode
            .unwrap()
            .sideband(),
        Some(Sideband::Usb)
    );
    let (executor, state) = service(vec![Action::Bytes(ACK.to_vec()), Action::Timeout]);
    assert_eq!(
        executor.execute(req(Operation::SetData {
            data: true,
            filter: 2
        })),
        Err(Error::Indeterminate)
    );
    assert_eq!(executor.snapshot().unwrap().state, State::Unavailable);
    assert_eq!(state.lock().unwrap().closed, 1);
}

// Proves: CL-008-03, CL-008-06; TC-009-001, TC-009-004.
#[test]
fn admission_and_cancel_never_publish_stale_data_or_retry_writes() {
    let (executor, state) = service(vec![Action::Cancel(MODE.to_vec())]);
    let mut stale = req(Operation::ReadMode);
    stale.authority.profile_revision += 1;
    assert_eq!(executor.execute(stale), Err(Error::StaleContext));
    assert_eq!(
        executor.execute(req(Operation::SetFrequency { frequency_hz: 1 })),
        Err(Error::InvalidRequest)
    );
    let cancelled = req(Operation::ReadMode);
    cancelled.cancelled.store(true, Ordering::Release);
    assert_eq!(executor.execute(cancelled), Err(Error::Cancelled));
    assert_eq!(state.lock().unwrap().writes.len(), 1);
    assert_eq!(
        executor.execute(req(Operation::ReadMode)),
        Err(Error::Cancelled)
    );
    assert_eq!(executor.snapshot().unwrap().observation.mode, None);
    assert_eq!(executor.snapshot().unwrap().state, State::Unavailable);
    assert_eq!(state.lock().unwrap().closed, 1);
    assert_eq!(
        executor.execute(req(Operation::ReadMode)),
        Err(Error::Unavailable)
    );
    assert_eq!(state.lock().unwrap().writes.len(), 2);
}

// Proves: CL-008-04, CL-008-06; TC-009-001.
#[test]
fn auto_baud_is_bounded_connection_discovery_and_does_not_rewrite_intent() {
    let state = Arc::new(Mutex::new(Script {
        actions: VecDeque::from([Action::Timeout, Action::Bytes(FREQUENCY.to_vec())]),
        ..Script::default()
    }));
    let cfg = Configuration::parse("COM3").unwrap();
    let expected = cfg.clone();
    let executor = Executor::connect(
        Fake(state.clone()),
        cfg,
        authority(),
        Catalogue::builtin().unwrap(),
        &AtomicBool::new(false),
    )
    .unwrap();
    assert_eq!(state.lock().unwrap().rates, [9600, 19200]);
    assert_eq!(state.lock().unwrap().quiet, 1);
    assert_eq!(expected.baud, Baud::Auto);
    assert_eq!(executor.snapshot().unwrap().effective_baud, Some(19200));
}

// Proves: CL-008-03, CL-008-05; TC-009-001, TC-009-003, TC-009-004.
#[test]
fn partial_writes_and_failed_close_keep_truthful_connection_state() {
    let (executor, state) = service(vec![Action::Partial]);
    assert_eq!(
        executor.execute(req(Operation::ReadMode)),
        Err(Error::PartialWrite)
    );
    assert_eq!(executor.snapshot().unwrap().state, State::Unavailable);
    assert_eq!(state.lock().unwrap().writes.len(), 2);
    let (executor, state) = service(vec![Action::Timeout]);
    state.lock().unwrap().close_error = true;
    assert_eq!(
        executor.execute(req(Operation::ReadMode)),
        Err(Error::FailedClose)
    );
    assert_eq!(executor.snapshot().unwrap().state, State::Closing);
}

// Proves: CL-008-03; TC-009-001.
#[test]
fn polling_has_one_cycle_per_second_and_fragmentation_never_renews_deadline() {
    let (executor, state) = service(vec![
        Action::Bytes(FREQUENCY.to_vec()),
        Action::Bytes(MODE.to_vec()),
        Action::Bytes(DATA.to_vec()),
        Action::Bytes(vec![0xfe, 0xfe, 0xe0, 0x94, 0x1c, 0, 0, 0xfd]),
        Action::Bytes(vec![0xfe, 0xfe, 0xe0, 0x94, 0x0f, 0, 0xfd]),
    ]);
    state.lock().unwrap().fragment = 1;
    executor
        .refresh(
            Arc::new(AtomicBool::new(false)),
            Instant::now() + Duration::from_secs(5),
        )
        .unwrap();
    let writes = state.lock().unwrap().writes.len();
    assert_eq!(
        executor.refresh(
            Arc::new(AtomicBool::new(false)),
            Instant::now() + Duration::from_secs(5)
        ),
        Err(Error::Busy)
    );
    assert_eq!(state.lock().unwrap().writes.len(), writes);
    let state = state.lock().unwrap();
    let frequency_deadline = state.deadlines[2];
    assert!(
        state.deadlines[2..2 + FREQUENCY.len()]
            .iter()
            .all(|deadline| *deadline == frequency_deadline)
    );
}
