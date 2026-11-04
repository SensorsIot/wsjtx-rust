#![forbid(unsafe_code)]
//! Ports the Rust tests hand to the node tests they start (#8): never one that Chromium
//! refuses (ERR_UNSAFE_PORT) or Node's fetch refuses ("bad port"). The one list is
//! tests/blocked-ports.json, which tests/support.cjs reads as well.
use std::sync::OnceLock;

pub(crate) fn blocked(port: u16) -> bool {
    static PORTS: OnceLock<Vec<u16>> = OnceLock::new();
    PORTS
        .get_or_init(|| {
            serde_json::from_str(include_str!("../../tests/blocked-ports.json")).unwrap()
        })
        .contains(&port)
}

/// Binds with `bind` until the bound port (`port`) is not blocked, dropping each blocked
/// binding; panics after 64 attempts.
pub(crate) fn first_allowed<L>(mut bind: impl FnMut() -> L, port: impl Fn(&L) -> u16) -> L {
    for _ in 0..64 {
        let bound = bind();
        if !blocked(port(&bound)) {
            return bound;
        }
    }
    panic!("no port that Chromium and fetch accept after 64 attempts");
}

/// A loopback listener on an OS-chosen port that Chromium and fetch accept.
#[cfg(not(debug_assertions))]
pub(crate) fn browser_listener() -> tokio::net::TcpListener {
    let listener = first_allowed(
        || std::net::TcpListener::bind("127.0.0.1:0").unwrap(),
        |l| l.local_addr().unwrap().port(),
    );
    listener.set_nonblocking(true).unwrap();
    tokio::net::TcpListener::from_std(listener).unwrap()
}

// Test-tool oracle: hand-picked ports of the Fetch standard's bad-port list and of
// Chromium's kRestrictedPorts; a binder that offers blocked ports first.
#[test]
fn first_allowed_skips_ports_chromium_or_fetch_refuse() {
    for port in [0, 1, 25, 4190, 6000, 6679, 6697, 10080] {
        assert!(blocked(port), "{port}");
    }
    for port in [80, 443, 1024, 8080, 40000] {
        assert!(!blocked(port), "{port}");
    }
    let offered = [4190, 6679, 10080, 6000, 40000];
    let mut calls = 0;
    let chosen = first_allowed(
        || {
            calls += 1;
            offered[calls - 1]
        },
        |p| *p,
    );
    assert_eq!((chosen, calls), (40000, 5));
}

#[test]
#[should_panic(expected = "no port that Chromium and fetch accept")]
fn first_allowed_refuses_when_only_blocked_ports_are_offered() {
    first_allowed(|| 4190u16, |p| *p);
}
