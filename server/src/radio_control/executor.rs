#![forbid(unsafe_code)]
use super::{
    Authority, Baud, Configuration, DataValue, Error, Observation, Operation, Request, Result,
    Snapshot, State,
    catalogue::Catalogue,
    codec::{self, Framer, Reply},
};
use std::{
    sync::{
        Arc, Mutex, TryLockError,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

/// Transport calls must finish at the absolute deadline and check cancellation at <=50 ms intervals.
pub trait Transport {
    fn physical_identity(&self) -> Option<&str> {
        None
    }
    fn configure(&mut self, baud: u32) -> Result<()>;
    fn write(&mut self, bytes: &[u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize>;
    fn read(&mut self, bytes: &mut [u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize>;
    fn quiet(&mut self, deadline: Instant, cancel: &AtomicBool) -> Result<()>;
    fn close(&mut self) -> Result<()>;
}
struct Inner<T> {
    transport: T,
    configuration: Configuration,
    last_poll: Option<Instant>,
}
pub struct Executor<T: Transport> {
    authority: Authority,
    catalogue: Catalogue,
    inner: Mutex<Inner<T>>,
    snapshot: Arc<Mutex<Snapshot>>,
}
impl<T: Transport> Executor<T> {
    pub fn connect(
        transport: T,
        configuration: Configuration,
        authority: Authority,
        catalogue: Catalogue,
        cancel: &AtomicBool,
    ) -> Result<Self> {
        Self::connect_until(
            transport,
            configuration,
            authority,
            catalogue,
            cancel,
            Instant::now() + Duration::from_secs(5),
        )
    }
    pub fn connect_until(
        mut transport: T,
        configuration: Configuration,
        authority: Authority,
        catalogue: Catalogue,
        cancel: &AtomicBool,
        overall: Instant,
    ) -> Result<Self> {
        if let Err(error) = configuration.validate() {
            let _ = transport.close();
            return Err(error);
        }
        if !catalogue.supports(&Operation::ReadFrequency) {
            let _ = transport.close();
            return Err(Error::Unsupported);
        }
        if let Err(error) = authority.validate() {
            if transport.close().is_err() {
                return Err(Error::FailedClose);
            }
            return Err(error);
        }
        let automatic = configuration.baud == Baud::Auto;
        let rates = match configuration.baud {
            Baud::Auto => vec![9600, 19200, 4800, 115200, 57600, 38400],
            Baud::Fixed(rate) => vec![rate],
        };
        let mut found = None;
        let mut last_error = Error::Timeout;
        for (index, rate) in rates.into_iter().enumerate() {
            if let Err(error) = check(overall, cancel) {
                last_error = error;
                break;
            }
            if index > 0
                && let Err(error) = transport.quiet(
                    std::cmp::min(overall, Instant::now() + Duration::from_millis(100)),
                    cancel,
                )
            {
                last_error = error;
                break;
            }
            if let Err(error) = transport.configure(rate) {
                last_error = error;
                break;
            }
            let budget = if automatic {
                Duration::from_millis(500)
            } else {
                Duration::from_secs(1)
            };
            let response = exchange(
                &mut transport,
                &configuration,
                &Operation::ReadFrequency,
                std::cmp::min(overall, Instant::now() + budget),
                cancel,
            );
            match response {
                Ok(Reply::Frequency(frequency)) => {
                    found = Some((rate, frequency));
                    break;
                }
                Ok(_) => last_error = Error::Protocol,
                Err(error) => {
                    last_error = error;
                    if !automatic
                        || matches!(
                            error,
                            Error::Cancelled
                                | Error::PartialWrite
                                | Error::Unavailable
                                | Error::FailedClose
                        )
                    {
                        break;
                    }
                }
            }
        }
        let Some((rate, frequency)) = found else {
            if transport.close().is_err() {
                return Err(Error::FailedClose);
            }
            return Err(last_error);
        };
        let observed_at = Instant::now();
        let observation = Observation {
            frequency_hz: Some(frequency),
            observed_at: Some(observed_at),
            ..Observation::default()
        };
        let snapshot = Arc::new(Mutex::new(Snapshot {
            publication: 0,
            closing_requested: false,
            state: State::Ready,
            authority: authority.clone(),
            effective_baud: Some(rate),
            observation,
            facts: super::Facts {
                sequence: 1,
                frequency: super::Fact::observed(frequency, 1, observed_at),
                ..super::Facts::default()
            },
            last_error: None,
        }));
        Ok(Self {
            authority,
            catalogue,
            inner: Mutex::new(Inner {
                transport,
                configuration,
                last_poll: None,
            }),
            snapshot,
        })
    }
    pub fn snapshot(&self) -> Result<Snapshot> {
        self.snapshot
            .lock()
            .map(|s| s.clone())
            .map_err(|_| Error::Unavailable)
    }
    pub(super) fn attach_snapshot(&mut self, shared: Arc<Mutex<Snapshot>>) -> Result<()> {
        let mut candidate = self.snapshot()?;
        {
            let mut current = shared.lock().map_err(|_| Error::Unavailable)?;
            candidate.publication = current.publication;
            candidate.publish()?;
            if current.closing_requested {
                candidate.closing_requested = true;
                candidate.state = current.state;
                candidate.last_error = current.last_error;
                candidate.facts.stale();
            }
            *current = candidate;
        }
        self.snapshot = shared;
        Ok(())
    }
    pub fn execute(&self, request: Request) -> Result<Observation> {
        request.operation.validate()?;
        if request.authority != self.authority {
            return Err(Error::StaleContext);
        }
        if request.request_id.is_empty() || request.request_id.len() > 64 {
            return Err(Error::InvalidRequest);
        }
        if !self.catalogue.supports(&request.operation) {
            return Err(Error::Unsupported);
        }
        check(request.deadline, &request.cancelled)?;
        let mut inner = self.inner.try_lock().map_err(|e| match e {
            TryLockError::WouldBlock => Error::Busy,
            TryLockError::Poisoned(_) => Error::Unavailable,
        })?;
        if self.snapshot()?.state != State::Ready {
            return Err(Error::Unavailable);
        }
        let composite = matches!(request.operation, Operation::ReceiveSetup { .. });
        let overall = std::cmp::min(
            request.deadline,
            Instant::now()
                + if composite {
                    Duration::from_secs(5)
                } else {
                    Duration::from_secs(2)
                },
        );
        let result = self
            .run(&mut inner, &request.operation, overall, &request.cancelled)
            .and_then(|()| check(overall, &request.cancelled));
        match result {
            Ok(()) => {
                let mut s = self.snapshot.lock().map_err(|_| Error::Unavailable)?;
                if !s.closing_requested && s.last_error.is_some() {
                    s.publish()?;
                    s.last_error = None;
                }
                Ok(s.observation.clone())
            }
            Err(error) => {
                self.snapshot
                    .lock()
                    .map_err(|_| Error::Unavailable)?
                    .invalidate(&request.operation)?;
                let must_close = !matches!(
                    error,
                    Error::Rejected
                        | Error::ReadbackMismatch
                        | Error::InvalidRequest
                        | Error::Unsupported
                );
                if must_close {
                    self.set_state(State::Closing, Some(error))?;
                    if inner.transport.close().is_err() {
                        self.set_state(State::Closing, Some(Error::FailedClose))?;
                        return Err(Error::FailedClose);
                    }
                    self.set_state(State::Unavailable, Some(error))?;
                } else {
                    self.set_state(State::Ready, Some(error))?;
                }
                Err(error)
            }
        }
    }
    pub fn refresh(&self, cancel: Arc<AtomicBool>, deadline: Instant) -> Result<Observation> {
        let mut inner = self.inner.try_lock().map_err(|_| Error::Busy)?;
        if self.snapshot()?.state != State::Ready {
            return Err(Error::Unavailable);
        }
        let now = Instant::now();
        if inner
            .last_poll
            .is_some_and(|last| now.duration_since(last) < Duration::from_secs(1))
        {
            return Err(Error::Busy);
        }
        inner.last_poll = Some(now);
        let overall = std::cmp::min(deadline, now + Duration::from_secs(5));
        let operations = [
            Operation::ReadFrequency,
            Operation::ReadMode,
            Operation::ReadData,
            Operation::ReadRxTx,
            Operation::ReadSplit,
        ];
        if !operations
            .iter()
            .all(|operation| self.catalogue.supports(operation))
        {
            return Err(Error::Unsupported);
        }
        for operation in operations {
            if let Err(error) = self.run(&mut inner, &operation, overall, &cancel) {
                self.set_state(State::Closing, Some(error))?;
                if inner.transport.close().is_err() {
                    self.set_state(State::Closing, Some(Error::FailedClose))?;
                    return Err(Error::FailedClose);
                }
                self.set_state(State::Unavailable, Some(error))?;
                return Err(error);
            }
        }
        Ok(self.snapshot()?.observation)
    }
    pub fn close(&self) -> Result<()> {
        let mut inner = self.inner.try_lock().map_err(|_| Error::Busy)?;
        self.set_state(State::Closing, None)?;
        if inner.transport.close().is_err() {
            self.set_state(State::Closing, Some(Error::FailedClose))?;
            return Err(Error::FailedClose);
        }
        self.set_state(State::Closed, None)
    }
    fn set_state(&self, state: State, error: Option<Error>) -> Result<()> {
        let mut snapshot = self.snapshot.lock().map_err(|_| Error::Unavailable)?;
        let state = if snapshot.closing_requested && state != State::Closed {
            State::Closing
        } else {
            state
        };
        snapshot.publish()?;
        snapshot.state = state;
        if state != State::Ready {
            snapshot.facts.stale();
        }
        snapshot.last_error = error;
        Ok(())
    }
    fn update(&self, reply: &Reply) -> Result<()> {
        let mut snapshot = self.snapshot.lock().map_err(|_| Error::Unavailable)?;
        if matches!(reply, Reply::Ack | Reply::Rejected) {
            return Ok(());
        }
        let sequence = snapshot
            .facts
            .sequence
            .checked_add(1)
            .filter(|n| *n <= 9_007_199_254_740_991)
            .ok_or(Error::Limit)?;
        let at = Instant::now();
        match reply {
            Reply::Frequency(v) => {
                snapshot.observation.frequency_hz = Some(*v);
                snapshot.facts.frequency = super::Fact::observed(*v, sequence, at);
            }
            Reply::Mode(v) => {
                snapshot.observation.mode = Some(*v);
                snapshot.facts.mode = super::Fact::observed(*v, sequence, at);
            }
            Reply::Data(v) => {
                snapshot.observation.data = Some(*v);
                snapshot.facts.data = super::Fact::observed(*v, sequence, at);
            }
            Reply::Transmitting(v) => {
                snapshot.observation.transmitting = Some(*v);
                snapshot.facts.rx_tx = super::Fact::observed(*v, sequence, at);
            }
            Reply::Split(v) => {
                snapshot.observation.split = Some(*v);
                snapshot.facts.split = super::Fact::observed(*v, sequence, at);
            }
            Reply::Ack | Reply::Rejected => return Ok(()),
        };
        snapshot.facts.sequence = sequence;
        snapshot.observation.observed_at = Some(at);
        if snapshot.closing_requested {
            snapshot.facts.stale();
        }
        snapshot.publish()?;
        Ok(())
    }
    fn run(
        &self,
        inner: &mut Inner<T>,
        operation: &Operation,
        overall: Instant,
        cancel: &AtomicBool,
    ) -> Result<()> {
        // Before a setter can emit bytes, its prior facts cease to establish readiness.
        self.snapshot
            .lock()
            .map_err(|_| Error::Unavailable)?
            .invalidate(operation)?;
        if let Operation::ReceiveSetup {
            frequency_hz,
            mode,
            filter,
            data,
            data_filter,
        } = operation
        {
            for setter in [
                Operation::SetMode {
                    mode: *mode,
                    filter: *filter,
                },
                Operation::SetData {
                    data: *data,
                    filter: *data_filter,
                },
                Operation::SetFrequency {
                    frequency_hz: *frequency_hz,
                },
            ] {
                self.run(inner, &setter, overall, cancel)?;
            }
            for query in [
                Operation::ReadMode,
                Operation::ReadData,
                Operation::ReadFrequency,
            ] {
                self.run(inner, &query, overall, cancel)?;
            }
            let actual = self.snapshot()?.observation;
            if actual.frequency_hz != Some(*frequency_hz)
                || actual
                    .mode
                    .is_none_or(|v| v.sideband() != Some(*mode) || v.filter != *filter)
                || actual.data
                    != Some(DataValue {
                        enabled: *data,
                        filter: *data_filter,
                    })
            {
                return Err(Error::ReadbackMismatch);
            }
            return Ok(());
        }
        let deadline = std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
        if self.snapshot()?.facts.sequence >= 9_007_199_254_740_991 {
            return Err(Error::Limit);
        }
        let reply = exchange(
            &mut inner.transport,
            &inner.configuration,
            operation,
            deadline,
            cancel,
        )?;
        self.update(&reply)?;
        if matches!(reply, Reply::Rejected) {
            return Err(Error::Rejected);
        }
        let query = match operation {
            Operation::SetFrequency { .. } => Some(Operation::ReadFrequency),
            Operation::SetMode { .. } => Some(Operation::ReadMode),
            Operation::SetData { .. } => Some(Operation::ReadData),
            _ => None,
        };
        if let Some(query) = query {
            if reply != Reply::Ack {
                return Err(Error::Protocol);
            }
            let deadline = std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
            let read = exchange(
                &mut inner.transport,
                &inner.configuration,
                &query,
                deadline,
                cancel,
            )
            .map_err(|error| {
                if error == Error::Cancelled {
                    error
                } else {
                    Error::Indeterminate
                }
            })?;
            self.update(&read)?;
            if read == Reply::Rejected {
                return Err(Error::Indeterminate);
            }
            let matched = match (operation, read) {
                (Operation::SetFrequency { frequency_hz }, Reply::Frequency(actual)) => {
                    *frequency_hz == actual
                }
                (Operation::SetMode { mode, filter }, Reply::Mode(actual)) => {
                    actual.sideband() == Some(*mode) && actual.filter == *filter
                }
                (Operation::SetData { data, filter }, Reply::Data(actual)) => {
                    actual
                        == DataValue {
                            enabled: *data,
                            filter: *filter,
                        }
                }
                _ => false,
            };
            if !matched {
                return Err(Error::ReadbackMismatch);
            }
        }
        Ok(())
    }
}
fn check(deadline: Instant, cancel: &AtomicBool) -> Result<()> {
    if cancel.load(Ordering::Acquire) {
        Err(Error::Cancelled)
    } else if Instant::now() >= deadline {
        Err(Error::Timeout)
    } else {
        Ok(())
    }
}
fn exchange<T: Transport>(
    transport: &mut T,
    configuration: &Configuration,
    operation: &Operation,
    deadline: Instant,
    cancel: &AtomicBool,
) -> Result<Reply> {
    check(deadline, cancel)?;
    let bytes = codec::request(configuration, operation)?;
    let count = transport.write(&bytes, deadline, cancel)?;
    if count != bytes.len() {
        return Err(Error::PartialWrite);
    }
    check(deadline, cancel)?;
    let mut framer = Framer::default();
    let mut buffer = [0; codec::MAX_READ];
    loop {
        check(deadline, cancel)?;
        let count = transport.read(&mut buffer, deadline, cancel)?;
        check(deadline, cancel)?;
        if count > buffer.len() {
            return Err(Error::Protocol);
        }
        if count == 0 {
            std::thread::yield_now();
            continue;
        }
        for frame in framer.feed(&buffer[..count])? {
            if let Some(reply) = codec::reply(configuration, &frame, operation)? {
                return Ok(reply);
            }
        }
    }
}

#[cfg(test)]
mod publication_tests {
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
}
