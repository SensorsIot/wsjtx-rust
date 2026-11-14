#![forbid(unsafe_code)]
// Proves: CL-040-01, CL-040-02, CL-040-03, CL-040-04, CL-040-06, TC-012-001, TC-012-002, TC-012-003,
// TC-012-004, TC-012-006, CL-040-07, TC-012-007.
// The actual router, UDP owner, contact engine and #9 transmit
// owner on the recording hardware double (no audio, PTT or radio), hand-authored rows
// packed with the real codec and loopback UDP peers on ephemeral ports (never 2237). The
// datagrams are read back with the independent big-endian reader below, not the encoder.
use super::*;
use crate::contact_http_tests::{Fixture, fixture, now_ms, period_text, record};
use axum::body::Body;
use std::sync::atomic::Ordering;
use tower::ServiceExt;

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
fn target_json(address: SocketAddr, messages: &[&str]) -> Value {
    json!({"address":address.to_string(),"enabled":true,"multicast_ttl":1,"multicast_interface":null,
        "messages":messages})
}
/// The fixture's own folder of instance-name locks, never the operator's.
fn locks(f: &Fixture) -> std::path::PathBuf {
    f.dir.join("udp-instance")
}
fn open(f: &Fixture, disabled: bool) -> Arc<Owner> {
    Owner::open(&f.state, disabled, &locks(f))
}
/// Writes udp.json before the owner opens, so no default target is ever activated.
fn install(f: &Fixture, targets: Vec<Value>) -> Arc<Owner> {
    let doc = json!({"schema_version":1,"profile_id":f.id,"revision":0,"targets":targets});
    std::fs::write(f.dir.join(FILE_NAME), serde_json::to_vec(&doc).unwrap()).unwrap();
    let owner = open(f, false);
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
/// Highlight Callsign (13): the call in red on an invalid foreground, Highlight last off.
fn highlight(call: &str) -> Vec<u8> {
    let mut b = header(13, 2, "WSTX-Rust");
    put_s(&mut b, call);
    b.push(1);
    for c in [0xFFFFu16, 0xFFFF, 0, 0, 0] {
        b.extend_from_slice(&c.to_be_bytes());
    }
    b.push(0);
    for c in [0xFFFFu16, 0, 0, 0, 0] {
        b.extend_from_slice(&c.to_be_bytes());
    }
    b.push(0);
    b
}
fn halt_tx(schema: u32, id: &str) -> Vec<u8> {
    let mut b = header(8, schema, id);
    b.push(0);
    b
}
fn location(text: &str) -> Vec<u8> {
    let mut b = header(11, 2, "WSTX-Rust");
    put_s(&mut b, text);
    b
}
fn heartbeat_from_tool(schema: u32, id: &str) -> Vec<u8> {
    let mut b = header(0, schema, id);
    b.extend_from_slice(&3u32.to_be_bytes());
    put_s(&mut b, "1.24");
    put_s(&mut b, "r1");
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
            target_json(a.local_addr().unwrap(), &MESSAGES),
            target_json(b.local_addr().unwrap(), &["decode"]),
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
    assert_eq!(status_fields(&changed[0])["report"], "-7");

    // CL-112-04: a second live job on the same band sends no Clear.
    f.state.recording.fixture_live_job("ft8");
    owner.step(&f.state);
    assert!(
        kinds(&drain(&a)).iter().all(|k| *k != 3),
        "no Clear after a second live job on the same band"
    );
    assert!(drain(&b).is_empty());

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
        "configuration":{"targets":targets}});
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&put).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(kinds(&drain(&a)), [6], "Close to the disabled target");
    assert_eq!(v["status"][0]["active"], false);
    assert_eq!(v["status"][1]["active"], true, "B keeps its socket");
    owner.step(&f.state);
    assert!(drain(&a).is_empty());
}

// Proves: CL-040-03, TC-012-003. Send-only (operator 2026-11-06): no inbound message acts on
// the station; the browser and MCP are the only control paths. A target's Heartbeat alone
// negotiates the header schema.
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_003_no_inbound_message_acts_on_the_station() {
    let f = fixture("http://127.0.0.1:18402", true);
    early_in_period(&f);
    let (a, x) = (peer(), peer());
    let owner = install(&f, vec![target_json(a.local_addr().unwrap(), &MESSAGES)]);
    f.state.recording.fixture_live_job("ft8");
    let period = 1_793_536_470_000i64;
    f.state.recording.fixture_publish_period(
        &period_text(period),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    owner.step(&f.state);
    let first = drain(&a);
    assert_eq!(kinds(&first), [0, 2, 1], "Heartbeat, Decode, Status");
    let grid_before = status_fields(first.last().unwrap())["de_grid"].clone();
    f.contact().grant.store(true, Ordering::SeqCst);
    operate(
        &f,
        "enable_tx",
        json!({"enabled":true,"safety_revision":3}),
        true,
    );
    assert_eq!(arm_state(&f), ArmState::Armed);
    owner.step(&f.state);
    drain(&a);
    let halts = || {
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .service
            .view()
            .last_disarm_cause
    };
    let cause = halts();
    let contact_before = f.contact().facts().0;
    let to = station_socket(&owner, 0);
    // Every former command, from the target itself and from another host.
    for from in [&a, &x] {
        for bytes in [
            halt_tx(2, "WSTX-Rust"),
            header(3, 2, "WSTX-Rust"),
            reply(45_270_000, -12, 1235, "CQ K1ABC FN42"),
            header(6, 2, "WSTX-Rust"),
            header(7, 2, "WSTX-Rust"),
            free_text("K1ABC HB9BLA 73"),
            location("JN36AB"),
            highlight("K1ABC"),
            header(14, 2, "WSTX-Rust"),
            header(15, 2, "WSTX-Rust"),
        ] {
            from.send_to(&bytes, to).unwrap();
        }
    }
    std::thread::sleep(Duration::from_millis(30));
    owner.step(&f.state);
    assert_eq!(
        arm_state(&f),
        ArmState::Armed,
        "Halt Tx over UDP does not halt"
    );
    assert_eq!(halts(), cause, "nothing disarmed");
    // Enable Tx alone prepared the own CQ: no command changed it or named a station.
    let (revision, facts, _) = f.contact().facts();
    assert_eq!(revision, contact_before, "the contact is untouched");
    assert_eq!(facts.and_then(|c| c.dx_call), None, "no station selected");
    assert_eq!(
        contact_http::profile_facts(&f.state).1,
        grid_before.as_str().map(str::to_owned),
        "the station grid stays the profile's"
    );
    let sent = drain(&a);
    assert!(
        kinds(&sent).iter().all(|k| *k == 1),
        "no Replay: at most a Status of a window or a change, {:?}",
        kinds(&sent)
    );
    assert_eq!(
        status_fields(
            &sent
                .last()
                .cloned()
                .unwrap_or_else(|| first.last().unwrap().clone())
        )["de_grid"],
        grid_before,
        "no session grid in Status"
    );
    // UdpSnapshot carries no inbound state.
    let snap = owner.snapshot(&f.state.recording);
    let mut keys: Vec<&str> = snap
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        [
            "boot_id",
            "configuration",
            "configuration_error",
            "instance_name",
            "profile_id",
            "revision",
            "status",
            "v"
        ]
    );
    let mut keys: Vec<&str> = snap["status"][0]
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        ["active", "address", "error", "last_send_utc_ms", "schema"]
    );

    // Negotiation: only a target's own Heartbeat with this id raises the schema, a 5000-byte
    // datagram does not hold back the Heartbeat behind it, and nothing ever lowers it.
    let schema = || owner.snapshot(&f.state.recording)["status"][0]["schema"].clone();
    for (from, bytes) in [
        (&x, heartbeat_from_tool(3, "WSTX-Rust")),
        (&a, heartbeat_from_tool(3, "OTHER")),
        (&a, heartbeat_from_tool(4, "WSTX-Rust")),
        (&a, header(7, 3, "WSTX-Rust")),
        (&a, halt_tx(3, "WSTX-Rust")),
    ] {
        from.send_to(&bytes, to).unwrap();
        std::thread::sleep(Duration::from_millis(20));
        owner.step(&f.state);
        assert_eq!(schema(), json!(2), "{bytes:02x?}");
    }
    let mut big = heartbeat_from_tool(3, "WSTX-Rust");
    big.resize(5000, 0);
    a.send_to(&big, to).unwrap();
    a.send_to(&heartbeat_from_tool(3, "WSTX-Rust"), to).unwrap();
    std::thread::sleep(Duration::from_millis(30));
    drain(&a);
    owner.step(&f.state);
    assert_eq!(schema(), json!(3));
    a.send_to(&heartbeat_from_tool(2, "WSTX-Rust"), to).unwrap();
    std::thread::sleep(Duration::from_millis(20));
    owner.step(&f.state);
    assert_eq!(schema(), json!(3), "never lowered");
    // The next datagram to the target carries the negotiated schema.
    f.state.recording.fixture_publish_period(
        &period_text(period + 15_000),
        vec![record("CQ W1AW FN31", 1500.0, Some(-5.0))],
    );
    owner.step(&f.state);
    let after = drain(&a);
    assert!(after.iter().any(|b| head(b).1 == 2), "a Decode was sent");
    assert!(after.iter().all(|b| head(b).0 == 3), "schema 3");
    assert_eq!(arm_state(&f), ArmState::Armed);
}

