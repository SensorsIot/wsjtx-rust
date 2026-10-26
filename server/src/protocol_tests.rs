use super::reply;
use serde_json::json;

// Proves: CL-006-03/04; TC-010-002 controlled transport readiness, independent of OS socket buffering.
#[test]
fn optional_readiness_skips_without_waiting_and_retains_at_most_one_frame() {
    use super::{Message, optional_flush, optional_write};
    use std::{
        convert::Infallible,
        pin::Pin,
        task::{Context, Poll},
    };
    struct Controlled {
        ready: bool,
        flush: bool,
        buffered: usize,
        starts: usize,
    }
    impl futures_sink::Sink<Message> for Controlled {
        type Error = Infallible;
        fn poll_ready(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
            if self.ready && self.buffered == 0 {
                Poll::Ready(Ok(()))
            } else {
                Poll::Pending
            }
        }
        fn start_send(mut self: Pin<&mut Self>, message: Message) -> Result<(), Self::Error> {
            assert_eq!(self.buffered, 0);
            assert!(message.into_data().len() <= 2048);
            self.buffered = 1;
            self.starts += 1;
            Ok(())
        }
        fn poll_flush(
            mut self: Pin<&mut Self>,
            _: &mut Context<'_>,
        ) -> Poll<Result<(), Self::Error>> {
            if self.flush {
                self.buffered = 0;
                Poll::Ready(Ok(()))
            } else {
                Poll::Pending
            }
        }
        fn poll_close(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
            Poll::Ready(Ok(()))
        }
    }
    let mut peer = Controlled {
        ready: false,
        flush: false,
        buffered: 0,
        starts: 0,
    };
    assert_eq!(
        optional_write(&mut peer, Message::Text("optional".into())).unwrap(),
        None
    );
    assert_eq!(peer.starts, 0);
    peer.ready = true;
    assert_eq!(
        optional_write(&mut peer, Message::Text("x".repeat(2049).into())).unwrap(),
        None
    );
    assert_eq!(peer.starts, 0);
    assert_eq!(
        optional_write(&mut peer, Message::Text("x".repeat(2048).into())).unwrap(),
        Some(false)
    );
    assert_eq!(peer.buffered, 1);
    for _ in 0..100 {
        assert!(!optional_flush(&mut peer).unwrap());
        assert_eq!(
            optional_write(&mut peer, Message::Text("replacement".into())).unwrap(),
            None
        );
    }
    assert_eq!(peer.starts, 1);
    assert_eq!(
        super::reply(r#"{"v":1,"type":"station.get","id":9}"#)["type"],
        "station.status"
    );
    peer.flush = true;
    assert!(optional_flush(&mut peer).unwrap());
    assert_eq!(peer.buffered, 0);
    assert_eq!(
        optional_write(&mut peer, Message::Text("latest".into())).unwrap(),
        Some(true)
    );
}

// Proves: FR-021; TC-021-005. Level 2: isolated tests on Windows PC/CI.
#[test]
fn protocol_returns_specified_response_and_errors() {
    assert_eq!(
        reply(r#"{"v":1,"type":"station.get","id":12}"#),
        json!({"v":1,"type":"station.status","id":12,"data":{"version":"0.1.0","radio":"unconfigured"}})
    );
    for (input, code) in [
        ("{", "invalid_json"),
        ("[]", "invalid_request"),
        (
            r#"{"v":2,"type":"station.get","id":1}"#,
            "unsupported_version",
        ),
        (r#"{"v":1,"type":"unknown","id":1}"#, "unknown_command"),
        (r#"{"v":1,"type":"station.get"}"#, "invalid_request"),
        (
            r#"{"v":1,"type":"station.get","id":"1"}"#,
            "invalid_request",
        ),
        (r#"{"v":1,"type":null,"id":1}"#, "invalid_request"),
        (
            r#"{"v":1,"type":"station.get","id":9007199254740992}"#,
            "invalid_request",
        ),
    ] {
        assert_eq!(reply(input)["data"]["code"], code, "{input}");
    }
}

// Proves: CL-006-03/04; TC-010-005 delayed tick cannot produce an early accepted successor.
#[tokio::test(start_paused = true)]
async fn detailed_late_tick_rearms_from_actual_acceptance() {
    use std::time::Duration;
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let origin = tokio::time::Instant::now();
    tick.tick().await;
    tokio::time::advance(Duration::from_millis(999)).await;
    tick.tick().await;
    let next = super::arm_detail(&mut tick, tokio::time::Instant::now());
    assert_eq!(next - origin, Duration::from_millis(1199));
    // An old Skip grid would tick again at1000ms, only1ms after the delayed tick.
    tokio::time::advance(Duration::from_millis(1)).await;
    assert!(
        tokio::time::timeout(Duration::from_millis(197), tick.tick())
            .await
            .is_err()
    );
    tick.tick().await;
    assert!(tokio::time::Instant::now() - origin >= Duration::from_millis(1199));
}
