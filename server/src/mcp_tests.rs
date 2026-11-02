#![forbid(unsafe_code)]
// Proves: CL-012-01, CL-012-02, CL-012-03, CL-012-04; TC-020-001, TC-020-002.
// The actual station router (selected HTTPS profile with its auth-v1 owner, the contact
// engine and the #9 transmit owner thread on the recording hardware double: no audio,
// PTT or radio) and an independent MCP test client that writes the literal JSON-RPC
// messages of MCP 2026-07-28 and 2025-11-25. Expected values come from the hand-authored
// fixture rows, the fixture's own identities and the WstxMcp tables, not from MCP output.
use super::*;
use crate::contact_http_tests::{Bench, now_ms, period_text, record};
use axum::body::Body;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ring::{rand::SecureRandom, signature::KeyPair};
use std::sync::atomic::Ordering;
use tower::ServiceExt;

pub(crate) struct Mcp {
    pub(crate) app: App,
    pub(crate) state: Arc<ProfileState>,
    pub(crate) id: String,
    pub(crate) boot: String,
    pub(crate) dir: std::path::PathBuf,
    pub(crate) bench: Bench,
    /// The browser's grant transport (cookie).
    pub(crate) token: String,
    /// The MCP client token (#58), created in Settings by that browser.
    pub(crate) mcp: String,
    pub(crate) scope: authorization::WireScope,
    key: Option<ring::signature::EcdsaKeyPair>,
    gid: String,
}
pub(crate) struct Reply {
    pub(crate) status: StatusCode,
    pub(crate) headers: HeaderMap,
    pub(crate) json: Value,
}
static PORT: std::sync::atomic::AtomicU16 = std::sync::atomic::AtomicU16::new(18600);

