#![forbid(unsafe_code)]
// Proves: CL-040-01, CL-040-02, CL-040-03, CL-040-04, CL-040-06, TC-012-001, TC-012-002, TC-012-003,
// TC-012-004, TC-012-006.
// The actual router, UDP owner, contact engine and #9 transmit
// owner on the recording hardware double (no audio, PTT or radio), hand-authored rows
// packed with the real codec and loopback UDP peers on ephemeral ports (never 2237). The
// datagrams are read back with the independent big-endian reader below, not the encoder.
use super::*;
use crate::contact_http_tests::{Fixture, fixture, now_ms, period_text, record};
use axum::body::Body;
use std::sync::atomic::Ordering;
use tower::ServiceExt;
use wstx_rust::transmit::service::DisarmCause;

fn peer() -> UdpSocket {
    let s = UdpSocket::bind("127.0.0.1:0").unwrap();
    s.set_read_timeout(Some(Duration::from_millis(150)))
        .unwrap();
    s
}
fn drain(p: &UdpSocket) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    let mut b = [0u8; 8192];
    while let Ok((n, _)) = p.recv_from(&mut b) {
        out.push(b[..n].to_vec());
    }
    out
}
/// Independent QDataStream reader of the received datagrams.
struct R<'a>(&'a [u8], usize);
impl R<'_> {
    fn take(&mut self, n: usize) -> &[u8] {
        let s = &self.0[self.1..self.1 + n];
        self.1 += n;
        s
    }
    fn u8(&mut self) -> u8 {
        self.take(1)[0]
    }
    fn u32(&mut self) -> u32 {
        u32::from_be_bytes(self.take(4).try_into().unwrap())
    }
    fn i32(&mut self) -> i32 {
        i32::from_be_bytes(self.take(4).try_into().unwrap())
    }
    fn u64(&mut self) -> u64 {
        u64::from_be_bytes(self.take(8).try_into().unwrap())
    }
    fn i64(&mut self) -> i64 {
        i64::from_be_bytes(self.take(8).try_into().unwrap())
    }
    fn f64(&mut self) -> f64 {
        f64::from_be_bytes(self.take(8).try_into().unwrap())
    }
    fn s(&mut self) -> String {
        let n = self.u32() as usize;
        String::from_utf8(self.take(n).to_vec()).unwrap()
    }
    fn end(&self) -> bool {
        self.1 == self.0.len()
    }
}
/// (schema, type, id, reader at the first field).
fn head(b: &[u8]) -> (u32, u32, String, R<'_>) {
    let mut r = R(b, 0);
    assert_eq!(r.u32(), 0xADBC_CBDA);
    let schema = r.u32();
    let kind = r.u32();
    let id = r.s();
    (schema, kind, id, r)
}
fn kinds(list: &[Vec<u8>]) -> Vec<u32> {
    list.iter().map(|b| head(b).1).collect()
}
/// Decode fields (new, time, snr, dt, df, mode, message).
fn decode_fields(b: &[u8]) -> (bool, u32, i32, f64, u32, String, String) {
    let (_, kind, _, mut r) = head(b);
    assert_eq!(kind, 2);
    let v = (
        r.u8() == 1,
        r.u32(),
        r.i32(),
        r.f64(),
        r.u32(),
        r.s(),
        r.s(),
    );
    assert_eq!((r.u8(), r.u8()), (0, 0), "low confidence, off air");
    assert!(r.end());
    v
}
/// Status fields by name.
fn status_fields(b: &[u8]) -> Value {
    let (_, kind, _, mut r) = head(b);
    assert_eq!(kind, 1);
    let v = json!({"dial":r.u64(),"mode":r.s(),"dx_call":r.s(),"report":r.s(),"tx_mode":r.s(),
        "tx_enabled":r.u8(),"transmitting":r.u8(),"decoding":r.u8(),"rx_df":r.u32(),"tx_df":r.u32(),
        "de_call":r.s(),"de_grid":r.s(),"dx_grid":r.s(),"watchdog":r.u8(),"sub_mode":r.s(),"fast":r.u8(),
        "special":r.u8(),"tolerance":r.u32(),"period":r.u32(),"configuration":r.s(),"tx_message":r.s()});
    assert!(r.end());
    v
}
fn target_json(address: SocketAddr, messages: &[&str], accept: bool) -> Value {
    json!({"address":address.to_string(),"enabled":true,"multicast_ttl":1,"multicast_interface":null,
        "messages":messages,"accept_commands":accept})
}
/// Writes udp.json before the owner opens, so no default target is ever activated.
fn install(f: &Fixture, targets: Vec<Value>) -> Arc<Owner> {
    let doc = json!({"schema_version":1,"profile_id":f.id,"revision":0,"instance_name":"WSTX-Rust","targets":targets});
    std::fs::write(f.dir.join(FILE_NAME), serde_json::to_vec(&doc).unwrap()).unwrap();
    let owner = Owner::open(&f.state, false);
    assert!(f.state.recording.udp.set(owner.clone()).is_ok());
    owner
}
async fn call(f: &Fixture, method: &str, path: &str, body: Option<Vec<u8>>) -> (StatusCode, Value) {
    call_with(f, method, path, body, "application/json").await
}
async fn call_with(
    f: &Fixture,
    method: &str,
    path: &str,
    body: Option<Vec<u8>>,
    media: &str,
) -> (StatusCode, Value) {
    let mut request = axum::http::Request::builder()
        .method(method)
        .uri(path)
        .header(header::ORIGIN, &f.origin);
    let request = match body {
        Some(b) => {
            request = request.header(header::CONTENT_TYPE, media);
            request.body(Body::from(b))
        }
        None => request.body(Body::empty()),
    }
    .unwrap();
    let response = f.router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 1 << 20)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