// Proves: CL-040-02, CL-112-01, TC-012-004. A udp.json saved before send-only and while the
// instance name was a setting keeps working: the retired accept_commands and instance_name
// keys are dropped on load and gone after the next save.
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_004_a_file_saved_with_accept_commands_keeps_loading() {
    let f = fixture("http://127.0.0.1:18409", true);
    let a = peer();
    let clean = target_json(a.local_addr().unwrap(), &["heartbeat"]);
    let mut saved = clean.clone();
    saved["accept_commands"] = json!(true);
    let doc = json!({"schema_version":1,"profile_id":f.id,"revision":0,
        "instance_name":"My station","targets":[saved]});
    std::fs::write(f.dir.join(FILE_NAME), serde_json::to_vec(&doc).unwrap()).unwrap();
    let owner = open(&f, false);
    assert!(f.state.recording.udp.set(owner.clone()).is_ok());
    let snap = owner.snapshot(&f.state.recording);
    assert_eq!(snap["configuration_error"], Value::Null, "{snap}");
    assert_eq!(snap["configuration"]["targets"], json!([clean]));
    owner.step(&f.state);
    assert_eq!(kinds(&drain(&a)), [0], "the target is active");
    let body = config_body(&f, 0, json!([clean]));
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    let file = std::fs::read_to_string(f.dir.join(FILE_NAME)).unwrap();
    assert!(!file.contains("accept_commands"), "{file}");
    assert!(!file.contains("instance_name"), "{file}");
    assert_eq!(
        v["instance_name"], "WSTX-Rust",
        "the saved name is no setting"
    );
}

// Proves: CL-040-02, TC-012-004. WstxUdp::UdpHttp: the order of PUT /udp refusals: envelope keys, then
// v (unsupported_version before any field), then the fields; an injected failed write of
// udp.json is 503 storage_unavailable and changes nothing.
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_004_refusal_order_and_a_failed_write() {
    let f = fixture("http://127.0.0.1:18410", true);
    let a = peer();
    let owner = install(&f, vec![target_json(a.local_addr().unwrap(), &MESSAGES)]);
    owner.step(&f.state);
    drain(&a);
    let good = json!([target_json(a.local_addr().unwrap(), &MESSAGES)]);
    let put = |body: Value| call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap()));
    let mut invalid_target = config_body(&f, 0, json!([{"address":"0.0.0.0:1"}]));
    invalid_target["v"] = json!(2);
    let mut missing = config_body(&f, 0, good.clone());
    missing["v"] = json!(2);
    missing.as_object_mut().unwrap().remove("boot_id");
    let mut text_v = config_body(&f, 0, good.clone());
    text_v["v"] = json!("1");
    for (body, code, field) in [
        (invalid_target, "unsupported_version", json!("v")),
        (missing, "invalid_request", json!("boot_id")),
        (text_v, "invalid_request", json!("v")),
    ] {
        let (s, v) = put(body.clone()).await;
        assert_eq!(
            (s, v["error"]["code"].as_str(), v["error"]["field"].clone()),
            (StatusCode::BAD_REQUEST, Some(code), field),
            "{body}"
        );
    }
    // Test gap 2: the write of udp.json fails.
    let before = std::fs::read(f.dir.join(FILE_NAME)).unwrap();
    let snapshot = owner.snapshot(&f.state.recording);
    let socket = station_socket(&owner, 0);
    let mut changed = good.clone();
    changed[0]["messages"] = json!(["heartbeat"]);
    owner
        .fail_write
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let (s, v) = put(config_body(&f, 0, changed.clone())).await;
    assert_eq!(
        (s, v["error"]["code"].as_str()),
        (StatusCode::SERVICE_UNAVAILABLE, Some("storage_unavailable"))
    );
    assert_eq!(std::fs::read(f.dir.join(FILE_NAME)).unwrap(), before);
    let after = owner.snapshot(&f.state.recording);
    assert_eq!(
        (
            &after["revision"],
            &after["configuration"],
            &after["status"]
        ),
        (
            &snapshot["revision"],
            &snapshot["configuration"],
            &snapshot["status"]
        )
    );
    assert_eq!(station_socket(&owner, 0), socket, "the socket is kept");
    assert!(drain(&a).is_empty(), "no Close, nothing sent");
    owner
        .fail_write
        .store(false, std::sync::atomic::Ordering::SeqCst);
    let (s, v) = put(config_body(&f, 0, changed)).await;
    assert_eq!(
        (s, v["revision"].clone()),
        (StatusCode::OK, json!(1)),
        "{v}"
    );
}

