#![forbid(unsafe_code)]
//! The single CAT I/O owner. An admitted operation holds one lease; there is no backlog.
use super::{
    Authority, Configuration, Error, Observation, Request, Result, SetupCommand, SetupReply,
    Snapshot, State,
    catalogue::Catalogue,
    executor::{Executor, Transport},
};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU8, Ordering},
        mpsc::{self, SyncSender, TrySendError},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

struct Command {
    request: Request,
    response: SyncSender<Result<Observation>>,
    reservation: Option<Arc<AtomicBool>>,
}
/// A transmit-switch exchange of the transmit hold, served before any ordinary command.
struct PttCommand {
    on: bool,
    deadline: Instant,
    response: SyncSender<Result<()>>,
}
/// #44 menu exchange under an ordinary lease (lease 1): excluded by any transmit hold.
struct SetupRequest {
    command: SetupCommand,
    deadline: Instant,
    response: SyncSender<Result<SetupReply>>,
    /// Set when the exchange runs inside a receive transition's reservation.
    reservation: Option<Arc<AtomicBool>>,
}
pub struct Actor {
    commands: SyncSender<Command>,
    snapshot: Arc<Mutex<Snapshot>>,
    lease: Arc<AtomicU8>,
    shutdown: Arc<AtomicBool>,
    current_cancel: Arc<Mutex<Option<Arc<AtomicBool>>>>,
    ptt: SyncSender<PttCommand>,
    setup: SyncSender<SetupRequest>,
    /// PTT keyed or not confirmed released by readback since the last key request.
    keyed: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}
// 0 idle,1 ordinary operation,2 reserved transition,3 reserved exchange,4 transmit hold.
const TRANSMIT_HOLD: u8 = 4;
struct Lease(Arc<AtomicU8>, Option<Arc<AtomicBool>>);
impl Drop for Lease {
    fn drop(&mut self) {
        if let Some(released) = &self.1 {
            self.0.store(2, Ordering::Release);
            if released.load(Ordering::Acquire) {
                let _ = self
                    .0
                    .compare_exchange(2, 0, Ordering::AcqRel, Ordering::Acquire);
            }
        } else {
            self.0.store(0, Ordering::Release);
        }
    }
}
/// A receive transition reserves the same actor across release/readback/start.
/// No queued operations or polling can interleave its typed exchanges.
pub struct TransitionLease {
    actor: Arc<Actor>,
    released: Arc<AtomicBool>,
}
impl TransitionLease {
    pub fn snapshot(&self) -> Result<Snapshot> {
        self.actor.snapshot()
    }
    pub fn execute(&self, request: Request) -> Result<Observation> {
        self.actor
            .execute_inner(request, Some(self.released.clone()))
    }
    /// A menu exchange (#44 AGC on mode selection) inside this reservation, so it
    /// completes before the transition releases the actor.
    pub fn setup(&self, command: SetupCommand, deadline: Instant) -> Result<SetupReply> {
        self.actor
            .setup_inner(command, deadline, Some(self.released.clone()))
    }
}
impl Drop for TransitionLease {
    fn drop(&mut self) {
        self.released.store(true, Ordering::Release);
        let _ = self
            .actor
            .lease
            .compare_exchange(2, 0, Ordering::AcqRel, Ordering::Acquire);
    }
}