fn operate(f: &Fixture, action: &str, extra: Value, granted: bool) {
    let (revision, _, _) = f.contact().facts();
    let mut body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "contact_revision":revision,"action":action});
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    f.contact()
        .operate(&f.state, body, granted)
        .unwrap_or_else(|e| panic!("{action}: {e:?}"));
}
fn arm_state(f: &Fixture) -> ArmState {
    f.state
        .recording
        .transmit
        .get()
        .unwrap()
        .service
        .view()
        .arm_state
}
/// Puts the bench 1 s into an even FT8 period: the published row's parity (12:34:30 is
/// even), so a contact replying to it transmits odd, 14 s away; nothing armed here
/// reaches its own period.
fn early_in_period(f: &Fixture) {
    let now = now_ms();
    f.bench
        .offset
        .store(30_000 - now.rem_euclid(30_000) + 1_000, Ordering::SeqCst);
}
fn header(kind: u32, schema: u32, id: &str) -> Vec<u8> {
    let mut b = Vec::new();
    b.extend_from_slice(&0xADBC_CBDAu32.to_be_bytes());
    b.extend_from_slice(&schema.to_be_bytes());
    b.extend_from_slice(&kind.to_be_bytes());
    put_s(&mut b, id);
    b
}
fn put_s(b: &mut Vec<u8>, s: &str) {
    b.extend_from_slice(&(s.len() as u32).to_be_bytes());
    b.extend_from_slice(s.as_bytes());
}
fn reply(time_ms: u32, snr: i32, df: u32, message: &str) -> Vec<u8> {
    let mut b = header(4, 2, "WSTX-Rust");
    b.extend_from_slice(&time_ms.to_be_bytes());
    b.extend_from_slice(&snr.to_be_bytes());
    b.extend_from_slice(&f64::from(0.1f32).to_be_bytes());
    b.extend_from_slice(&df.to_be_bytes());
    put_s(&mut b, "~");
    put_s(&mut b, message);
    b.push(0);
    b.push(0);
    b
}
fn free_text(text: &str) -> Vec<u8> {
    let mut b = header(9, 2, "WSTX-Rust");
    put_s(&mut b, text);
    b.push(1);
    b
}
fn highlight(call: &str, bg: Option<(u8, u8, u8)>) -> Vec<u8> {
    let mut b = header(13, 2, "WSTX-Rust");
    put_s(&mut b, call);
    for color in [bg, Some((255, 255, 255))] {
        b.push(u8::from(color.is_some()));
        let (r, g, bl) = color.unwrap_or_default();
        for c in [255u16, u16::from(r), u16::from(g), u16::from(bl), 0] {
            b.extend_from_slice(
                &(if c == 255 && color.is_none() {
                    0
                } else {
                    c * 257
                })
                .to_be_bytes(),
            );
        }
    }
    b.push(0);
    b
}
fn halt_tx(schema: u32, id: &str) -> Vec<u8> {
    let mut b = header(8, schema, id);
    b.push(0);
    b
}
fn station_socket(owner: &Owner, i: usize) -> SocketAddr {
    owner.lock().runtimes[i]
        .socket
        .as_ref()
        .unwrap()
        .local_addr()
        .unwrap()
}
/// Sends from `from` to station socket `i`, runs one step and returns its last_command.
fn command(f: &Fixture, owner: &Owner, from: &UdpSocket, i: usize, bytes: &[u8]) -> Value {
    from.send_to(bytes, station_socket(owner, i)).unwrap();
    std::thread::sleep(Duration::from_millis(20));
    owner.step(&f.state);
    owner.snapshot(&f.state.recording)["status"][i]["last_command"].clone()
}
fn outcome(v: &Value) -> (String, Value) {
    (
        v["outcome"].as_str().unwrap_or("none").to_owned(),
        v["code"].clone(),
    )
}

// Proves: CL-040-04, TC-012-001
#[test]
fn tc_012_001_decode_text_uses_the_wsjtx_report_form() {
    let r = |text: &str| wsjtx_text(&record(text, 1000.0, Some(0.0))).unwrap();
    // The decoder renders the separate R; the hand table is WSJT-X's.
    assert_eq!(
        record("K1ABC W9XYZ R-09", 1000.0, None)["text"],
        "K1ABC W9XYZ R -09"
    );
    assert_eq!(r("K1ABC W9XYZ R-09"), "K1ABC W9XYZ R-09");
    assert_eq!(r("K1ABC W9XYZ R+03"), "K1ABC W9XYZ R+03");
    assert_eq!(r("K1ABC W9XYZ -09"), "K1ABC W9XYZ -09");
    assert_eq!(r("K1ABC W9XYZ R FN42"), "K1ABC W9XYZ R FN42");
    assert_eq!(r("CQ K1ABC FN42"), "CQ K1ABC FN42");
    assert_eq!(r("K1ABC W9XYZ RR73"), "K1ABC W9XYZ RR73");
}

// Proves: CL-040-01, CL-040-02, CL-040-04, TC-012-002
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_002_outbound_messages_to_several_targets() {
    let f = fixture("http://127.0.0.1:18401", true);
    let (a, b) = (peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES, false),
            target_json(b.local_addr().unwrap(), &["decode"], false),
        ],
    );
    owner.step(&f.state);
    let first = drain(&a);
    assert_eq!(kinds(&first), [0, 1], "Heartbeat then Status at activation");
    let (schema, _, id, mut hb) = head(&first[0]);
    assert_eq!((schema, id.as_str()), (2, "WSTX-Rust"));
    assert_eq!(hb.u32(), 3, "maximum schema");
    assert_eq!(hb.s(), env!("CARGO_PKG_VERSION"));
    assert_eq!(hb.s(), "");
    let status = status_fields(&first[1]);
    assert_eq!(
        (
            &status["mode"],
            &status["de_call"],
            &status["de_grid"],
            &status["tx_enabled"]
        ),
        (&json!("FT8"), &json!("HB9BLA"), &json!("JN47AA"), &json!(0))
    );
    assert_eq!(
        (
            &status["tolerance"],
            &status["period"],
            &status["configuration"]
        ),
        (&json!(u32::MAX), &json!(15), &json!("Contact fixture"))
    );
    assert!(drain(&b).is_empty(), "B selects only decode");
    owner.step(&f.state);
    assert!(drain(&a).is_empty(), "unchanged Status is not repeated");

    f.state.recording.fixture_live_job("ft8");
    let period = 1_793_536_470_000i64; // 2026-11-01T12:34:30Z
    f.state.recording.fixture_publish_period(
        &period_text(period),
        vec![
            record("CQ K1ABC FN42", 1234.6, Some(-12.4)),
            record("HB9BLA W9XYZ R-09", 900.0, Some(-3.0)),
        ],
    );
    owner.step(&f.state);
    let at_a = drain(&a);
    let at_b = drain(&b);
    let decodes: Vec<_> = at_a.iter().filter(|d| head(d).1 == 2).collect();
    assert_eq!(decodes.len(), 2, "{:?}", kinds(&at_a));
    assert_eq!(kinds(&at_b), [2, 2]);
    let time = 45_270_000; // (12 * 3600 + 34 * 60 + 30) * 1000
    let first = decode_fields(decodes[0]);
    assert_eq!(
        (
            first.0,
            first.1,
            first.2,
            first.4,
            first.5.as_str(),
            first.6.as_str()
        ),
        (true, time, -12, 1235, "~", "CQ K1ABC FN42")
    );
    assert!((first.3 - 0.1).abs() < 1e-6, "dt {}", first.3);
    let second = decode_fields(decodes[1]);
    assert_eq!(
        (second.2, second.4, second.6.as_str()),
        (-3, 900, "HB9BLA W9XYZ R-09")
    );
    assert_eq!(decode_fields(&at_b[1]).6, "HB9BLA W9XYZ R-09");
    owner.step(&f.state);
    assert!(
        drain(&a).iter().all(|d| head(d).1 != 2) && drain(&b).is_empty(),
        "each decode is sent once"
    );

    operate(&f, "set_report", json!({"report":-7}), false);
    owner.step(&f.state);
    let changed = drain(&a);
    assert_eq!(kinds(&changed), [1]);
    assert_eq!(status_fields(&changed[0])["report"], "-07");

    f.state.recording.fixture_live_job("ft8");
    owner.step(&f.state);
    assert_eq!(kinds(&drain(&a)), [3], "Clear after the live job changed");
    assert!(drain(&b).is_empty(), "B does not select clear");

    let contact = profile::new_uuid().unwrap();
    let saved = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "record":{"contact_id":contact,"call":"K1ABC","gridsquare":"FN42","mode":"FT8","submode":null,
        "rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"123430",
        "qso_date_off":"20261101","time_off":"123615","band":"20m","freq":"14.075500",
        "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":null,"comment":null}});
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&saved).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    let logged = drain(&a);
    assert_eq!(kinds(&logged), [5, 12], "QSO Logged then Logged ADIF");
    let (_, _, _, mut q) = head(&logged[0]);
    // Julian day of 2026-11-01 = 2440588 + 20758 days since 1970-01-01.
    assert_eq!(
        (q.i64(), q.u32(), q.u8()),
        (2_461_346, 45_375_000, 1),
        "time off"
    );
    assert_eq!(
        (q.s(), q.s(), q.u64(), q.s()),
        ("K1ABC".into(), "FN42".into(), 14_075_500, "FT8".into())
    );
    assert_eq!((q.s(), q.s()), ("-12".into(), "-09".into()));
    let (_, _, _, mut adif) = head(&logged[1]);
    let text = adif.s();
    assert!(
        text.starts_with("\n<adif_ver:5>3.1.8\n<programid:9>WSTX-Rust\n<EOH>\n<call:5>K1ABC"),
        "{text}"
    );
    assert!(
        text.ends_with(&format!("<app_wstxrust_contact_id:36>{contact} <EOR>")),
        "{text}"
    );
    assert!(drain(&b).is_empty());
    let (s, _) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&saved).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "retained receipt");
    let mut again = saved.clone();
    again["command_id"] = json!(profile::new_uuid().unwrap());
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&again).unwrap()),
    )
    .await;
    assert_eq!(
        (s, v["outcome"].as_str()),
        (StatusCode::OK, Some("already_saved"))
    );
    assert!(
        drain(&a).is_empty(),
        "an already saved contact is not sent again"
    );

    let (_, snap) = call(&f, "GET", "/udp", None).await;
    for i in 0..2 {
        assert!(snap["status"][i]["last_send_utc_ms"].is_i64(), "{snap}");
        assert_eq!(snap["status"][i]["error"], Value::Null);
    }
    let mut targets = snap["configuration"]["targets"].clone();
    targets[0]["enabled"] = json!(false);
    let put = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":0,
        "configuration":{"instance_name":"WSTX-Rust","targets":targets}});
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&put).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(kinds(&drain(&a)), [6], "Close to the disabled target");
    assert_eq!(v["status"][0]["active"], false);
    assert_eq!(v["status"][1]["active"], true, "B keeps its socket");
    owner.step(&f.state);
    assert!(drain(&a).is_empty());
}

