//! H1 compatibility prerequisites; transport behavior tests are added before integration.
use axum::{
    body::{Body, to_bytes},
    http::{Extensions, HeaderMap, Request, StatusCode, Version},
    response::Response,
};
use std::{convert::Infallible, future::ready};
use tower::{Layer, ServiceExt, service_fn};
use tower_http::compression::CompressionLayer;

#[tokio::test]
async fn standard_layer_supports_one_existing_axum_response() {
    let mut response = Some(Response::new(Body::from("{}")));
    let one_response = service_fn(move |_: Request<Body>| {
        ready(Ok::<_, Infallible>(
            response
                .take()
                .expect("one response service is called once"),
        ))
    });
    let layer = CompressionLayer::new()
        .gzip(true)
        .compress_when(|_: StatusCode, _: Version, _: &HeaderMap, _: &Extensions| true);
    let response = layer
        .layer(one_response)
        .oneshot(
            Request::builder()
                .header("accept-encoding", "identity;q=0,gzip")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.headers()["content-encoding"], "gzip");
    let bytes = to_bytes(Body::new(response.into_body()), 1024)
        .await
        .unwrap();
    assert_eq!(&bytes[..3], &[0x1f, 0x8b, 8]);
}

// Proves: CL-003-08, CL-008-07; TC-009-005 case8. Read only the reviewed,
// fixed-shape SysML oracle declarations, never the implementation negotiator.
fn canonical_negotiations(source: &str) -> Result<Vec<(Vec<String>, &'static str)>, &'static str> {
    fn value<'a>(line: Option<&'a str>, prefix: &str) -> Result<&'a str, &'static str> {
        line.and_then(|line| line.strip_prefix(prefix))
            .and_then(|line| line.strip_suffix(';'))
            .ok_or("malformed canonical negotiation field")
    }
    for (name, expected) in [
        (
            "negotiationSourceSha256",
            "329bf57ef2a989f3128d96b845c4064dbda01a595b7e2fa1a594de77c18b9e56",
        ),
        (
            "originalVectorArtifactSha256",
            "d8da8bdb86485cc8691e2ad4f37afcbbaf84969c5b1a145f3a187a86d114a3c9",
        ),
    ] {
        let prefix = format!("attribute {name} : String = ");
        let mut declarations = source
            .lines()
            .map(str::trim)
            .filter(|line| line.starts_with(&prefix));
        let raw = value(declarations.next(), &prefix)?;
        let actual: String =
            serde_json::from_str(raw).map_err(|_| "malformed oracle provenance")?;
        if actual != expected || declarations.next().is_some() {
            return Err("missing, changed or duplicate oracle provenance");
        }
    }
    let mut lines = source.lines().map(str::trim);
    let mut vectors = Vec::new();
    while let Some(line) = lines.next() {
        if !line.contains(": NegotiationOracleVector") {
            continue;
        }
        let name = line
            .strip_prefix("attribute negotiation")
            .and_then(|line| line.strip_suffix(" : NegotiationOracleVector {"))
            .ok_or("malformed canonical negotiation declaration")?;
        let ordinal: usize = name.parse().map_err(|_| "invalid negotiation ordinal")?;
        if name != format!("{ordinal:02}") || ordinal != vectors.len() + 1 {
            return Err("missing, duplicate or reordered negotiation case");
        }
        let case_id = value(lines.next(), "attribute :>> caseId = ")?
            .parse::<usize>()
            .map_err(|_| "invalid negotiation case ID")?;
        if case_id != ordinal {
            return Err("negotiation declaration and case ID differ");
        }
        let encoded: String = serde_json::from_str(value(
            lines.next(),
            "attribute :>> orderedRawHeaderFieldsJson = ",
        )?)
        .map_err(|_| "malformed SysML oracle string")?;
        let fields: Vec<String> =
            serde_json::from_str(&encoded).map_err(|_| "invalid ordered raw-header array")?;
        let expected = match value(
            lines.next(),
            "attribute :>> expected = HttpCodingSelection::",
        )? {
            "gzip" => "gzip",
            "identity" => "identity",
            "noAcceptable" => "406",
            _ => return Err("unknown independently specified outcome"),
        };
        if lines.next() != Some("}") {
            return Err("extra or missing negotiation fields");
        }
        vectors.push((fields, expected));
    }
    if vectors.len() != 49 {
        return Err("all 49 canonical negotiation cases are required");
    }
    Ok(vectors)
}

