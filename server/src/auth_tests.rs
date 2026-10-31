use super::*;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use ring::{
    rand::SecureRandom,
    signature::{self, KeyPair},
};
use tower::ServiceExt;

// Proves: FR-021, FR-022; CL-005-03; TC-022-004. Independent cookie/header vectors.
#[test]
fn profile_credentials_require_one_selected_cookie_across_all_header_fields() {
    let app = App {
        origin: "https://localhost:18001".into(),
        profile: None,
        profile_id: Some("00000000-0000-4000-8000-000000000001".into()),
        token: Some("IndependentFixtureToken01234567890".into()),
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let selected = "wstx_session_00000000-0000-4000-8000-000000000001=00000000-0000-4000-8000-000000000001.IndependentFixtureToken01234567890";
    let mut headers = HeaderMap::new();
    headers.append(header::COOKIE, selected.parse().unwrap());
    assert!(
        !authenticated(&headers, &app),
        "a selected HTTPS profile never migrates a runtime-token cookie into a grant"
    );
    headers.append(header::COOKIE, selected.parse().unwrap());
    assert!(
        !authenticated(&headers, &app),
        "repeated Cookie fields must not hide a duplicate"
    );
    headers.clear();
    headers.insert(header::ORIGIN, "https://localhost:18001".parse().unwrap());
    assert!(allowed_origin(&headers, &app));
    headers.append(header::ORIGIN, "https://localhost:18002".parse().unwrap());
    assert!(!allowed_origin(&headers, &app));
}

struct HttpFixture {
    app: Option<App>,
    directory: PathBuf,
}
struct HttpReply {
    status: StatusCode,
    headers: HeaderMap,
    body: Vec<u8>,
}
impl HttpReply {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap()
    }
    fn cookie(&self) -> String {
        self.headers[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .into()
    }
}
struct BrowserGrant {
    key: signature::EcdsaKeyPair,
    id: String,
    operation: String,
    scope: authorization::WireScope,
    cookie: String,
}
impl HttpFixture {
    fn new(origin: &str) -> Self {
        let directory =
            std::env::temp_dir().join(format!("wstx-auth-http-{}", profile::new_uuid().unwrap()));
        profile::Store::create(&directory).unwrap();
        let (store, _) = profile::Store::open(&directory).unwrap();
        let app = Self::app_from_store(store, &directory, origin);
        Self {
            app: Some(app),
            directory,
        }
    }
    fn app_from_store(mut store: profile::Store, directory: &std::path::Path, origin: &str) -> App {
        let id = store.document.profile_id.clone();
        let boot = profile::new_uuid().unwrap();
        let authority = authorization_http::Service::initialize(&mut store, origin).unwrap();
        let recording = recording::Recording::open(directory, id.clone(), boot.clone());
        recording.initialize_profile_revision(store.document.revision);
        App {
            origin: origin.into(),
            profile: Some(Arc::new(ProfileState {
                store: Mutex::new(store),
                authorization: Mutex::new(authority),
                boot,
                recording,
            })),
            profile_id: Some(id),
            token: origin
                .starts_with("https://")
                .then(|| "DisposableFixtureToken01234567890".into()),
            connections: Arc::new(Semaphore::new(16)),
            login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
        }
    }
    fn reopen(&mut self) {
        let old = self.app.take().unwrap();
        let origin = old.origin.clone();
        drop(old); // Release the existing Store/UUID locks before opening again.
        let (store, _) = profile::Store::open(&self.directory).unwrap();
        self.app = Some(Self::app_from_store(store, &self.directory, &origin));
    }
    fn app(&self) -> &App {
        self.app.as_ref().unwrap()
    }
    fn headers(&self, cookie: Option<&str>) -> HeaderMap {
        let mut headers = HeaderMap::new();
        headers.insert(header::ORIGIN, self.app().origin.parse().unwrap());
        headers.insert(header::CONTENT_TYPE, "application/json".parse().unwrap());
        headers.insert(header::ACCEPT_ENCODING, "gzip".parse().unwrap());
        if let Some(cookie) = cookie {
            headers.insert(header::COOKIE, cookie.parse().unwrap());
        }
        headers
    }
    async fn request(
        &self,
        method: axum::http::Method,
        path: &str,
        body: impl Into<axum::body::Body>,
        headers: HeaderMap,
    ) -> HttpReply {
        let mut request = axum::http::Request::builder()
            .method(method)
            .uri(path)
            .body(body.into())
            .unwrap();
        *request.headers_mut() = headers;
        let response = router(self.app().clone()).oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        HttpReply {
            status: parts.status,
            headers: parts.headers,
            body: axum::body::to_bytes(body, 8192).await.unwrap().to_vec(),
        }
    }
    async fn post(&self, path: &str, value: Value, cookie: Option<&str>) -> HttpReply {
        self.request(
            axum::http::Method::POST,
            path,
            serde_json::to_vec(&value).unwrap(),
            self.headers(cookie),
        )
        .await
    }
    async fn authorize(&self) -> BrowserGrant {
        let response = self
            .request(
                axum::http::Method::POST,
                "/session",
                self.app().token.clone().unwrap(),
                self.headers(None),
            )
            .await;
        assert_eq!(response.status, StatusCode::NO_CONTENT);
        let bootstrap = response.cookie();
        assert!(bootstrap.starts_with("wstx_bootstrap_"));
        let response = self
            .post(
                "/authorization/v1/bootstrap-scope",
                json!({"version":1}),
                Some(&bootstrap),
            )
            .await;
        assert_eq!(response.status, StatusCode::OK);
        assert_eq!(response.json().as_object().unwrap().len(), 2);
        let scope: authorization::WireScope =
            serde_json::from_value(response.json()["current_scope"].clone()).unwrap();
        let key = authorization::authorization_tests::peer_key();
        let mut id = [0; 32];
        ring::rand::SystemRandom::new().fill(&mut id).unwrap();
        let id = URL_SAFE_NO_PAD.encode(id);
        let operation = profile::new_uuid().unwrap();
        let response = self.post("/authorization/v1/enroll", json!({"version":1,"operation_id":operation,"scope":scope,"grant_id":id,"public_key":URL_SAFE_NO_PAD.encode(key.public_key().as_ref())}), Some(&bootstrap)).await;
        assert_eq!(response.status, StatusCode::OK);
        assert_eq!(response.json()["outcome"], "committed");
        let mut grant = BrowserGrant {
            key,
            id,
            operation,
            scope,
            cookie: String::new(),
        };
        grant.cookie = self.renew(&grant).await;
        grant
    }
    async fn renew(&self, grant: &BrowserGrant) -> String {
        let response = self
            .post(
                "/authorization/v1/challenge",
                json!({"version":1,"grant_id":grant.id}),
                None,
            )
            .await;
        assert_eq!(response.status, StatusCode::OK);
        let challenge = response.json();
        let scope: authorization::WireScope =
            serde_json::from_value(challenge["scope"].clone()).unwrap();
        let scope = scope.in_validated_origin(&self.app().origin).unwrap();
        let nonce = challenge["nonce"].as_str().unwrap();
        let signature = authorization::authorization_tests::peer_sign(
            &grant.key, &scope, &grant.id, nonce, None,
        );
        let response = self
            .post(
                "/authorization/v1/proof",
                json!({"version":1,"grant_id":grant.id,"nonce":nonce,"signature":signature}),
                None,
            )
            .await;
        assert_eq!(response.status, StatusCode::NO_CONTENT);
        assert!(response.body.is_empty());
        response.cookie()
    }
}
impl Drop for HttpFixture {
    fn drop(&mut self) {
        self.app.take();
        std::fs::remove_dir_all(&self.directory).unwrap();
    }
}

// CL-022-01/02 replaces the old token cookie without removing ambiguity checks.
#[tokio::test]
async fn http_auth_current_grant_cookie_positive_duplicates_legacy_and_wrong_profile_negative() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let response = f
        .post(
            "/authorization/v1/status",
            json!({"version":1}),
            Some(&g.cookie),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.headers[header::CACHE_CONTROL], "no-store");
    assert!(!response.headers.contains_key(header::CONTENT_ENCODING));
    assert!(response.body.len() <= 1024);
    let value = response.json();
    assert_eq!(value.as_object().unwrap().len(), 7);
    assert_eq!(value["scope"].as_object().unwrap().len(), 3);
    assert_eq!(value["condition"], "disabled");
    assert_eq!(value["commissioned"], false);
    let mut duplicate = f.headers(Some(&g.cookie));
    duplicate.append(header::COOKIE, g.cookie.parse().unwrap());
    let response = f
        .request(
            axum::http::Method::POST,
            "/authorization/v1/status",
            r#"{"version":1}"#,
            duplicate,
        )
        .await;
    assert_eq!(response.status, StatusCode::UNAUTHORIZED);
    let old = format!(
        "{}={}.{}",
        cookie_name(f.app()),
        f.app().profile_id.as_deref().unwrap(),
        f.app().token.as_deref().unwrap()
    );
    assert_eq!(
        f.post("/authorization/v1/status", json!({"version":1}), Some(&old))
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
    let other = HttpFixture::new("https://localhost:8081");
    assert_eq!(
        other
            .post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(&g.cookie)
            )
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
}

const OPERATING_MUTATIONS: [&str; 8] = [
    "/receive/start",
    "/receive/stop",
    "/receive/select",
    "/radio/connect",
    "/radio/disconnect",
    "/radio/operation",
    "/recording/imports",
    "/recording/replay",
];

/// Actual WS handshake over a served router; returns the HTTP status line.
async fn ws_status(app: App, cookie: Option<String>) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let origin = app.origin.clone();
    let server = tokio::spawn(async move {
        axum::serve(listener, router(app)).await.unwrap();
    });
    let line = tokio::task::spawn_blocking(move || {
        use std::io::{BufRead, Write};
        let mut stream = std::net::TcpStream::connect(address).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let cookie = cookie.map_or(String::new(), |c| {
            format!(
                "Cookie: {c}
"
            )
        });
        write!(
            stream,
            "GET /ws HTTP/1.1
Host: {address}
Origin: {origin}
Connection: Upgrade
Upgrade: websocket
Sec-WebSocket-Version: 13
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Protocol: wstx.v1
{cookie}
"
        )
        .unwrap();
        let mut line = String::new();
        std::io::BufReader::new(stream)
            .read_line(&mut line)
            .unwrap();
        line
    })
    .await
    .unwrap();
    server.abort();
    line.trim_end().to_owned()
}

