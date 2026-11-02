use super::reply;
use serde_json::{Value, json};

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

// Proves: FR-021; TC-021-005, TC-051-001. Level 2: isolated tests on Windows PC/CI.
#[test]
fn protocol_returns_specified_response_and_errors() {
    let status = reply(r#"{"v":1,"type":"station.get","id":12}"#);
    let build = status["data"]["build"]
        .as_str()
        .unwrap_or_default()
        .to_owned();
    assert!(
        build.len() == 16
            && build
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)),
        "#51 client build is 16 lower-case hex digits: {build}"
    );
    assert_eq!(
        status,
        json!({"v":1,"type":"station.status","id":12,"data":{"version":"0.1.0","radio":"unconfigured","build":build}})
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
    let next = super::arm_detail(&mut tick, tokio::time::Instant::now(), false);
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

// Proves: CL-054-01; TC-054-001 every retained Detailed row is sent once, in order, after a stall.
#[tokio::test(start_paused = true)]
async fn detailed_rows_after_a_stall_are_sent_in_order_with_bounded_catch_up() {
    use std::time::Duration;
    let row = |job: &str, sequence: u64| json!({"data":{"job_id":job,"sequence":sequence}});
    // Five rows arrived at once after a stall; the socket last sent row 10 of job a.
    let recent: std::collections::VecDeque<Value> = (11..=15).map(|n| row("a", n)).collect();
    let mut seen = Some((json!("a"), json!(10)));
    let mut sent = Vec::new();
    while let Some((frame, behind)) = super::detail_after(&recent, &seen) {
        sent.push((frame["data"]["sequence"].as_u64().unwrap(), behind));
        seen = Some((
            frame["data"]["job_id"].clone(),
            frame["data"]["sequence"].clone(),
        ));
    }
    assert_eq!(
        sent,
        vec![(11, true), (12, true), (13, true), (14, true), (15, false)]
    );
    // A new job's rows are all new; nothing is resent once caught up.
    let other: std::collections::VecDeque<Value> = (0..2).map(|n| row("b", n)).collect();
    assert_eq!(
        super::detail_after(&other, &seen).map(|(f, b)| (f["data"]["sequence"].clone(), b)),
        Some((json!(0), true))
    );
    assert!(super::detail_after(&recent, &Some((json!("a"), json!(15)))).is_none());
    // Catch-up spacing is 170 ms (at most 5.9 rows/s), the steady spacing 200 ms.
    let mut tick = tokio::time::interval(Duration::from_millis(200));
    let now = tokio::time::Instant::now();
    assert_eq!(
        super::arm_detail(&mut tick, now, true) - now,
        Duration::from_millis(170)
    );
    assert_eq!(
        super::arm_detail(&mut tick, now, false) - now,
        Duration::from_millis(200)
    );
}

// Proves: CL-054-01; TC-054-001 Thin sends keep a 2 s grid instead of drifting by the tick delay.
#[test]
fn thin_sends_are_anchored_to_the_previous_deadline() {
    use std::time::{Duration, Instant};
    let start = Instant::now();
    let period = Duration::from_secs(2);
    // Sends land up to 100 ms after each due time; the anchors stay on the 2 s grid.
    let mut anchor = start;
    for n in 1..=10u32 {
        let sent = start + period * n + Duration::from_millis(100);
        anchor = super::next_thin_anchor(anchor, period, sent);
        assert_eq!(anchor - start, period * n);
    }
    // After a pause of more than a period the grid restarts at the send.
    let late = anchor + Duration::from_secs(5);
    assert_eq!(super::next_thin_anchor(anchor, period, late), late);
}
