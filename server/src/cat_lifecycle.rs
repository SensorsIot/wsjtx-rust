#![forbid(unsafe_code)]
//! CL-022-03/04 automatic read-only CAT lifecycle: one pure policy per station.
//! It decides only; the station owner (Recording) performs the single attempt or
//! close through the existing typed actor. Time is injected monotonic time.
use std::time::{Duration, Instant};
use wstx_rust::radio_control as cat;

/// Precondition result computed under the profile store and authority locks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Gate {
    Disabled,
    Unauthorized,
    CommissioningRequired,
    /// Commissioned, but the saved endpoint is not a supported CAT configuration.
    InvalidConfiguration,
    Eligible {
        key: Key,
        configuration: cat::Configuration,
    },
}
/// Identity of one eligible configuration. Any change cancels and restarts.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Key {
    pub radio_id: String,
    pub safety_revision: u64,
    pub profile_revision: u64,
    pub endpoint: String,
}
/// Current actor observation, read outside the station lock.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Observed {
    /// No installed actor (never attempted, or the previous one was removed).
    Absent,
    Connecting,
    Ready,
    /// The attempt or connection failed and its transport close succeeded.
    FailedReleased(cat::Error),
    /// Close requested and not yet acknowledged.
    Closing,
    Closed,
    /// Transport close failed: the resource stays owned.
    FailedClose,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Action {
    None,
    /// Remove any released actor and start exactly one new read-only attempt.
    Attempt,
    /// Cancel the current attempt/connection through the existing release rules.
    Close,
}
pub(crate) const DELAYS: [u64; 4] = [1, 2, 4, 8];

pub(crate) struct Lifecycle {
    key: Option<Key>,
    failures: usize,
    next_at: Option<Instant>,
    quarantined: bool,
    /// Mapped error code of the last failed attempt.
    last_error: Option<&'static str>,
    gate: Gate,
    observed: Observed,
    now: Option<Instant>,
}
impl Lifecycle {
    pub(crate) fn new() -> Self {
        Self {
            key: None,
            failures: 0,
            next_at: None,
            quarantined: false,
            last_error: None,
            gate: Gate::Unauthorized,
            observed: Observed::Absent,
            now: None,
        }
    }
    pub(crate) fn step(&mut self, gate: &Gate, observed: Observed, now: Instant) -> Action {
        self.gate = gate.clone();
        self.observed = observed;
        self.now = Some(now);
        if observed == Observed::FailedClose {
            // No timed reopen: the failed resource stays owned until process restart.
            self.quarantined = true;
            self.last_error = Some("radio_failed_close");
            self.next_at = None;
        }
        let live = matches!(
            observed,
            Observed::Connecting | Observed::Ready | Observed::FailedReleased(_)
        );
        let Gate::Eligible { key, .. } = gate else {
            self.key = None;
            self.failures = 0;
            self.next_at = None;
            return if live { Action::Close } else { Action::None };
        };
        if self.key.as_ref() != Some(key) {
            // Startup, enable, new valid configuration or identity change: one
            // immediate attempt, but only after the previous owner is released.
            self.key = Some(key.clone());
            self.failures = 0;
            self.last_error = None;
            self.next_at = Some(now);
            if live {
                return Action::Close;
            }
        }
        if self.quarantined {
            return Action::None;
        }
        match observed {
            Observed::Connecting | Observed::Closing | Observed::FailedClose => Action::None,
            Observed::Ready => {
                // Only actual fresh readback (the connection probe or poll) resets.
                self.failures = 0;
                self.next_at = None;
                self.last_error = None;
                Action::None
            }
            Observed::FailedReleased(_) | Observed::Closed | Observed::Absent => {
                if let Observed::FailedReleased(error) = observed {
                    self.last_error = Some(crate::selection::radio_error(error));
                }
                let due = *self.next_at.get_or_insert_with(|| {
                    let delay = DELAYS[self.failures.min(DELAYS.len() - 1)];
                    self.failures += 1;
                    now + Duration::from_secs(delay)
                });
                if now >= due {
                    self.next_at = None;
                    Action::Attempt
                } else {
                    Action::None
                }
            }
        }
    }
    /// An attempt could not start (for example another owner holds the lease):
    /// the same due time is retried on the next tick; it is not a failure.
    pub(crate) fn deferred(&mut self, now: Instant) {
        self.next_at.get_or_insert(now);
    }
    /// An attempt failed before any actor existed (for example Actor::begin refused):
    /// it is a failed released attempt with this mapped reason.
    pub(crate) fn failed(&mut self, error: &'static str, now: Instant) {
        self.last_error = Some(error);
        let delay = DELAYS[self.failures.min(DELAYS.len() - 1)];
        self.failures += 1;
        self.next_at = Some(now + Duration::from_secs(delay));
        self.observed = Observed::Absent;
        self.now = Some(now);
    }
    /// Status against the freshly computed gate: an eligible configuration the policy
    /// has not yet observed is only waiting, never the previous key's ready/retry.
    pub(crate) fn status_for(
        &self,
        gate: &Gate,
    ) -> (&'static str, Option<&'static str>, Option<u64>) {
        if let Gate::Eligible { key, .. } = gate
            && self.key.as_ref() != Some(key)
        {
            return ("waitingForDevice", None, None);
        }
        self.status()
    }
    /// Condition, mapped error and retry delay for the additive status object.
    pub(crate) fn status(&self) -> (&'static str, Option<&'static str>, Option<u64>) {
        let error = self.last_error;
        match &self.gate {
            Gate::Disabled => return ("disabled", None, None),
            Gate::Unauthorized => return ("unauthorized", None, None),
            Gate::CommissioningRequired => return ("commissioningRequired", None, None),
            Gate::InvalidConfiguration => {
                return ("waitingForDevice", Some("invalid_request"), None);
            }
            Gate::Eligible { .. } => {}
        }
        if self.quarantined {
            return ("quarantined", Some("radio_failed_close"), None);
        }
        match self.observed {
            Observed::Ready => ("ready", None, None),
            Observed::Connecting => ("connecting", error, None),
            Observed::Closing => ("closing", error, None),
            Observed::FailedClose => ("quarantined", Some("radio_failed_close"), None),
            _ => match (self.next_at, self.now) {
                (Some(due), Some(now)) if due > now && self.failures > 0 => (
                    "retryWaiting",
                    error,
                    Some((due - now).as_millis().min(8000) as u64),
                ),
                _ => ("waitingForDevice", error, None),
            },
        }
    }
}