// Proves: CL-022-02; TC-022-007. A current grant dispatches operating HTTP/WS
// effects under the authority lock; foreign and revoked transports cannot.
#[tokio::test]
async fn http_auth_current_grant_dispatches_operating_mutations_revoked_or_foreign_cannot() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let radio_before = f.app().profile.as_ref().unwrap().recording.radio_view();
    for path in OPERATING_MUTATIONS {
        let reply = f.post(path, json!({}), Some(&g.cookie)).await;
        assert_eq!(
            reply.status,
            StatusCode::BAD_REQUEST,
            "{path} reaches dispatch validation"
        );
        assert!(
            reply
                .body
                .starts_with(br#"{"error":{"code":"invalid_request"#),
            "{path}: {}",
            String::from_utf8_lossy(&reply.body)
        );
    }
    assert_eq!(
        f.app().profile.as_ref().unwrap().recording.radio_view(),
        radio_before,
        "invalid requests cause no native radio effect"
    );
    let snapshot = f
        .request(
            axum::http::Method::GET,
            "/recording",
            Vec::new(),
            f.headers(Some(&g.cookie)),
        )
        .await;
    assert_eq!(snapshot.status, StatusCode::OK);
    let s = f.app().profile.as_ref().unwrap().recording.snapshot();
    let reserve = f
        .post(
            "/recording/imports",
            json!({"v":1,"profile_id":s["profile_id"],"boot_id":s["boot_id"],"generation":s["generation"]}),
            Some(&g.cookie),
        )
        .await;
    assert!(
        reserve.status.is_success(),
        "authorized storage mutation dispatches: {}",
        reserve.status
    );
    assert_eq!(
        f.app().profile.as_ref().unwrap().recording.snapshot()["import"]["state"],
        "reserved"
    );
    assert!(
        ws_status(f.app().clone(), Some(g.cookie.clone()))
            .await
            .starts_with("HTTP/1.1 101")
    );

    let other = HttpFixture::new("https://localhost:8081");
    let foreign = other.authorize().await;
    let foreign = format!(
        "{}={}",
        cookie_name(f.app()),
        foreign.cookie.split_once('=').unwrap().1
    );
    let response = f.post("/authorization/v1/revoke",json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":g.scope,"all_for_radio":false}),Some(&g.cookie)).await;
    assert_eq!(response.status, StatusCode::OK);
    assert!(
        response.headers[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .starts_with(&format!("{}=; ", cookie_name(f.app())))
            && response.headers[header::SET_COOKIE]
                .to_str()
                .unwrap()
                .contains("Max-Age=0"),
        "logout clears the browser transport cookie"
    );
    for cookie in [&g.cookie, &foreign] {
        for path in OPERATING_MUTATIONS {
            assert_eq!(
                f.post(path, json!({}), Some(cookie)).await.status,
                StatusCode::UNAUTHORIZED,
                "{path}"
            );
        }
        assert_eq!(
            f.request(
                axum::http::Method::GET,
                "/receive",
                Vec::new(),
                f.headers(Some(cookie))
            )
            .await
            .status,
            StatusCode::UNAUTHORIZED
        );
        assert!(
            ws_status(f.app().clone(), Some(cookie.clone()))
                .await
                .starts_with("HTTP/1.1 401")
        );
    }
}

// Proves: CL-022-01; TC-022-006. A plaintext selected profile has no grant service
// and keeps the runtime-token contract for operating HTTP routes and WS.
#[tokio::test]
async fn plaintext_profile_operating_routes_and_ws_require_runtime_token() {
    let mut f = HttpFixture::new("http://localhost:8080");
    let token = "PlaintextFixtureToken0123456789ab";
    f.app.as_mut().unwrap().token = Some(token.into());
    let good = format!("{}={}", cookie_name(f.app()), cookie_value(f.app(), token));
    let wrong = format!(
        "{}={}",
        cookie_name(f.app()),
        cookie_value(f.app(), "WrongFixtureToken0123456789abcdef")
    );
    for path in OPERATING_MUTATIONS {
        let reply = f.post(path, json!({}), Some(&good)).await;
        assert_eq!(reply.status, StatusCode::BAD_REQUEST, "{path}");
        for cookie in [None, Some(wrong.as_str())] {
            assert_eq!(
                f.post(path, json!({}), cookie).await.status,
                StatusCode::UNAUTHORIZED,
                "{path}"
            );
        }
    }
    let read = |cookie: Option<&str>| {
        f.request(
            axum::http::Method::GET,
            "/receive",
            Vec::new(),
            f.headers(cookie),
        )
    };
    assert_eq!(read(Some(&good)).await.status, StatusCode::OK);
    assert_eq!(read(None).await.status, StatusCode::UNAUTHORIZED);
    assert!(
        ws_status(f.app().clone(), Some(good.clone()))
            .await
            .starts_with("HTTP/1.1 101")
    );
    assert!(
        ws_status(f.app().clone(), None)
            .await
            .starts_with("HTTP/1.1 401")
    );
    assert!(
        ws_status(f.app().clone(), Some(wrong))
            .await
            .starts_with("HTTP/1.1 401")
    );
}

#[tokio::test]
async fn http_auth_origin_tls_precede_credentials_and_strict_body_bounds_have_no_commit() {
    let f = HttpFixture::new("https://localhost:8080");
    let committed = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let mut wrong = f.headers(None);
    wrong.insert(header::ORIGIN, "https://wrong.example".parse().unwrap());
    for path in [
        "bootstrap-scope",
        "enroll",
        "challenge",
        "proof",
        "status",
        "receipt",
        "revoke",
        "commission",
    ] {
        let reply = f
            .request(
                axum::http::Method::POST,
                &format!("/authorization/v1/{path}"),
                vec![b'x'; 1025],
                wrong.clone(),
            )
            .await;
        assert_eq!(reply.status, StatusCode::FORBIDDEN);
    }
    let response = f
        .request(
            axum::http::Method::POST,
            "/session",
            f.app().token.clone().unwrap(),
            f.headers(None),
        )
        .await;
    let bootstrap = response.cookie();
    let bodies = [
        r#"{"version":1,"version":1}"#,
        r#"{"version":1,"extra":0}"#,
        r#"{"version":1,"operation_id":null}"#,
        r#"{"version":2}"#,
        r#"{}"#,
    ];
    for body in bodies {
        assert_eq!(
            f.request(
                axum::http::Method::POST,
                "/authorization/v1/bootstrap-scope",
                body,
                f.headers(Some(&bootstrap))
            )
            .await
            .status,
            StatusCode::BAD_REQUEST
        );
    }
    let mut body = br#"{"version":1}"#.to_vec();
    body.resize(1024, b' ');
    assert_eq!(
        f.request(
            axum::http::Method::POST,
            "/authorization/v1/bootstrap-scope",
            body.clone(),
            f.headers(Some(&bootstrap))
        )
        .await
        .status,
        StatusCode::OK
    );
    body.push(b' ');
    assert_eq!(
        f.request(
            axum::http::Method::POST,
            "/authorization/v1/bootstrap-scope",
            body,
            f.headers(Some(&bootstrap))
        )
        .await
        .status,
        StatusCode::PAYLOAD_TOO_LARGE
    );
    let mut media = f.headers(Some(&bootstrap));
    media.insert(header::CONTENT_TYPE, "text/plain".parse().unwrap());
    assert_eq!(
        f.request(
            axum::http::Method::POST,
            "/authorization/v1/bootstrap-scope",
            r#"{"version":1}"#,
            media
        )
        .await
        .status,
        StatusCode::UNSUPPORTED_MEDIA_TYPE
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        committed
    );
    let plaintext = HttpFixture::new("http://localhost:8080");
    assert_eq!(
        plaintext
            .post("/authorization/v1/status", json!({"version":1}), None)
            .await
            .status,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        plaintext
            .request(
                axum::http::Method::GET,
                "/profile",
                Vec::new(),
                HeaderMap::new()
            )
            .await
            .status,
        StatusCode::OK,
        "trusted loopback configuration GET remains compatible"
    );
    assert_eq!(
        plaintext
            .request(
                axum::http::Method::GET,
                "/radio",
                Vec::new(),
                HeaderMap::new()
            )
            .await
            .status,
        StatusCode::OK,
        "trusted plaintext loopback keeps its runtime-token operating contract"
    );
    let (id, settings) = {
        let store = plaintext
            .app()
            .profile
            .as_ref()
            .unwrap()
            .store
            .lock()
            .unwrap();
        (store.document.profile_id.clone(), store.document.settings())
    };
    assert_eq!(
        plaintext
            .request(
                axum::http::Method::PUT,
                "/profile",
                serde_json::to_vec(&json!({"profile_id":id,"revision":0,"settings":settings}))
                    .unwrap(),
                plaintext.headers(None)
            )
            .await
            .status,
        StatusCode::OK,
        "trusted plaintext configuration PUT remains compatible"
    );
    assert!(
        !plaintext.directory.join("authorization.json").exists(),
        "plaintext config never creates a grant/identity record"
    );
    let malformed = f
        .request(
            axum::http::Method::PUT,
            "/profile",
            "not JSON",
            f.headers(None),
        )
        .await;
    assert_eq!(
        malformed.status,
        StatusCode::UNAUTHORIZED,
        "selected grant admission precedes malformed settings"
    );
}

#[tokio::test]
async fn http_auth_bootstrap_never_controls_receipt_proof_never_rotates_transport() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let committed = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let response = f
        .post(
            "/authorization/v1/challenge",
            json!({"version":1,"operation_id":g.operation,"scope":g.scope}),
            None,
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    let challenge = response.json();
    let nonce = challenge["nonce"].as_str().unwrap();
    let scope = g
        .scope
        .clone()
        .in_validated_origin(&f.app().origin)
        .unwrap();
    let signature = authorization::authorization_tests::peer_sign(
        &g.key,
        &scope,
        &g.id,
        nonce,
        Some(&g.operation),
    );
    let response = f.post("/authorization/v1/receipt", json!({"version":1,"operation_id":g.operation,"scope":g.scope,"grant_id":g.id,"nonce":nonce,"signature":signature}), None).await;
    assert_eq!(response.status, StatusCode::OK);
    assert!(!response.headers.contains_key(header::SET_COOKIE));
    assert_eq!(response.json()["operation_id"], g.operation);
    assert_eq!(
        f.post(
            "/authorization/v1/status",
            json!({"version":1}),
            Some(&g.cookie)
        )
        .await
        .status,
        StatusCode::OK
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        committed
    );
    let fresh = HttpFixture::new("https://localhost:8082");
    let response = fresh
        .request(
            axum::http::Method::POST,
            "/session",
            fresh.app().token.clone().unwrap(),
            fresh.headers(None),
        )
        .await;
    let bootstrap = response.cookie();
    assert_eq!(
        fresh
            .post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(&bootstrap)
            )
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
    assert!(
        !fresh
            .app()
            .profile
            .as_ref()
            .unwrap()
            .authorization
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .authority
            .record()
            .grants
            .iter()
            .any(|_| true)
    );
}

#[tokio::test]
async fn http_auth_rotation_retains_ws_grant_but_committed_revoke_fences_it() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let access = authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app())
        .unwrap()
        .unwrap();
    let context = ConnectionAuthority {
        state: f.app().profile.as_ref().unwrap().clone(),
        access: access.clone(),
    };
    let new_cookie = f.renew(&g).await;
    assert!(
        context.current(),
        "transport rotation must not revoke established WS grant context"
    );
    assert!(authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app()).is_err());
    let response = f.post("/authorization/v1/revoke",json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":g.scope,"all_for_radio":false}),Some(&new_cookie)).await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.json()["outcome"], "committed");
    assert!(!context.current());
    let state = f.app().profile.as_ref().unwrap();
    assert!(
        state
            .authorization
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .authority
            .recheck_dispatch(&access)
            .is_err()
    );
    assert_eq!(
        f.post(
            "/authorization/v1/status",
            json!({"version":1}),
            Some(&new_cookie)
        )
        .await
        .status,
        StatusCode::UNAUTHORIZED
    );
    drop(context); // release the extra owned profile lock holder before fixture cleanup.
}

