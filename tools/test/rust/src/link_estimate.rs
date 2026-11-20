//! The link byte log's estimate oracle of the link log tests.

/// WstxListener::LinkTrafficLog estimate, as the contract
/// states it: t = 29 on TLS, 0 on plaintext; each message of b bytes takes
/// w = b + t x ceil(b / 16384) wire bytes and ceil(w / 512) segments, the rest of the bytes
/// ceil(r / 512); estimate = bytes + 80 x S(this direction) + 80 x S(other direction).
pub fn estimate(
    bytes: u64,
    messages: &[(String, u64)],
    other_bytes: u64,
    other: &[(String, u64)],
    tls: bool,
) -> u64 {
    let t = if tls { 29 } else { 0 };
    let segments = |bytes: u64, messages: &[(String, u64)]| {
        let (mut wire, mut segments) = (0, 0);
        for (_, b) in messages {
            let w = b + t * b.div_ceil(16384);
            wire += w;
            segments += w.div_ceil(512);
        }
        segments + bytes.saturating_sub(wire).div_ceil(512)
    };
    bytes + 80 * segments(bytes, messages) + 80 * segments(other_bytes, other)
}

// The oracle above reproduces the contract's worked example (TLS, one FT8 period, one Thin
// browser): 1995 and 1065 bytes.
#[test]
fn estimate_oracle_reproduces_the_worked_example() {
    let mut to = vec![("ws station.tick".to_owned(), 228); 3];
    to.extend(vec![("ws heartbeat".to_owned(), 28); 3]);
    to.extend(vec![("ws ping".to_owned(), 2); 3]);
    let from = vec![("ws pong".to_owned(), 6); 3];
    assert_eq!(estimate(1035, &to, 105, &from, true), 1995);
    assert_eq!(estimate(105, &from, 1035, &to, true), 1065);
}