/// A selected HTTPS profile (HB9BLA, JN47AA) whose transmit owner runs on the bench, with
/// one enrolled auth-v1 grant; `token` is that grant's current transport.
pub(crate) async fn station(transmit: bool) -> Mcp {
    let dir = std::env::temp_dir().join(format!("wstx-mcp-{}", profile::new_uuid().unwrap()));
    std::fs::create_dir(&dir).unwrap();
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let port = PORT.fetch_add(1, Ordering::SeqCst);
    let origin = format!("https://127.0.0.1:{port}");
    let mut doc = json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"MCP fixture",
        "callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":format!("127.0.0.1:{port}"),"origin":origin},
        "connection_type":"standard","audio":{"input_device":null,"output_device":null},
        "control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    if transmit {
        doc["audio"]["output_device"] = json!("fixture-output-device");
        doc["control"] = json!({"mode":"cat","endpoint":"icom7300://COM250","ptt":"cat"});
    }
    std::fs::write(dir.join("profile.json"), serde_json::to_vec(&doc).unwrap()).unwrap();
    let (mut store, _) = profile::Store::open(&dir).unwrap();
    let authority = authorization_http::Service::initialize(&mut store, &origin).unwrap();
    let recording = recording::Recording::open(&dir, id.clone(), boot.clone());
    recording.initialize_profile_revision(store.document.revision);
    let bench = Bench::default();
    bench.unsupported.store(!transmit, Ordering::SeqCst);
    let _ = recording
        .transmit
        .set(transmit_http::Station::start_with(Box::new(bench.clone())).unwrap());
    let _ = recording.contact.set(contact_http::Station::start());
    let state = Arc::new(ProfileState {
        store: Mutex::new(store),
        authorization: Mutex::new(authority),
        boot: boot.clone(),
        recording,
        logbook: Arc::new(crate::logbook::Logbook::open(&dir)),
    });
    let app = App {
        origin,
        profile: Some(state.clone()),
        profile_id: Some(id.clone()),
        token: Some("DisposableFixtureToken01234567890".into()),
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let mut f = Mcp {
        app,
        state,
        id,
        boot,
        dir,
        bench,
        token: String::new(),
        mcp: String::new(),
        scope: authorization::WireScope {
            profile_id: String::new(),
            radio_id: String::new(),
            safety_revision: 0,
        },
        key: None,
        gid: String::new(),
    };
    f.enroll().await;
    f.mcp = f.new_mcp_client("fixture agent").await.1;
    f
}
impl Drop for Mcp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}
impl Mcp {
    pub(crate) fn cookie(&self) -> String {
        format!("wstx_session_{}={}", self.id, self.token)
    }
    pub(crate) async fn http(
        &self,
        method: &str,
        uri: &str,
        headers: &[(&str, String)],
        body: Option<Vec<u8>>,
    ) -> Reply {
        let mut b = axum::http::Request::builder().method(method).uri(uri);
        for (k, v) in headers {
            b = b.header(*k, v.as_str());
        }
        let request = b.body(body.map_or_else(Body::empty, Body::from)).unwrap();
        let response = router(self.app.clone()).oneshot(request).await.unwrap();
        let status = response.status();
        let headers = response.headers().clone();
        let bytes = axum::body::to_bytes(response.into_body(), 1 << 20)
            .await
            .unwrap();
        Reply {
            status,
            headers,
            json: serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        }
    }
    /// A browser request: exact Origin and the grant transport cookie.
    pub(crate) async fn browser(&self, method: &str, uri: &str, body: Option<Value>) -> Reply {
        let mut h = vec![
            ("origin", self.app.origin.clone()),
            ("cookie", self.cookie()),
        ];
        if body.is_some() {
            h.push(("content-type", "application/json".into()));
        }
        self.http(
            method,
            uri,
            &h,
            body.map(|b| serde_json::to_vec(&b).unwrap()),
        )
        .await
    }
    /// Settings > Access & grants > MCP clients: create one with the browser's grant;
    /// returns (client_id, token).
    pub(crate) async fn new_mcp_client(&self, name: &str) -> (String, String) {
        let r = self
            .browser(
                "POST",
                "/authorization/v1/mcp-clients/create",
                Some(json!({"version":1,"name":name})),
            )
            .await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.json);
        (
            r.json["client_id"].as_str().unwrap().to_owned(),
            r.json["token"].as_str().unwrap().to_owned(),
        )
    }
    pub(crate) async fn revoke_mcp_client(&self, client_id: &str) -> Reply {
        self.browser(
            "POST",
            "/authorization/v1/mcp-clients/revoke",
            Some(json!({"version":1,"client_id":client_id})),
        )
        .await
    }
    async fn enroll(&mut self) {
        let (scope, key, gid) = self.grant().await;
        self.scope = scope;
        self.key = Some(key);
        self.gid = gid;
        self.renew().await;
    }
    /// A fresh proof of the retained key: a new transport replaces this grant's old one.
    pub(crate) async fn renew(&mut self) {
        let origin = self.app.origin.clone();
        let h = vec![
            ("origin", origin.clone()),
            ("content-type", "application/json".to_string()),
        ];
        let body = json!({"version":1,"grant_id":self.gid});
        let r = self
            .http(
                "POST",
                "/authorization/v1/challenge",
                &h,
                Some(serde_json::to_vec(&body).unwrap()),
            )
            .await;
        let nonce = r.json["nonce"].as_str().unwrap().to_owned();
        let signed = self.scope.clone().in_validated_origin(&origin).unwrap();
        let signature = authorization::authorization_tests::peer_sign(
            self.key.as_ref().unwrap(),
            &signed,
            &self.gid,
            &nonce,
            None,
        );
        let body = json!({"version":1,"grant_id":self.gid,"nonce":nonce,"signature":signature});
        let r = self
            .http(
                "POST",
                "/authorization/v1/proof",
                &h,
                Some(serde_json::to_vec(&body).unwrap()),
            )
            .await;
        assert_eq!(r.status, StatusCode::NO_CONTENT);
        let cookie = r.headers[header::SET_COOKIE].to_str().unwrap();
        self.token = cookie
            .split(';')
            .next()
            .unwrap()
            .split_once('=')
            .unwrap()
            .1
            .to_owned();
    }
    async fn grant(
        &self,
    ) -> (
        authorization::WireScope,
        ring::signature::EcdsaKeyPair,
        String,
    ) {
        let me = self;
        let origin = self.app.origin.clone();
        let base = |cookie: Option<String>| {
            let mut h = vec![
                ("origin", origin.clone()),
                ("content-type", "application/json".to_string()),
            ];
            if let Some(c) = cookie {
                h.push(("cookie", c));
            }
            h
        };
        let set_cookie = |r: &Reply| {
            r.headers[header::SET_COOKIE]
                .to_str()
                .unwrap()
                .split(';')
                .next()
                .unwrap()
                .to_owned()
        };
        let r = self
            .http(
                "POST",
                "/session",
                &base(None),
                Some(b"DisposableFixtureToken01234567890".to_vec()),
            )
            .await;
        assert_eq!(r.status, StatusCode::NO_CONTENT);
        let bootstrap = set_cookie(&r);
        let post = |path: &'static str, v: Value, c: Option<String>| {
            let h = base(c);
            async move {
                me.http("POST", path, &h, Some(serde_json::to_vec(&v).unwrap()))
                    .await
            }
        };
        let r = post(
            "/authorization/v1/bootstrap-scope",
            json!({"version":1}),
            Some(bootstrap.clone()),
        )
        .await;
        assert_eq!(r.status, StatusCode::OK);
        let scope: authorization::WireScope =
            serde_json::from_value(r.json["current_scope"].clone()).unwrap();
        let key = authorization::authorization_tests::peer_key();
        let mut gid = [0; 32];
        ring::rand::SystemRandom::new().fill(&mut gid).unwrap();
        let gid = URL_SAFE_NO_PAD.encode(gid);
        let r = post(
            "/authorization/v1/enroll",
            json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":scope,
            "grant_id":gid,"public_key":URL_SAFE_NO_PAD.encode(key.public_key().as_ref())}),
            Some(bootstrap),
        )
        .await;
        assert_eq!(r.json["outcome"], "committed", "{}", r.json);
        (scope, key, gid)
    }
    /// A modern (2026-07-28) request with its mirrored headers and the bearer.
    pub(crate) async fn modern(&self, method: &str, mut params: Value) -> Reply {
        params["_meta"] = json!({"io.modelcontextprotocol/protocolVersion":"2026-07-28",
            "io.modelcontextprotocol/clientInfo":{"name":"wstx-test-client","version":"1"},
            "io.modelcontextprotocol/clientCapabilities":{}});
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("accept", "application/json, text/event-stream".into()),
            ("authorization", format!("Bearer {}", self.mcp)),
            ("mcp-protocol-version", "2026-07-28".into()),
            ("mcp-method", method.into()),
        ];
        if let Some(name) = params["name"].as_str() {
            h.push(("mcp-name", name.into()));
        }
        let body = json!({"jsonrpc":"2.0","id":7,"method":method,"params":params});
        self.http("POST", "/mcp", &h, Some(serde_json::to_vec(&body).unwrap()))
            .await
    }
    pub(crate) async fn tool(&self, name: &str, arguments: Value) -> Value {
        let r = self
            .modern("tools/call", json!({"name":name,"arguments":arguments}))
            .await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.json);
        let result = &r.json["result"];
        assert_eq!(result["resultType"], "complete");
        // The text item is the same canonical JSON as structuredContent, not a second truth.
        let text: Value =
            serde_json::from_str(result["content"][0]["text"].as_str().unwrap()).unwrap();
        assert_eq!(text, result["structuredContent"]);
        assert_eq!(
            result["isError"],
            result["structuredContent"]["status"].as_u64().unwrap() >= 400
        );
        result["structuredContent"].clone()
    }
    pub(crate) async fn read(&self, view: &str) -> Value {
        let v = self.tool("wstx_read", json!({"view":view})).await;
        assert_eq!(v["status"], 200, "{v}");
        v["result"].clone()
    }
    pub(crate) fn command(&self, revision: u64, action: &str, extra: Value) -> Value {
        let mut b = json!({"v":1,"profile_id":self.id,"boot_id":self.boot,"command_id":profile::new_uuid().unwrap(),
            "contact_revision":revision,"action":action});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        b
    }
    /// A human action in the browser (cookie and Origin): the operator action the Tx
    /// watchdog counts from (#39). MCP requests never are one.
    pub(crate) async fn operator_present(&self) {
        let c = self.browser("GET", "/contact", None).await.json;
        let body = self.command(
            c["contact_revision"].as_u64().unwrap(),
            "set_watchdogs",
            json!({"tx_minutes":c["settings"]["tx_minutes"],"tune_seconds":c["settings"]["tune_seconds"]}),
        );
        let r = self.browser("POST", "/contact/command", Some(body)).await;
        assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    }
    pub(crate) fn tick(&self) {
        contact_http::station_tick(&self.state);
    }
    pub(crate) fn keys(&self) -> usize {
        self.bench.keys.lock().unwrap().len()
    }
}
/// A view without its per-read clock fields (monotonic_ms, utc_ms).
fn timeless(mut v: Value) -> Value {
    if let Some(o) = v.as_object_mut() {
        o.remove("monotonic_ms");
        o.remove("utc_ms");
    }
    v
}
pub(crate) fn even_period() -> i64 {
    now_ms().div_euclid(30_000) * 30_000
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_001_mcp_observes_the_browser_state_in_both_protocol_eras() {
    let f = station(true).await;
    let (source, job, generation) = f.state.recording.fixture_live_job("ft8");
    let period = even_period();
    let sequences = f.state.recording.fixture_publish_period(
        &period_text(period),
        vec![
            record("CQ K1ABC FN42", 1234.6, Some(-12.4)),
            record("CQ W1AW FN31", 900.0, Some(-3.0)),
        ],
    );
    f.tick();
    // Modern discovery and the fixed WstxMcp::ToolCatalog.
    let d = f.modern("server/discover", json!({})).await;
    assert_eq!(d.status, StatusCode::OK);
    assert_eq!(
        d.json["result"]["supportedVersions"],
        json!(["2026-07-28", "2025-11-25", "2025-06-18"])
    );
    assert_eq!(
        d.json["result"]["capabilities"],
        json!({"tools":{"listChanged":false}})
    );
    let list = f.modern("tools/list", json!({})).await;
    let names: Vec<_> = list.json["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(
        names,
        [
            "wstx_read",
            "wstx_results",
            "wstx_contact_command",
            "wstx_transmit_halt",
            "wstx_automation_command"
        ]
    );
    // Every view equals the browser's response for the same station.
    for (view, path) in [
        ("profile", "/profile"),
        ("receive", "/receive"),
        ("selection", "/receive/selection"),
        ("transmit", "/transmit"),
        ("contact", "/contact"),
        ("automation", "/automation"),
    ] {
        let browser = f.browser("GET", path, None).await;
        assert_eq!(browser.status, StatusCode::OK, "{path}: {}", browser.json);
        assert_eq!(
            timeless(f.read(view).await),
            timeless(browser.json),
            "{view}"
        );
    }
    // Same profile identity as the fixture, independently known.
    let contact = f.read("contact").await;
    assert_eq!(
        (contact["profile_id"].as_str(), contact["boot_id"].as_str()),
        (Some(f.id.as_str()), Some(f.boot.as_str()))
    );
    let automation = f.read("automation").await;
    assert_eq!(
        (
            automation["configuration"].clone(),
            automation["run"].clone()
        ),
        (Value::Null, Value::Null),
        "unconfigured, no run"
    );
    // Decoded results: the hand-authored rows, literally, and the browser's page.
    let args =
        json!({"source_id":source,"job_id":job,"generation":generation,"cursor":0,"limit":16});
    let page = f.tool("wstx_results", args).await;
    let uri = format!(
        "/receive/results?source_id={source}&job_id={job}&generation={generation}&cursor=0&limit=16"
    );
    assert_eq!(page["result"], f.browser("GET", &uri, None).await.json);
    let rows: Vec<_> = page["result"]["records"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["sequence"].as_u64().unwrap(),
                r["text"].as_str().unwrap().to_owned(),
                r["frequency_hz"].as_f64().unwrap(),
                r["snr_db"].as_f64(),
            )
        })
        .collect();
    assert_eq!(
        rows,
        vec![
            (sequences[0], "CQ K1ABC FN42".into(), 1234.6, Some(-12.4)),
            (sequences[1], "CQ W1AW FN31".into(), 900.0, Some(-3.0))
        ]
    );
    // Legacy 2025-11-25 client: initialize, initialized, then the same tools and state.
    let legacy = |body: Value, version: Option<&str>| {
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("authorization", format!("Bearer {}", f.mcp)),
        ];
        if let Some(v) = version {
            h.push(("mcp-protocol-version", v.to_string()));
        }
        let f = &f;
        async move {
            f.http("POST", "/mcp", &h, Some(serde_json::to_vec(&body).unwrap()))
                .await
        }
    };
    let init = legacy(json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25",
        "capabilities":{},"clientInfo":{"name":"legacy","version":"1"}}}), None).await;
    assert_eq!(init.json["result"]["protocolVersion"], "2025-11-25");
    assert!(
        init.headers.get("mcp-session-id").is_none(),
        "stateless: no session"
    );
    let note = legacy(
        json!({"jsonrpc":"2.0","method":"notifications/initialized"}),
        Some("2025-11-25"),
    )
    .await;
    assert_eq!(note.status, StatusCode::ACCEPTED);
    let tools = legacy(
        json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
        Some("2025-11-25"),
    )
    .await;
    assert_eq!(tools.json["result"]["tools"], list.json["result"]["tools"]);
    assert!(tools.json["result"].get("resultType").is_none());
    let call = legacy(json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"wstx_read","arguments":{"view":"profile"}}}), Some("2025-11-25")).await;
    assert_eq!(
        call.json["result"]["structuredContent"]["result"],
        f.browser("GET", "/profile", None).await.json
    );
    assert_eq!(f.keys(), 0, "observation never keys");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_002_invalid_unauthorized_and_wrong_station_requests_are_refused_before_effects() {
    let f = station(true).await;
    let other = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    let sequences = f.state.recording.fixture_publish_period(
        &period_text(even_period()),
        vec![record("CQ K1ABC FN42", 1234.6, Some(-12.4))],
    );
    f.tick();
    let before = f.read("contact").await;
    let revision = before["contact_revision"].as_u64().unwrap();
    let body = |v: &Value| Some(serde_json::to_vec(v).unwrap());
    let list = json!({"jsonrpc":"2.0","id":1,"method":"tools/list"});
    let legacy = |auth: Option<String>, extra: Vec<(&'static str, String)>| {
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("mcp-protocol-version", "2025-11-25".to_string()),
        ];
        if let Some(a) = auth {
            h.push(("authorization", a));
        }
        h.extend(extra);
        h
    };
    // Authorization: only one of this station's MCP client tokens as a bearer (#58).
    for (auth, extra, label) in [
        (None, vec![], "no credential"),
        (None, vec![("cookie", f.cookie())], "browser cookie alone"),
        (
            Some(format!("bearer {}", f.mcp)),
            vec![],
            "scheme is case-exact",
        ),
        (Some("Bearer short".into()), vec![], "malformed token"),
        (
            Some(format!("Bearer {}", URL_SAFE_NO_PAD.encode([7u8; 32]))),
            vec![],
            "unknown token",
        ),
        (
            Some(format!(
                "Bearer {}{}",
                authorization::MCP_TOKEN_PREFIX,
                URL_SAFE_NO_PAD.encode([7u8; 32])
            )),
            vec![],
            "unknown MCP client token",
        ),
        (
            Some(format!("Bearer {}", other.mcp)),
            vec![],
            "another station's MCP client",
        ),
        (
            Some(format!("Bearer {}", f.token)),
            vec![],
            "this station's own browser grant transport",
        ),
    ] {
        let r = f
            .http("POST", "/mcp", &legacy(auth, extra), body(&list))
            .await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "{label}");
        assert_eq!(
            r.headers[header::WWW_AUTHENTICATE],
            "Bearer realm=\"wstx\"",
            "{label}"
        );
        assert!(r.json.get("result").is_none(), "{label}");
    }
    // Two Authorization fields are ambiguous.
    let mut h = legacy(Some(format!("Bearer {}", f.mcp)), vec![]);
    h.push(("authorization", format!("Bearer {}", f.mcp)));
    assert_eq!(
        f.http("POST", "/mcp", &h, body(&list)).await.status,
        StatusCode::UNAUTHORIZED
    );
    // A plaintext profile has no grant authority: no MCP at all.
    let plain = crate::contact_http_tests::fixture("http://127.0.0.1:18690", true);
    let request = axum::http::Request::builder()
        .method("POST")
        .uri("/mcp")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {}", f.mcp))
        .body(Body::from(serde_json::to_vec(&list).unwrap()))
        .unwrap();
    assert_eq!(
        plain
            .router
            .clone()
            .oneshot(request)
            .await
            .unwrap()
            .status(),
        StatusCode::UNAUTHORIZED
    );
    // Origin and transport shape.
    let ok = |extra: Vec<(&'static str, String)>| legacy(Some(format!("Bearer {}", f.mcp)), extra);
    assert_eq!(
        f.http(
            "POST",
            "/mcp",
            &ok(vec![("origin", "https://evil.example".into())]),
            body(&list)
        )
        .await
        .status,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        f.http("GET", "/mcp", &ok(vec![]), None).await.status,
        StatusCode::METHOD_NOT_ALLOWED
    );
    let mut h = ok(vec![]);
    h.retain(|(k, _)| *k != "content-type");
    h.push(("content-type", "text/plain".into()));
    assert_eq!(
        f.http("POST", "/mcp", &h, body(&list)).await.status,
        StatusCode::UNSUPPORTED_MEDIA_TYPE
    );
    assert_eq!(
        f.http(
            "POST",
            "/mcp",
            &ok(vec![]),
            Some(vec![b' '; mcp::BODY_MAX + 1])
        )
        .await
        .status,
        StatusCode::PAYLOAD_TOO_LARGE
    );
    let code = |r: &Reply| r.json["error"]["code"].as_i64();
    let r = f
        .http("POST", "/mcp", &ok(vec![]), Some(b"{not json".to_vec()))
        .await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32700))
    );
    for bad in [
        json!([list]),
        json!({"jsonrpc":"1.0","id":1,"method":"tools/list"}),
        json!({"jsonrpc":"2.0","id":null,"method":"tools/list"}),
        json!({"jsonrpc":"2.0","id":1.5,"method":"tools/list"}),
        json!({"jsonrpc":"2.0","id":1,"method":"tools/list","params":[]}),
    ] {
        let r = f.http("POST", "/mcp", &ok(vec![]), body(&bad)).await;
        assert_eq!(
            (r.status, code(&r)),
            (StatusCode::BAD_REQUEST, Some(-32600)),
            "{bad}"
        );
    }
    let r = f
        .http(
            "POST",
            "/mcp",
            &legacy(Some(format!("Bearer {}", f.mcp)), vec![])
                .into_iter()
                .map(|(k, v)| {
                    if k == "mcp-protocol-version" {
                        (k, "2024-11-05".to_string())
                    } else {
                        (k, v)
                    }
                })
                .collect::<Vec<_>>(),
            body(&list),
        )
        .await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32022)),
        "unsupported legacy version"
    );
    // 2025-03-26 (which needs batches) is not offered: a legacy request without the
    // version header and the 2025-03-26 header are both refused.
    for version in [None, Some("2025-03-26")] {
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("authorization", format!("Bearer {}", f.mcp)),
        ];
        if let Some(v) = version {
            h.push(("mcp-protocol-version", v.to_string()));
        }
        let r = f.http("POST", "/mcp", &h, body(&list)).await;
        let expected = if version.is_some() { -32022 } else { -32020 };
        assert_eq!(
            (r.status, code(&r)),
            (StatusCode::BAD_REQUEST, Some(expected)),
            "{version:?}"
        );
    }
    // Modern era: version, mirrored headers, unknown method/tool.
    let modern = |version: &str,
                  header_method: &str,
                  name: Option<&str>,
                  method: &str,
                  params: Value| {
        let mut p = params;
        p["_meta"] = json!({"io.modelcontextprotocol/protocolVersion":version,"io.modelcontextprotocol/clientCapabilities":{},
            "io.modelcontextprotocol/clientInfo":{"name":"t","version":"1"}});
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("authorization", format!("Bearer {}", f.mcp)),
            ("mcp-protocol-version", "2026-07-28".to_string()),
            ("mcp-method", header_method.to_string()),
        ];
        if let Some(n) = name {
            h.push(("mcp-name", n.to_string()));
        }
        let b = json!({"jsonrpc":"2.0","id":"m","method":method,"params":p});
        let f = &f;
        async move {
            f.http("POST", "/mcp", &h, Some(serde_json::to_vec(&b).unwrap()))
                .await
        }
    };
    let r = modern("1900-01-01", "tools/list", None, "tools/list", json!({})).await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32022))
    );
    assert_eq!(
        r.json["error"]["data"],
        json!({"supported":["2026-07-28","2025-11-25","2025-06-18"],"requested":"1900-01-01"})
    );
    let r = modern("2026-07-28", "tools/call", None, "tools/list", json!({})).await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32020)),
        "Mcp-Method mismatch"
    );
    let r = modern(
        "2026-07-28",
        "tools/call",
        Some("wstx_results"),
        "tools/call",
        json!({"name":"wstx_read","arguments":{"view":"contact"}}),
    )
    .await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32020)),
        "Mcp-Name mismatch"
    );
    let r = modern(
        "2026-07-28",
        "tools/call",
        Some("=?base64?d3N0eF9yZWFk?="),
        "tools/call",
        json!({"name":"wstx_read","arguments":{"view":"contact"}}),
    )
    .await;
    assert_eq!(
        r.status,
        StatusCode::OK,
        "Base64 sentinel Mcp-Name decodes: {}",
        r.json
    );
    let r = modern(
        "2026-07-28",
        "resources/list",
        None,
        "resources/list",
        json!({}),
    )
    .await;
    assert_eq!((r.status, code(&r)), (StatusCode::NOT_FOUND, Some(-32601)));
    let r = f
        .modern("tools/call", json!({"name":"wstx_raw_ptt","arguments":{}}))
        .await;
    assert_eq!(
        (r.status, code(&r)),
        (StatusCode::BAD_REQUEST, Some(-32602)),
        "no raw/unknown tool"
    );
    // Tool argument and station refusals: tool errors with the station's own code.
    let refused = |v: &Value| {
        (
            v["status"].as_u64().unwrap(),
            v["result"]["error"]["code"].as_str().unwrap().to_owned(),
            v["result"]["error"]["field"].clone(),
        )
    };
    let v = f
        .tool("wstx_read", json!({"view":"contact","extra":1}))
        .await;
    assert_eq!(refused(&v), (400, "invalid_request".into(), json!("extra")));
    let v = f.tool("wstx_read", json!({"view":"secrets"})).await;
    assert_eq!(refused(&v), (400, "invalid_request".into(), json!("view")));
    let v = f
        .tool(
            "wstx_results",
            json!({"source_id":"x&cursor=1","job_id":"x","generation":0,"cursor":0}),
        )
        .await;
    assert_eq!(
        refused(&v),
        (400, "invalid_request".into(), json!("source_id")),
        "no query injection"
    );
    let select = |rev: u64| {
        f.command(rev, "select_row", json!({"row":{"source_id":"00000000-0000-4000-8000-000000000000","job_id":"00000000-0000-4000-8000-000000000000","generation":1,"sequence":sequences[0]},"replace":false}))
    };
    let mut wrong = select(revision);
    wrong["profile_id"] = json!(other.id);
    let v = f
        .tool("wstx_contact_command", json!({"command":wrong}))
        .await;
    assert_eq!(
        refused(&v),
        (403, "wrong_profile".into(), json!("profile_id"))
    );
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":select(revision + 1)}),
        )
        .await;
    assert_eq!(
        refused(&v),
        (409, "stale_revision".into(), json!("contact_revision"))
    );
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":f.command(revision, "key_ptt", json!({}))}),
        )
        .await;
    assert_eq!(
        refused(&v),
        (400, "invalid_request".into(), json!("action"))
    );
    let v = f
        .tool("wstx_contact_command", json!({"command":select(revision)}))
        .await;
    assert_eq!(
        refused(&v),
        (409, "row_unavailable".into(), json!("row")),
        "a row of another job"
    );
    let mut stale_boot = f.command(
        revision,
        "enable_tx",
        json!({"enabled":true,"safety_revision":3}),
    );
    stale_boot["boot_id"] = json!(other.boot);
    let v = f
        .tool("wstx_contact_command", json!({"command":stale_boot}))
        .await;
    assert_eq!(
        refused(&v),
        (409, "state_conflict".into(), json!("boot_id"))
    );
    let auto = |action: &str, extra: Value| {
        let mut b = json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap(),"action":action});
        b.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        b
    };
    let v = f.tool("wstx_automation_command", json!({"command":auto("start",json!({"expected_policy_revision":0,"expected_run_revision":0,"mode":"ft8","safety_revision":3}))})).await;
    assert_eq!(
        refused(&v),
        (409, "not_configured".into(), json!("configuration")),
        "unconfigured never starts"
    );
    let mut cfg = crate::automation_tests::config_json();
    cfg["max_contacts"] = json!(0);
    let v = f.tool("wstx_automation_command", json!({"command":auto("configure",json!({"expected_policy_revision":0,"configuration":cfg}))})).await;
    assert_eq!(
        refused(&v),
        (400, "invalid_request".into(), json!("max_contacts"))
    );
    // Nothing above changed the station or keyed.
    let after = f.read("contact").await;
    assert_eq!(after["contact_revision"], before["contact_revision"]);
    assert_eq!(after["contact"], Value::Null);
    assert_eq!(after["transmit"]["arm_state"], "disarmed");
    assert_eq!(f.read("automation").await["policy_revision"], 0);
    assert_eq!(f.keys(), 0);
    // A valid MCP Enable Tx uses this credential's grant (CL-022), once per command_id,
    // within the Tx watchdog time of the operator's last browser action (#39).
    f.operator_present().await;
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    let enable = f.command(
        revision,
        "enable_tx",
        json!({"enabled":true,"safety_revision":3}),
    );
    let first = f
        .tool("wstx_contact_command", json!({"command":enable}))
        .await;
    assert_eq!(first["status"], 202, "{first}");
    let again = f
        .tool("wstx_contact_command", json!({"command":enable}))
        .await;
    assert_eq!(
        (again["status"].clone(), again["result"].clone()),
        (json!(200), first["result"].clone()),
        "same receipt, no second effect"
    );
    let mut changed = enable.clone();
    changed["enabled"] = json!(false);
    let v = f
        .tool("wstx_contact_command", json!({"command":changed}))
        .await;
    assert_eq!(
        refused(&v),
        (409, "state_conflict".into(), json!("command_id")),
        "a reused command_id with another body"
    );
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "armed");
    let halt =
        json!({"v":1,"profile_id":f.id,"boot_id":f.boot,"command_id":profile::new_uuid().unwrap()});
    assert_eq!(
        f.tool("wstx_transmit_halt", json!({"halt":halt})).await["status"],
        202
    );
    assert_eq!(f.read("contact").await["transmit"]["arm_state"], "disarmed");
}