// Proves: CL-022-01; TC-022-004. The 10/60 setup budget counts session/bootstrap-scope/
// enroll only; grant operations (challenge, status) neither spend nor are refused by it.
#[tokio::test]
async fn http_auth_setup_budget_counts_only_setup_calls() {
    let f = HttpFixture::new("https://localhost:8080");
    for _ in 0..9 {
        assert_eq!(
            f.request(
                axum::http::Method::POST,
                "/session",
                "wrong fixture token",
                f.headers(None)
            )
            .await
            .status,
            StatusCode::UNAUTHORIZED
        );
    }
    let unknown = json!({"version":1,"grant_id":URL_SAFE_NO_PAD.encode([3;32])});
    for _ in 0..3 {
        assert_eq!(
            f.post("/authorization/v1/challenge", unknown.clone(), None)
                .await
                .status,
            StatusCode::UNAUTHORIZED,
            "a grant operation is not a setup admission"
        );
    }
    assert_eq!(
        f.post(
            "/authorization/v1/bootstrap-scope",
            json!({"version":1}),
            None
        )
        .await
        .status,
        StatusCode::UNAUTHORIZED,
        "10th setup admission is admitted (then lacks a bootstrap cookie)"
    );
    for (path, body) in [
        ("/session", None),
        (
            "/authorization/v1/bootstrap-scope",
            Some(json!({"version":1})),
        ),
    ] {
        let status = match body {
            None => {
                f.request(
                    axum::http::Method::POST,
                    path,
                    f.app().token.clone().unwrap(),
                    f.headers(None),
                )
                .await
                .status
            }
            Some(body) => f.post(path, body, None).await.status,
        };
        assert_eq!(
            status,
            StatusCode::TOO_MANY_REQUESTS,
            "{path} beyond setup budget"
        );
    }
    assert_eq!(
        f.post("/authorization/v1/challenge", unknown, None)
            .await
            .status,
        StatusCode::UNAUTHORIZED,
        "an exhausted setup budget never refuses grant operations"
    );
}