// Proves: CL-040-03, TC-012-003
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_003_inbound_commands_never_key_the_transmitter() {
    let f = fixture("http://127.0.0.1:18402", true);
    early_in_period(&f);
    let (a, c, x) = (peer(), peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES, false),
            target_json(c.local_addr().unwrap(), &MESSAGES, true),
        ],
    );
    f.state.recording.fixture_live_job("ft8");
    let period = 1_793_536_470_000i64;
    f.state.recording.fixture_publish_period(
        &period_text(period),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    owner.step(&f.state);
    drain(&a);
    drain(&c);
    let time = 45_270_000;
    let matching = reply(time, -12, 1235, "CQ K1ABC FN42");
    let none = || f.contact().facts().1.is_none();
    // Free Text needs a prepared contact and a standard message (browser parity).
    let v = command(&f, &owner, &c, 1, &free_text("CQ POTA HB9BLA"));
    assert_eq!(outcome(&v), ("refused".into(), json!("no_contact")), "{v}");

    // Accept commands off (A), and C's socket from a source that is not C: no effect.
    for (from, i) in [(&a, 0usize), (&x, 1)] {
        for bytes in [
            matching.clone(),
            free_text("K1ABC HB9BLA 73"),
            header(7, 2, "WSTX-Rust"),
            header(3, 2, "WSTX-Rust"),
            highlight("K1ABC", Some((255, 0, 0))),
        ] {
            let v = command(&f, &owner, from, i, &bytes);
            assert_eq!(outcome(&v).0, "not_accepted", "{v}");
        }
        assert!(none(), "no contact prepared");
        assert!(
            drain(&a).is_empty() && drain(&c).is_empty(),
            "no Replay sent"
        );
    }
    let snap = owner.snapshot(&f.state.recording);
    assert_eq!(
        (
            snap["highlights"].clone(),
            snap["clear"]["sequence"].clone()
        ),
        (json!([]), json!(0))
    );

    // From C: a mismatching Reply, then the matching one prepares K1ABC disarmed.
    let v = command(&f, &owner, &c, 1, &reply(time, -11, 1235, "CQ K1ABC FN42"));
    assert_eq!(outcome(&v), ("refused".into(), json!("no_match")));
    let v = command(
        &f,
        &owner,
        &c,
        1,
        &reply(time, -12, 1235, " CQ K1ABC FN42 "),
    );
    assert_eq!(outcome(&v), ("applied".into(), Value::Null), "{v}");
    assert_eq!(v["type"], "reply");
    let (_, facts, _) = f.contact().facts();
    let facts = facts.unwrap();
    assert_eq!(
        (facts.state, facts.dx_call.as_deref()),
        ("replying", Some("K1ABC"))
    );
    assert_eq!(
        f.contact().status_facts().next_message.as_deref(),
        Some("K1ABC HB9BLA JN47")
    );
    assert_eq!(arm_state(&f), ArmState::Disarmed);

    let v = command(&f, &owner, &c, 1, &free_text("TNX 73 GL"));
    assert_eq!(
        outcome(&v),
        ("refused".into(), json!("invalid_message")),
        "{v}"
    );
    let v = command(&f, &owner, &c, 1, &free_text("K1ABC HB9BLA 73"));
    assert_eq!(outcome(&v).0, "applied", "{v}");
    let snapshot: Value = serde_json::from_slice(&f.contact().snapshot(&f.state).unwrap()).unwrap();
    assert_eq!(snapshot["contact"]["messages"][4], "K1ABC HB9BLA 73");
    assert_eq!(
        arm_state(&f),
        ArmState::Disarmed,
        "the Send flag is ignored"
    );

    // Replay goes to C only: the retained decode with New false, then Status.
    drain(&c);
    let v = command(&f, &owner, &c, 1, &header(7, 2, "WSTX-Rust"));
    assert_eq!(outcome(&v).0, "applied");
    let replayed = drain(&c);
    assert_eq!(kinds(&replayed), [2, 1]);
    let d = decode_fields(&replayed[0]);
    assert_eq!((d.0, d.1, d.6.as_str()), (false, time, "CQ K1ABC FN42"));
    assert!(
        drain(&a).iter().all(|d| head(d).1 != 2),
        "nothing replayed to A"
    );

    let v = command(&f, &owner, &c, 1, &highlight("K1ABC", Some((255, 0, 0))));
    assert_eq!(outcome(&v).0, "applied");
    assert_eq!(
        owner.snapshot(&f.state.recording)["highlights"],
        json!([{"call":"K1ABC","background":"#ff0000","foreground":"#ffffff","last_only":false}])
    );
    command(&f, &owner, &c, 1, &highlight("W1AW", Some((0, 255, 0))));
    command(&f, &owner, &c, 1, &highlight("K1ABC", None));
    assert_eq!(
        owner.snapshot(&f.state.recording)["highlights"][0]["call"],
        "W1AW",
        "invalid colour removes"
    );
    command(&f, &owner, &c, 1, &highlight("CLEARALL!", Some((0, 0, 0))));
    assert_eq!(owner.snapshot(&f.state.recording)["highlights"], json!([]));

    for (bytes, kind) in [
        (header(6, 2, "WSTX-Rust"), "close"),
        (header(15, 2, "WSTX-Rust"), "configure"),
    ] {
        let v = command(&f, &owner, &c, 1, &bytes);
        assert_eq!(
            (v["type"].as_str(), outcome(&v).0.as_str()),
            (Some(kind), "ignored")
        );
    }

    // Armed by the browser: Reply and Free Text are refused tx_enabled.
    f.contact().grant.store(true, Ordering::SeqCst);
    let transmit = f.state.recording.transmit.get().unwrap().clone();
    let arm = || {
        operate(
            &f,
            "enable_tx",
            json!({"enabled":true,"safety_revision":3}),
            true,
        );
        assert_eq!(arm_state(&f), ArmState::Armed);
    };
    arm();
    let v = command(&f, &owner, &c, 1, &matching);
    assert_eq!(outcome(&v), ("refused".into(), json!("tx_enabled")));
    let v = command(&f, &owner, &c, 1, &free_text("K1ABC HB9BLA RR73"));
    assert_eq!(outcome(&v), ("refused".into(), json!("tx_enabled")));
    // A foreign id or schema 4 is no Halt Tx of this station.
    let before = transmit.service.halt_requests();
    for bytes in [halt_tx(2, "WSJT-X"), halt_tx(4, "WSTX-Rust")] {
        c.send_to(&bytes, station_socket(&owner, 1)).unwrap();
        std::thread::sleep(Duration::from_millis(20));
        owner.step(&f.state);
    }
    assert_eq!(
        (arm_state(&f), transmit.service.halt_requests()),
        (ArmState::Armed, before)
    );
    assert!(
        owner.snapshot(&f.state.recording)["ignored"]
            .as_u64()
            .unwrap()
            >= 2
    );
    // Halt Tx always acts: from A (accept off), from a non-target source and from C.
    for (n, (from, i)) in [(&a, 0usize), (&x, 0), (&c, 1)].into_iter().enumerate() {
        if n > 0 {
            arm();
        }
        let v = command(
            &f,
            &owner,
            from,
            i,
            &halt_tx(2 + (n as u32 % 2), "WSTX-Rust"),
        );
        assert_eq!(
            (v["type"].as_str(), outcome(&v).0.as_str()),
            (Some("halt_tx"), "applied")
        );
        let view = transmit.service.view();
        assert_eq!(
            (view.arm_state, view.last_disarm_cause),
            (ArmState::Disarmed, DisarmCause::Halt)
        );
        assert_eq!(transmit.service.halt_requests(), before + n as u64 + 1);
    }

    // Clear (window 0) hides the earlier decodes from Replay and Reply.
    let v = command(&f, &owner, &c, 1, &header(3, 2, "WSTX-Rust"));
    assert_eq!(outcome(&v).0, "applied");
    assert_eq!(
        owner.snapshot(&f.state.recording)["clear"],
        json!({"sequence":1,"window":0})
    );
    drain(&c);
    command(&f, &owner, &c, 1, &header(7, 2, "WSTX-Rust"));
    assert_eq!(kinds(&drain(&c)), [1], "Replay after Clear: Status only");
    operate(&f, "cancel", json!({}), false);
    let v = command(&f, &owner, &c, 1, &matching);
    assert_eq!(outcome(&v), ("refused".into(), json!("no_match")));
    let keys = f.bench.keys.lock().unwrap().clone();
    assert!(keys.iter().all(|(_, on)| !on), "PTT never keyed: {keys:?}");
}