fn config_body(f: &Fixture, revision: u64, targets: Value) -> Value {
    json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"expected_revision":revision,
        "configuration":{"targets":targets}})
}

// Proves: CL-040-02, TC-012-004
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_004_target_configuration_and_persistence() {
    let f = fixture("http://127.0.0.1:18403", false);
    // WSTX_UDP=off semantics: the default list is shown, no socket is opened.
    let owner = open(&f, true);
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
            json!({"targets":[{"address":"127.0.0.1:2237","enabled":true,
                "multicast_ttl":1,"multicast_interface":null,"messages":MESSAGES}]}),
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
         "messages":["decode"]},
        {"address":"239.255.0.1:2237","enabled":false,"multicast_ttl":2,"multicast_interface":"127.0.0.1",
         "messages":["logged_adif","heartbeat","status"]}]);
    let good = config_body(&f, 0, targets.clone());
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&good).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["revision"], 1);
    assert_eq!(
        v["configuration"]["targets"][1]["messages"],
        json!(["heartbeat", "status", "logged_adif"])
    );
    let saved = v["configuration"].clone();
    let reopened = open(&f, true).snapshot(&f.state.recording);
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
            "multicast_interface":null,"messages":[]})
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
                list[1]["accept_commands"] = json!(false);
                list
            },
            "targets[1]",
        ),
    ] {
        cases.push((
            config_body(&f, 1, list),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!(field),
        ));
    }
    // CL-112-01: the instance name is no setting.
    let mut named = config_body(&f, 1, targets.clone());
    named["configuration"]["instance_name"] = json!("WSTX-Rust");
    cases.push((
        named,
        StatusCode::BAD_REQUEST,
        "invalid_request",
        json!("configuration"),
    ));
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
    let broken = open(&g, false);
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
        json!([target_json(p.local_addr().unwrap(), &MESSAGES)]),
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
// Proves: CL-010-04, CL-040-01, TC-011-001, TC-012-002. #41 WstxLogbook::DirectLog: the
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
            target_json(a.local_addr().unwrap(), &["qso_logged", "logged_adif"]),
            target_json(b.local_addr().unwrap(), &["heartbeat"]),
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
            "stx":null,"stx_string":null,"srx":null,"contest_id":null,"srx_string":null,"class":null,"arrl_sect":null,"state":null,"unknown_field_count":0})
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

    // W1AW: Log QSO before completion stores it now and closes the contact (#37).
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
    assert_eq!(
        f.contact().facts().1.unwrap().state,
        "completed",
        "Log QSO closed the contact"
    );
    // The partner's later messages neither advance nor log the closed contact again.
    partner(&f, P1101 + 90_000, "HB9BLA W1AW R-05");
    partner(&f, P1101 + 120_000, "HB9BLA W1AW 73");
    assert_eq!(
        stored(&f),
        early,
        "one record per contact identity, kept as logged"
    );
    assert!(
        drain(&a).is_empty(),
        "each contact reaches the targets once"
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
    // The due retry runs in the station's contact step.
    f.contact().retry_logs_now();
    f.tick();
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
fn multicast_json(address: &str, hops: u32, interface: Value) -> Value {
    json!({"address":address,"enabled":true,"multicast_ttl":hops,"multicast_interface":interface,
        "messages":["heartbeat","status"]})
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
    let good = multicast_json(&address, 2, json!("1"));
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
    let mut org = multicast_json("[ff08::5754:5358]:2239", 1, Value::Null);
    org["enabled"] = json!(false);
    let targets = json!([
        good,
        multicast_json("[ff05::5754:5358]:2237", 255, json!("1")),
        multicast_json("[ff15::5754:5358]:2238", 1, json!("4000000000")),
        org,
    ]);
    let body = config_body(&f, 0, targets.clone());
    let (s, v) = call(&f, "PUT", "/udp", Some(serde_json::to_vec(&body).unwrap())).await;
    assert_eq!(s, StatusCode::OK, "{v}");
    assert_eq!(v["configuration"]["targets"], targets, "saved as given");
    let reopened = open(&f, true).snapshot(&f.state.recording);
    assert_eq!(reopened["configuration"]["targets"], targets);

    // An IPv6 unicast target keeps the #40 IPv4 interface form (a saved file loads).
    let mut unicast = multicast_json("[::1]:2240", 1, json!("127.0.0.1"));
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
}

// Proves: CL-040-07, TC-012-007. Status cadence as WSJT-X (MainWindow::beginDecode /
// endDecode -> updateDecodeControls -> statusUpdate; MessageClient pulse 15 s): one Status
// for each decoding toggle of the actual live-decoder signal, one for a window begun and
// ended between two steps, and the unchanged Status resent with each Heartbeat pulse; a
// target without status receives none of them. Time is deterministic: the pulse is
// reached by back-dating the stored pulse instant, never by sleeping.
#[tokio::test(flavor = "multi_thread")]
async fn tc_012_007_status_follows_each_decode_window_and_the_pulse() {
    let f = fixture("http://127.0.0.1:18409", true);
    let (a, b, c) = (peer(), peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES),
            target_json(b.local_addr().unwrap(), &["status"]),
            target_json(c.local_addr().unwrap(), &["heartbeat", "decode"]),
        ],
    );
    let r = &f.state.recording;
    let decoding = |list: &[Vec<u8>]| -> Vec<Value> {
        list.iter()
            .filter(|d| head(d).1 == 1)
            .map(|d| status_fields(d)["decoding"].clone())
            .collect()
    };
    owner.step(&f.state);
    let first = drain(&a);
    assert_eq!(kinds(&first), [0, 1], "Heartbeat then Status at activation");
    assert_eq!(decoding(&first), [json!(0)]);
    assert_eq!(kinds(&drain(&b)), [1]);
    assert_eq!(kinds(&drain(&c)), [0], "C selects no status");
    owner.step(&f.state);
    assert!(drain(&a).is_empty() && drain(&b).is_empty() && drain(&c).is_empty());

    // Two decode windows (one T/R period with its early and late window).
    for window in 0..2 {
        let busy = r.begin_window_decode();
        owner.step(&f.state);
        let at_a = drain(&a);
        assert_eq!(kinds(&at_a), [1], "window {window} begins");
        assert_eq!(decoding(&at_a), [json!(1)]);
        assert_eq!(decoding(&drain(&b)), [json!(1)]);
        owner.step(&f.state);
        assert!(drain(&a).is_empty(), "no repeat while the window decodes");
        drop(busy);
        owner.step(&f.state);
        let at_a = drain(&a);
        assert_eq!(kinds(&at_a), [1], "window {window} ends");
        assert_eq!(decoding(&at_a), [json!(0)]);
        assert_eq!(decoding(&drain(&b)), [json!(0)]);
        assert!(drain(&c).is_empty(), "C never receives a Status");
    }
    // A window begun and ended between two steps still sends one Status.
    drop(r.begin_window_decode());
    owner.step(&f.state);
    assert_eq!(decoding(&drain(&a)), [json!(0)]);
    assert_eq!(kinds(&drain(&b)), [1]);
    owner.step(&f.state);
    assert!(drain(&a).is_empty() && drain(&b).is_empty());

    let back_date = |seconds: u64| {
        let at = Instant::now()
            .checked_sub(Duration::from_secs(seconds))
            .unwrap();
        for rt in owner.lock().runtimes.iter_mut() {
            rt.pulse_at = Some(at);
        }
    };
    // 14 s after the pulse: nothing is due.
    back_date(14);
    owner.step(&f.state);
    assert!(drain(&a).is_empty() && drain(&b).is_empty() && drain(&c).is_empty());
    // 15 s: Heartbeat and the unchanged Status, byte for byte the last one sent.
    let last = owner.lock().runtimes[0].last_status.clone().unwrap();
    back_date(15);
    owner.step(&f.state);
    let pulse = drain(&a);
    assert_eq!(kinds(&pulse), [0, 1], "pulse: Heartbeat then Status");
    assert_eq!(pulse[1], last, "the Status is resent unchanged");
    assert_eq!(
        kinds(&drain(&b)),
        [1],
        "status without heartbeat is resent too"
    );
    assert_eq!(kinds(&drain(&c)), [0], "heartbeat only, no Status");
    owner.step(&f.state);
    assert!(drain(&a).is_empty() && drain(&b).is_empty() && drain(&c).is_empty());
}