#[test]
fn canonical_negotiation_oracle_rejects_missing_malformed_and_duplicate_data() {
    let source = include_str!("../../docs/sysml/OperatingReceive.sysml");
    assert_eq!(canonical_negotiations(source).unwrap().len(), 49);
    for damaged in [
        source.replace("attribute negotiation01 :", "attribute omitted01 :"),
        source.replace("attribute :>> caseId = 2;", "attribute :>> caseId = 1;"),
        source.replace(
            "HttpCodingSelection::noAcceptable;",
            "HttpCodingSelection::unknown;",
        ),
        source.replace(
            "329bf57ef2a989f3128d96b845c4064dbda01a595b7e2fa1a594de77c18b9e56",
            "changed",
        ),
    ] {
        assert!(canonical_negotiations(&damaged).is_err());
    }
}

#[tokio::test]
async fn pinned_library_matches_all_49_independent_negotiations() {
    let source = include_str!("../../docs/sysml/OperatingReceive.sysml");
    let mut count = 0;
    for (fields, expected) in canonical_negotiations(source).unwrap() {
        let mut request = Request::new(Body::empty());
        for field in fields {
            request
                .headers_mut()
                .append("accept-encoding", field.parse().unwrap());
        }
        let mut existing = Some(Response::new(Body::from("{}")));
        let service = service_fn(move |_: Request<Body>| {
            ready(Ok::<_, Infallible>(existing.take().unwrap()))
        });
        let response = CompressionLayer::new()
            .gzip(true)
            .compress_when(|_: StatusCode, _: Version, _: &HeaderMap, _: &Extensions| true)
            .layer(service)
            .oneshot(request)
            .await
            .unwrap();
        let status = response.status();
        let encoding = response
            .headers()
            .get("content-encoding")
            .map(|v| v.to_str().unwrap());
        match expected {
            "gzip" => {
                assert_eq!(status, StatusCode::OK, "vector{count}");
                assert_eq!(encoding, Some("gzip"), "vector{count}");
            }
            "identity" => {
                assert_eq!(status, StatusCode::OK, "vector{count}");
                assert_eq!(encoding, None, "vector{count}");
            }
            "406" => {
                assert_eq!(status, StatusCode::NOT_ACCEPTABLE, "vector{count}");
                assert_eq!(encoding, None, "vector{count}");
            }
            _ => panic!("unknown independently specified outcome"),
        }
        let bytes = to_bytes(Body::new(response.into_body()), 1024)
            .await
            .unwrap();
        if expected == "gzip" {
            assert_eq!(&bytes[..3], &[0x1f, 0x8b, 8]);
        } else {
            assert_eq!(&bytes[..], b"{}");
        }
        count += 1;
    }
    assert_eq!(
        count, 49,
        "every frozen ordered-header oracle must actually execute"
    );
}