#[tokio::test]
async fn http_auth_safety_edit_preserves_key_identity_but_advances_scope_and_clears_transport() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let (id, mut settings) = {
        let store = f.app().profile.as_ref().unwrap().store.lock().unwrap();
        (store.document.profile_id.clone(), store.document.settings())
    };
    settings.display_name = "Renamed station".into();
    let response = f
        .request(
            axum::http::Method::PUT,
            "/profile",
            serde_json::to_vec(&json!({"profile_id":id,"revision":0,"settings":settings})).unwrap(),
            f.headers(Some(&g.cookie)),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert!(
        authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app()).is_ok(),
        "non-safety edit must preserve current transport"
    );
    settings.control = profile::Control {
        mode: "cat".into(),
        endpoint: Some("fixture-cat-endpoint".into()),
        ptt: "disabled".into(),
    };
    let response = f
        .request(
            axum::http::Method::PUT,
            "/profile",
            serde_json::to_vec(&json!({"profile_id":id,"revision":1,"settings":settings})).unwrap(),
            f.headers(Some(&g.cookie)),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert!(authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app()).is_err());
    {
        let state = f.app().profile.as_ref().unwrap();
        let service = state.authorization.lock().unwrap();
        let record = service.as_ref().unwrap().authority.record();
        assert_eq!(
            record.current_scope.as_ref().unwrap().wire.radio_id,
            g.scope.radio_id
        );
        assert_eq!(
            record.current_scope.as_ref().unwrap().wire.safety_revision,
            g.scope.safety_revision + 1
        );
        assert_eq!(record.grants.len(), 1);
        assert_eq!(record.grants[0].grant_id, g.id);
        assert!(record.commissioning.is_none());
    }
    let new_cookie = f.renew(&g).await;
    let response = f
        .post(
            "/authorization/v1/status",
            json!({"version":1}),
            Some(&new_cookie),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.json()["condition"], "commissioningRequired");
    assert_eq!(response.json()["scope"]["safety_revision"], 2);
    let before = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let operation_id = profile::new_uuid().unwrap();
    let confirmed = f.post("/authorization/v1/commission",json!({"version":1,"operation_id":operation_id,"scope":response.json()["scope"],"receive_only_confirmed":true}),Some(&new_cookie)).await;
    assert_eq!(confirmed.status, StatusCode::OK);
    assert_eq!(confirmed.json()["operation_id"], operation_id);
    assert_eq!(confirmed.json()["scope"], response.json()["scope"]);
    assert_ne!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        before
    );
    let committed: authorization::Record =
        serde_json::from_slice(&std::fs::read(f.directory.join("authorization.json")).unwrap())
            .unwrap();
    assert_eq!(
        committed.commissioning.as_ref().unwrap().control,
        settings.control
    );
    assert_eq!(
        committed
            .commissioning
            .as_ref()
            .unwrap()
            .scope
            .wire
            .safety_revision,
        2
    );
}

// External route regression uses only preexisting App fields; a restored parent
// binary can be exercised without relying on a missing new Rust module/API.
#[tokio::test]
async fn http_auth_status_requires_post_and_wrong_origin_is_forbidden_before_auth() {
    let app = App {
        origin: "https://localhost:8080".into(),
        profile: None,
        profile_id: None,
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let request = axum::http::Request::builder()
        .uri("/authorization/v1/status")
        .body(axum::body::Body::empty())
        .unwrap();
    assert_eq!(
        router(app.clone()).oneshot(request).await.unwrap().status(),
        StatusCode::METHOD_NOT_ALLOWED
    );
    let request = axum::http::Request::builder()
        .method("POST")
        .uri("/authorization/v1/status")
        .header(header::ORIGIN, "https://wrong.example")
        .header(header::CONTENT_TYPE, "application/json")
        .body(axum::body::Body::from(r#"{"version":1}"#))
        .unwrap();
    assert_eq!(
        router(app).oneshot(request).await.unwrap().status(),
        StatusCode::FORBIDDEN
    );
}

#[tokio::test]
async fn http_review_revoke_wins_queued_real_profile_put_without_any_later_write() {
    use std::{
        future::Future,
        task::{Context, Poll, Waker},
    };
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let state = f.app().profile.as_ref().unwrap().clone();
    let (mut future, public_after_revoke, private_after_revoke) = {
        let mut store = state.store.lock().unwrap();
        let mut settings = store.document.settings();
        settings.display_name = "Must not commit after revoke".into();
        let body=serde_json::to_vec(&json!({"profile_id":store.document.profile_id,"revision":store.document.revision,"settings":settings})).unwrap();
        let mut future = Box::pin(put_profile(
            State(f.app().clone()),
            f.headers(Some(&g.cookie)),
            Ok(Bytes::from(body)),
        ));
        let mut context = Context::from_waker(Waker::noop());
        assert!(
            matches!(future.as_mut().poll(&mut context), Poll::Pending),
            "the real handler must queue behind the held profile writer"
        );
        // Both versions have exactly one asynchronous boundary in put_profile:
        // its spawn_blocking write. Thus the held writer is an independent barrier,
        // not a guessed sleep between preflight and commit.
        let mut owner = state.authorization.lock().unwrap();
        owner
            .as_mut()
            .unwrap()
            .authority
            .revoke(&mut store, &g.id, &profile::new_uuid().unwrap(), false)
            .unwrap();
        drop(owner);
        let public = std::fs::read(f.directory.join("profile.json")).unwrap();
        let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
        (future, public, private)
    };
    let response = tokio::time::timeout(Duration::from_secs(2), future.as_mut())
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::UNAUTHORIZED,
        "queued configuration write used revoked authority"
    );
    assert_eq!(
        std::fs::read(f.directory.join("profile.json")).unwrap(),
        public_after_revoke
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        private_after_revoke
    );
    assert_eq!(state.store.lock().unwrap().document.revision, 0);
    drop(future);
    drop(state);
}

#[tokio::test(flavor = "current_thread")]
async fn http_review_authority_wait_yields_to_heartbeat_and_cancel_then_returns_actual_grant() {
    use std::{
        future::Future,
        sync::atomic::{AtomicBool, Ordering},
        task::{Context, Poll, Waker},
    };
    for operation in ["get", "session"] {
        let f = HttpFixture::new("https://localhost:8080");
        let g = f.authorize().await;
        let state = f.app().profile.as_ref().unwrap().clone();
        let (held_tx, held_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let released = Arc::new(AtomicBool::new(false));
        let owned_released = released.clone();
        let owner = std::thread::spawn(move || {
            let guard = state.authorization.lock().unwrap();
            held_tx.send(()).unwrap();
            // External, bounded release guard: even the blocking parent cannot hang
            // this current-thread runtime/test indefinitely.
            let _ = release_rx.recv_timeout(Duration::from_millis(500));
            drop(guard);
            owned_released.store(true, Ordering::SeqCst);
        });
        held_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        let heartbeat = Arc::new(AtomicBool::new(false));
        let cancel = Arc::new(AtomicBool::new(false));
        let hb = heartbeat.clone();
        let cancellation = cancel.clone();
        let progress_started = Instant::now();
        let progress = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(10)).await;
            hb.store(true, Ordering::SeqCst);
            eprintln!(
                "diagnostic heartbeat fired at {:?}",
                progress_started.elapsed()
            );
            tokio::time::sleep(Duration::from_millis(10)).await;
            cancellation.store(true, Ordering::SeqCst);
            eprintln!(
                "diagnostic cancellation fired at {:?}",
                progress_started.elapsed()
            );
        });
        let mut pending: std::pin::Pin<Box<dyn Future<Output = Response>>> = if operation == "get" {
            Box::pin(get_profile(
                State(f.app().clone()),
                f.headers(Some(&g.cookie)),
            ))
        } else {
            Box::pin(session(
                State(f.app().clone()),
                f.headers(None),
                Ok(Bytes::from(f.app().token.clone().unwrap())),
            ))
        };
        let started = Instant::now();
        let first = pending
            .as_mut()
            .poll(&mut Context::from_waker(Waker::noop()));
        let poll_elapsed = started.elapsed();
        let initially_pending = first.is_pending();
        tokio::time::timeout(Duration::from_secs(2), progress)
            .await
            .unwrap()
            .unwrap();
        let advanced = heartbeat.load(Ordering::SeqCst) && cancel.load(Ordering::SeqCst);
        let observed_while_held = !released.load(Ordering::SeqCst);
        let second = if initially_pending {
            Some(
                pending
                    .as_mut()
                    .poll(&mut Context::from_waker(Waker::noop())),
            )
        } else {
            None
        };
        let still_pending = second.as_ref().is_some_and(Poll::is_pending);
        eprintln!(
            "diagnostic {operation} observation at {:?}: heartbeat={} cancellation={} authority_held={observed_while_held} first_poll={poll_elapsed:?}",
            progress_started.elapsed(),
            heartbeat.load(Ordering::SeqCst),
            cancel.load(Ordering::SeqCst)
        );
        let _ = release_tx.send(());
        owner.join().unwrap();
        let response = match (first, second) {
            (Poll::Ready(r), _) | (Poll::Pending, Some(Poll::Ready(r))) => r,
            (Poll::Pending, _) => tokio::time::timeout(Duration::from_secs(2), pending.as_mut())
                .await
                .unwrap(),
        };
        assert_eq!(
            response.status(),
            if operation == "get" {
                StatusCode::OK
            } else {
                StatusCode::NO_CONTENT
            },
            "contention must not become fake unauthorized"
        );
        assert!(
            advanced
                && observed_while_held
                && initially_pending
                && still_pending
                && poll_elapsed < Duration::from_millis(200),
            "{operation} blocked executor work: heartbeat/cancel={advanced}, held={observed_while_held}, first_poll={poll_elapsed:?}"
        );
        drop(pending);
    }
}