// Proves: CL-010-04, TC-011-002. #10 Update logbook from ADIF sends nothing anywhere: the
// added records reach no UDP target as QSO Logged or Logged ADIF (only DirectLog and
// SaveContact send logged contacts).
#[tokio::test(flavor = "multi_thread")]
async fn tc_011_002_update_logbook_adds_records_without_any_udp_datagram() {
    let f = fixture("http://127.0.0.1:18409", false);
    let a = peer();
    let owner = install(
        &f,
        vec![target_json(
            a.local_addr().unwrap(),
            &["qso_logged", "logged_adif"],
        )],
    );
    owner.step(&f.state);
    drain(&a);
    let file = b"Log4OM export\n<PROGRAMID:7>LOG4OM2 <eoh>\n<CALL:5>K1ABC <BAND:3>20m <MODE:3>FT8 <QSO_DATE:8>20261101 <TIME_ON:6>120000 <eor>\n<CALL:6>DL1ABC <BAND:3>20m <MODE:4>MFSK <SUBMODE:3>FT4 <QSO_DATE:8>20261101 <TIME_ON:6>121000 <eor>\n";
    let sha: String = ring::digest::digest(&ring::digest::SHA256, file)
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    let id = profile::new_uuid().unwrap();
    let reserve = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"import_id":id,"total_bytes":file.len(),"sha256":sha});
    let (s, v) = call(
        &f,
        "POST",
        "/contacts/imports",
        Some(serde_json::to_vec(&reserve).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    let request = axum::http::Request::builder()
        .method("PUT")
        .uri(format!("/contacts/imports/{id}"))
        .header(header::ORIGIN, &f.origin)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(
            header::CONTENT_RANGE,
            format!("bytes 0-{}/{}", file.len() - 1, file.len()),
        )
        .body(Body::from(file.to_vec()))
        .unwrap();
    let response = f.router.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let view: Value = serde_json::from_slice(
        &axum::body::to_bytes(response.into_body(), 1 << 20)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(
        (view["added"].clone(), view["present"].clone()),
        (json!(2), json!(0)),
        "{view}"
    );
    assert_eq!(stored(&f).len(), 2);
    owner.step(&f.state);
    assert!(
        drain(&a).is_empty(),
        "no QSO Logged or Logged ADIF for updated records"
    );
}

// ------------------------------------------------------------------ #112 (CL-112-01..06)

/// The saved control of the fixture profile (no radio command).
fn control(f: &Fixture, mode: &str, endpoint: Option<&str>) {
    let mut store = f.state.store.lock().unwrap();
    store.document.control.mode = mode.into();
    store.document.control.endpoint = endpoint.map(str::to_owned);
}
/// An owner on a udp.json without targets (nothing is ever sent), its name in `root`.
fn quiet_owner(f: &Fixture, root: &std::path::Path) -> Arc<Owner> {
    let doc = json!({"schema_version":1,"profile_id":f.id,"revision":0,"targets":[]});
    std::fs::write(f.dir.join(FILE_NAME), serde_json::to_vec(&doc).unwrap()).unwrap();
    Owner::open(&f.state, false, root)
}
fn name_of(owner: &Owner, f: &Fixture) -> Value {
    owner.snapshot(&f.state.recording)["instance_name"].clone()
}
/// A native Flex fixture: the session double, set before the owner opens.
fn flex_fixture(origin: &str) -> (Fixture, Arc<wstx_rust::flex::Session>) {
    let f = fixture(origin, false);
    let session = wstx_rust::flex::Session::double();
    assert!(f.state.recording.flex.set(session.clone()).is_ok());
    (f, session)
}
fn flex_ready(session: &wstx_rust::flex::Session, letter: &str) {
    session.double_set(|s| {
        s.state = wstx_rust::flex::State::Ready;
        s.radio = Some(wstx_rust::flex::session::RadioFacts {
            model: Some("FLEX-6600".into()),
            ..Default::default()
        });
        s.slice = Some(wstx_rust::flex::session::SliceFacts {
            letter: Some(letter.into()),
            ..Default::default()
        });
    });
}

/// The lock file a `lock_holder_child` process holds, and the line it prints once it holds it.
const LOCK_HOLDER: &str = "WSTX_TEST_LOCK_HOLDER";
const LOCKED: &str = "lock-holder: locked";
/// Not a test of its own: the child process of TC-112-001 (c). It holds an exclusive lock on
/// the file LOCK_HOLDER names until it is killed (as a live server holds its name).
#[test]
#[ignore = "child process of tc_112_001_instance_name"]
fn lock_holder_child() {
    let Some(path) = std::env::var_os(LOCK_HOLDER) else {
        return;
    };
    let file = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(path)
        .unwrap();
    file.lock().unwrap();
    println!("{LOCKED}");
    // Held until killed; a parent that ends without killing it closes this pipe.
    let _ = std::io::Read::read_to_end(&mut std::io::stdin(), &mut Vec::new());
}

// Proves: CL-112-01, TC-112-001. The instance name: base forms, numbering on a clash, a
// released name taken again (dropped, and a killed process), an unusable lock folder, the name
// on every datagram and in GET /udp, no change by a radio change while running, WSTX_UDP=off
// claims nothing.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_001_instance_name() {
    let f = fixture("http://127.0.0.1:18411", false);
    let root = locks(&f);
    // (a) and (b).
    control(&f, "disabled", None);
    let plain = quiet_owner(&f, &root);
    assert_eq!(name_of(&plain, &f), "WSTX-Rust");
    control(
        &f,
        "cat",
        Some("icom7300://COM3?baud=9600&radio=94&controller=E0"),
    );
    let saved = quiet_owner(&f, &root);
    assert_eq!(name_of(&saved, &f), "WSTX-Rust - IC-7300");
    drop(saved);
    control(&f, "cat", Some("COM3"));
    let first = quiet_owner(&f, &root);
    assert_eq!(
        name_of(&first, &f),
        "WSTX-Rust - IC-7300",
        "a plain COM3 is an IC-7300; the released name is free again"
    );
    let second = quiet_owner(&f, &root);
    let third = quiet_owner(&f, &root);
    assert_eq!(name_of(&second, &f), "WSTX-Rust - IC-7300 2");
    assert_eq!(name_of(&third, &f), "WSTX-Rust - IC-7300 3");
    control(&f, "disabled", None);
    assert_eq!(name_of(&quiet_owner(&f, &root), &f), "WSTX-Rust 2");
    // (c) the first released: a new start takes the base form.
    drop(first);
    control(&f, "cat", Some("COM3"));
    let again = quiet_owner(&f, &root);
    assert_eq!(name_of(&again, &f), "WSTX-Rust - IC-7300");
    // (f) a radio change while running does not change the name.
    control(&f, "disabled", None);
    again.step(&f.state);
    assert_eq!(name_of(&again, &f), "WSTX-Rust - IC-7300");
    drop((plain, second, third, again));

    // (c) a killed process: a child process holds the base form's lock; while it lives a new
    // owner numbers, once it is killed the next owner takes the base form.
    let p = fixture("http://127.0.0.1:18424", false);
    control(&p, "cat", Some("COM3"));
    let root = locks(&p);
    std::fs::create_dir_all(&root).unwrap();
    let held = root.join("WSTX-Rust_-_IC-7300.lock");
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "udp::tests::lock_holder_child",
            "--ignored",
            "--nocapture",
            "--test-threads=1",
        ])
        .env(LOCK_HOLDER, &held)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    {
        use std::io::BufRead;
        let out = std::io::BufReader::new(child.stdout.take().unwrap());
        assert!(
            out.lines()
                .map_while(Result::ok)
                .any(|l| l.contains(LOCKED)),
            "the child holds the lock"
        );
    }
    let while_alive = quiet_owner(&p, &root);
    assert_eq!(name_of(&while_alive, &p), "WSTX-Rust - IC-7300 2");
    child.kill().unwrap();
    child.wait().unwrap();
    let after_kill = quiet_owner(&p, &root);
    assert_eq!(
        name_of(&after_kill, &p),
        "WSTX-Rust - IC-7300",
        "a killed process frees its name"
    );
    drop((while_alive, after_kill));

    // (d) an unusable lock folder (a file): the base form, the start proceeds and sends.
    let g = fixture("http://127.0.0.1:18412", false);
    control(&g, "cat", Some("COM3"));
    let a = peer();
    let doc = json!({"schema_version":1,"profile_id":g.id,"revision":0,
        "targets":[target_json(a.local_addr().unwrap(), &MESSAGES)]});
    std::fs::write(g.dir.join(FILE_NAME), serde_json::to_vec(&doc).unwrap()).unwrap();
    let unusable = g.dir.join("profile.json");
    let owner = Owner::open(&g.state, false, &unusable);
    owner.step(&g.state);
    let sent = drain(&a);
    assert_eq!(kinds(&sent), [0, 1]);
    assert_eq!(head(&sent[0]).2, "WSTX-Rust - IC-7300");
    drop(owner);

    // (e) every datagram carries the name; GET /udp shows it.
    let h = fixture("http://127.0.0.1:18413", false);
    control(&h, "cat", Some("COM3"));
    let a = peer();
    let owner = install(&h, vec![target_json(a.local_addr().unwrap(), &MESSAGES)]);
    let name = "WSTX-Rust - IC-7300";
    let (_, v) = call(&h, "GET", "/udp", None).await;
    assert_eq!(v["instance_name"], name);
    h.state
        .recording
        .fixture_operating(Some("20m"), Some(14_074_000), "manual");
    h.state.recording.fixture_live_job("ft8");
    h.state.recording.fixture_publish_period(
        &period_text(P1101),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    owner.step(&h.state);
    h.state
        .recording
        .fixture_operating(Some("40m"), Some(7_074_000), "manual");
    owner.step(&h.state);
    let saved = json!({"v":1,"profile_id":h.id,"boot_id":h.boot,"command_id":profile::new_uuid().unwrap(),
        "record":{"contact_id":profile::new_uuid().unwrap(),"call":"K1ABC","gridsquare":"FN42","mode":"FT8",
        "submode":null,"rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"123430",
        "qso_date_off":"20261101","time_off":"123615","band":null,"freq":null,
        "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":null,"comment":null}});
    let (s, v) = call(
        &h,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&saved).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{v}");
    owner.close_all();
    let all = drain(&a);
    let mut seen = kinds(&all);
    seen.sort_unstable();
    seen.dedup();
    assert_eq!(seen, [0, 1, 2, 3, 5, 6, 12], "every kind was sent");
    assert!(all.iter().all(|b| head(b).2 == name), "{:?}", kinds(&all));
    drop(owner);

    // (g) native Flex: nothing before the first ready, then the name with model and slice
    // letter, kept after a reconnect with another letter; a second Flex owner numbers.
    let (k, session) = flex_fixture("http://127.0.0.1:18414");
    let a = peer();
    let owner = install(&k, vec![target_json(a.local_addr().unwrap(), &MESSAGES)]);
    owner.step(&k.state);
    assert!(drain(&a).is_empty(), "no datagram before the first ready");
    assert_eq!(name_of(&owner, &k), Value::Null);
    session.double_set(|s| s.state = wstx_rust::flex::State::Connecting);
    owner.step(&k.state);
    assert!(drain(&a).is_empty());
    flex_ready(&session, "A");
    owner.step(&k.state);
    let sent = drain(&a);
    assert_eq!(kinds(&sent), [0, 1]);
    assert_eq!(head(&sent[0]).2, "WSTX-Rust - FLEX-6600 A");
    assert_eq!(name_of(&owner, &k), "WSTX-Rust - FLEX-6600 A");
    session.double_set(|s| s.state = wstx_rust::flex::State::Connecting);
    owner.step(&k.state);
    flex_ready(&session, "B");
    owner.step(&k.state);
    assert_eq!(
        name_of(&owner, &k),
        "WSTX-Rust - FLEX-6600 A",
        "kept after a reconnect"
    );
    let (m, other) = flex_fixture("http://127.0.0.1:18415");
    let second = quiet_owner(&m, &locks(&k));
    flex_ready(&other, "A");
    second.step(&m.state);
    assert_eq!(name_of(&second, &m), "WSTX-Rust - FLEX-6600 A 2");

    // (h) WSTX_UDP=off: no lock file is created.
    let n = fixture("http://127.0.0.1:18416", false);
    let off = open(&n, true);
    assert_eq!(name_of(&off, &n), "WSTX-Rust");
    assert!(!locks(&n).exists(), "nothing claimed");
}

