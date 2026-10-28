#![forbid(unsafe_code)]
//! The single CAT I/O owner. An admitted operation holds one lease; there is no backlog.
use super::{
    Authority, Configuration, Error, Observation, Request, Result, Snapshot, State,
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
pub struct Actor {
    commands: SyncSender<Command>,
    snapshot: Arc<Mutex<Snapshot>>,
    lease: Arc<AtomicU8>,
    shutdown: Arc<AtomicBool>,
    current_cancel: Arc<Mutex<Option<Arc<AtomicBool>>>>,
    thread: Option<JoinHandle<()>>,
}
// 0 idle,1 ordinary operation,2 reserved transition,3 reserved exchange.
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
        let (shared, busy, stop, current) = (
            snapshot.clone(),
            lease.clone(),
            shutdown.clone(),
            current_cancel.clone(),
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
                    match receive.recv_timeout(Duration::from_millis(20)) {
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
                let _ = executor.close();
            })
            .map_err(|_| Error::Unavailable)?;
        Ok(Self {
            commands,
            snapshot,
            lease,
            shutdown,
            current_cancel,
            thread: Some(worker),
        })
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