fn config_body(f: &Fixture, revision: u64, targets: Value) -> Value {
    json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":revision,
        "configuration":{"instance_name":"WSTX-Rust","targets":targets}})
}

// Proves: CL-040-02, TC-012-004
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_004_target_configuration_and_persistence() {
    let f = fixture("http://127.0.0.1:18403", false);
    // WSTX_UDP=off semantics: the default list is shown, no socket is opened.
    let owner = Owner::open(&f.state, true);
    assert!(f.state.recording.udp.set(owner.clone()).is_ok());
    let (s, v) = call(&f, "GET", "/udp", None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(
        (
            v["revision"].clone(),
            v["configuration"].clone(),
            v["configuration_error"].clone()
        ),
        (
            json!(0),
            json!({"instance_name":"WSTX-Rust","targets":[{"address":"127.0.0.1:2237","enabled":true,
                "multicast_ttl":1,"multicast_interface":null,"messages":MESSAGES,"accept_commands":false}]}),
            Value::Null
        )
    );
    assert_eq!(v["status"][0]["active"], false);
    assert!(
        !f.dir.join(FILE_NAME).exists(),
        "the default is not written"
    );

    let targets = json!([
        {"address":"127.0.0.1:52001","enabled":true,"multicast_ttl":1,"multicast_interface":null,
         "messages":["decode"],"accept_commands":false},
        {"address":"239.255.0.1:2237","enabled":false,"multicast_ttl":2,"multicast_interface":"127.0.0.1",
         "messages":["logged_adif","heartbeat","status"],"accept_commands":false}]);
    let good = config_body(&f, 0, targets.clone());
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&good).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["revision"], 1);
    assert_eq!(
        v["configuration"]["targets"][1]["messages"],
        json!(["heartbeat", "status", "logged_adif"])
    );
    let saved = v["configuration"].clone();
    let reopened = Owner::open(&f.state, true).snapshot(&f.state.recording);
    assert_eq!(
        (
            reopened["revision"].clone(),
            reopened["configuration"].clone()
        ),
        (json!(1), saved.clone())
    );

    let mut cases: Vec<(Value, StatusCode, &str, Value)> = Vec::new();
    let t = |k: &str, value: Value| {
        let mut list = targets.clone();
        list[0][k] = value;
        list
    };
    let with = |k: &str, value: Value| {
        let mut b = config_body(&f, 1, targets.clone());
        b[k] = value;
        b
    };
    cases.push((
        config_body(&f, 0, targets.clone()),
        StatusCode::CONFLICT,
        "stale_revision",
        json!("expected_revision"),
    ));
    cases.push((
        with("profile_id", json!(profile::new_uuid().unwrap())),
        StatusCode::FORBIDDEN,
        "wrong_profile",
        json!("profile_id"),
    ));
    cases.push((
        with("boot_id", json!(profile::new_uuid().unwrap())),
        StatusCode::CONFLICT,
        "state_conflict",
        json!("boot_id"),
    ));
    cases.push((
        with("extra", json!(1)),
        StatusCode::BAD_REQUEST,
        "invalid_request",
        Value::Null,
    ));
    cases.push((
        with("v", json!(2)),
        StatusCode::BAD_REQUEST,
        "unsupported_version",
        json!("v"),
    ));
    let seventeen: Vec<Value> = (0..17)
        .map(|i| {
            json!({"address":format!("127.0.0.1:{}", 52100 + i),"enabled":true,"multicast_ttl":1,
            "multicast_interface":null,"messages":[],"accept_commands":false})
        })
        .collect();
    let sixteen = Value::from(seventeen[..16].to_vec());
    let mut duplicate = targets.clone();
    duplicate[1] = duplicate[0].clone();
    for (list, field) in [
        (Value::from(seventeen), "targets"),
        (duplicate, "targets[1].address"),
        (t("address", json!("127.0.0.1:0")), "targets[0].address"),
        (t("address", json!("0.0.0.0:2237")), "targets[0].address"),
        (
            t("address", json!("[ff02::1]:2237")),
            "targets[0].multicast_interface",
        ),
        (
            t("address", json!("255.255.255.255:2237")),
            "targets[0].address",
        ),
        (t("address", json!("localhost:2237")), "targets[0].address"),
        (t("multicast_ttl", json!(0)), "targets[0].multicast_ttl"),
        (t("multicast_ttl", json!(256)), "targets[0].multicast_ttl"),
        (
            t("multicast_interface", json!("::1")),
            "targets[0].multicast_interface",
        ),
        (
            t("messages", json!(["decode", "decode"])),
            "targets[0].messages",
        ),
        (t("messages", json!(["wspr_decode"])), "targets[0].messages"),
        (t("enabled", json!("yes")), "targets[0].enabled"),
        (
            {
                let mut list = targets.clone();
                list[1]["accept_commands"] = json!(true);
                list
            },
            "targets[1].accept_commands",
        ),
    ] {
        cases.push((
            config_body(&f, 1, list),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!(field),
        ));
    }
    for name in [
        json!(""),
        json!("x".repeat(65)),
        json!(" WSTX"),
        json!("a\u{7}b"),
    ] {
        let mut b = config_body(&f, 1, targets.clone());
        b["configuration"]["instance_name"] = name;
        cases.push((
            b,
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!("instance_name"),
        ));
    }
    for (body, status, code, field) in cases {
        let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
        assert_eq!(
            (s, v["error"]["code"].as_str(), v["error"]["field"].clone()),
            (status, Some(code), field.clone()),
            "{body}"
        );
    }
    let bytes = serde_json::to_vec(&config_body(&f, 1, targets.clone())).unwrap();
    let (s, v) = call_with(&f, "PUT", "/udp", Some(bytes.clone()), "text/plain").await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            Some("unsupported_media_type")
        )
    );
    let mut big = bytes.clone();
    big.resize(BODY_MAX + 1, b' ');
    let (s, _) = call(&f, "PUT", "/udp", Some(big)).await;
    assert_eq!(s, StatusCode::PAYLOAD_TOO_LARGE);
    let (s, _) = call(&f, "PUT", "/udp?x=1", Some(bytes.clone())).await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let (_, v) = call(&f, "GET", "/udp", None).await;
    assert_eq!(
        (v["revision"].clone(), v["configuration"].clone()),
        (json!(1), saved),
        "nothing saved"
    );
    // Sixteen targets is the maximum.
    let (s, v) = call(
        &f,
        "PUT",
        "/udp",
        Some(serde_json::to_vec(&config_body(&f, 1, sixteen)).unwrap()),
    )
    .await;
    assert_eq!(
        (s, v["revision"].clone()),
        (StatusCode::OK, json!(2)),
        "{v}"
    );

    // An invalid udp.json: configuration null, no socket, until a valid PUT.
    let g = fixture("http://127.0.0.1:18404", false);
    std::fs::write(g.dir.join(FILE_NAME), b"{\"schema_version\":1}").unwrap();
    let broken = Owner::open(&g.state, false);
    let v = broken.snapshot(&g.state.recording);
    assert_eq!(
        (
            v["configuration"].clone(),
            v["configuration_error"].clone(),
            v["status"].clone()
        ),
        (Value::Null, json!("invalid_configuration"), json!([]))
    );
    // Decodes published while the configuration was invalid are never sent as new
    // after a valid PUT repairs it.
    assert!(g.state.recording.udp.set(broken.clone()).is_ok());
    g.state.recording.fixture_live_job("ft8");
    g.state.recording.fixture_publish_period(
        &period_text(1_793_536_470_000),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    broken.step(&g.state);
    let p = peer();
    let body = config_body(
        &g,
        0,
        json!([target_json(p.local_addr().unwrap(), &MESSAGES, false)]),
    );
    let (s, v) = call(&g, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(
        (s, v["configuration_error"].clone()),
        (StatusCode::OK, Value::Null),
        "{v}"
    );
    broken.step(&g.state);
    assert_eq!(
        kinds(&drain(&p)),
        [0, 1],
        "Heartbeat and Status, no stale Decode"
    );
}

fn location(text: &str) -> Vec<u8> {
    let mut b = header(11, 2, "WSTX-Rust");
    put_s(&mut b, text);
    b
}

// Proves: CL-040-05, TC-012-005
#[test]
fn tc_012_005_location_text_rules() {
    // WSJT-X MainWindow::locationChange: <= 6 characters is a grid, longer needs GRID:.
    assert_eq!(location_grid("JN47"), Some("JN47".into()));
    assert_eq!(location_grid(" jn36ab "), Some("JN36AB".into()));
    assert_eq!(location_grid("GRID:JN36AB"), Some("JN36AB".into()));
    assert_eq!(location_grid("grid: fn42"), Some("FN42".into()));
    for bad in [
        "",
        "XX",
        "JN4",
        "JN47A",
        "JN47AA11",
        "47.1,8.5",
        "LOC:JN47AA",
        "ZZ99",
    ] {
        assert_eq!(location_grid(bad), None, "{bad}");
    }
}

// Proves: CL-040-05, TC-012-005
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_005_location_sets_a_session_grid() {
    let f = fixture("http://127.0.0.1:18405", true);
    early_in_period(&f);
    let (a, c) = (peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES, false),
            target_json(c.local_addr().unwrap(), &MESSAGES, true),
        ],
    );
    owner.step(&f.state);
    let first = drain(&c);
    assert_eq!(status_fields(&first[1])["de_grid"], "JN47AA");
    // From a target without accept_commands: no effect.
    let v = command(&f, &owner, &a, 0, &location("JN36AB"));
    assert_eq!(outcome(&v).0, "not_accepted");
    let v = command(&f, &owner, &c, 1, &location("XX"));
    assert_eq!(outcome(&v), ("refused".into(), json!("invalid_grid")));
    assert!(drain(&c).is_empty(), "nothing changed");
    let v = command(&f, &owner, &c, 1, &location("GRID:JN36AB"));
    assert_eq!(
        (v["type"].as_str(), outcome(&v).0.as_str()),
        (Some("location"), "applied")
    );
    let changed = drain(&c);
    assert_eq!(kinds(&changed), [1]);
    assert_eq!(
        status_fields(&changed[0])["de_grid"],
        "JN36AB",
        "Status DE grid"
    );

    // Generated messages use the session grid (Tx1 carries its 4-character square).
    f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_publish_period(
        &period_text(1_793_536_470_000),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    owner.step(&f.state);
    let v = command(
        &f,
        &owner,
        &c,
        1,
        &reply(45_270_000, -12, 1235, "CQ K1ABC FN42"),
    );
    assert_eq!(outcome(&v).0, "applied", "{v}");
    assert_eq!(
        f.contact().status_facts().next_message.as_deref(),
        Some("K1ABC HB9BLA JN36")
    );
    let snapshot: Value = serde_json::from_slice(&f.contact().snapshot(&f.state).unwrap()).unwrap();
    assert_eq!(snapshot["contact"]["messages"][5], "CQ HB9BLA JN36");

    // The log takes the session grid as my_gridsquare; the profile grid is refused.
    let body = |grid: &str| {
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
            "record":{"contact_id":profile::new_uuid().unwrap(),"call":"K1ABC","gridsquare":"FN42","mode":"FT8",
            "submode":null,"rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"123430",
            "qso_date_off":"20261101","time_off":"123615","band":"20m","freq":"14.075500",
            "station_callsign":"HB9BLA","my_gridsquare":grid,"tx_pwr":null,"comment":null}})
    };
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&body("JN47AA")).unwrap()),
    )
    .await;
    assert_eq!(
        (s, v["error"]["field"].as_str()),
        (StatusCode::BAD_REQUEST, Some("record.my_gridsquare")),
        "{v}"
    );
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&body("JN36AB")).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{v}");

    // Session only: the profile is unchanged and a new owner (a restart) has no override.
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.dir.join("profile.json")).unwrap()).unwrap();
    assert_eq!(saved["locator"], "JN47AA");
    assert_eq!(f.state.store.lock().unwrap().document.locator, "JN47AA");
    let restarted = Owner::open(&f.state, true);
    assert_eq!(*restarted.grid.lock().unwrap(), None);
    assert!(f.bench.keys.lock().unwrap().iter().all(|(_, on)| !on));
}