// Proves: CL-112-02, TC-112-002. Status dial frequency (CAT, else the selection, else 0) and
// the report as WSJT-X QString::number writes it.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_002_status_dial_and_report() {
    let f = fixture("http://127.0.0.1:18417", false);
    let r = &f.state.recording;
    assert_eq!(status_of(&f.state, r).dial_hz, 0, "neither");
    r.fixture_operating(Some("40m"), Some(7_074_000), "manual");
    assert_eq!(status_of(&f.state, r).dial_hz, 7_074_000, "CAT unconfirmed");
    r.fixture_operating(Some("20m"), Some(14_074_000), "manual");
    // The radio double's dial is 7.074 MHz once its CAT confirms it.
    let (actor, _) = crate::radio_http_tests::actor(r.profile.clone(), r.boot.clone(), 0, false);
    r.fixture_radio(actor.clone());
    let deadline = Instant::now() + Duration::from_secs(3);
    while contact_http::confirmed_dial(r).is_none() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(
        status_of(&f.state, r).dial_hz,
        7_074_000,
        "the confirmed CAT dial wins over the selection 14074000"
    );
    actor.request_close();
    for (report, text) in [
        (-9, "-9"),
        (3, "3"),
        (0, "0"),
        (-24, "-24"),
        (49, "49"),
        (-50, "-50"),
    ] {
        operate(&f, "set_report", json!({ "report": report }), false);
        assert_eq!(status_of(&f.state, r).report, text);
    }
}