/// The internal MCP-principal station transport of an MCP client token: the handle the
/// in-process dispatch presents. No client ever receives it; tests use it to send an
/// MCP-principal request straight to a browser route.
fn internal_transport(f: &Mcp, token: &str) -> String {
    let mut owner = f.state.authorization.lock().unwrap();
    let service = owner.as_mut().unwrap();
    service
        .authority
        .mcp_transport(token, &f.app.origin, Instant::now())
        .unwrap()
        .0
}
/// A request presenting `value` as the station session cookie (with Origin).
async fn with_cookie(f: &Mcp, method: &str, uri: &str, value: &str, body: Option<Value>) -> Reply {
    let mut h = vec![
        ("origin", f.app.origin.clone()),
        ("cookie", format!("wstx_session_{}={value}", f.id)),
    ];
    if body.is_some() {
        h.push(("content-type", "application/json".into()));
    }
    f.http(
        method,
        uri,
        &h,
        body.map(|b| serde_json::to_vec(&b).unwrap()),
    )
    .await
}
async fn mcp_clients(f: &Mcp) -> Value {
    let r = f
        .browser("GET", "/authorization/v1/mcp-clients", None)
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(r.headers[header::CACHE_CONTROL], "no-store");
    r.json
}

// Proves: CL-012-03; TC-020-004. #58: the MCP client token is a credential of its own,
// shown once and stored hashed; it never opens a browser route or becomes a browser
// session, a browser credential never opens /mcp, every use is audited and revocation
// is immediate.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_004_the_mcp_client_token_is_separate_from_the_browser_credential() {
    let mut f = station(true).await;
    let (id, token) = f.new_mcp_client("Claude Code").await;
    assert!(
        token.starts_with("wstx_mcp_") && token.len() == 9 + 43,
        "{token}"
    );
    // Shown once: the listing has name, created and last used, never the token or hash.
    let list = mcp_clients(&f).await;
    let names: Vec<_> = list["clients"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].clone())
        .collect();
    assert_eq!(names, vec![json!("fixture agent"), json!("Claude Code")]);
    let mine = &list["clients"][1];
    assert_eq!(mine["client_id"], id.as_str());
    assert!(mine["created_utc_ms"].as_u64().unwrap() > 1_700_000_000_000);
    assert_eq!(mine["last_used_utc_ms"], Value::Null, "not used yet");
    let digest = URL_SAFE_NO_PAD.encode(ring::digest::digest(
        &ring::digest::SHA256,
        token.as_bytes(),
    ));
    let text = list.to_string();
    assert!(!text.contains(&token[9..]) && !text.contains(&digest));
    // Stored hashed: the record holds the SHA-256 of the token, never the token.
    let stored = std::fs::read_to_string(f.dir.join("authorization.json")).unwrap();
    assert!(!stored.contains(&token[9..]), "no token at rest");
    assert!(stored.contains(&digest), "its SHA-256 is kept");

    // An MCP token on browser routes is refused, as a cookie and as a bearer.
    let contact = f.browser("GET", "/contact", None).await.json;
    let revision = contact["contact_revision"].as_u64().unwrap();
    let cmd = f.command(
        revision,
        "set_frequency",
        json!({"rx_hz":1300,"tx_hz":null}),
    );
    for (method, uri, body) in [
        ("GET", "/contact", None),
        ("GET", "/profile", None),
        ("POST", "/contact/command", Some(cmd.clone())),
        ("POST", "/automation/command", Some(json!({}))),
    ] {
        let r = with_cookie(&f, method, uri, &token, body.clone()).await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "cookie {uri}");
        let mut h = vec![
            ("origin", f.app.origin.clone()),
            ("authorization", format!("Bearer {token}")),
        ];
        if body.is_some() {
            h.push(("content-type", "application/json".into()));
        }
        let r = f
            .http(
                method,
                uri,
                &h,
                body.map(|b| serde_json::to_vec(&b).unwrap()),
            )
            .await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "bearer {uri}");
    }
    assert_eq!(
        f.browser("GET", "/contact", None).await.json["contact_revision"],
        revision,
        "no effect"
    );
    // No exchange for a browser session or grant: /session, MCP client management and
    // the auth-v1 status all refuse it.
    let r = f
        .http(
            "POST",
            "/session",
            &[("origin", f.app.origin.clone())],
            Some(token.clone().into_bytes()),
        )
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED, "/session");
    assert!(r.headers.get(header::SET_COOKIE).is_none());
    for (method, uri, body) in [
        ("GET", "/authorization/v1/mcp-clients", None),
        (
            "POST",
            "/authorization/v1/mcp-clients/create",
            Some(json!({"version":1,"name":"x"})),
        ),
        (
            "POST",
            "/authorization/v1/status",
            Some(json!({"version":1})),
        ),
    ] {
        let r = with_cookie(&f, method, uri, &token, body).await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "{uri}");
    }
    // Even the internal MCP-principal transport is no browser credential for them.
    let internal = internal_transport(&f, &token);
    for (method, uri, body) in [
        ("GET", "/authorization/v1/mcp-clients", None),
        (
            "POST",
            "/authorization/v1/mcp-clients/create",
            Some(json!({"version":1,"name":"x"})),
        ),
        (
            "POST",
            "/authorization/v1/mcp-clients/revoke",
            Some(json!({"version":1,"client_id":id})),
        ),
        (
            "POST",
            "/authorization/v1/status",
            Some(json!({"version":1})),
        ),
    ] {
        let r = with_cookie(&f, method, uri, &internal, body).await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "internal {uri}");
    }
    assert_eq!(
        mcp_clients(&f).await["clients"].as_array().unwrap().len(),
        2
    );

    // A browser credential on /mcp: the cookie is never read; the grant transport or the
    // station access token as a bearer is refused with the hint to the MCP client token.
    let tools = |auth: Option<String>, cookie: Option<String>| {
        let mut h = vec![
            ("content-type", "application/json".to_string()),
            ("mcp-protocol-version", "2025-11-25".to_string()),
        ];
        if let Some(a) = auth {
            h.push(("authorization", a));
        }
        if let Some(c) = cookie {
            h.push(("cookie", c));
        }
        h
    };
    let list_body =
        serde_json::to_vec(&json!({"jsonrpc":"2.0","id":1,"method":"tools/list"})).unwrap();
    let r = f
        .http(
            "POST",
            "/mcp",
            &tools(None, Some(f.cookie())),
            Some(list_body.clone()),
        )
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    for legacy in [
        f.token.clone(),
        "DisposableFixtureToken01234567890".to_string(),
    ] {
        let r = f
            .http(
                "POST",
                "/mcp",
                &tools(Some(format!("Bearer {legacy}")), None),
                Some(list_body.clone()),
            )
            .await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED);
        assert_eq!(r.json["error"]["data"]["reason"], "mcp_token_required");
        let hint = r.json["error"]["data"]["hint"].as_str().unwrap();
        assert!(
            hint.contains("Settings") && hint.contains("MCP clients"),
            "{hint}"
        );
    }
    let bearer = tools(Some(format!("Bearer {token}")), None);
    let r = f
        .http("POST", "/mcp", &bearer, Some(list_body.clone()))
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);

    // Audit: each use with the token's name, action and time; last used is set.
    let fixture = std::mem::replace(&mut f.mcp, token.clone());
    let v = f.tool("wstx_read", json!({"view":"contact"})).await;
    assert_eq!(v["status"], 200);
    f.mcp = fixture;
    let list = mcp_clients(&f).await;
    let recent = &list["recent"][0];
    assert_eq!(
        (
            recent["name"].clone(),
            recent["action"].clone(),
            recent["status"].clone()
        ),
        (
            json!("Claude Code"),
            json!("tools/call wstx_read contact"),
            json!(200)
        )
    );
    assert!(recent["utc_ms"].as_u64().unwrap() > 1_700_000_000_000);
    assert_eq!(list["recent"][1]["action"], "tools/list");
    assert!(list["clients"][1]["last_used_utc_ms"].as_u64().is_some());
    let log = std::fs::read_to_string(f.dir.join("mcp-audit.log")).unwrap();
    let last: Value = serde_json::from_str(log.lines().last().unwrap()).unwrap();
    assert_eq!(last["action"], "tools/call wstx_read contact");
    assert_eq!(last["client_id"], id.as_str());
    assert!(!log.contains(&token[9..]), "the audit log holds no token");

    // Revocation takes effect at once: the token and its internal transport are refused.
    let r = f.revoke_mcp_client(&id).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.json);
    assert_eq!(r.json["clients"].as_array().unwrap().len(), 1);
    let r = f
        .http("POST", "/mcp", &bearer, Some(list_body.clone()))
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    assert_eq!(r.json["error"]["data"]["reason"], "mcp_token_invalid");
    assert_eq!(
        with_cookie(&f, "GET", "/contact", &internal, None)
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(f.revoke_mcp_client(&id).await.status, StatusCode::CONFLICT);
    // The other client and the browser are untouched.
    assert_eq!(f.read("profile").await["profile_id"], f.id.as_str());
    assert_eq!(
        f.browser("GET", "/contact", None).await.status,
        StatusCode::OK
    );

    // At most 8 clients; refused tokens are rate limited, a valid one never waits.
    for n in 1..8 {
        f.new_mcp_client(&format!("agent {n}")).await;
    }
    let r = f
        .browser(
            "POST",
            "/authorization/v1/mcp-clients/create",
            Some(json!({"version":1,"name":"ninth"})),
        )
        .await;
    assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS);
    let mut statuses = Vec::new();
    for _ in 0..10 {
        let r = f
            .http("POST", "/mcp", &bearer, Some(list_body.clone()))
            .await;
        statuses.push(r.status.as_u16());
    }
    // Two refusals above (the grant transport and the station access token), one after
    // the revocation, then these: the 10/60 s budget is spent at the eleventh.
    assert_eq!(statuses[..7], [401; 7]);
    assert_eq!(statuses[7..], [429; 3]);
    assert_eq!(f.read("profile").await["profile_id"], f.id.as_str());
}