fn commission_body(g: &BrowserGrant, operation_id: &str) -> Value {
    json!({"version":1,"operation_id":operation_id,"scope":g.scope,"receive_only_confirmed":true})
}

// Proves: CL-022-02/03; TC-022-007. Literal persisted acknowledgement, not a status-only oracle.
#[tokio::test]
async fn commission_http_commits_exact_disabled_configuration_and_retained_duplicate_is_read_only()
{
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let operation = profile::new_uuid().unwrap();
    let public = std::fs::read(f.directory.join("profile.json")).unwrap();
    let prior: Value =
        serde_json::from_slice(&std::fs::read(f.directory.join("authorization.json")).unwrap())
            .unwrap();
    let access = authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app())
        .unwrap()
        .unwrap();
    let response = f
        .post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    let expected = json!({"version":1,"operation_id":operation,"scope":g.scope,"outcome":"committed","grant_id":g.id});
    assert_eq!(response.json(), expected);
    assert_eq!(response.headers[header::CACHE_CONTROL], "no-store");
    assert!(!response.headers.contains_key(header::CONTENT_ENCODING));
    assert!(response.body.len() <= 1024);
    let bytes = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let committed: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        committed["commissioning"],
        json!({"scope":prior["current_scope"],"receive_only_confirmed":true,"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}})
    );
    assert_eq!(committed["grants"], prior["grants"]);
    assert_eq!(
        committed["revocation_generation"],
        prior["revocation_generation"]
    );
    assert_eq!(committed["checked_control"], prior["checked_control"]);
    assert_eq!(committed["operation_receipts"].as_array().unwrap().len(), 2);
    assert_eq!(committed["operation_receipts"][1]["kind"], "commission");
    assert_eq!(
        committed["operation_receipts"][1]["owner_verifier"],
        prior["grants"][0]
    );
    assert_eq!(
        std::fs::read(f.directory.join("profile.json")).unwrap(),
        public
    );
    assert_eq!(
        authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app())
            .unwrap()
            .unwrap(),
        access
    );
    let duplicate = f
        .post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie),
        )
        .await;
    assert_eq!(duplicate.status, StatusCode::OK);
    assert_eq!(duplicate.json(), expected);
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        bytes
    );
    // A write checkpoint remains armed: a duplicate must bypass persistence entirely.
    let duplicate = authorization_http::commission_with_fault(
        f.app().clone(),
        f.headers(Some(&g.cookie)),
        Bytes::from(serde_json::to_vec(&commission_body(&g, &operation)).unwrap()),
        "write",
    )
    .await;
    assert_eq!(duplicate.status(), StatusCode::OK);
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        bytes
    );
    assert_eq!(
        authorization_http::operating_access(&f.headers(Some(&g.cookie)), f.app())
            .unwrap()
            .unwrap(),
        access
    );
}

// Proves: CL-022-02; TC-022-007. Each invalid request has an independent pristine fixture.
#[tokio::test]
async fn commission_http_strict_negatives_never_change_acknowledgement_or_files() {
    for case in [
        "false",
        "missing",
        "duplicate",
        "extra",
        "type",
        "scope_null",
        "scope_stale",
        "profile",
        "missing_cookie",
        "legacy_cookie",
        "duplicate_cookie",
        "wrong_origin",
        "oversize",
    ] {
        let f = HttpFixture::new("https://localhost:8080");
        let g = f.authorize().await;
        let mut value = commission_body(&g, &profile::new_uuid().unwrap());
        let mut headers = f.headers(Some(&g.cookie));
        let expected = match case {
            "false" => {
                value["receive_only_confirmed"] = json!(false);
                StatusCode::BAD_REQUEST
            }
            "missing" => {
                value
                    .as_object_mut()
                    .unwrap()
                    .remove("receive_only_confirmed");
                StatusCode::BAD_REQUEST
            }
            "extra" => {
                value["control"] = json!({"mode":"disabled"});
                StatusCode::BAD_REQUEST
            }
            "type" => {
                value["receive_only_confirmed"] = json!("true");
                StatusCode::BAD_REQUEST
            }
            "scope_null" => {
                value["scope"] = Value::Null;
                StatusCode::BAD_REQUEST
            }
            "scope_stale" => {
                value["scope"]["safety_revision"] = json!(2);
                StatusCode::CONFLICT
            }
            "profile" => {
                value["scope"]["profile_id"] = json!("00000000-0000-4000-8000-000000000099");
                StatusCode::CONFLICT
            }
            "missing_cookie" => {
                headers.remove(header::COOKIE);
                StatusCode::UNAUTHORIZED
            }
            "legacy_cookie" => {
                headers.insert(
                    header::COOKIE,
                    format!(
                        "wstx_session_{}={}.legacy",
                        g.scope.profile_id, g.scope.profile_id
                    )
                    .parse()
                    .unwrap(),
                );
                StatusCode::UNAUTHORIZED
            }
            "duplicate_cookie" => {
                headers.append(header::COOKIE, g.cookie.parse().unwrap());
                StatusCode::UNAUTHORIZED
            }
            "wrong_origin" => {
                headers.insert(header::ORIGIN, "https://wrong.example".parse().unwrap());
                StatusCode::FORBIDDEN
            }
            "oversize" => StatusCode::PAYLOAD_TOO_LARGE,
            "duplicate" => StatusCode::BAD_REQUEST,
            _ => unreachable!(),
        };
        let mut raw = serde_json::to_string(&value).unwrap();
        if case == "duplicate" {
            raw.pop();
            raw.push_str(",\"receive_only_confirmed\":true}");
        }
        if case == "oversize" {
            raw.push_str(&" ".repeat(1025));
        }
        let public = std::fs::read(f.directory.join("profile.json")).unwrap();
        let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
        let response = f
            .request(
                axum::http::Method::POST,
                "/authorization/v1/commission",
                raw,
                headers,
            )
            .await;
        assert_eq!(response.status, expected, "{case}");
        assert_eq!(
            std::fs::read(f.directory.join("profile.json")).unwrap(),
            public,
            "{case}"
        );
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            private,
            "{case}"
        );
    }
    let f = HttpFixture::new("http://localhost:8080");
    let response = f
        .post("/authorization/v1/commission", json!({}), None)
        .await;
    assert_eq!(response.status, StatusCode::FORBIDDEN);
    assert!(!f.directory.join("authorization.json").exists());
    let f = HttpFixture::new("https://localhost:8080");
    let response = f
        .request(
            axum::http::Method::POST,
            "/session",
            f.app().token.clone().unwrap(),
            f.headers(None),
        )
        .await;
    let bootstrap = response.cookie();
    let selected = f
        .app()
        .profile
        .as_ref()
        .unwrap()
        .authorization
        .lock()
        .unwrap()
        .as_ref()
        .unwrap()
        .authority
        .record()
        .current_scope
        .clone()
        .unwrap();
    let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let response = f.post("/authorization/v1/commission", json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":selected.wire,"receive_only_confirmed":true}), Some(&bootstrap)).await;
    assert_eq!(response.status, StatusCode::UNAUTHORIZED);
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        private
    );
}