// Proves: CL-112-03, TC-112-003. Decode delta time rounded to one decimal as Band Activity
// shows it; a live record without a period start gives no Decode and is never sent later.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_003_decode_delta_time() {
    for (dt, tenths) in [
        (Some(0.04), "0.0"),
        (Some(-0.06), "-0.1"),
        (Some(0.25), "0.3"),
        (Some(-0.25), "-0.3"),
        (Some(1.349), "1.3"),
        (None, "0"),
    ] {
        assert_eq!(delta_time(dt), tenths.parse::<f32>().unwrap(), "{dt:?}");
    }
    let f = fixture("http://127.0.0.1:18418", false);
    let a = peer();
    let owner = install(&f, vec![target_json(a.local_addr().unwrap(), &["decode"])]);
    f.state.recording.fixture_live_job("ft8");
    let mut row = record("CQ K1ABC FN42", 1234.6, Some(-12.4));
    row["dt_seconds"] = json!(0.25);
    let first = f
        .state
        .recording
        .fixture_publish_period(&period_text(P1101), vec![row.clone()]);
    f.state.recording.fixture_uncorrelated(first[0]);
    owner.step(&f.state);
    assert!(drain(&a).is_empty(), "no Decode without a period start");
    f.state
        .recording
        .fixture_publish_period(&period_text(P1101 + 15_000), vec![row]);
    owner.step(&f.state);
    let sent = drain(&a);
    assert_eq!(kinds(&sent), [2], "the later correlated record, once");
    let decode = decode_fields(&sent[0]);
    assert_eq!(decode.3, f64::from("0.3".parse::<f32>().unwrap()));
    assert_eq!(decode.1, 45_285_000, "the second period");
    owner.step(&f.state);
    assert!(
        drain(&a).is_empty(),
        "the uncorrelated record is never sent"
    );
}

// Proves: CL-112-04, TC-112-004. Clear only when the operating selection's band changes.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_004_clear_on_a_band_change_only() {
    let f = fixture("http://127.0.0.1:18419", false);
    let r = &f.state.recording;
    let (a, b) = (peer(), peer());
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES),
            target_json(
                b.local_addr().unwrap(),
                &["heartbeat", "decode", "qso_logged"],
            ),
        ],
    );
    let mut period = P1101;
    let mut decoded = |owner: &Owner| {
        if r.live_identity().is_some() {
            period += 15_000;
            r.fixture_publish_period(
                &period_text(period),
                vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
            );
        }
        owner.step(&f.state);
        drain(&a);
        drain(&b);
    };
    let clears = |list: &[Vec<u8>]| kinds(list).iter().filter(|k| **k == 3).count();
    r.fixture_operating(Some("20m"), Some(14_074_000), "manual");
    r.fixture_live_job("ft8");
    decoded(&owner);
    // A band selection 20m -> 40m.
    r.fixture_operating(Some("40m"), Some(7_074_000), "manual");
    owner.step(&f.state);
    assert_eq!(clears(&drain(&a)), 1, "band selection");
    assert_eq!(clears(&drain(&b)), 0, "B does not select clear");
    // Adoption of a CAT dial on another band (ReadbackSelectionAdoption).
    decoded(&owner);
    r.fixture_operating(None, None, "manual");
    owner.step(&f.state);
    r.fixture_operating(Some("20m"), Some(14_074_000), "cat_readback");
    owner.step(&f.state);
    assert_eq!(clears(&drain(&a)), 1, "CAT readback adoption");
    // A second band change with no Decode in between.
    r.fixture_operating(Some("40m"), Some(7_074_000), "manual");
    owner.step(&f.state);
    assert_eq!(clears(&drain(&a)), 1, "without a Decode since");
    // No Clear on the same band.
    let none: [(&str, &dyn Fn()); 6] = [
        ("mode change FT8 -> FT4", &|| {
            r.fixture_live_job("ft4");
        }),
        ("receive restart", &|| {
            r.fixture_live_job("ft4");
        }),
        ("loss-only source epoch", &|| r.fixture_loss_epoch()),
        ("receive stop", &|| r.fixture_stop_live_job()),
        ("new live job", &|| {
            r.fixture_live_job("ft8");
        }),
        ("frequency within the band", &|| {
            r.fixture_operating(Some("40m"), Some(7_047_500), "manual")
        }),
    ];
    for (what, change) in none {
        decoded(&owner);
        change();
        owner.step(&f.state);
        assert_eq!(clears(&drain(&a)), 0, "{what}");
    }
}

