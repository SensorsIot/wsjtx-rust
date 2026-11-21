//! The radio connection of a station: its CAT owner, the lifecycle tick and the radio view.

use super::*;

impl Recording {
    pub(crate) fn radio_actor(&self) -> Option<Arc<wstx_rust::radio_control::actor::Actor>> {
        self.state.lock().unwrap().operating.radio.actor.clone()
    }
    pub(super) fn radio_reserve(
        &self,
        revision: u64,
    ) -> Result<(u64, Option<Arc<wstx_rust::radio_control::actor::Actor>>)> {
        self.refresh_radio_cache();
        let (generation, old) = {
            let mut s = self.state.lock().unwrap();
            if s.operating.profile_revision != revision {
                return Err("state_conflict");
            }
            if s.operating.active() || s.operating.radio.connecting {
                return Err("busy");
            }
            if s.operating.radio.actor.is_some()
                && s.operating
                    .radio
                    .cached
                    .as_ref()
                    .is_none_or(|a| a.state != wstx_rust::radio_control::State::Closed)
            {
                return Err("busy");
            }
            if s.operating.radio.generation == profile::MAX_REVISION {
                return Err("counter_exhausted");
            }
            let radio = &mut s.operating.radio;
            let old = radio.actor.take();
            radio.generation += 1;
            radio.connecting = true;
            radio.cached = None;
            radio.error = None;
            (radio.generation, old)
        };
        Ok((generation, old))
    }
    pub(crate) fn radio_connect(
        self: &Arc<Self>,
        configuration: wstx_rust::radio_control::Configuration,
        revision: u64,
    ) -> Result<Value> {
        use wstx_rust::radio_control::Authority;
        let (generation, old) = self.radio_reserve(revision)?;
        // Final Arc destruction invokes Actor::Drop and therefore belongs outside state locks.
        drop(old);
        let authority = Authority {
            profile_id: self.profile.clone(),
            boot_id: self.boot.clone(),
            profile_revision: revision,
            resource_id: format!("COM{}", configuration.port),
            connection_generation: generation,
        };
        let started = self.radio_begin(configuration, authority);
        let actor = match started {
            Ok(actor) => Arc::new(actor),
            Err(e) => {
                let mut s = self.state.lock().unwrap();
                if s.operating.radio.generation == generation {
                    s.operating.radio.connecting = false;
                    s.operating.radio.error = Some(selection::radio_error(e));
                }
                return Err(selection::radio_error(e));
            }
        };
        self.radio_install(generation, revision, actor)
    }
    fn radio_begin(
        &self,
        configuration: wstx_rust::radio_control::Configuration,
        authority: wstx_rust::radio_control::Authority,
    ) -> std::result::Result<wstx_rust::radio_control::actor::Actor, wstx_rust::radio_control::Error>
    {
        use wstx_rust::radio_control::{actor::Actor, catalogue::Catalogue};
        let Some(opener) = self.cat_opener.get().cloned() else {
            return Err(wstx_rust::radio_control::Error::Unavailable);
        };
        let native = configuration.clone();
        Catalogue::builtin().and_then(|catalogue| {
            Actor::begin(
                configuration,
                authority,
                catalogue,
                move |deadline, cancel| opener.open(&native, deadline, cancel),
            )
        })
    }
    /// One tick of the automatic read-only lifecycle. The caller holds the profile
    /// store and authority locks (lock order store -> authorization -> recording), so a
    /// committed revocation or configuration edit is observed before any new attempt.
    pub(crate) fn cat_maintain(self: &Arc<Self>, gate: &crate::cat_lifecycle::Gate, now: Instant) {
        use crate::cat_lifecycle::{Action, Gate, Observed};
        use wstx_rust::radio_control::{Error, State as Cat};
        let (actor, generation) = {
            let s = self.state.lock().unwrap();
            (
                s.operating.radio.actor.clone(),
                s.operating.radio.generation,
            )
        };
        let observed = match actor.as_ref().map(|a| a.snapshot()) {
            None => Observed::Absent,
            Some(Err(_)) => Observed::Closing,
            Some(Ok(v)) => match (v.state, v.last_error) {
                (_, Some(Error::FailedClose)) => Observed::FailedClose,
                (Cat::Connecting, _) => Observed::Connecting,
                (Cat::Ready, _) => Observed::Ready,
                (Cat::Unavailable, e) => Observed::FailedReleased(e.unwrap_or(Error::Unavailable)),
                (Cat::Closing, _) => Observed::Closing,
                (Cat::Closed, _) => Observed::Closed,
            },
        };
        let action = self.cat.lock().unwrap().step(gate, observed, now);
        match action {
            Action::None => {}
            Action::Close => {
                let _ = self.radio_disconnect(generation);
            }
            Action::Attempt => {
                let Gate::Eligible { key, configuration } = gate else {
                    return;
                };
                // The released previous actor is removed only if it is still current;
                // its final drop happens outside the state lock.
                let old = {
                    let mut s = self.state.lock().unwrap();
                    let radio = &mut s.operating.radio;
                    match (&radio.actor, &actor) {
                        (Some(a), Some(b)) if Arc::ptr_eq(a, b) => radio.actor.take(),
                        _ => None,
                    }
                };
                drop(old);
                drop(actor);
                match self.radio_connect(configuration.clone(), key.profile_revision) {
                    Ok(_) => {}
                    Err("busy" | "state_conflict") => self.cat.lock().unwrap().deferred(now),
                    Err(error) => self.cat.lock().unwrap().failed(error, now),
                }
            }
        }
        self.refresh_radio_cache();
        if observed == Observed::Ready
            && action == Action::None
            && let Gate::Eligible { key, .. } = gate
        {
            self.adopt_readback_selection(key.profile_revision);
        }
    }
    /// Current automatic CAT condition for the additive authorization status.
    pub(crate) fn cat_status(
        &self,
        gate: &crate::cat_lifecycle::Gate,
    ) -> (&'static str, Option<&'static str>, Option<u64>) {
        self.cat.lock().unwrap().status_for(gate)
    }
    pub(super) fn radio_install(
        &self,
        generation: u64,
        revision: u64,
        actor: Arc<wstx_rust::radio_control::actor::Actor>,
    ) -> Result<Value> {
        let installed = {
            let mut s = self.state.lock().unwrap();
            if s.operating.radio.generation == generation
                && s.operating.radio.connecting
                && s.operating.profile_revision == revision
            {
                s.operating.radio.actor = Some(actor.clone());
                s.operating.radio.connecting = false;
                true
            } else {
                // A profile edit ends only this still-owned reservation. A later
                // generation or explicit Disconnect must remain authoritative.
                if s.operating.radio.generation == generation && s.operating.radio.connecting {
                    s.operating.radio.connecting = false;
                    s.operating.radio.error = Some("state_conflict");
                }
                false
            }
        };
        if !installed {
            actor.request_close();
            return Err("state_conflict");
        }
        Ok(self.radio_view())
    }
    pub(crate) fn radio_disconnect(&self, generation: u64) -> Result<Value> {
        let actor = {
            let mut s = self.state.lock().unwrap();
            if generation != s.operating.radio.generation {
                return Err("state_conflict");
            }
            s.operating.radio.connecting = false;
            if s.operating.radio.actor.is_none() {
                s.operating.radio.error = None;
            }
            if let Some(o) = s
                .operating
                .operation
                .as_mut()
                .filter(|o| o.result == "pending")
            {
                o.cancelled.store(true, Ordering::Release);
                o.monitor_wanted = false;
                o.result = "failed";
                o.phase = "failed";
                o.error = Some("radio_unavailable");
            }
            s.operating.radio.actor.clone()
        };
        if let Some(actor) = actor {
            actor.request_close();
        }
        Ok(self.radio_view())
    }
    pub(crate) fn radio_execute(
        &self,
        generation: u64,
        operation: wstx_rust::radio_control::Operation,
    ) -> Result<Value> {
        let (actor, revision, at) = {
            let s = self.state.lock().unwrap();
            if s.operating.active() {
                return Err("busy");
            }
            if generation != s.operating.radio.generation {
                return Err("state_conflict");
            }
            (
                s.operating.radio.actor.clone().ok_or("radio_unavailable")?,
                s.operating.profile_revision,
                s.operating.boot_at,
            )
        };
        let snapshot = actor.snapshot().map_err(selection::radio_error)?;
        if snapshot.authority.profile_revision != revision {
            return Err("state_conflict");
        }
        let name = operation.key();
        let observation = actor
            .execute(wstx_rust::radio_control::Request {
                authority: snapshot.authority,
                request_id: profile::new_uuid().map_err(|_| "storage_unavailable")?,
                operation,
                deadline: Instant::now() + Duration::from_secs(5),
                cancelled: Arc::new(AtomicBool::new(false)),
            })
            .map_err(selection::radio_error)?;
        self.refresh_radio_cache();
        if self.state.lock().unwrap().operating.radio.generation != generation {
            return Err("state_conflict");
        }
        Ok(
            json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"connection_generation":generation,"operation":name,"observation":selection::observation(&observation,at)}),
        )
    }
    pub(crate) fn refresh_radio_cache(&self) {
        let (actor, generation) = {
            let s = self.state.lock().unwrap();
            (
                s.operating.radio.actor.clone(),
                s.operating.radio.generation,
            )
        };
        // Actor snapshot/drop must happen outside the Recording lock.
        let observed = actor.as_ref().and_then(|a| a.snapshot().ok());
        self.commit_radio_cache(actor, generation, observed);
    }
    pub(super) fn commit_radio_cache(
        &self,
        actor: Option<Arc<wstx_rust::radio_control::actor::Actor>>,
        generation: u64,
        observed: Option<wstx_rust::radio_control::Snapshot>,
    ) {
        let mut s = self.state.lock().unwrap();
        let same = match (&actor, &s.operating.radio.actor) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        };
        if same && let Some(observed) = observed {
            let radio = &mut s.operating.radio;
            if generation == radio.generation
                && observed.authority.connection_generation == generation
                && radio
                    .cached
                    .as_ref()
                    .is_none_or(|old| observed.publication() >= old.publication())
            {
                radio.cached = Some(observed);
            }
        }
    }
    pub(crate) fn radio_view(&self) -> Value {
        self.refresh_radio_cache();
        let s = self.state.lock().unwrap();
        let o = &s.operating;
        let r = &o.radio;
        let bound = selection::bound_snapshot(r.cached.as_ref(), o.profile_revision);
        let snapshot = bound.as_ref();
        json!({"v":1,"profile_id":self.profile,"boot_id":self.boot,"connection_generation":r.generation,
            "state":snapshot.map(|v|selection::state_name(v.state)).unwrap_or(if r.connecting {"connecting"}else if r.error.is_some(){"unavailable"}else{"closed"}),
            "error":snapshot.and_then(|v|v.last_error.map(selection::radio_error)).or(r.error),
            "device_id":snapshot.map(|v|v.authority.resource_id.as_str()),"effective_baud":snapshot.and_then(|v|v.effective_baud),
            "observation":snapshot.and_then(|v|v.observation.observed_at.map(|_|selection::observation(&v.observation,o.boot_at)))})
    }
}
