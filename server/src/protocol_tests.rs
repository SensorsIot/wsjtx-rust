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
    // TC-010-008: run acceptance accounting through the same operation as the connection.
    let mut delivery = super::DetailDelivery::new(json!("current"), 5);
    let mut frame = super::recording::DetailedFrame {
        text: "x".repeat(2048),
        identity: json!("current"),
        sequence: 6,
    };
    peer.ready = false;
    peer.flush = false;
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), None);
    assert_eq!((delivery.cursor, delivery.tokens), (5, 1.0));
    peer.ready = true;
    frame.text.push('x');
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), None);
    assert_eq!((delivery.cursor, delivery.tokens), (5, 1.0));
    frame.text.pop();
    frame.identity = json!("obsolete");
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), None);
    frame.identity = json!("current");
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), Some(false));
    assert_eq!((delivery.cursor, delivery.tokens), (7, 0.0));
    assert_eq!(peer.buffered, 1);
    delivery.refill(delivery.updated + std::time::Duration::from_millis(400));
    frame.sequence = 7;
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), None);
    assert_eq!((delivery.cursor, delivery.tokens), (7, 2.0));
    peer.flush = true;
    assert!(optional_flush(&mut peer).unwrap());
    assert_eq!(delivery.write(&mut peer, &frame).unwrap(), Some(true));
    assert_eq!((delivery.cursor, delivery.tokens), (8, 1.0));
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

// Proves: CL-006-03/04; TC-010-008 fixed subscription phase after delayed wakes.
#[tokio::test(start_paused = true)]
async fn detailed_late_tick_keeps_subscription_phase() {
    use std::time::Duration;
    let origin = tokio::time::Instant::now();
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    tick.tick().await;
    tokio::time::advance(Duration::from_millis(999)).await;
    let next = super::arm_detail(&mut tick, origin);
    assert_eq!(next - origin, Duration::from_millis(1000));
    tick.tick().await;
    assert_eq!(
        tokio::time::Instant::now() - origin,
        Duration::from_millis(1000)
    );
    tokio::time::advance(Duration::from_millis(149)).await;
    assert_eq!(
        super::arm_detail(&mut tick, origin) - origin,
        Duration::from_millis(1200)
    );
}

// Proves: CL-006-03/04; TC-010-008 independent token arithmetic and acceptance-only state.
#[tokio::test(start_paused = true)]
async fn detailed_tokens_bound_catchup_without_charging_refusal_or_backwards_time() {
    use super::DetailDelivery;
    let now = tokio::time::Instant::now();
    let mut delivery = DetailDelivery::new(json!(["boot", "source", "job", 1]), 5);
    assert_eq!(delivery.tokens, 1.0);
    delivery.refill(now + std::time::Duration::from_millis(100));
    assert!((delivery.tokens - 1.5).abs() < 1e-9);
    // Selecting/refusing an optional write has no acceptance side effect.
    assert_eq!(delivery.cursor, 5);
    delivery.refill(now);
    assert!((delivery.tokens - 1.5).abs() < 1e-9);
    delivery.accepted(6);
    assert_eq!(delivery.cursor, 7);
    assert!((delivery.tokens - 0.5).abs() < 1e-9);
    assert_eq!(
        delivery.ready_at(delivery.updated) - delivery.updated,
        std::time::Duration::from_millis(100)
    );
    delivery.refill(now + std::time::Duration::from_secs(10));
    assert_eq!(delivery.tokens, 2.0);
    delivery.accepted(7);
    delivery.accepted(8);
    assert_eq!(delivery.tokens, 0.0);
    assert_eq!(delivery.cursor, 9);
}