// Proves: CL-040-01, CL-112-04. Guard of existing behaviour: decodes of a played recording are
// never sent, and no Clear goes out for them.
#[tokio::test(flavor = "multi_thread")]
async fn played_recording_sends_no_decode_and_no_clear() {
    let f = fixture("http://127.0.0.1:18420", false);
    let a = peer();
    let owner = install(&f, vec![target_json(a.local_addr().unwrap(), &MESSAGES)]);
    owner.step(&f.state);
    drain(&a);
    f.state.recording.fixture_live_job("ft8");
    f.state.recording.fixture_job_kind("recording");
    f.state.recording.fixture_publish_period(
        &period_text(P1101),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    owner.step(&f.state);
    f.state.recording.fixture_stop_live_job();
    owner.step(&f.state);
    assert!(
        kinds(&drain(&a)).iter().all(|k| *k != 2 && *k != 3),
        "no Decode and no Clear"
    );
}

/// (exchange sent, exchange received) of a QSO Logged datagram.
fn exchanges(b: &[u8]) -> (String, String) {
    let (_, kind, _, mut q) = head(b);
    assert_eq!(kind, 5);
    let _ = (q.i64(), q.u32(), q.u8());
    let _ = (q.s(), q.s(), q.u64());
    for _ in 0..6 {
        q.s();
    }
    let _ = (q.i64(), q.u32(), q.u8());
    for _ in 0..3 {
        q.s();
    }
    (q.s(), q.s())
}
/// A completed contact of `activity` with the exchanges and grid as the engine holds them.
fn contest_contact(
    activity: contact::Activity,
    grid: Option<&str>,
    sent: Option<&str>,
    rcvd: Option<&str>,
) -> contact::Contact {
    contact::Contact {
        id: profile::new_uuid().unwrap(),
        origin: contact::Origin::DecodedRow,
        mode: decoder::Mode::Ft8,
        dx_call: Some("K1ABC".into()),
        dx_grid: grid.map(str::to_owned),
        report: -12,
        report_rcvd: Some(-9),
        report_sent: Some(-12),
        exchange_sent: sent.map(str::to_owned),
        exchange_rcvd: rcvd.map(str::to_owned),
        activity,
        band: None,
        state: contact::State::Completed,
        next: contact::Slot::Tx6,
        tx4: contact::Tx4::Rr73,
        messages: Default::default(),
        started_tx1_skipped: false,
        prepared_utc_ms: P1101,
        first_tx_period: Some(P1101 + 15_000),
        first_tx2_period: Some(P1101 + 15_000),
        first_tx3_period: None,
        last_counted_end: Some(P1101 + 60_000),
        logged_on_completion: true,
        suggested: None,
        last_rcvd: None,
        dialogue: Default::default(),
        busy_with: None,
        his_last: None,
    }
}
async fn text_of(f: &Fixture, path: &str) -> String {
    let request = axum::http::Request::builder()
        .method("GET")
        .uri(path)
        .header(header::ORIGIN, &f.origin)
        .body(Body::empty())
        .unwrap();
    let response = f.router.clone().oneshot(request).await.unwrap();
    let bytes = axum::body::to_bytes(response.into_body(), 1 << 20)
        .await
        .unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

// Proves: CL-112-05, TC-112-005. QSO Logged exchanges as WSJT-X, built the same way from the
// stored record by DirectLog and SaveContact; the logged record carries its activity.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_005_qso_logged_exchanges() {
    use contact::Activity as A;
    let f = fixture("http://127.0.0.1:18421", false);
    f.state.recording.fixture_live_job("ft8");
    let a = peer();
    let owner = install(
        &f,
        vec![target_json(
            a.local_addr().unwrap(),
            &["qso_logged", "logged_adif"],
        )],
    );
    owner.step(&f.state);
    let cases = [
        (
            A::FieldDay,
            None,
            Some("1A EMA"),
            Some("2B CT"),
            "JN47AA",
            ("1A EMA", "2B CT"),
        ),
        (
            A::Rtty,
            None,
            Some("559 MA"),
            Some("579 MA"),
            "JN47AA",
            ("559 MA", "579 MA"),
        ),
        (
            A::Rtty,
            None,
            Some("559 0003"),
            Some("559 0013"),
            "JN47AA",
            ("559 0003", "559 0013"),
        ),
        (
            A::EuVhf,
            Some("IO91NP"),
            Some("550001 JN37VL"),
            Some("590003 IO91NP"),
            "JN37VL",
            ("550001 JN37VL", "590003 IO91NP"),
        ),
        (
            A::NaVhf,
            Some("FN42"),
            None,
            None,
            "JN47AA",
            ("JN47", "FN42"),
        ),
        (
            A::WwDigi,
            Some("FN42ab"),
            None,
            None,
            "JN47AA",
            ("JN47", "FN42"),
        ),
        (A::ArrlDigi, None, None, None, "JN47AA", ("JN47", "")),
        (A::Hound, Some("FN42"), None, None, "JN47AA", ("", "")),
        (A::None, Some("FN42"), None, None, "JN47AA", ("", "")),
    ];
    for (n, (activity, grid, sent, rcvd, locator, expected)) in cases.into_iter().enumerate() {
        f.state.store.lock().unwrap().document.locator = locator.into();
        let mut c = contest_contact(activity, grid, sent, rcvd);
        // #85 CL-085-01: another station each time, never the newest record's station again.
        c.dx_call = Some(format!("K{n}ABC"));
        let id = c.id.clone();
        f.contact().fixture_log(c);
        f.tick();
        let logged = drain(&a);
        assert_eq!(kinds(&logged), [5, 12], "{activity:?} DirectLog");
        let want = (expected.0.to_owned(), expected.1.to_owned());
        assert_eq!(exchanges(&logged[0]), want, "{activity:?} DirectLog");
        // The same record through SaveContact under a new contact id.
        let total = f.state.logbook.total().unwrap();
        let mut wire = f.state.logbook.history(&f.id, total - 1, 1).unwrap()["records"][0].clone();
        assert_eq!(wire["contact_id"], id.as_str());
        let saved_id = profile::new_uuid().unwrap();
        let o = wire.as_object_mut().unwrap();
        o.remove("index");
        o.remove("unknown_field_count");
        o.insert("contact_id".into(), json!(saved_id));
        if activity != A::None {
            o.insert("app_wstxrust_activity".into(), json!(activity.name()));
        }
        let body = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,
            "command_id":profile::new_uuid().unwrap(),"record":wire});
        let (s, v) = call(
            &f,
            "POST",
            "/contacts",
            Some(serde_json::to_vec(&body).unwrap()),
        )
        .await;
        assert_eq!(s, StatusCode::CREATED, "{activity:?} {v}");
        let logged = drain(&a);
        assert_eq!(exchanges(&logged[0]), want, "{activity:?} SaveContact");
        let (_, _, _, mut adif) = head(&logged[1]);
        let text = adif.s();
        if activity == A::None {
            assert!(!text.contains("app_wstxrust_activity"), "{text}");
        } else {
            let field = format!(
                "<app_wstxrust_contact_id:36>{saved_id} <app_wstxrust_activity:{}>{} <EOR>",
                activity.name().len(),
                activity.name()
            );
            assert!(text.ends_with(&field), "{text}");
        }
    }
    f.state.store.lock().unwrap().document.locator = "JN47AA".into();
    // A record without the field (an older log) has activity none: "" / "".
    let older = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),
        "record":{"contact_id":profile::new_uuid().unwrap(),"call":"K1ABC","gridsquare":"FN42","mode":"FT8",
        "submode":null,"rst_sent":"-12","rst_rcvd":"-09","qso_date":"20261101","time_on":"123430",
        "qso_date_off":"20261101","time_off":"123615","band":null,"freq":null,
        "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":null,"comment":null,
        "stx_string":"1A EMA","srx_string":"2B CT"}});
    let (s, _) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&older).unwrap()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(exchanges(&drain(&a)[0]), (String::new(), String::new()));
    // An invalid activity is refused with its field; nothing is stored.
    let total = f.state.logbook.total().unwrap();
    let mut invalid = older.clone();
    invalid["command_id"] = json!(profile::new_uuid().unwrap());
    invalid["record"]["contact_id"] = json!(profile::new_uuid().unwrap());
    invalid["record"]["app_wstxrust_activity"] = json!("contest");
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&invalid).unwrap()),
    )
    .await;
    assert_eq!(
        (s, v["error"]["code"].as_str(), v["error"]["field"].as_str()),
        (
            StatusCode::BAD_REQUEST,
            Some("log_invalid_field"),
            Some("record.app_wstxrust_activity")
        )
    );
    assert_eq!(f.state.logbook.total().unwrap(), total, "nothing stored");
    // A resave differing only in the activity: already_saved, unchanged, no datagram.
    let mut resave = older.clone();
    resave["command_id"] = json!(profile::new_uuid().unwrap());
    resave["record"]["app_wstxrust_activity"] = json!("field_day");
    let before = std::fs::read(f.dir.join(logbook::FILE_NAME)).unwrap();
    let (s, v) = call(
        &f,
        "POST",
        "/contacts",
        Some(serde_json::to_vec(&resave).unwrap()),
    )
    .await;
    assert_eq!(
        (s, v["outcome"].as_str()),
        (StatusCode::OK, Some("already_saved"))
    );
    assert_eq!(
        std::fs::read(f.dir.join(logbook::FILE_NAME)).unwrap(),
        before
    );
    assert!(drain(&a).is_empty(), "no datagram for already_saved");
    // Placement in contacts.adi and the ADI export, and the reopen.
    let stored = String::from_utf8(before).unwrap();
    assert!(
        stored.contains("<app_wstxrust_activity:6>na_vhf <eor>"),
        "after the contact id: {stored}"
    );
    let export = text_of(&f, "/contacts/export.adi").await;
    assert!(
        export.contains("<app_wstxrust_activity:6>na_vhf <eor>"),
        "{export}"
    );
    // After APP_WSTXRUST_SOURCE on a record that has one.
    let record = logbook::Record {
        contact_id: "11111111-1111-4111-8111-111111111111".into(),
        source: Some("LOG4OM2".into()),
        activity: Some("na_vhf".into()),
        ..Default::default()
    };
    assert!(record.adi_fields().ends_with(
        "<app_wstxrust_contact_id:36>11111111-1111-4111-8111-111111111111 \
         <app_wstxrust_source:7>LOG4OM2 <app_wstxrust_activity:6>na_vhf"
    ));
    let f = f.restart();
    let export = text_of(&f, "/contacts/export.adi").await;
    assert!(
        export.contains("<app_wstxrust_activity:6>na_vhf <eor>"),
        "it survives a reopen: {export}"
    );
}