// Proves: CL-039-06, CL-012-03; TC-020-004. #58: the principal comes from the
// credential, whatever route carries it: an MCP request never resets the Tx watchdog,
// also when its MCP-principal transport reaches /contact/command directly.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn tc_020_004_mcp_never_resets_the_tx_watchdog_on_any_route() {
    let f = station(true).await;
    f.state.recording.fixture_live_job("ft8");
    crate::automation_tests::at_even(&f);
    let service = &f.state.recording.transmit.get().unwrap().service;
    let spent = || service.with(|c| c.watchdog_spent());
    let advance = |ms: i64| {
        f.bench.offset.fetch_add(ms, Ordering::SeqCst);
    };
    let internal = internal_transport(&f, &f.mcp);
    let direct = |action: &'static str, extra: Value| {
        let f = &f;
        let internal = internal.clone();
        async move {
            let revision = f.browser("GET", "/contact", None).await.json["contact_revision"]
                .as_u64()
                .unwrap();
            with_cookie(
                f,
                "POST",
                "/contact/command",
                &internal,
                Some(f.command(revision, action, extra)),
            )
            .await
        }
    };
    // A browser action sets the Tx watchdog to 1 minute and starts it.
    let c = f.browser("GET", "/contact", None).await.json;
    let body = f.command(
        c["contact_revision"].as_u64().unwrap(),
        "set_watchdogs",
        json!({"tx_minutes":1,"tune_seconds":90}),
    );
    assert_eq!(
        f.browser("POST", "/contact/command", Some(body))
            .await
            .status,
        StatusCode::ACCEPTED
    );
    // MCP-principal commands at 20 s and 40 s, through the tool and straight to the
    // browser route, are accepted but never extend it.
    advance(20_000);
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":f.command(revision, "set_frequency", json!({"rx_hz":1200,"tx_hz":null}))}),
        )
        .await;
    assert_eq!(v["status"], 202, "{v}");
    advance(20_000);
    let r = direct("set_frequency", json!({"rx_hz":1250,"tx_hz":null})).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json);
    // The MCP-principal transport may not change the watchdog on the browser route.
    let r = direct("set_watchdogs", json!({"tx_minutes":99,"tune_seconds":90})).await;
    assert_eq!(r.json["error"]["code"], "operator_required", "{}", r.json);
    // The MCP token itself never reaches /contact/command (refused before any effect).
    let revision = f.browser("GET", "/contact", None).await.json["contact_revision"]
        .as_u64()
        .unwrap();
    let r = with_cookie(
        &f,
        "POST",
        "/contact/command",
        &f.mcp,
        Some(f.command(
            revision,
            "set_frequency",
            json!({"rx_hz":1300,"tx_hz":null}),
        )),
    )
    .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    advance(21_000);
    assert!(spent(), "61 s after the only browser action");
    let r = direct("enable_tx", json!({"enabled":true,"safety_revision":3})).await;
    assert_eq!(r.json["error"]["code"], "tx_watchdog", "{}", r.json);
    let revision = f.read("contact").await["contact_revision"]
        .as_u64()
        .unwrap();
    let v = f
        .tool(
            "wstx_contact_command",
            json!({"command":f.command(revision, "enable_tx", json!({"enabled":true,"safety_revision":3}))}),
        )
        .await;
    assert_eq!(v["result"]["error"]["code"], "tx_watchdog", "{v}");
    assert_eq!(f.keys(), 0);
}