fn headers(fields: &[&str]) -> HeaderMap {
    let mut headers = HeaderMap::new();
    for field in fields {
        headers.append("accept-encoding", field.parse().unwrap());
    }
    headers
}
fn json_body(bytes: Vec<u8>) -> Response {
    Response::builder()
        .header("content-type", "application/json")
        .header("content-length", bytes.len())
        .header("cache-control", "no-store")
        .header("x-content-type-options", "nosniff")
        .header("content-security-policy", "default-src 'self'")
        .body(Body::from(bytes))
        .unwrap()
}
#[tokio::test]
async fn h1_exact_vary_merge_framing_and_validator_rules() {
    use axum::http::{Method, header};
    for (original, expected) in [
        (
            vec!["Origin", "X-Accept-Encoding-Other"],
            vec!["Origin", "X-Accept-Encoding-Other", "Accept-Encoding"],
        ),
        (
            vec!["origin", "aCcEpT-EnCoDiNg"],
            vec!["origin", "aCcEpT-EnCoDiNg"],
        ),
        (
            vec!["Origin, *", "X-Accept-Encoding-Other"],
            vec!["Origin, *", "X-Accept-Encoding-Other"],
        ),
        (
            vec!["Origin,  accept-encoding  "],
            vec!["Origin,  accept-encoding  "],
        ),
    ] {
        let mut response = json_body(b"{}".to_vec());
        for value in original {
            response
                .headers_mut()
                .append(header::VARY, value.parse().unwrap());
        }
        response
            .headers_mut()
            .insert(header::ETAG, "\"identity-validator\"".parse().unwrap());
        let response = crate::http_compression::encode_response(
            &Method::GET,
            "/profile",
            headers(&["identity;q=0,gzip"]),
            response,
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[header::CONTENT_ENCODING], "gzip");
        assert!(!response.headers().contains_key(header::CONTENT_LENGTH));
        assert!(!response.headers().contains_key(header::ETAG));
        let actual: Vec<_> = response
            .headers()
            .get_all(header::VARY)
            .iter()
            .map(|v| v.to_str().unwrap())
            .collect();
        assert_eq!(actual, expected);
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
        assert_eq!(response.headers()["x-content-type-options"], "nosniff");
        assert_eq!(
            response.headers()["content-security-policy"],
            "default-src 'self'"
        );
        let bytes = to_bytes(response.into_body(), 1024).await.unwrap();
        assert_eq!(&bytes[..3], &[31, 139, 8]);
    }
}
#[tokio::test]
async fn h1_exclusions_preserve_original_before_forbidden_negotiation() {
    use axum::http::{Method, header};
    for (method, path, status, special) in [
        (Method::POST, "/receive/select", 200, None),
        (Method::PUT, "/profile", 200, None),
        (Method::GET, "/session", 200, None),
        (Method::GET, "/app.js", 200, None),
        (Method::GET, "/ws", 200, None),
        (Method::HEAD, "/profile", 200, None),
        (Method::GET, "/profile", 204, None),
        (Method::GET, "/profile", 205, None),
        (Method::GET, "/profile", 304, None),
        (Method::GET, "/profile", 401, None),
        (Method::GET, "/profile", 403, None),
        (Method::GET, "/profile", 400, None),
        (Method::GET, "/profile", 404, None),
        (Method::GET, "/profile", 409, None),
        (Method::GET, "/profile", 500, None),
        (Method::GET, "/profile", 503, None),
        (
            Method::GET,
            "/profile",
            200,
            Some(("content-encoding", "gzip")),
        ),
        (
            Method::GET,
            "/profile",
            206,
            Some(("content-range", "bytes0-1/2")),
        ),
        (
            Method::GET,
            "/profile",
            200,
            Some(("content-type", "text/plain")),
        ),
    ] {
        let mut response = json_body(b"{}".to_vec());
        *response.status_mut() = StatusCode::from_u16(status).unwrap();
        if let Some((name, value)) = special {
            response.headers_mut().insert(
                axum::http::HeaderName::from_bytes(name.as_bytes()).unwrap(),
                value.parse().unwrap(),
            );
        }
        let expected = response.headers().clone();
        let response = crate::http_compression::encode_response(
            &method,
            path,
            headers(&["gzip;q=0,identity;q=0"]),
            response,
        )
        .await;
        assert_eq!(response.status().as_u16(), status, "{method}{path}");
        assert_eq!(response.headers(), &expected);
        assert_eq!(
            &to_bytes(response.into_body(), 1024).await.unwrap()[..],
            b"{}"
        );
    }
    let response = json_body(Vec::new());
    let response = crate::http_compression::encode_response(
        &Method::GET,
        "/profile",
        headers(&["*;q=0"]),
        response,
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    assert!(!response.headers().contains_key(header::CONTENT_ENCODING));
    assert!(
        to_bytes(response.into_body(), 1024)
            .await
            .unwrap()
            .is_empty()
    );
}
#[tokio::test]
async fn h1_each_logical_cap_precedes_encoding_and_unknown_bodies_fail_closed() {
    use axum::http::{Method, header};
    for (path, cap) in [
        ("/profile", 8192),
        ("/recording", 8192),
        ("/receive", 8192),
        ("/radio", 2048),
        ("/receive/selection", 3072),
        ("/receive/results", 16384),
    ] {
        assert_eq!(crate::http_compression::logical_cap(path), Some(cap));
        let mut exact = b"{\"pad\":\"".to_vec();
        exact.resize(cap as usize - 2, b'x');
        exact.extend_from_slice(b"\"}");
        assert_eq!(exact.len(), cap as usize);
        serde_json::from_slice::<serde_json::Value>(&exact).unwrap();
        let response = crate::http_compression::encode_response(
            &Method::GET,
            path,
            headers(&["identity"]),
            json_body(exact.clone()),
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            &to_bytes(response.into_body(), cap as usize).await.unwrap()[..],
            exact
        );
        let response = crate::http_compression::encode_response(
            &Method::GET,
            path,
            headers(&["gzip"]),
            json_body(exact),
        )
        .await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[header::CONTENT_ENCODING], "gzip");
        assert_eq!(
            &to_bytes(response.into_body(), 32768).await.unwrap()[..3],
            &[31, 139, 8]
        );
        for encoding in ["gzip", "identity;q=0,gzip;q=0"] {
            let response = crate::http_compression::encode_response(
                &Method::GET,
                path,
                headers(&[encoding]),
                json_body(vec![b' '; cap as usize + 1]),
            )
            .await;
            assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
            assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
            assert!(!response.headers().contains_key(header::CONTENT_ENCODING));
            assert_eq!(
                &to_bytes(response.into_body(), 512).await.unwrap()[..],
                b"{\"error\":{\"code\":\"snapshot_limit\",\"field\":null}}"
            );
        }
        let mut unknown = json_body(b"{}".to_vec());
        *unknown.body_mut() = Body::from_stream(Body::from("{}").into_data_stream());
        assert_eq!(
            axum::body::HttpBody::size_hint(unknown.body()).exact(),
            None
        );
        let response = crate::http_compression::encode_response(
            &Method::GET,
            path,
            headers(&["*;q=0"]),
            unknown,
        )
        .await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(!response.headers().contains_key(header::CONTENT_ENCODING));
        assert!(!response.headers().contains_key(header::CONTENT_LENGTH));
        assert_eq!(
            &to_bytes(response.into_body(), 512).await.unwrap()[..],
            b"{\"error\":{\"code\":\"snapshot_limit\",\"field\":null}}"
        );
    }
}
#[tokio::test]
async fn h1_existing_handler_executes_once_and_retains_query() {
    use axum::{Router, routing::get};
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    let calls = Arc::new(AtomicUsize::new(0));
    let observer = calls.clone();
    let app = Router::new()
        .route(
            "/receive/results",
            get(move |request: Request<Body>| {
                let calls = observer.clone();
                async move {
                    assert_eq!(request.uri().query(), Some("cursor=17&limit=1"));
                    calls.fetch_add(1, Ordering::SeqCst);
                    json_body(b"{}".to_vec())
                }
            }),
        )
        .layer(axum::middleware::from_fn(crate::http_compression::encode));
    let response = app
        .oneshot(
            Request::builder()
                .uri("/receive/results?cursor=17&limit=1")
                .header("accept-encoding", "*;q=0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_ACCEPTABLE);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn h1_six_production_handlers_have_exact_bounded_json_bodies() {
    use crate::{App, ProfileState, audio, profile, receive_http_tests, recording};
    use std::{
        fs,
        sync::{Arc, Mutex},
        time::{Duration, Instant},
    };
    struct Fixture {
        root: std::path::PathBuf,
        app: Option<App>,
        r: Arc<recording::Recording>,
        id: String,
        boot: String,
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let current = self.r.receive_snapshot();
            if let (Some(generation), Some(id)) = (
                current["generation"].as_u64(),
                current["job"]["id"].as_str(),
            ) {
                let _ = self.r.receive_stop(&self.id, &self.boot, generation, id);
            }
            let deadline = Instant::now() + Duration::from_secs(2);
            while self.r.selection_snapshot(false).unwrap()["receive"]["owner_released"] != true
                && Instant::now() < deadline
            {
                std::thread::sleep(Duration::from_millis(1));
            }
            drop(self.app.take());
            let _ = fs::remove_dir_all(&self.root);
        }
    }
    let root = std::env::temp_dir().join(format!("wstx-h1-body-{}", profile::new_uuid().unwrap()));
    fs::create_dir(&root).unwrap();
    let id = profile::new_uuid().unwrap();
    let boot = profile::new_uuid().unwrap();
    let document = serde_json::json!({"schema_version":1,"profile_id":id,"revision":0,"display_name":"H1 fixed-body fixture","callsign":"HB9BLA","locator":"JN47AA","endpoint":{"bind":"127.0.0.1:18001","origin":null},"connection_type":"standard","audio":{"input_device":null,"output_device":null},"control":{"mode":"disabled","endpoint":null,"ptt":"disabled"}});
    fs::write(
        root.join("profile.json"),
        serde_json::to_vec(&document).unwrap(),
    )
    .unwrap();
    let (store, _) = profile::Store::open(&root).unwrap();
    let r = recording::Recording::open(&root, id.clone(), boot.clone());
    r.initialize_profile_revision(0);
    let app = App {
        origin: "https://localhost:18001".into(),
        profile: Some(Arc::new(ProfileState {
            store: Mutex::new(store),
            boot: boot.clone(),
            recording: r.clone(),
        })),
        profile_id: Some(id.clone()),
        token: Some("IsolatedH1FixtureToken012345678901".into()),
        connections: Arc::new(crate::Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    let fixture = Fixture {
        root,
        app: Some(app.clone()),
        r: r.clone(),
        id: id.clone(),
        boot: boot.clone(),
    };
    let (input, queue) = receive_http_tests::Input::queued();
    r.receive_start_input(
        &id,
        &boot,
        0,
        "isolated-native-queue".into(),
        "ft8",
        Box::new(input),
    )
    .unwrap();
    assert!(queue.push(&[], 480, 0, 0, audio::SILENT));
    let deadline = Instant::now() + Duration::from_secs(2);
    let receive = loop {
        let receive = r.receive_snapshot();
        if receive["source"]["id"].is_string() {
            break receive;
        }
        assert!(
            Instant::now() < deadline,
            "actual queued input must publish its acknowledged source"
        );
        std::thread::sleep(Duration::from_millis(1));
    };
    let query = format!(
        "/receive/results?source_id={}&job_id={}&generation={}&cursor=0&limit=16",
        receive["source"]["id"].as_str().unwrap(),
        receive["job"]["id"].as_str().unwrap(),
        receive["generation"].as_u64().unwrap()
    );
    let cookie = format!(
        "{}={}",
        crate::cookie_name(&app),
        crate::cookie_value(&app, app.token.as_deref().unwrap())
    );
    for (uri, cap) in [
        ("/profile", 8192),
        ("/recording", 8192),
        ("/receive", 8192),
        ("/radio", 2048),
        ("/receive/selection", 3072),
        (query.as_str(), 16384),
    ] {
        let response = crate::router(app.clone())
            .oneshot(
                Request::builder()
                    .uri(uri)
                    .header("cookie", &cookie)
                    .header("origin", &app.origin)
                    .header("accept-encoding", "identity")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK, "actual route{uri}");
        assert!(response.headers().get("content-encoding").is_none());
        let size = axum::body::HttpBody::size_hint(response.body())
            .exact()
            .expect("the actual typed route supplies an exact fixed body");
        assert!(size > 0 && size <= cap);
        let bytes = to_bytes(response.into_body(), cap as usize).await.unwrap();
        assert_eq!(bytes.len() as u64, size);
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        if uri.starts_with("/receive/results?") {
            assert_eq!(value["records"], serde_json::json!([]));
        }
    }
    drop(fixture);
}