impl Actor {
    /// The factory runs inside the I/O thread, so native handles never need an unsafe Send promise.
    pub fn begin<T, F>(
        configuration: Configuration,
        mut authority: Authority,
        catalogue: Catalogue,
        factory: F,
    ) -> Result<Self>
    where
        T: Transport + 'static,
        F: FnOnce(Instant, &AtomicBool) -> Result<T> + Send + 'static,
    {
        configuration.validate()?;
        authority.validate()?;
        if !catalogue.supports(&super::Operation::ReadFrequency) {
            return Err(Error::Unsupported);
        }
        let deadline = Instant::now() + Duration::from_secs(5);
        let snapshot = Arc::new(Mutex::new(Snapshot {
            publication: 0,
            closing_requested: false,
            state: State::Connecting,
            authority: authority.clone(),
            effective_baud: None,
            observation: Observation::default(),
            facts: super::Facts::default(),
            last_error: None,
        }));
        let lease = Arc::new(AtomicU8::new(1));
        let shutdown = Arc::new(AtomicBool::new(false));
        let current_cancel = Arc::new(Mutex::new(None::<Arc<AtomicBool>>));
        let (commands, receive) = mpsc::sync_channel::<Command>(1);
        let (ptt, ptt_receive) = mpsc::sync_channel::<PttCommand>(1);
        let (setup, setup_receive) = mpsc::sync_channel::<SetupRequest>(1);
        let keyed = Arc::new(AtomicBool::new(false));
        let (shared, busy, stop, current, worker_keyed) = (
            snapshot.clone(),
            lease.clone(),
            shutdown.clone(),
            current_cancel.clone(),
            keyed.clone(),
        );
        let worker = thread::Builder::new()
            .name("cat-io".into())
            .spawn(move || {
                let connected = (|| {
                    if stop.load(Ordering::Acquire) {
                        return Err(Error::Cancelled);
                    }
                    let transport = factory(deadline, &stop)?;
                    if let Some(identity) = transport.physical_identity() {
                        authority.resource_id = identity.to_owned();
                    }
                    Executor::connect_until(
                        transport,
                        configuration,
                        authority,
                        catalogue,
                        &stop,
                        deadline,
                    )
                })();
                let mut executor = match connected {
                    Ok(value) => value,
                    Err(error) => {
                        if let Ok(mut state) = shared.lock() {
                            state.state = if error == Error::FailedClose {
                                State::Closing
                            } else if stop.load(Ordering::Acquire) {
                                State::Closed
                            } else {
                                State::Unavailable
                            };
                            state.last_error = Some(error);
                            state.facts.stale();
                            let _ = state.publish();
                        }
                        busy.store(0, Ordering::Release);
                        return;
                    }
                };
                if executor.attach_snapshot(shared.clone()).is_err() {
                    let _ = executor.close();
                    busy.store(0, Ordering::Release);
                    return;
                }
                busy.store(0, Ordering::Release);
                let mut last_poll = Instant::now();
                while !stop.load(Ordering::Acquire) {
                    // Transmit-switch exchanges of the transmit hold come first; while the
                    // hold is held no ordinary operation or poll can start (lease 4).
                    if let Ok(command) = ptt_receive.try_recv() {
                        let result = if stop.load(Ordering::Acquire) {
                            Err(Error::Cancelled)
                        } else {
                            executor.set_ptt(command.on, command.deadline, &AtomicBool::new(false))
                        };
                        if !command.on && result.is_ok() {
                            worker_keyed.store(false, Ordering::Release);
                        }
                        let _ = command.response.try_send(result);
                        continue;
                    }
                    if let Ok(request) = setup_receive.try_recv() {
                        let _lease = Lease(busy.clone(), request.reservation);
                        let result = if stop.load(Ordering::Acquire) {
                            Err(Error::Cancelled)
                        } else {
                            executor.setup(request.command, request.deadline, &stop)
                        };
                        drop(_lease);
                        let _ = request.response.try_send(result);
                        continue;
                    }
                    match receive.recv_timeout(Duration::from_millis(5)) {
                        Ok(command) => {
                            let _lease = Lease(busy.clone(), command.reservation);
                            if let Ok(mut value) = current.lock() {
                                *value = Some(command.request.cancelled.clone());
                            }
                            let result = if stop.load(Ordering::Acquire) {
                                Err(Error::Cancelled)
                            } else {
                                executor.execute(command.request)
                            };
                            if let Ok(mut value) = current.lock() {
                                *value = None;
                            }
                            drop(_lease);
                            let _ = command.response.try_send(if stop.load(Ordering::Acquire) {
                                Err(Error::Cancelled)
                            } else {
                                result
                            });
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            if last_poll.elapsed() >= Duration::from_secs(1)
                                && busy
                                    .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
                                    .is_ok()
                            {
                                let _lease = Lease(busy.clone(), None);
                                last_poll = Instant::now();
                                let _ = executor
                                    .refresh(stop.clone(), last_poll + Duration::from_secs(5));
                            }
                        }
                    }
                }
                // Closing a connection whose transmit switch may be keyed first sends
                // exactly one off-only switch with readback (never a key).
                if worker_keyed.load(Ordering::Acquire)
                    && executor
                        .set_ptt(
                            false,
                            Instant::now() + Duration::from_millis(250),
                            &AtomicBool::new(false),
                        )
                        .is_ok()
                {
                    worker_keyed.store(false, Ordering::Release);
                }
                let _ = executor.close();
            })
            .map_err(|_| Error::Unavailable)?;
        Ok(Self {
            commands,
            snapshot,
            lease,
            shutdown,
            current_cancel,
            ptt,
            setup,
            keyed,
            thread: Some(worker),
        })
    }
    /// WstxTransmit::PttControl. Keys (`on`) or releases the transmit switch with
    /// readback through this single I/O owner. Keying first takes the transmit hold
    /// (lease 4), waiting until `deadline` for a running poll or operation to finish;
    /// the hold excludes every ordinary operation, transition and poll until a release
    /// is confirmed by readback. Release is admitted with or without the hold. No queue:
    /// one switch exchange at a time.
    pub fn ptt(&self, on: bool, deadline: Instant) -> Result<()> {
        self.ptt_abortable(on, deadline, &AtomicBool::new(false))
    }
    /// As `ptt`; while the switch frame is not yet sent, a set `abort` (priority halt)
    /// ends the wait with Busy and no bytes.
    pub fn ptt_abortable(&self, on: bool, deadline: Instant, abort: &AtomicBool) -> Result<()> {
        if on && self.shutdown.load(Ordering::Acquire) {
            return Err(Error::Unavailable);
        }
        if self.lease.load(Ordering::Acquire) != TRANSMIT_HOLD {
            loop {
                match self.lease.compare_exchange(
                    0,
                    TRANSMIT_HOLD,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                ) {
                    Ok(_) => break,
                    Err(TRANSMIT_HOLD) => break,
                    Err(_) if Instant::now() >= deadline || abort.load(Ordering::Acquire) => {
                        return Err(Error::Busy);
                    }
                    Err(_) => thread::sleep(Duration::from_millis(1)),
                }
            }
        }
        if on && abort.load(Ordering::Acquire) {
            if !self.keyed.load(Ordering::Acquire) {
                self.release_hold();
            }
            return Err(Error::Busy);
        }
        if on {
            self.keyed.store(true, Ordering::Release);
        }
        let (response, result) = mpsc::sync_channel(1);
        if let Err(error) = self.ptt.try_send(PttCommand {
            on,
            deadline,
            response,
        }) {
            if !self.keyed.load(Ordering::Acquire) {
                self.release_hold();
            }
            return Err(match error {
                TrySendError::Full(_) => Error::Busy,
                TrySendError::Disconnected(_) => Error::Unavailable,
            });
        }
        let outcome = loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            // The worker bounds the exchange by the same deadline; allow its reply.
            match result.recv_timeout(remaining.max(Duration::from_millis(50))) {
                Ok(value) => break value,
                Err(mpsc::RecvTimeoutError::Disconnected) => break Err(Error::Unavailable),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if Instant::now() >= deadline + Duration::from_secs(2) {
                        break Err(Error::Timeout);
                    }
                }
            }
        };
        if !on && outcome.is_ok() {
            self.release_hold();
        }
        outcome
    }
    /// #44 menu exchange (ID read, menu read, menu write with readback) through this
    /// single I/O owner. It takes the ordinary lease, waiting until deadline while an
    /// operation, transition, poll or transmit hold holds it (then Busy); no queue.
    pub fn setup(&self, command: SetupCommand, deadline: Instant) -> Result<SetupReply> {
        self.setup_inner(command, deadline, None)
    }
    fn setup_inner(
        &self,
        command: SetupCommand,
        deadline: Instant,
        reservation: Option<Arc<AtomicBool>>,
    ) -> Result<SetupReply> {
        if self.shutdown.load(Ordering::Acquire) {
            return Err(Error::Unavailable);
        }
        let (expected, occupied) = if reservation.is_some() {
            (2, 3)
        } else {
            (0, 1)
        };
        // The 1 s poll holds the lease briefly; wait for it (bounded by the deadline)
        // instead of refusing, as the transmit hold does.
        while self
            .lease
            .compare_exchange(expected, occupied, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            if Instant::now() >= deadline || self.shutdown.load(Ordering::Acquire) {
                return Err(Error::Busy);
            }
            thread::sleep(Duration::from_millis(1));
        }
        let (response, result) = mpsc::sync_channel(1);
        if let Err(error) = self.setup.try_send(SetupRequest {
            command,
            deadline,
            response,
            reservation,
        }) {
            self.lease.store(expected, Ordering::Release);
            return Err(match error {
                TrySendError::Full(_) => Error::Busy,
                TrySendError::Disconnected(_) => Error::Unavailable,
            });
        }
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            match result.recv_timeout(remaining.max(Duration::from_millis(50))) {
                Ok(value) => return value,
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err(Error::Unavailable),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if Instant::now() >= deadline + Duration::from_secs(2) {
                        return Err(Error::Timeout);
                    }
                }
            }
        }
    }
    /// True after a key request until a release is confirmed by readback.
    pub fn ptt_indeterminate(&self) -> bool {
        self.keyed.load(Ordering::Acquire)
    }
    fn release_hold(&self) {
        let _ = self
            .lease
            .compare_exchange(TRANSMIT_HOLD, 0, Ordering::AcqRel, Ordering::Acquire);
    }
    pub fn snapshot(&self) -> Result<Snapshot> {
        self.snapshot
            .lock()
            .map(|s| s.clone())
            .map_err(|_| Error::Unavailable)
    }
    pub fn execute(&self, request: Request) -> Result<Observation> {
        self.execute_inner(request, None)
    }
    pub fn reserve_transition(self: &Arc<Self>) -> Result<TransitionLease> {
        if self.shutdown.load(Ordering::Acquire) {
            return Err(Error::Unavailable);
        }
        self.lease
            .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| Error::Busy)?;
        Ok(TransitionLease {
            actor: self.clone(),
            released: Arc::new(AtomicBool::new(false)),
        })
    }
    fn execute_inner(
        &self,
        request: Request,
        reservation: Option<Arc<AtomicBool>>,
    ) -> Result<Observation> {
        if self.shutdown.load(Ordering::Acquire) {
            return Err(Error::Unavailable);
        }
        if request.cancelled.load(Ordering::Acquire) {
            return Err(Error::Cancelled);
        }
        if Instant::now() >= request.deadline {
            return Err(Error::Timeout);
        }
        let (expected, occupied) = if reservation.is_some() {
            (2, 3)
        } else {
            (0, 1)
        };
        self.lease
            .compare_exchange(expected, occupied, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| Error::Busy)?;
        let deadline = request.deadline;
        let cancel = request.cancelled.clone();
        let (response, result) = mpsc::sync_channel(1);
        match self.commands.try_send(Command {
            request,
            response,
            reservation: reservation.clone(),
        }) {
            Ok(()) => {}
            Err(error) => {
                self.lease.store(expected, Ordering::Release);
                return Err(match error {
                    TrySendError::Full(_) => Error::Busy,
                    TrySendError::Disconnected(_) => Error::Unavailable,
                });
            }
        }
        loop {
            if self.shutdown.load(Ordering::Acquire) || cancel.load(Ordering::Acquire) {
                cancel.store(true, Ordering::Release);
                return Err(Error::Cancelled);
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                cancel.store(true, Ordering::Release);
                return Err(Error::Timeout);
            }
            match result.recv_timeout(remaining.min(Duration::from_millis(50))) {
                Ok(value) => return value,
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err(Error::Unavailable),
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
        }
    }
    pub fn request_close(&self) {
        self.shutdown.store(true, Ordering::Release);
        if let Ok(cancel) = self.current_cancel.lock()
            && let Some(cancel) = cancel.as_ref()
        {
            cancel.store(true, Ordering::Release);
        }
        if let Ok(mut snapshot) = self.snapshot.lock() {
            let before = (
                snapshot.closing_requested,
                snapshot.state,
                snapshot.facts.clone(),
            );
            snapshot.closing_requested = true;
            snapshot.facts.stale();
            if snapshot.last_error == Some(Error::FailedClose) {
                snapshot.state = State::Closing;
            } else if self.thread.as_ref().is_some_and(JoinHandle::is_finished) {
                snapshot.state = State::Closed;
            } else {
                snapshot.state = State::Closing;
            }
            if before
                != (
                    snapshot.closing_requested,
                    snapshot.state,
                    snapshot.facts.clone(),
                )
            {
                let _ = snapshot.publish();
            }
        }
    }
    pub fn close_complete(&self) -> bool {
        self.snapshot().is_ok_and(|s| s.state == State::Closed)
    }
}
impl Drop for Actor {
    fn drop(&mut self) {
        self.request_close();
        if self.thread.as_ref().is_some_and(JoinHandle::is_finished)
            && let Some(worker) = self.thread.take()
        {
            let _ = worker.join();
        }
    }
}
