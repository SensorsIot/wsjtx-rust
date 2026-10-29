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
        let (mut store, _) = profile::Store::open(&directory).unwrap();
        let id = store.document.profile_id.clone();
        let boot = profile::new_uuid().unwrap();
        let authority = authorization_http::Service::initialize(&mut store, origin).unwrap();
        let recording = recording::Recording::open(&directory, id.clone(), boot.clone());
        recording.initialize_profile_revision(store.document.revision);
        let app = App {
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
        };
        Self {
            app: Some(app),
            directory,
        }
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
        assert!(response.json()["identity_receipt"].is_null());
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
    let radio_before = f.app().profile.as_ref().unwrap().recording.radio_view();
    assert_eq!(
        f.post("/radio/connect", json!({}), Some(&g.cookie))
            .await
            .status,
        StatusCode::CONFLICT,
        "unwired native dispatch stays fail closed"
    );
    assert_eq!(
        f.app().profile.as_ref().unwrap().recording.radio_view(),
        radio_before
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
        "radio-identity",
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
        StatusCode::UNAUTHORIZED,
        "configuration trust never grants native runtime access"
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
    let access = authorization_http::access(&f.headers(Some(&g.cookie)), f.app()).unwrap();
    let context = ConnectionAuthority {
        state: f.app().profile.as_ref().unwrap().clone(),
        access: access.clone(),
    };
    let new_cookie = f.renew(&g).await;
    assert!(
        context.current(),
        "transport rotation must not revoke established WS grant context"
    );
    assert!(authorization_http::access(&f.headers(Some(&g.cookie)), f.app()).is_err());
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

#[tokio::test]
async fn http_auth_process_attempt_cap_is_shared_by_session_and_auth_routes() {
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
    assert_eq!(
        f.post(
            "/authorization/v1/challenge",
            json!({"version":1,"grant_id":URL_SAFE_NO_PAD.encode([3;32])}),
            None
        )
        .await
        .status,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        f.request(
            axum::http::Method::POST,
            "/session",
            f.app().token.clone().unwrap(),
            f.headers(None)
        )
        .await
        .status,
        StatusCode::TOO_MANY_REQUESTS
    );
    assert_eq!(
        f.post("/authorization/v1/status", json!({"version":1}), None)
            .await
            .status,
        StatusCode::TOO_MANY_REQUESTS
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
        authorization_http::access(&f.headers(Some(&g.cookie)), f.app()).is_ok(),
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
    assert!(authorization_http::access(&f.headers(Some(&g.cookie)), f.app()).is_err());
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
    assert_eq!(f.post("/authorization/v1/commission",json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":response.json()["scope"],"receive_only_confirmed":true}),Some(&new_cookie)).await.status,StatusCode::CONFLICT,"unwired setup must never return a fabricated commitment");
    assert_eq!(
        std::fs::read(f.directory.join("authorization.json")).unwrap(),
        before
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
