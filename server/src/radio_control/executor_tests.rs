use super::*;
struct NoIo;
impl Transport for NoIo {
    fn configure(&mut self, _: u32) -> Result<()> {
        panic!("no I/O in publication interleaving")
    }
    fn write(&mut self, _: &[u8], _: Instant, _: &AtomicBool) -> Result<usize> {
        panic!("no I/O in publication interleaving")
    }
    fn read(&mut self, _: &mut [u8], _: Instant, _: &AtomicBool) -> Result<usize> {
        panic!("no I/O in publication interleaving")
    }
    fn quiet(&mut self, _: Instant, _: &AtomicBool) -> Result<()> {
        panic!("no I/O in publication interleaving")
    }
    fn close(&mut self) -> Result<()> {
        panic!("no I/O in publication interleaving")
    }
}
/// Records whether the frequency fact counts as confirmed when the setter frame is sent.
struct Probe {
    shared: Arc<Mutex<Snapshot>>,
    replies: std::collections::VecDeque<Vec<u8>>,
    pending: Vec<u8>,
    at_setter: Arc<Mutex<Vec<bool>>>,
}
impl Transport for Probe {
    fn configure(&mut self, _: u32) -> Result<()> {
        Ok(())
    }
    fn write(&mut self, bytes: &[u8], _: Instant, _: &AtomicBool) -> Result<usize> {
        if bytes[4] == 5 {
            let confirmed = self.shared.lock().unwrap().facts.frequency.confirmed;
            self.at_setter.lock().unwrap().push(confirmed);
        }
        self.pending = self.replies.pop_front().unwrap();
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
// The read-first read does not re-confirm the old value
// while the setter frame is on the wire; the read-back confirms the new one.
// Proves: TC-044-012
#[test]
fn setter_fact_stays_unconfirmed_from_the_write_until_its_read_back() {
    let authority = Authority {
        profile_id: "a".into(),
        boot_id: "b".into(),
        profile_revision: 0,
        resource_id: "isolated".into(),
        connection_generation: 1,
    };
    let shared = Arc::new(Mutex::new(Snapshot {
        publication: 0,
        closing_requested: false,
        state: State::Ready,
        authority: authority.clone(),
        effective_baud: Some(9600),
        observation: Observation::default(),
        facts: super::super::Facts::default(),
        last_error: None,
    }));
    let at_setter = Arc::new(Mutex::new(Vec::new()));
    let executor = Executor {
        authority,
        catalogue: Catalogue::builtin().unwrap(),
        inner: Mutex::new(Inner {
            transport: Probe {
                shared: shared.clone(),
                replies: [
                    vec![0xfe, 0xfe, 0xe0, 0x94, 3, 0, 0x40, 7, 7, 0, 0xfd],
                    vec![0xfe, 0xfe, 0xe0, 0x94, 0xfb, 0xfd],
                    vec![0xfe, 0xfe, 0xe0, 0x94, 3, 0, 0x40, 7, 0x14, 0, 0xfd],
                ]
                .into(),
                pending: Vec::new(),
                at_setter: at_setter.clone(),
            },
            configuration: Configuration::parse("COM3").unwrap(),
            last_poll: None,
        }),
        snapshot: shared.clone(),
    };
    let mut inner = executor.inner.lock().unwrap();
    executor
        .run(
            &mut inner,
            &Operation::SetFrequency {
                frequency_hz: 14_074_000,
            },
            Instant::now() + Duration::from_secs(3),
            &AtomicBool::new(false),
        )
        .unwrap();
    assert_eq!(*at_setter.lock().unwrap(), [false]);
    let facts = shared.lock().unwrap().facts.clone();
    assert_eq!(
        (facts.frequency.confirmed, facts.frequency.value),
        (true, Some(14_074_000))
    );
}
#[test]
fn closing_publication_survives_late_attach_and_query() {
    let authority = Authority {
        profile_id: "a".into(),
        boot_id: "b".into(),
        profile_revision: 0,
        resource_id: "isolated".into(),
        connection_generation: 1,
    };
    let ready = Snapshot {
        publication: 0,
        closing_requested: false,
        state: State::Ready,
        authority: authority.clone(),
        effective_baud: Some(9600),
        observation: Observation::default(),
        facts: super::super::Facts::default(),
        last_error: None,
    };
    let mut closing = ready.clone();
    closing.publication = 9;
    closing.closing_requested = true;
    closing.state = State::Closing;
    let shared = Arc::new(Mutex::new(closing));
    let mut executor = Executor {
        authority,
        catalogue: Catalogue::builtin().unwrap(),
        inner: Mutex::new(Inner {
            transport: NoIo,
            configuration: Configuration::parse("COM3").unwrap(),
            last_poll: None,
        }),
        snapshot: Arc::new(Mutex::new(ready)),
    };
    executor.attach_snapshot(shared).unwrap();
    let attached = executor.snapshot().unwrap();
    assert_eq!(attached.state, State::Closing);
    assert_eq!(attached.publication(), 10);
    executor
        .update(&Reply::Mode(super::super::ModeValue { code: 1, filter: 1 }))
        .unwrap();
    executor.set_state(State::Ready, None).unwrap();
    let late = executor.snapshot().unwrap();
    assert_eq!(
        late.state,
        State::Closing,
        "late executor success cannot undo requested close"
    );
    assert!(
        late.facts.mode.value.is_some(),
        "late reply can retain a dated observation"
    );
    assert!(
        !late.facts.mode.confirmed,
        "late reply cannot restore freshness after close"
    );
    assert!(late.publication() > attached.publication());
    assert_eq!(
        executor.snapshot().unwrap().publication(),
        late.publication(),
        "pure reads do not publish"
    );
}