// Proves: CL-112-06, TC-112-006. The exit guard: the transmit release first within its bound,
// then one Close under the instance name to each active target that selects close.
#[tokio::test(flavor = "multi_thread")]
async fn tc_112_006_close_at_shutdown() {
    let f = fixture("http://127.0.0.1:18422", true);
    let (a, b, c) = (peer(), peer(), peer());
    let mut disabled = target_json(c.local_addr().unwrap(), &MESSAGES);
    disabled["enabled"] = json!(false);
    let owner = install(
        &f,
        vec![
            target_json(a.local_addr().unwrap(), &MESSAGES),
            target_json(b.local_addr().unwrap(), &["heartbeat", "status"]),
            disabled,
            json!({"address":"[ff15::5754:5358]:2238","enabled":true,"multicast_ttl":1,
                "multicast_interface":"4000000000","messages":MESSAGES}),
        ],
    );
    owner.step(&f.state);
    drain(&a);
    drain(&b);
    assert_eq!(
        owner.snapshot(&f.state.recording)["status"][3]["error"],
        "socket_unavailable"
    );
    let mut released = None;
    exit(&f.state.recording, || {
        let at = Instant::now();
        f.state
            .recording
            .transmit
            .get()
            .unwrap()
            .emergency_release();
        released = Some((at.elapsed(), drain(&a).len()));
    });
    let (took, before) = released.expect("the release ran");
    assert!(took < Duration::from_millis(500), "{took:?}");
    assert_eq!(before, 0, "nothing was sent before the release returned");
    let sent = drain(&a);
    assert_eq!(kinds(&sent), [6], "one Close");
    assert_eq!(head(&sent[0]).2, "WSTX-Rust");
    assert!(drain(&b).is_empty() && drain(&c).is_empty());
    // A Flex server whose session was never ready sends nothing.
    let (k, _session) = flex_fixture("http://127.0.0.1:18423");
    let p = peer();
    let _owner = install(&k, vec![target_json(p.local_addr().unwrap(), &MESSAGES)]);
    exit(&k.state.recording, || {});
    assert!(drain(&p).is_empty());
}