// Proves: CL-022-02; only the original current owner/kind/scope can reconcile a retained ID.
#[tokio::test]
async fn commission_http_retained_id_cannot_rebind_owner_kind_or_new_safety_scope() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&g, &g.operation),
            Some(&g.cookie)
        )
        .await
        .status,
        StatusCode::CONFLICT
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        private
    );
    let operation = profile::new_uuid().unwrap();
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie)
        )
        .await
        .status,
        StatusCode::OK
    );
    let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let key = authorization::authorization_tests::peer_key();
    let mut id = [0; 32];
    ring::rand::SystemRandom::new().fill(&mut id).unwrap();
    let id = URL_SAFE_NO_PAD.encode(id);
    let second_operation = profile::new_uuid().unwrap();
    // Use the SAME enrollment core to set up the second owner without relaxing the
    // separately verified 10/60 HTTP budget merely to arrange this boundary test.
    {
        let state = f.app().profile.as_ref().unwrap();
        let mut store = state.store.lock().unwrap();
        let mut owner = state.authorization.lock().unwrap();
        owner
            .as_mut()
            .unwrap()
            .authority
            .enroll(
                &mut store,
                authorization::Verifier {
                    grant_id: id.clone(),
                    enrollment_operation_id: second_operation.clone(),
                    public_key: URL_SAFE_NO_PAD.encode(key.public_key().as_ref()),
                    scope: g
                        .scope
                        .clone()
                        .in_validated_origin(&f.app().origin)
                        .unwrap(),
                },
            )
            .unwrap();
    }
    let mut second = BrowserGrant {
        key,
        id,
        operation: second_operation,
        scope: g.scope.clone(),
        cookie: String::new(),
    };
    second.cookie = f.renew(&second).await;
    let before_refusal = std::fs::read(f.directory.join("authorization.json")).unwrap();
    assert_ne!(
        before_refusal, private,
        "second verifier setup was a real persisted enrollment"
    );
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&second, &operation),
            Some(&second.cookie)
        )
        .await
        .status,
        StatusCode::CONFLICT
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        before_refusal
    );

    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let operation = profile::new_uuid().unwrap();
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie)
        )
        .await
        .status,
        StatusCode::OK
    );
    let state = f.app().profile.as_ref().unwrap();
    {
        let mut store = state.store.lock().unwrap();
        let mut settings = store.document.settings();
        settings.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some("fixture-cat".into()),
            ptt: "disabled".into(),
        };
        store.save(settings).unwrap();
        state
            .authorization
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .authority
            .reconcile_control(&mut store)
            .unwrap();
    }
    let new_cookie = f.renew(&g).await;
    let bytes = std::fs::read(f.directory.join("authorization.json")).unwrap();
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&new_cookie)
        )
        .await
        .status,
        StatusCode::CONFLICT
    );
    let mut new_body = commission_body(&g, &operation);
    new_body["scope"]["safety_revision"] = json!(2);
    assert_eq!(
        f.post("/authorization/v1/commission", new_body, Some(&new_cookie))
            .await
            .status,
        StatusCode::CONFLICT
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        bytes
    );
}

// Proves: CL-022-02; the real queued handler cannot acknowledge after a competing commit.
#[tokio::test]
async fn commission_http_revoke_or_safety_edit_wins_queued_acknowledgement_without_writes() {
    use std::{
        future::Future,
        task::{Context, Poll, Waker},
    };
    for change in ["revoke", "configuration"] {
        let f = HttpFixture::new("https://localhost:8080");
        let g = f.authorize().await;
        let state = f.app().profile.as_ref().unwrap().clone();
        let (mut queued, public, private) = {
            let mut store = state.store.lock().unwrap();
            let mut queued = Box::pin(authorization_http::commission(
                State(f.app().clone()),
                f.headers(Some(&g.cookie)),
                axum::extract::RawQuery(None),
                Ok(Bytes::from(
                    serde_json::to_vec(&commission_body(&g, &profile::new_uuid().unwrap()))
                        .unwrap(),
                )),
            ));
            assert!(matches!(
                queued
                    .as_mut()
                    .poll(&mut Context::from_waker(Waker::noop())),
                Poll::Pending
            ));
            let mut owner = state.authorization.lock().unwrap();
            let a = &mut owner.as_mut().unwrap().authority;
            if change == "revoke" {
                a.revoke(&mut store, &g.id, &profile::new_uuid().unwrap(), false)
                    .unwrap();
            } else {
                let mut settings = store.document.settings();
                settings.control = profile::Control {
                    mode: "cat".into(),
                    endpoint: Some("fixture-cat".into()),
                    ptt: "disabled".into(),
                };
                store.save(settings).unwrap();
                a.reconcile_control(&mut store).unwrap();
            }
            (
                queued,
                std::fs::read(f.directory.join("profile.json")).unwrap(),
                std::fs::read(f.directory.join("authorization.json")).unwrap(),
            )
        };
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(2), queued.as_mut())
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED,
            "{change}"
        );
        assert_eq!(
            std::fs::read(f.directory.join("profile.json")).unwrap(),
            public
        );
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            private
        );
        drop(queued);
        drop(state);
    }
}

// Proves: CL-022-02. Both controls are valid individually; the mismatch is semantic corruption.
#[tokio::test]
async fn commission_http_corrupt_acknowledgement_watermark_is_rejected_on_save_and_reopen() {
    for field in ["commissioning", "checked_control"] {
        let mut f = HttpFixture::new("https://localhost:8080");
        let g = f.authorize().await;
        assert_eq!(
            f.post(
                "/authorization/v1/commission",
                commission_body(&g, &profile::new_uuid().unwrap()),
                Some(&g.cookie)
            )
            .await
            .status,
            StatusCode::OK
        );
        let public = std::fs::read(f.directory.join("profile.json")).unwrap();
        let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
        let mut value: Value = serde_json::from_slice(&private).unwrap();
        let different = json!({"mode":"cat","endpoint":"other-fixture-port","ptt":"disabled"});
        if field == "commissioning" {
            value["commissioning"]["control"] = different;
        } else {
            value["checked_control"] = different;
        }
        let invalid: authorization::Record = serde_json::from_value(value.clone()).unwrap();
        assert!(invalid.validate(&g.scope.profile_id).is_err());
        assert!(
            f.app()
                .profile
                .as_ref()
                .unwrap()
                .store
                .lock()
                .unwrap()
                .save_authorization(&invalid)
                .is_err()
        );
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            private
        );
        let corrupt = serde_json::to_vec(&value).unwrap();
        f.app.take();
        std::fs::write(f.directory.join("authorization.json"), &corrupt).unwrap();
        assert!(matches!(
            profile::Store::open(&f.directory),
            Err("resource_unavailable")
        ));
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            corrupt
        );
        assert_eq!(
            std::fs::read(f.directory.join("profile.json")).unwrap(),
            public
        );
    }
}

impl HttpFixture {
    async fn receipt_for(&self, g: &BrowserGrant, operation: &str) -> HttpReply {
        let challenge = self
            .post(
                "/authorization/v1/challenge",
                json!({"version":1,"operation_id":operation,"scope":g.scope}),
                None,
            )
            .await;
        if challenge.status != StatusCode::OK {
            return challenge;
        }
        let value = challenge.json();
        let nonce = value["nonce"].as_str().unwrap();
        let scope = g
            .scope
            .clone()
            .in_validated_origin(&self.app().origin)
            .unwrap();
        let signature = authorization::authorization_tests::peer_sign(
            &g.key,
            &scope,
            &g.id,
            nonce,
            Some(operation),
        );
        self.post("/authorization/v1/receipt", json!({"version":1,"operation_id":operation,"scope":g.scope,"grant_id":g.id,"nonce":nonce,"signature":signature}), None).await
    }
}