// Proves: CL-040-03, TC-012-003
#[test]
fn tc_012_003_oversize_datagram_does_not_hold_back_halt() {
    let f = fixture("http://127.0.0.1:18406", true);
    early_in_period(&f);
    let a = peer();
    let owner = install(
        &f,
        vec![target_json(a.local_addr().unwrap(), &MESSAGES, false)],
    );
    owner.step(&f.state);
    f.contact().grant.store(true, Ordering::SeqCst);
    operate(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":3}),
        true,
    );
    assert_eq!(arm_state(&f), ArmState::Armed);
    let before = owner.snapshot(&f.state.recording)["ignored"]
        .as_u64()
        .unwrap();
    let to = station_socket(&owner, 0);
    let mut big = header(7, 2, "WSTX-Rust");
    big.resize(5000, 0);
    a.send_to(&big, to).unwrap();
    a.send_to(&halt_tx(2, "WSTX-Rust"), to).unwrap();
    std::thread::sleep(Duration::from_millis(30));
    owner.step(&f.state);
    let snap = owner.snapshot(&f.state.recording);
    assert_eq!(
        arm_state(&f),
        ArmState::Disarmed,
        "the Halt behind it acts in the same step"
    );
    assert_eq!(snap["status"][0]["last_command"]["type"], "halt_tx");
    assert_eq!(
        snap["ignored"].as_u64().unwrap(),
        before + 1,
        "the oversize datagram is counted"
    );
}

