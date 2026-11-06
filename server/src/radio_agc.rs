#![forbid(unsafe_code)]
//! #44 CL-044-10/11 the station-managed radio AGC. The profile's AGC is applied through
//! the station's CAT owner when a connection becomes ready and on each FT8/FT4 mode
//! selection, by one `EnsureAgc` exchange: read 16 12, write only when it differs, read
//! back (CL-044-09). Nothing is sent while the transmitter is armed or keyed; the
//! executor also refuses a write unless the radio reports RX. The outcome is pushed to
//! the station's WebSocket peers as `radio.agc` on change (no polling).
use crate::recording::Recording;
use serde_json::{Value, json};
use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use wstx_rust::radio_control::{self as cat, SetupCommand, SetupReply, setup::Agc};

/// Bound of one AGC exchange (read, RX check, write, readback).
const EXCHANGE: Duration = Duration::from_secs(3);
/// A busy CAT owner (lease held, radio reports TX) is tried again after this delay.
pub(crate) const RETRY: Duration = Duration::from_secs(2);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Status {
    pub generation: u64,
    pub target: Agc,
    /// The AGC the radio reported last (read, or read back after a write).
    pub value: Option<Agc>,
    /// unchanged, written, or the radio error code.
    pub result: &'static str,
    /// connect or selection.
    pub trigger: &'static str,
}
#[derive(Default)]
struct Inner {
    target: Option<Agc>,
    /// The connection generation whose AGC is applied (or failed for good).
    applied: u64,
    running: bool,
    retry_at: Option<Instant>,
    status: Option<Status>,
    revision: u64,
}
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
}
impl Owner {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    pub(crate) fn revision(&self) -> u64 {
        self.lock().revision
    }
    #[cfg(test)]
    pub(crate) fn status(&self) -> Option<Status> {
        self.lock().status
    }
    pub(crate) fn target(&self) -> Option<Agc> {
        self.lock().target
    }
    fn set_target(&self, target: Option<Agc>) {
        let mut i = self.lock();
        if i.target != target {
            i.target = target;
            // A new target is applied again on the current connection.
            i.applied = 0;
            i.retry_at = None;
            if target.is_none() {
                i.status = None;
            }
            i.revision += 1;
        }
    }
    fn record(
        &self,
        generation: u64,
        target: Agc,
        outcome: cat::Result<SetupReply>,
        trigger: &'static str,
    ) {
        let mut i = self.lock();
        let (value, result) = match outcome {
            Ok(SetupReply::Agc { value, written }) => {
                (Some(value), if written { "written" } else { "unchanged" })
            }
            Ok(_) => (None, "radio_unavailable"),
            Err(error) => (
                i.status
                    .filter(|s| s.generation == generation)
                    .and_then(|s| s.value),
                crate::selection::radio_error(error),
            ),
        };
        if result == "busy" {
            i.retry_at = Some(Instant::now() + RETRY);
        } else if i.target == Some(target) {
            i.applied = generation;
            i.retry_at = None;
        }
        let status = Status {
            generation,
            target,
            value,
            result,
            trigger,
        };
        if i.status != Some(status) {
            i.status = Some(status);
            i.revision += 1;
        }
    }
}

fn transmitter_quiet(recording: &Recording) -> bool {
    recording.transmit.get().is_none_or(|t| {
        let view = t.service.view();
        view.arm_state == wstx_rust::transmit::service::ArmState::Disarmed
            && !view.tune
            && !view.transmitting
    })
}

/// One tick under the CAT lifecycle (`cat_tick`): `target` is the saved profile's AGC
/// (None: the radio has no managed settings). Applies it once per ready connection.
pub(crate) fn tick(recording: &Arc<Recording>, target: Option<Agc>, now: Instant) {
    recording.agc.set_target(target);
    let Some(target) = target else {
        return;
    };
    let Some(actor) = recording.radio_actor() else {
        return;
    };
    let Ok(snapshot) = actor.snapshot() else {
        return;
    };
    let generation = snapshot.authority.connection_generation;
    if snapshot.state != cat::State::Ready {
        return;
    }
    {
        let mut i = recording.agc.lock();
        if i.applied == generation || i.running || i.retry_at.is_some_and(|t| now < t) {
            return;
        }
        if !transmitter_quiet(recording) {
            return;
        }
        i.running = true;
    }
    let owner = recording.clone();
    let spawned = std::thread::Builder::new()
        .name("cat-agc".into())
        .spawn(move || {
            let outcome = actor.setup(SetupCommand::EnsureAgc(target), Instant::now() + EXCHANGE);
            owner.agc.lock().running = false;
            owner.agc.record(generation, target, outcome, "connect");
            owner.refresh_radio_cache();
        });
    if spawned.is_err() {
        recording.agc.lock().running = false;
    }
}

/// CL-044-10 on an FT8/FT4 mode selection: inside the selection's CAT reservation, after
/// its receive setup and before receive restarts. An AGC failure is reported, never a
/// failure of the selection.
pub(crate) fn on_selection(
    recording: &Recording,
    lease: &cat::actor::TransitionLease,
    generation: u64,
) {
    let Some(target) = recording.agc.target() else {
        return;
    };
    if !transmitter_quiet(recording) {
        return;
    }
    let outcome = lease.setup(SetupCommand::EnsureAgc(target), Instant::now() + EXCHANGE);
    recording
        .agc
        .record(generation, target, outcome, "selection");
}

/// The `radio.agc` event of the current state.
pub(crate) fn event(recording: &Recording) -> (u64, String) {
    let (revision, target, status) = {
        let i = recording.agc.lock();
        (i.revision, i.target, i.status)
    };
    let name = |a: Option<Agc>| a.map_or(Value::Null, |a| json!(a.name()));
    let data = json!({"profile_id":recording.profile,"boot_id":recording.boot,
        "target":name(target),
        "connection_generation":status.map(|s|s.generation),
        "value":name(status.and_then(|s|s.value)),
        "result":status.map(|s|s.result),
        "trigger":status.map(|s|s.trigger)});
    (
        revision,
        json!({"v":1,"type":"radio.agc","data":data}).to_string(),
    )
}

#[cfg(test)]
#[path = "radio_agc_tests.rs"]
mod tests;