// Proves: CL-022-02; receipt-purpose proof recovers an ACK without reviving revoked control.
#[tokio::test]
async fn commission_http_read_only_receipt_survives_logout_without_mutation_replay() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let operation = profile::new_uuid().unwrap();
    let confirmed = f
        .post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie),
        )
        .await;
    assert_eq!(confirmed.status, StatusCode::OK);
    let expected = confirmed.json();
    let revoked=f.post("/authorization/v1/revoke",json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":g.scope,"all_for_radio":false}),Some(&g.cookie)).await;
    assert_eq!(revoked.status, StatusCode::OK);
    let before = std::fs::read(f.directory.join("authorization.json")).unwrap();
    let receipt = f.receipt_for(&g, &operation).await;
    assert_eq!(receipt.status, StatusCode::OK);
    assert_eq!(receipt.json(), expected);
    assert!(!receipt.headers.contains_key(header::SET_COOKIE));
    assert_eq!(
        f.post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie)
        )
        .await
        .status,
        StatusCode::UNAUTHORIZED,
        "retained receipt must not bypass current grant admission"
    );
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        before
    );
    assert!(
        f.app()
            .profile
            .as_ref()
            .unwrap()
            .authorization
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .authority
            .record()
            .grants
            .is_empty()
    );
}

// Proves: CL-022-02; the transaction and SAME production completion mapping, not Router admission.
#[tokio::test]
async fn commission_http_transaction_faults_never_ack_and_store_reopen_reads_only_committed_outcome()
 {
    for stage in [
        "write",
        "flush",
        "replace",
        "before_replace",
        "after_replace",
    ] {
        let mut f = HttpFixture::new("https://localhost:8080");
        let g = f.authorize().await;
        let operation = profile::new_uuid().unwrap();
        let public = std::fs::read(f.directory.join("profile.json")).unwrap();
        let private = std::fs::read(f.directory.join("authorization.json")).unwrap();
        let failed = authorization_http::commission_with_fault(
            f.app().clone(),
            f.headers(Some(&g.cookie)),
            Bytes::from(serde_json::to_vec(&commission_body(&g, &operation)).unwrap()),
            stage,
        )
        .await;
        assert_eq!(failed.status(), StatusCode::SERVICE_UNAVAILABLE, "{stage}");
        assert!(!failed.headers().contains_key(header::SET_COOKIE));
        assert_eq!(
            std::fs::read(f.directory.join("profile.json")).unwrap(),
            public
        );
        let committed = std::fs::read(f.directory.join("authorization.json")).unwrap();
        if stage == "after_replace" {
            assert_ne!(committed, private);
            let value: Value = serde_json::from_slice(&committed).unwrap();
            assert_eq!(value["commissioning"]["receive_only_confirmed"], true);
            assert_eq!(value["operation_receipts"][1]["operation_id"], operation);
        } else {
            assert_eq!(committed, private, "{stage}");
        }
        assert_eq!(
            f.post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(&g.cookie)
            )
            .await
            .status,
            StatusCode::SERVICE_UNAVAILABLE,
            "current process must remain quarantined after {stage}"
        );
        f.reopen(); // Store/owner reload, NOT an actual process or browser restart.
        let recovered = f.receipt_for(&g, &operation).await;
        if stage == "after_replace" {
            assert_eq!(recovered.status, StatusCode::OK);
            assert_eq!(
                recovered.json(),
                json!({"version":1,"operation_id":operation,"scope":g.scope,"outcome":"committed","grant_id":g.id})
            );
            assert!(!recovered.headers.contains_key(header::SET_COOKIE));
        } else {
            assert_eq!(
                recovered.status,
                StatusCode::CONFLICT,
                "missing receipt is unknown, never synthetic success"
            );
        }
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            committed
        );
        assert_eq!(
            f.post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(&g.cookie)
            )
            .await
            .status,
            StatusCode::UNAUTHORIZED,
            "volatile transport must not survive Store/service reopen"
        );
        let cookie = f.renew(&g).await;
        let current = f
            .post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(&cookie),
            )
            .await;
        assert_eq!(current.status, StatusCode::OK);
        assert_eq!(current.json()["commissioned"], stage == "after_replace");
        assert_eq!(
            std::fs::read(f.directory.join("authorization.json")).unwrap(),
            committed,
            "proof/receipt recovery must not recommit the mutation"
        );
    }
}

// The selected release-prefix wrapper invokes this SAME HTTP fixture and existing Rig.
#[cfg(all(test, not(debug_assertions)))]
pub(crate) async fn commission_zero_native_io_case() {
    let f = HttpFixture::new("https://localhost:8080");
    let g = f.authorize().await;
    let state = f.app().profile.as_ref().unwrap().clone();
    let revision = state.store.lock().unwrap().document.revision;
    let (actor, rig) = crate::radio_http_tests::actor(
        g.scope.profile_id.clone(),
        state.boot.clone(),
        revision,
        false,
    );
    state.recording.fixture_radio(actor.clone());
    // Suppress the fixture Actor's independent periodic refresh; reserving this
    // existing lease executes no setup/setter and creates no maintenance owner.
    let lease = actor.reserve_transition().unwrap();
    let before = {
        let r = rig.lock().unwrap();
        (
            r.writes.clone(),
            r.exchanges.clone(),
            r.setups.clone(),
            r.closed,
        )
    };
    let authority_before = actor.snapshot().unwrap().authority;
    let operation = profile::new_uuid().unwrap();
    let response = f
        .post(
            "/authorization/v1/commission",
            commission_body(&g, &operation),
            Some(&g.cookie),
        )
        .await;
    let after = {
        let r = rig.lock().unwrap();
        (
            r.writes.clone(),
            r.exchanges.clone(),
            r.setups.clone(),
            r.closed,
        )
    };
    let same = state
        .recording
        .radio_actor()
        .is_some_and(|installed| Arc::ptr_eq(&installed, &actor));
    let authority_after = actor.snapshot().unwrap().authority;
    let saved: Value =
        serde_json::from_slice(&std::fs::read(f.directory.join("authorization.json")).unwrap())
            .unwrap();
    drop(lease);
    actor.request_close();
    let deadline = Instant::now() + Duration::from_millis(250);
    while !actor.close_complete() && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(1)).await;
    }
    let released = actor.close_complete();
    let closed = rig.lock().unwrap().closed;
    drop(state);
    drop(actor);
    drop(rig);
    // Perform assertions after explicit owned release even on the pre-feature RED.
    assert!(
        released && closed,
        "owned fixture must acknowledge release within original budget"
    );
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(
        after, before,
        "confirmation itself must issue ZERO native writes/exchanges/setups/close"
    );
    assert!(same);
    assert_eq!(authority_after, authority_before);
    assert_eq!(saved["commissioning"]["receive_only_confirmed"], true);
    assert_eq!(
        saved["operation_receipts"]
            .as_array()
            .unwrap()
            .last()
            .unwrap()["operation_id"],
        operation
    );
}

// Proves: CL-022-03, CL-022-04, CL-022-05; TC-022-009. Real grant/commissioning HTTP
// flow with the independent scripted peer: automatic read-only CAT runs only under
// a matching unrevoked grant plus durable commissioning, and is cancelled by
// commissioning invalidation and last-grant revocation.
mod automatic_cat {
    use super::*;
    use crate::cat_lifecycle_tests::{Device, ENDPOINT, attach_peer};