/// 2026-11-01T12:34:30Z, an even FT8 period (Julian day 2461346, see tc_012_002).
const P1101: i64 = 1_793_536_470_000;
/// Publishes `text` from the partner in FT8 period `period` and runs one contact step
/// with the station clock frozen 16 s into that period (after its decode).
fn partner(f: &Fixture, period: i64, text: &str) {
    f.state
        .recording
        .fixture_publish_period(&period_text(period), vec![record(text, 1500.0, Some(-9.0))]);
    f.bench.frozen.store(period + 16_000, Ordering::SeqCst);
    f.tick();
}
fn stored(f: &Fixture) -> Vec<Value> {
    f.state.logbook.history(&f.id, 0, 10).unwrap()["records"]
        .as_array()
        .unwrap()
        .clone()
}
fn log_view(f: &Fixture) -> Value {
    let bytes = f.contact().snapshot(&f.state).unwrap();
    serde_json::from_slice::<Value>(&bytes).unwrap()["log"].clone()
}
fn enter(f: &Fixture, call: &str, grid: Option<&str>) {
    operate(
        f,
        "enter_dx",
        json!({"dx_call":call,"dx_grid":grid,"replace":true}),
        false,
    );
}
// Proves: CL-010-04, CL-040-01, TC-011-001, TC-012-002. #41 WstxContact::DirectLog: the
// completed contact logs itself (no review, no browser) and reaches the UDP target as QSO
// Logged + Logged ADIF; exactly one record per contact identity. Expected fields are
// hand-computed from the LogRecord rules: TIME_ON = preparation (nothing transmitted),
// TIME_OFF = end of the partner's last counted period, MY_GRIDSQUARE the profile locator.
#[tokio::test(flavor = "multi_thread")]
async fn tc_011_001_a_completed_contact_logs_itself_once_and_reaches_the_udp_target() {
    let f = fixture("http://127.0.0.1:18408", true);
    // No radio: the dial is unconfirmed, so BAND and FREQ are absent (record_of with a
    // confirmed dial: contact_http_tests::direct_log_record_fields_from_the_confirmed_dial).
    f.state.recording.fixture_live_job("ft8");
    let (a, b) = (peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(
                a.local_addr().unwrap(),
                &["qso_logged", "logged_adif"],
                false,
            ),
            target_json(b.local_addr().unwrap(), &["heartbeat"], true),
        ],
    );
    owner.step(&f.state);
    drain(&a);

    // K1ABC: prepared at 12:34:20, R-09 in 12:34:30, 73 in 12:35:00 (rogers -> completed).
    f.bench.frozen.store(P1101 - 10_000, Ordering::SeqCst);
    enter(&f, "K1ABC", Some("FN42"));
    partner(&f, P1101, "HB9BLA K1ABC R-09");
    assert!(stored(&f).is_empty(), "nothing is logged before completion");
    partner(&f, P1101 + 30_000, "HB9BLA K1ABC 73");
    let records = stored(&f);
    assert_eq!(records.len(), 1, "{records:?}");
    let id = f.contact().facts().1.unwrap().id;
    assert_eq!(
        records[0],
        json!({"index":0,"contact_id":id,"call":"K1ABC","gridsquare":"FN42","mode":"FT8","submode":null,
            "rst_sent":null,"rst_rcvd":"-09","qso_date":"20261101","time_on":"123420",
            "qso_date_off":"20261101","time_off":"123515","band":null,"freq":null,
            "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":null,"comment":null,
            "unknown_field_count":0})
    );
    let logged = drain(&a);
    assert_eq!(kinds(&logged), [5, 12], "QSO Logged then Logged ADIF");
    let (_, _, _, mut q) = head(&logged[0]);
    let _time_off = (q.i64(), q.u32(), q.u8());
    assert_eq!(
        (q.s(), q.s(), q.u64(), q.s()),
        ("K1ABC".into(), "FN42".into(), 0, "FT8".into())
    );
    assert_eq!(
        log_view(&f),
        json!({"contact_id":id,"call":"K1ABC","outcome":"saved","error":null})
    );
    // A repeated 73 and a Log QSO of the completed contact add no record and send
    // nothing; the record keeps what held at completion (a later location is not used).
    partner(&f, P1101 + 60_000, "HB9BLA K1ABC 73");
    f.state.store.lock().unwrap().document.locator = "JN46AA".into();
    operate(&f, "open_log", json!({}), false);
    f.tick();
    assert_eq!(stored(&f), records, "the completion record is kept");
    assert!(drain(&a).is_empty(), "already stored: nothing sent again");
    f.state.store.lock().unwrap().document.locator = "JN47AA".into();

    // W1AW: Log QSO before completion stores it now; completion replaces it in place.
    f.bench.frozen.store(P1101 + 80_000, Ordering::SeqCst);
    enter(&f, "W1AW", None);
    operate(&f, "open_log", json!({}), false);
    f.tick();
    let early = stored(&f);
    assert_eq!(early.len(), 2);
    assert_eq!(
        (
            early[1]["call"].as_str(),
            early[1]["time_off"].as_str(),
            early[1]["rst_rcvd"].clone()
        ),
        (Some("W1AW"), Some("123550"), Value::Null),
        "logged now with the times so far"
    );
    assert_eq!(kinds(&drain(&a)), [5, 12]);
    partner(&f, P1101 + 90_000, "HB9BLA W1AW R-05");
    partner(&f, P1101 + 120_000, "HB9BLA W1AW 73");
    let replaced = stored(&f);
    assert_eq!(replaced.len(), 2, "one record per contact identity");
    assert_eq!(replaced[1]["contact_id"], early[1]["contact_id"]);
    assert_eq!(
        (
            replaced[1]["time_off"].as_str(),
            replaced[1]["rst_rcvd"].as_str()
        ),
        (Some("123645"), Some("-05"))
    );
    assert!(
        drain(&a).is_empty(),
        "the replacement stays internal: each contact reaches the targets once"
    );

    // Storage failure at completion: unsaved and visible, retried only after the backoff.
    f.state.logbook.inject_fault(Some("write"));
    f.bench.frozen.store(P1101 + 140_000, Ordering::SeqCst);
    enter(&f, "K1ABC", None);
    partner(&f, P1101 + 150_000, "HB9BLA K1ABC R-03");
    partner(&f, P1101 + 180_000, "HB9BLA K1ABC 73");
    let third = f.contact().facts().1.unwrap().id;
    assert_ne!(third, id, "the same call later is a new contact");
    assert_eq!(
        log_view(&f),
        json!({"contact_id":third,"call":"K1ABC","outcome":"unsaved","error":"storage_unavailable"})
    );
    f.state.logbook.inject_fault(None);
    f.tick();
    assert_eq!(stored(&f).len(), 2, "no retry before the backoff");
    assert!(drain(&a).is_empty());
    // The due retry runs in a command reached from a UDP FreeText while the UDP owner
    // holds its lock: the step returns (no re-entry) and the datagrams follow the tick.
    f.contact().retry_logs_now();
    b.send_to(&free_text("K1ABC HB9BLA 73"), station_socket(&owner, 1))
        .unwrap();
    std::thread::sleep(Duration::from_millis(20));
    let (done, finished) = std::sync::mpsc::channel();
    let (o, state) = (owner.clone(), f.state.clone());
    std::thread::spawn(move || {
        o.step(&state);
        let _ = done.send(());
    });
    finished
        .recv_timeout(Duration::from_secs(5))
        .expect("the UDP step returns");
    assert_eq!(
        owner.snapshot(&f.state.recording)["status"][1]["last_command"]["outcome"],
        "applied"
    );
    let after = stored(&f);
    assert_eq!(after.len(), 3, "the retry stores it");
    f.tick();
    assert_eq!(
        (after[2]["contact_id"].as_str(), after[2]["call"].as_str()),
        (Some(third.as_str()), Some("K1ABC"))
    );
    assert_eq!(kinds(&drain(&a)), [5, 12]);
    assert_eq!(log_view(&f)["outcome"], "saved");
    // Records survive a restart (a fresh station starts no contact, so logs nothing again).
    assert_eq!(crate::logbook::Logbook::open(&f.dir).total().unwrap(), 3);

    // While storage fails at most LOG_PENDING_MAX records wait; the oldest is dropped.
    f.state.logbook.inject_fault(Some("write"));
    for i in 0..=contact_http::LOG_PENDING_MAX {
        let suffix: String = [b'A' + (i / 26) as u8, b'A' + (i % 26) as u8]
            .iter()
            .map(|&b| b as char)
            .collect();
        enter(&f, &format!("DL1{suffix}"), None);
        operate(&f, "open_log", json!({}), false);
    }
    assert_eq!(
        (
            log_view(&f)["call"].as_str(),
            log_view(&f)["error"].as_str()
        ),
        (Some("DL1AA"), Some("log_queue_full")),
        "the dropped record stays shown"
    );
    f.state.logbook.inject_fault(None);
    f.contact().retry_logs_now();
    f.tick();
    assert_eq!(
        f.state.logbook.total().unwrap(),
        3 + contact_http::LOG_PENDING_MAX
    );
    let page = f.state.logbook.history(&f.id, 3, 1).unwrap();
    assert_eq!(
        page["records"][0]["call"], "DL1AB",
        "DL1AA was dropped (log_queue_full)"
    );
    assert_eq!(kinds(&drain(&a)).len(), 2 * contact_http::LOG_PENDING_MAX);
}

