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
/// A station owner may select its physical transport at runtime (serial or fixture).
impl<T: Transport + ?Sized> Transport for Box<T> {
    fn physical_identity(&self) -> Option<&str> {
        (**self).physical_identity()
    }
    fn configure(&mut self, baud: u32) -> Result<()> {
        (**self).configure(baud)
    }
    fn write(&mut self, bytes: &[u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        (**self).write(bytes, deadline, cancel)
    }
    fn read(&mut self, bytes: &mut [u8], deadline: Instant, cancel: &AtomicBool) -> Result<usize> {
        (**self).read(bytes, deadline, cancel)
    }
    fn quiet(&mut self, deadline: Instant, cancel: &AtomicBool) -> Result<()> {
        (**self).quiet(deadline, cancel)
    }
    fn close(&mut self) -> Result<()> {
        (**self).close()
    }
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
    /// Transmit switch with independent readback (WstxTransmit::PttControl): write
    /// 1C 00 01|00, require ACK, then read 1C 00 and require the requested state.
    /// Only the actor's transmit hold calls this; it is not an `Operation`, so neither
    /// the catalogue nor the wire can reach it. Exchange failure closes the connection
    /// as for every other exchange; the PTT state is then indeterminate.
    pub fn set_ptt(&self, on: bool, deadline: Instant, cancel: &AtomicBool) -> Result<()> {
        check(deadline, cancel)?;
        let mut inner = self.inner.try_lock().map_err(|e| match e {
            TryLockError::WouldBlock => Error::Busy,
            TryLockError::Poisoned(_) => Error::Unavailable,
        })?;
        // An off-only release is still admitted on a connection whose close was
        // requested but whose transport is not yet closed.
        let state = self.snapshot()?.state;
        if state != State::Ready && (on || state != State::Closing) {
            return Err(Error::Unavailable);
        }
        let overall = std::cmp::min(deadline, Instant::now() + Duration::from_secs(2));
        let Inner {
            transport,
            configuration,
            ..
        } = &mut *inner;
        let result = (|| {
            {
                let mut s = self.snapshot.lock().map_err(|_| Error::Unavailable)?;
                if s.facts.rx_tx.confirmed {
                    s.facts.rx_tx.confirmed = false;
                    s.publish()?;
                }
            }
            let bytes = codec::ptt_request(configuration, on)?;
            let write_deadline = std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
            let reply = exchange_bytes(transport, &bytes, write_deadline, cancel, |frame| {
                codec::ptt_reply(configuration, frame)
            })?;
            match reply {
                Reply::Ack => {}
                Reply::Rejected => return Err(Error::Rejected),
                _ => return Err(Error::Protocol),
            }
            let read_deadline = std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
            let read = exchange(
                transport,
                configuration,
                &Operation::ReadRxTx,
                read_deadline,
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
            match read {
                Reply::Transmitting(actual) if actual == on => Ok(()),
                Reply::Transmitting(_) => Err(Error::ReadbackMismatch),
                _ => Err(Error::Indeterminate),
            }
        })();
        if let Err(error) = result {
            let must_close = !matches!(
                error,
                Error::Rejected | Error::ReadbackMismatch | Error::InvalidRequest
            );
            if must_close {
                self.set_state(State::Closing, Some(error))?;
                if transport.close().is_err() {
                    self.set_state(State::Closing, Some(Error::FailedClose))?;
                    return Err(Error::FailedClose);
                }
                self.set_state(State::Unavailable, Some(error))?;
            } else {
                self.set_state(State::Ready, Some(error))?;
            }
            return Err(error);
        }
        Ok(())
    }
    /// #44 CL-044-01/03/04 menu exchanges through this single I/O owner. Like `set_ptt`
    /// it is not an `Operation`: neither the catalogue nor /radio/operation reaches it.
    /// A write requires the radio to report RX first, an ACK, and an equal readback.
    pub fn setup(
        &self,
        command: super::SetupCommand,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<super::SetupReply> {
        use super::{SetupCommand, SetupReply, setup};
        check(deadline, cancel)?;
        let mut inner = self.inner.try_lock().map_err(|e| match e {
            TryLockError::WouldBlock => Error::Busy,
            TryLockError::Poisoned(_) => Error::Unavailable,
        })?;
        if self.snapshot()?.state != State::Ready {
            return Err(Error::Unavailable);
        }
        let overall = std::cmp::min(deadline, Instant::now() + Duration::from_secs(3));
        let Inner {
            transport,
            configuration,
            ..
        } = &mut *inner;
        let address = configuration.radio_address;
        let step = || std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
        let read = |transport: &mut T, setting: setup::Setting| -> Result<Option<u16>> {
            let bytes = setup::read_setting_frame(address, setting);
            exchange_setup(transport, &bytes, step(), cancel, |h| match h {
                setup::Heard::Setting {
                    address: a,
                    setting: s,
                    data,
                } if a == address && s == setting => Some(setting.decode(&data).map(Some)),
                setup::Heard::Ng { address: a } if a == address => Some(Ok(None)),
                _ => None,
            })?
        };
        // FA: the radio refused the read (Rejected); a code outside 01..03 is a protocol error.
        let read_agc = |transport: &mut T| -> Result<setup::Agc> {
            let bytes = setup::read_agc_frame(address);
            exchange_setup(transport, &bytes, step(), cancel, |h| match h {
                setup::Heard::Agc { address: a, code } if a == address => {
                    Some(setup::Agc::from_code(code).ok_or(Error::Protocol))
                }
                setup::Heard::Ng { address: a } if a == address => Some(Err(Error::Rejected)),
                _ => None,
            })?
        };
        let result = (|| match command {
            // CL-044-09 read, compare, write only on a difference, verify by readback.
            SetupCommand::EnsureAgc(target) => {
                let current = read_agc(transport)?;
                if current == target {
                    return Ok(SetupReply::Agc {
                        value: current,
                        written: false,
                    });
                }
                let state = exchange(
                    transport,
                    configuration,
                    &Operation::ReadRxTx,
                    step(),
                    cancel,
                )?;
                if state != Reply::Transmitting(false) {
                    return Err(Error::Busy);
                }
                let bytes = setup::write_agc_frame(address, target);
                let acknowledged =
                    exchange_setup(transport, &bytes, step(), cancel, |h| match h {
                        setup::Heard::Ack { address: a } if a == address => Some(true),
                        setup::Heard::Ng { address: a } if a == address => Some(false),
                        _ => None,
                    })?;
                if !acknowledged {
                    return Err(Error::Rejected);
                }
                match read_agc(transport) {
                    Ok(actual) if actual == target => Ok(SetupReply::Agc {
                        value: actual,
                        written: true,
                    }),
                    Ok(_) => Err(Error::ReadbackMismatch),
                    Err(_) => Err(Error::Indeterminate),
                }
            }
            SetupCommand::ReadId => {
                let bytes = setup::ProbeFrame::ReadId(address).bytes();
                exchange_setup(transport, &bytes, step(), cancel, |h| match h {
                    setup::Heard::Id { address: a, id } if a == address => Some(id),
                    _ => None,
                })
                .map(SetupReply::Id)
            }
            SetupCommand::Read(setting) => read(transport, setting).map(SetupReply::Value),
            SetupCommand::Write(setting, value) => {
                setting.encode(value)?;
                // CL-044-09: read first; a fitting value is not written again, and a
                // value the radio refuses to report is not written blind.
                match read(transport, setting)? {
                    Some(current) if current == value => {
                        return Ok(SetupReply::Value(Some(value)));
                    }
                    Some(_) => {}
                    None => return Err(Error::Rejected),
                }
                let state = exchange(
                    transport,
                    configuration,
                    &Operation::ReadRxTx,
                    step(),
                    cancel,
                )?;
                if state != Reply::Transmitting(false) {
                    return Err(Error::Busy);
                }
                let bytes = setup::write_setting_frame(address, setting, value)?;
                let acknowledged =
                    exchange_setup(transport, &bytes, step(), cancel, |h| match h {
                        setup::Heard::Ack { address: a } if a == address => Some(true),
                        setup::Heard::Ng { address: a } if a == address => Some(false),
                        _ => None,
                    })?;
                if !acknowledged {
                    return Err(Error::Rejected);
                }
                match read(transport, setting) {
                    Ok(Some(actual)) if actual == value => Ok(SetupReply::Value(Some(actual))),
                    Ok(Some(_)) => Err(Error::ReadbackMismatch),
                    Ok(None) | Err(_) => Err(Error::Indeterminate),
                }
            }
        })();
        if let Err(error) = result
            && !matches!(
                error,
                Error::Rejected | Error::ReadbackMismatch | Error::InvalidRequest | Error::Busy
            )
        {
            self.set_state(State::Closing, Some(error))?;
            if transport.close().is_err() {
                self.set_state(State::Closing, Some(Error::FailedClose))?;
                return Err(Error::FailedClose);
            }
            self.set_state(State::Unavailable, Some(error))?;
        }
        result
    }
    /// #44 CL-044-12 one meter burst under the transmit hold. It changes no radio setting
    /// and no connection state: a timeout or a cancel (a PTT exchange waits for nothing)
    /// never closes the connection a keyed transmission still needs. A refused read (FA)
    /// is a missing meter; a late reply is skipped by the next exchange's parse.
    pub fn read_meters(
        &self,
        deadline: Instant,
        cancel: &AtomicBool,
    ) -> Result<super::setup::Meters> {
        use super::setup::{self, Heard, Meter};
        check(deadline, cancel)?;
        let mut inner = self.inner.try_lock().map_err(|e| match e {
            TryLockError::WouldBlock => Error::Busy,
            TryLockError::Poisoned(_) => Error::Unavailable,
        })?;
        if self.snapshot()?.state != State::Ready {
            return Err(Error::Unavailable);
        }
        let address = inner.configuration.radio_address;
        let mut meters = setup::Meters::default();
        for meter in Meter::ALL {
            let bytes = setup::read_meter_frame(address, meter);
            let value = exchange_setup(
                &mut inner.transport,
                &bytes,
                deadline,
                cancel,
                |h| match h {
                    Heard::Meter {
                        address: a,
                        sub_command,
                        data,
                    } if a == address && sub_command == meter.sub_command() => {
                        Some(setup::decode_bcd(data))
                    }
                    Heard::Ng { address: a } if a == address => Some(None),
                    _ => None,
                },
            )?;
            match meter {
                Meter::Alc => meters.alc = value,
                Meter::Po => meters.po = value,
                Meter::Swr => meters.swr = value,
            }
        }
        Ok(meters)
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
        self.run_written(inner, operation, overall, cancel)
            .map(|_| ())
    }
    /// As `run`; true when a setter frame was sent. CL-044-09: a setter first reads its
    /// value and sends no write frame when it already fits.
    fn run_written(
        &self,
        inner: &mut Inner<T>,
        operation: &Operation,
        overall: Instant,
        cancel: &AtomicBool,
    ) -> Result<bool> {
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
            let mut written = false;
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
                written |= self.run_written(inner, &setter, overall, cancel)?;
            }
            // Each setter read its value first; with nothing written those reads are
            // the confirmation, otherwise the final state is read again.
            if !written {
                return Ok(false);
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
            return Ok(true);
        }
        let query = match operation {
            Operation::SetFrequency { .. } => Some(Operation::ReadFrequency),
            Operation::SetMode { .. } => Some(Operation::ReadMode),
            Operation::SetData { .. } => Some(Operation::ReadData),
            _ => None,
        };
        if let Some(query) = &query {
            if self.snapshot()?.facts.sequence >= 9_007_199_254_740_991 {
                return Err(Error::Limit);
            }
            let deadline = std::cmp::min(overall, Instant::now() + Duration::from_secs(1));
            let current = exchange(
                &mut inner.transport,
                &inner.configuration,
                query,
                deadline,
                cancel,
            )?;
            self.update(&current)?;
            if current == Reply::Rejected {
                return Err(Error::Rejected);
            }
            if fits(operation, &current) {
                return Ok(false);
            }
            // That read confirmed the old value; while the setter frame is on the wire
            // the fact establishes nothing until the read-back.
            self.snapshot
                .lock()
                .map_err(|_| Error::Unavailable)?
                .invalidate(operation)?;
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
            if !fits(operation, &read) {
                return Err(Error::ReadbackMismatch);
            }
            return Ok(true);
        }
        Ok(false)
    }
}
/// True when a setter's query reply already shows the setter's value.
fn fits(operation: &Operation, reply: &Reply) -> bool {
    match (operation, reply) {
        (Operation::SetFrequency { frequency_hz }, Reply::Frequency(actual)) => {
            frequency_hz == actual
        }
        (Operation::SetMode { mode, filter }, Reply::Mode(actual)) => {
            actual.sideband() == Some(*mode) && actual.filter == *filter
        }
        (Operation::SetData { data, filter }, Reply::Data(actual)) => {
            *actual
                == DataValue {
                    enabled: *data,
                    filter: *filter,
                }
        }
        _ => false,
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
    let bytes = codec::request(configuration, operation)?;
    exchange_bytes(transport, &bytes, deadline, cancel, |frame| {
        codec::reply(configuration, frame, operation)
    })
}
/// One menu/ID exchange: frames are classified by `setup::hear`; echo and unrelated
/// traffic are skipped until `parse` claims a frame.
fn exchange_setup<T: Transport, R>(
    transport: &mut T,
    bytes: &[u8],
    deadline: Instant,
    cancel: &AtomicBool,
    parse: impl Fn(super::setup::Heard) -> Option<R>,
) -> Result<R> {
    check(deadline, cancel)?;
    if transport.write(bytes, deadline, cancel)? != bytes.len() {
        return Err(Error::PartialWrite);
    }
    let mut framer = Framer::default();
    let mut buffer = [0; codec::MAX_READ];
    loop {
        check(deadline, cancel)?;
        let count = transport.read(&mut buffer, deadline, cancel)?;
        if count > buffer.len() {
            return Err(Error::Protocol);
        }
        if count == 0 {
            std::thread::yield_now();
            continue;
        }
        for frame in framer.feed(&buffer[..count])? {
            if let Some(reply) = parse(super::setup::hear(&frame)) {
                return Ok(reply);
            }
        }
    }
}
fn exchange_bytes<T: Transport>(
    transport: &mut T,
    bytes: &[u8],
    deadline: Instant,
    cancel: &AtomicBool,
    parse: impl Fn(&[u8]) -> Result<Option<Reply>>,
) -> Result<Reply> {
    check(deadline, cancel)?;
    let count = transport.write(bytes, deadline, cancel)?;
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
            if let Some(reply) = parse(&frame)? {
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
    // Proves: CL-044-09; TC-044-012. The read-first read does not re-confirm the old value
    // while the setter frame is on the wire; the read-back confirms the new one.
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
}
