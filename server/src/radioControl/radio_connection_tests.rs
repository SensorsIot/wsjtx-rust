use super::*;

#[test]
fn selection_radio_cache_old_ready_cannot_overwrite_closed() {
    use wstx_rust::radio_control::State;
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let old = actor.snapshot().unwrap();
    assert_eq!(old.state, State::Ready);
    actor.request_close();
    let deadline = Instant::now() + Duration::from_secs(2);
    while !actor.close_complete() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert!(actor.close_complete());
    r.refresh_radio_cache();
    r.commit_radio_cache(Some(actor), 1, Some(old));
    assert_eq!(
        r.state
            .lock()
            .unwrap()
            .operating
            .radio
            .cached
            .as_ref()
            .unwrap()
            .state,
        State::Closed,
        "a delayed Ready capture must not resurrect a closed actor"
    );
}

#[test]
fn selection_radio_cache_reordered_capture_cannot_erase_mode_query() {
    use wstx_rust::radio_control::{Operation, Request};
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let old = actor.snapshot().unwrap();
    assert!(!old.facts.mode.confirmed);
    actor
        .execute(Request {
            authority: old.authority.clone(),
            request_id: "cache-mode".into(),
            operation: Operation::ReadMode,
            deadline: Instant::now() + Duration::from_secs(2),
            cancelled: Arc::new(AtomicBool::new(false)),
        })
        .unwrap();
    r.refresh_radio_cache();
    assert!(
        r.state
            .lock()
            .unwrap()
            .operating
            .radio
            .cached
            .as_ref()
            .unwrap()
            .facts
            .mode
            .confirmed
    );
    r.commit_radio_cache(Some(actor.clone()), 1, Some(old));
    assert!(
        r.state
            .lock()
            .unwrap()
            .operating
            .radio
            .cached
            .as_ref()
            .unwrap()
            .facts
            .mode
            .confirmed,
        "a delayed older capture must not erase an independently observed mode query"
    );
    actor.request_close();
}

#[test]
fn selection_radio_cache_unversioned_failure_cannot_clear_current_facts() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    r.commit_radio_cache(Some(actor.clone()), 1, None);
    assert!(
        r.state.lock().unwrap().operating.radio.cached.is_some(),
        "an unversioned failed observation cannot clear a newer published cache"
    );
    actor.request_close();
}

#[test]
fn recording_without_cat_port_opens_no_line() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    assert_eq!(
        r.radio_connect(
            wstx_rust::radio_control::Configuration::parse("COM3").unwrap(),
            0
        )
        .err(),
        Some("radio_unavailable")
    );
    let view = r.radio_view();
    assert_eq!(view["state"], "unavailable");
    assert_eq!(view["error"], "radio_unavailable");
    assert!(r.radio_actor().is_none(), "no CAT owner, so no serial open");
}

#[test]
fn review_connect_profile_edit_before_install_releases_own_reservation() {
    let fixture = Fixture::new();
    let r = fixture.recording();
    let (generation, old) = r.radio_reserve(0).unwrap();
    drop(old);
    let (actor, rig) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.profile_changed(1); // deterministic reservation -> successful-save invalidation -> install
    assert_eq!(
        r.radio_install(generation, 0, actor.clone()),
        Err("state_conflict")
    );
    let deadline = Instant::now() + Duration::from_secs(2);
    while !rig.lock().unwrap().closed && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(1));
    }
    assert!(
        rig.lock().unwrap().closed,
        "obsolete physical actor closes outside Recording lock"
    );
    assert!(
        !r.state.lock().unwrap().operating.radio.connecting,
        "a profile edit before install must terminate this attempt's connecting reservation"
    );
    assert!(r.radio_actor().is_none());
    let (next, old) = r
        .radio_reserve(1)
        .expect("new current-profile Connect is recoverable");
    drop(old);
    assert_eq!(next, generation + 1);
    r.radio_disconnect(next).unwrap();
}

#[test]
fn review_obsolete_connect_cannot_clear_newer_or_disconnected_reservation() {
    for newer in [false, true] {
        let fixture = Fixture::new();
        let r = fixture.recording();
        let (generation, old) = r.radio_reserve(0).unwrap();
        drop(old);
        let (actor, rig) =
            crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
        r.radio_disconnect(generation).unwrap();
        let expected = if newer {
            r.profile_changed(1);
            let (next, old) = r.radio_reserve(1).unwrap();
            drop(old);
            next
        } else {
            generation
        };
        assert_eq!(
            r.radio_install(generation, 0, actor.clone()),
            Err("state_conflict")
        );
        {
            let s = r.state.lock().unwrap();
            assert_eq!(s.operating.radio.generation, expected);
            assert_eq!(s.operating.radio.connecting, newer);
            assert_eq!(s.operating.radio.error, None);
            assert!(s.operating.radio.actor.is_none());
        }
        let deadline = Instant::now() + Duration::from_secs(2);
        while !rig.lock().unwrap().closed && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(rig.lock().unwrap().closed);
        if newer {
            r.radio_disconnect(expected).unwrap();
        }
    }
}