/// The Windows loopback pseudo-interface ("Loopback Pseudo-Interface 1").
const LOOPBACK_INDEX: u32 = 1;
/// A transient link-local test group (flags 1, scope 2), never a well-known one.
const GROUP: &str = "ff12::5754:5358";
fn multicast_json(address: &str, hops: u32, interface: Value, accept: bool) -> Value {
    json!({"address":address,"enabled":true,"multicast_ttl":hops,"multicast_interface":interface,
        "messages":["heartbeat","status"],"accept_commands":accept})
}

// Proves: CL-040-06, TC-012-006
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_006_ipv6_multicast_targets() {
    let f = fixture("http://127.0.0.1:18407", false);
    let owner = install(&f, vec![]);
    // A peer joined to the group on the loopback interface.
    let group: Ipv6Addr = GROUP.parse().unwrap();
    let joined = socket2::Socket::new(
        socket2::Domain::IPV6,
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    )
    .unwrap();
    joined
        .bind(&SocketAddr::from((Ipv6Addr::UNSPECIFIED, 0)).into())
        .unwrap();
    joined.join_multicast_v6(&group, LOOPBACK_INDEX).unwrap();
    let joined: UdpSocket = joined.into();
    joined
        .set_read_timeout(Some(Duration::from_millis(300)))
        .unwrap();
    let port = joined.local_addr().unwrap().port();
    let address = format!("[{GROUP}]:{port}");

    // Refusals: each with its field, nothing saved.
    let good = multicast_json(&address, 2, json!("1"), false);
    let with = |k: &str, value: Value| {
        let mut t = good.clone();
        t[k] = value;
        t
    };
    let mut refused = vec![
        (with("address", json!("[ff00::1]:2237")), "address"),
        (with("address", json!("[ff0f::1]:2237")), "address"),
        (with("address", json!("[ff1f::1]:2237")), "address"),
        (
            with("multicast_interface", Value::Null),
            "multicast_interface",
        ),
        (
            {
                let mut t = with("address", json!("[ff01::1]:2237"));
                t["multicast_interface"] = Value::Null;
                t
            },
            "multicast_interface",
        ),
        (with("multicast_ttl", json!(0)), "multicast_ttl"),
        (with("multicast_ttl", json!(256)), "multicast_ttl"),
        (with("accept_commands", json!(true)), "accept_commands"),
        (
            {
                let mut t = with("address", json!("239.255.0.1:2237"));
                t["multicast_interface"] = json!("1");
                t
            },
            "multicast_interface",
        ),
    ];
    for interface in [
        json!("0"),
        json!("01"),
        json!("-1"),
        json!("+1"),
        json!(" 1"),
        json!("4294967296"),
        json!("Ethernet"),
        json!("127.0.0.1"),
        json!("::1"),
        json!(""),
        json!(1),
    ] {
        refused.push((
            with("multicast_interface", interface),
            "multicast_interface",
        ));
    }
    for (target, field) in refused {
        let body = config_body(&f, 0, json!([target]));
        let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
        assert_eq!(
            (s, v["error"]["code"].as_str(), v["error"]["field"].clone()),
            (
                StatusCode::BAD_REQUEST,
                Some("invalid_request"),
                json!(format!("targets[0].{field}"))
            ),
            "{body}"
        );
    }
    let (_, v) = call(&f, "GET", "/udp", None).await;
    assert_eq!(
        (v["revision"].clone(), v["configuration"]["targets"].clone()),
        (json!(0), json!([])),
        "nothing saved"
    );

    // Admitted: the link-local group on the loopback interface with hop limit 2, a
    // site-local group with hop limit 255 (on loopback, so nothing leaves the machine),
    // an index no interface has, and a disabled organization-local group without an
    // interface (optional above link scope).
    let mut org = multicast_json("[ff08::5754:5358]:2239", 1, Value::Null, false);
    org["enabled"] = json!(false);
    let targets = json!([
        good,
        multicast_json("[ff05::5754:5358]:2237", 255, json!("1"), false),
        multicast_json("[ff15::5754:5358]:2238", 1, json!("4000000000"), false),
        org,
    ]);
    let body = config_body(&f, 0, targets.clone());
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["configuration"]["targets"], targets, "saved as given");
    let reopened = Owner::open(&f.state, true).snapshot(&f.state.recording);
    assert_eq!(reopened["configuration"]["targets"], targets);

    // An IPv6 unicast target keeps the #40 IPv4 interface form (a saved file loads).
    let mut unicast = multicast_json("[::1]:2240", 1, json!("127.0.0.1"), false);
    unicast["enabled"] = json!(false);
    let mut with_unicast = targets.as_array().unwrap().clone();
    with_unicast.push(unicast.clone());
    let body = config_body(&f, 1, Value::from(with_unicast.clone()));
    let (s, v2) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v2}");
    assert_eq!(v2["configuration"]["targets"][4], unicast);
    let mut index = unicast.clone();
    index["multicast_interface"] = json!("1");
    let mut refused_list = targets.as_array().unwrap().clone();
    refused_list.push(index);
    let body = config_body(&f, 2, Value::from(refused_list));
    let (s, v2) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(
        (s, v2["error"]["field"].clone()),
        (
            StatusCode::BAD_REQUEST,
            json!("targets[4].multicast_interface")
        )
    );

    // The socket carries the hop limit and the interface.
    {
        let inner = owner.lock();
        let socket = socket2::SockRef::from(inner.runtimes[0].socket.as_ref().unwrap());
        assert_eq!(socket.multicast_hops_v6().unwrap(), 2);
        assert_eq!(socket.multicast_if_v6().unwrap(), LOOPBACK_INDEX);
        assert!(socket.multicast_loop_v6().unwrap());
        let site = socket2::SockRef::from(inner.runtimes[1].socket.as_ref().unwrap());
        assert_eq!(site.multicast_hops_v6().unwrap(), 255);
    }
    let status = &v["status"];
    assert_eq!(
        (&status[0]["active"], &status[0]["error"]),
        (&json!(true), &Value::Null)
    );
    assert_eq!(
        (&status[2]["active"], &status[2]["error"]),
        (&json!(false), &json!("socket_unavailable")),
        "an index no interface has"
    );

    // The joined peer receives Heartbeat and Status.
    owner.step(&f.state);
    let got = drain(&joined);
    assert_eq!(kinds(&got), [0, 1], "Heartbeat then Status to the group");
    let (schema, _, id, _) = head(&got[0]);
    assert_eq!((schema, id.as_str()), (2, "WSTX-Rust"));

    // A command sent to the multicast target's socket from a host is not accepted.
    let host = UdpSocket::bind("[::1]:0").unwrap();
    let to = SocketAddr::from((Ipv6Addr::LOCALHOST, station_socket(&owner, 0).port()));
    host.send_to(&free_text("TNX 73 GL"), to).unwrap();
    std::thread::sleep(Duration::from_millis(20));
    owner.step(&f.state);
    let last = owner.snapshot(&f.state.recording)["status"][0]["last_command"].clone();
    assert_eq!(
        (last["type"].as_str(), outcome(&last).0.as_str()),
        (Some("free_text"), "not_accepted")
    );
}