    async fn wait_state(f: &HttpFixture, done: impl Fn(&Value) -> bool) -> Value {
        let state = f.app().profile.as_ref().unwrap().clone();
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            authorization_http::cat_tick(&state, Instant::now());
            let view = state.recording.radio_view();
            if done(&view) {
                return view;
            }
            assert!(Instant::now() < deadline, "radio did not settle: {view}");
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    }
    async fn put_control(f: &HttpFixture, cookie: &str, endpoint: &str) -> HttpReply {
        let (id, revision, mut settings) = {
            let store = f.app().profile.as_ref().unwrap().store.lock().unwrap();
            (
                store.document.profile_id.clone(),
                store.document.revision,
                store.document.settings(),
            )
        };
        settings.control = profile::Control {
            mode: "cat".into(),
            endpoint: Some(endpoint.into()),
            ptt: "disabled".into(),
        };
        f.request(
            axum::http::Method::PUT,
            "/profile",
            serde_json::to_vec(&json!({"profile_id":id,"revision":revision,"settings":settings}))
                .unwrap(),
            f.headers(Some(cookie)),
        )
        .await
    }
    async fn status(f: &HttpFixture, cookie: &str) -> Value {
        let reply = f
            .post(
                "/authorization/v1/status",
                json!({"version":1}),
                Some(cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::OK);
        assert!(reply.body.len() <= 1024);
        reply.json()
    }
    async fn commission(f: &HttpFixture, cookie: &str, scope: &Value) {
        let reply = f
            .post(
                "/authorization/v1/commission",
                json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":scope,"receive_only_confirmed":true}),
                Some(cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::OK);
    }
    fn ticks(f: &HttpFixture, n: usize) {
        let state = f.app().profile.as_ref().unwrap();
        for _ in 0..n {
            authorization_http::cat_tick(state, Instant::now());
        }
    }

    #[tokio::test]
    async fn grant_and_commissioning_gate_every_native_effect_and_revocation_releases() {
        let f = HttpFixture::new("https://localhost:8080");
        let state = f.app().profile.as_ref().unwrap().clone();
        let peer = attach_peer(&state.recording, Device::Present);
        ticks(&f, 20);
        let g = f.authorize().await;
        assert_eq!(
            put_control(&f, &g.cookie, ENDPOINT).await.status,
            StatusCode::OK
        );
        // No commissioning yet: zero native open/query/setter/PTT.
        let cookie = f.renew(&g).await;
        ticks(&f, 20);
        let before = status(&f, &cookie).await;
        assert_eq!(before["condition"], "commissioningRequired");
        assert_eq!(before["commissioned"], false);
        assert_eq!(peer.lock().unwrap().opens, 0);
        assert!(peer.lock().unwrap().writes.is_empty());
        // Confirmation itself has no native effect; the next tick attempts once.
        commission(&f, &cookie, &before["scope"]).await;
        assert_eq!(peer.lock().unwrap().opens, 0);
        let ready = wait_state(&f, |v| v["state"] == "ready").await;
        assert_eq!(ready["observation"]["frequency_hz"], 7_074_000);
        let current = status(&f, &cookie).await;
        assert_eq!(current["condition"], "ready");
        assert_eq!(current["commissioned"], true);
        assert_eq!(current["error"], Value::Null);
        // Session, CAT and audio/decoder remain separate lanes.
        assert_eq!(current["receive_state"]["audio"], "closed");
        assert_eq!(current["receive_state"]["decoder"], Value::Null);
        assert_eq!(peer.lock().unwrap().opens, 1);
        // Review F1: a non-safety edit is a new key; before the next tick the status
        // reports waiting, never the previous connection's ready/fresh readback.
        let (id, revision, mut settings) = {
            let store = state.store.lock().unwrap();
            (
                store.document.profile_id.clone(),
                store.document.revision,
                store.document.settings(),
            )
        };
        settings.display_name = "Renamed station".into();
        let reply = f
            .request(
                axum::http::Method::PUT,
                "/profile",
                serde_json::to_vec(
                    &json!({"profile_id":id,"revision":revision,"settings":settings}),
                )
                .unwrap(),
                f.headers(Some(&cookie)),
            )
            .await;
        assert_eq!(reply.status, StatusCode::OK);
        let renamed = status(&f, &cookie).await;
        assert_eq!(renamed["condition"], "waitingForDevice");
        assert_eq!(renamed["retry_after_ms"], Value::Null);
        wait_state(&f, |v| v["state"] == "ready").await;
        assert_eq!(peer.lock().unwrap().opens, 2);
        // Endpoint edit advances the safety revision and invalidates commissioning:
        // the lifecycle cancels and releases; no reopen until re-confirmation.
        assert_eq!(
            put_control(
                &f,
                &cookie,
                "icom7300://COM4?baud=9600&radio=94&controller=E0"
            )
            .await
            .status,
            StatusCode::OK
        );
        wait_state(&f, |v| v["state"] == "closed").await;
        assert!(peer.lock().unwrap().closes >= 1);
        ticks(&f, 40);
        assert_eq!(peer.lock().unwrap().opens, 2);
        let cookie = f.renew(&g).await;
        let changed = status(&f, &cookie).await;
        assert_eq!(changed["condition"], "commissioningRequired");
        commission(&f, &cookie, &changed["scope"]).await;
        wait_state(&f, |v| v["state"] == "ready").await;
        assert_eq!(peer.lock().unwrap().opens, 3);
        // Last-grant revocation (logout) cancels the lifecycle and releases the owner.
        let reply = f
            .post(
                "/authorization/v1/revoke",
                json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":changed["scope"],"all_for_radio":false}),
                Some(&cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::OK);
        wait_state(&f, |v| v["state"] == "closed").await;
        let writes = peer.lock().unwrap().writes.len();
        ticks(&f, 40);
        assert_eq!(peer.lock().unwrap().opens, 3);
        assert_eq!(peer.lock().unwrap().writes.len(), writes);
        let queries: [&[u8]; 5] = [&[3], &[4], &[0x1a, 6], &[0x1c, 0], &[0x0f]];
        for w in &peer.lock().unwrap().writes {
            assert!(
                queries.contains(&&w[4..w.len() - 1]),
                "non-query frame {w:02x?}"
            );
        }
    }

    #[tokio::test]
    async fn status_reports_retry_reason_and_never_fresh_frequency_while_unavailable() {
        let f = HttpFixture::new("https://localhost:8080");
        let state = f.app().profile.as_ref().unwrap().clone();
        let peer = attach_peer(&state.recording, Device::Absent);
        let g = f.authorize().await;
        assert_eq!(
            put_control(&f, &g.cookie, ENDPOINT).await.status,
            StatusCode::OK
        );
        let cookie = f.renew(&g).await;
        let scope = status(&f, &cookie).await["scope"].clone();
        commission(&f, &cookie, &scope).await;
        wait_state(&f, |v| v["state"] == "unavailable").await;
        ticks(&f, 1);
        let value = status(&f, &cookie).await;
        assert_eq!(value["condition"], "retryWaiting");
        assert_eq!(value["error"], "radio_unavailable");
        let retry = value["retry_after_ms"].as_u64().unwrap();
        assert!((1..=1000).contains(&retry), "{retry}");
        let selection = state.recording.selection_snapshot(true).unwrap();
        assert_eq!(selection["radio"]["state"], "unavailable");
        assert_eq!(
            selection["radio"]["observations"]["frequency"]["confirmed"],
            false
        );
        assert_eq!(peer.lock().unwrap().opens, 1);
    }

    #[tokio::test]
    async fn deprecated_connect_and_disconnect_validate_then_refuse_with_zero_io() {
        let f = HttpFixture::new("https://localhost:8080");
        let state = f.app().profile.as_ref().unwrap().clone();
        let peer = attach_peer(&state.recording, Device::Present);
        let g = f.authorize().await;
        assert_eq!(
            put_control(&f, &g.cookie, ENDPOINT).await.status,
            StatusCode::OK
        );
        let cookie = f.renew(&g).await;
        let view = state.recording.radio_view();
        let (profile_id, boot_id) = (view["profile_id"].clone(), view["boot_id"].clone());
        let revision = state.store.lock().unwrap().document.revision;
        for verified in [true, false] {
            let reply = f
                .post(
                    "/radio/connect",
                    json!({"v":1,"profile_id":profile_id,"boot_id":boot_id,"profile_revision":revision,"receive_only_verified":verified}),
                    Some(&cookie),
                )
                .await;
            assert_eq!(reply.status, StatusCode::CONFLICT);
            assert_eq!(reply.json()["error"]["code"], "automatic_lifecycle");
        }
        let reply = f
            .post(
                "/radio/disconnect",
                json!({"v":1,"profile_id":profile_id,"boot_id":boot_id,"connection_generation":0}),
                Some(&cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::CONFLICT);
        assert_eq!(reply.json()["error"]["code"], "automatic_lifecycle");
        // Strict validation is unchanged: extra keys and wrong identity refuse first.
        let reply = f
            .post(
                "/radio/connect",
                json!({"v":1,"profile_id":profile_id,"boot_id":boot_id,"profile_revision":revision,"receive_only_verified":true,"extra":1}),
                Some(&cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::BAD_REQUEST);
        let reply = f
            .post(
                "/radio/disconnect",
                json!({"v":1,"profile_id":profile::new_uuid().unwrap(),"boot_id":boot_id,"connection_generation":0}),
                Some(&cookie),
            )
            .await;
        assert_eq!(reply.status, StatusCode::FORBIDDEN);
        assert_eq!(state.recording.radio_view(), view, "no owner created");
        let p = peer.lock().unwrap();
        assert_eq!((p.opens, p.writes.len(), p.closes), (0, 0, 0));
    }
}
