// Cost 2: actual Router over disposable selected profiles (HTTPS grant and plaintext
// runtime token). Expected codes, keys and caps are written from WstxContact::ContactWire.
use super::*;
use axum::http::Method;

const CONTACT: &str = "77777777-7777-4777-8777-777777777777";

fn ready(f: &HttpFixture) {
    let state = f.app().profile.as_ref().unwrap();
    let mut store = state.store.lock().unwrap();
    let mut settings = store.document.settings();
    settings.callsign = "HB9BLA".into();
    settings.locator = "JN47AA".into();
    store.save(settings).unwrap();
}
fn ids(f: &HttpFixture) -> (String, String) {
    let state = f.app().profile.as_ref().unwrap();
    (
        state.store.lock().unwrap().document.profile_id.clone(),
        state.boot.clone(),
    )
}
fn record(contact: &str) -> Value {
    json!({"contact_id":contact,"call":"K1ABC","gridsquare":"FN42","mode":"FT8","submode":null,
        "rst_sent":"-12","rst_rcvd":"-05","qso_date":"20261031","time_on":"123015",
        "qso_date_off":"20261031","time_off":"123200","band":"20m","freq":"14.075500",
        "station_callsign":"HB9BLA","my_gridsquare":"JN47AA","tx_pwr":"10","comment":"Tnx"})
}
fn save_body(f: &HttpFixture, record: Value) -> Value {
    let (profile, boot) = ids(f);
    save_body_with(&profile, &boot, record)
}
fn save_body_with(profile: &str, boot: &str, record: Value) -> Value {
    json!({"v":1,"profile_id":profile,"boot_id":boot,"command_id":profile::new_uuid().unwrap(),"record":record})
}
async fn raw(
    f: &HttpFixture,
    method: Method,
    path: &str,
    body: Vec<u8>,
    headers: HeaderMap,
) -> HttpReply {
    let mut request = axum::http::Request::builder()
        .method(method)
        .uri(path)
        .body(axum::body::Body::from(body))
        .unwrap();
    *request.headers_mut() = headers;
    let response = router(f.app().clone()).oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    HttpReply {
        status: parts.status,
        headers: parts.headers,
        body: axum::body::to_bytes(body, 1 << 26).await.unwrap().to_vec(),
    }
}
async fn get(f: &HttpFixture, path: &str, cookie: Option<&str>) -> HttpReply {
    raw(f, Method::GET, path, Vec::new(), f.headers(cookie)).await
}
fn code(reply: &HttpReply) -> (StatusCode, Value, Value) {
    let v = reply.json();
    (
        reply.status,
        v["error"]["code"].clone(),
        v["error"]["field"].clone(),
    )
}
fn sha(bytes: &[u8]) -> String {
    ring::digest::digest(&ring::digest::SHA256, bytes)
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
async fn chunk(
    f: &HttpFixture,
    id: &str,
    start: usize,
    total: usize,
    bytes: &[u8],
    cookie: Option<&str>,
) -> HttpReply {
    let mut headers = f.headers(cookie);
    headers.insert(
        header::CONTENT_TYPE,
        "application/octet-stream".parse().unwrap(),
    );
    let range = format!("bytes {start}-{}/{total}", start + bytes.len() - 1);
    headers.insert(header::CONTENT_RANGE, range.parse().unwrap());
    raw(
        f,
        Method::PUT,
        &format!("/contacts/imports/{id}"),
        bytes.to_vec(),
        headers,
    )
    .await
}

// Proves: CL-010-04, CL-010-15; TC-007-004 every log route requires the HTTPS durable
// grant; a revoked grant is 401 and changes nothing.
#[tokio::test]
async fn https_log_routes_require_current_grant_and_revocation_refuses_without_effect() {
    let f = HttpFixture::new("https://localhost:8090");
    ready(&f);
    let g = f.authorize().await;
    let saved = f
        .post("/contacts", save_body(&f, record(CONTACT)), Some(&g.cookie))
        .await;
    assert_eq!(
        saved.status,
        StatusCode::CREATED,
        "{}",
        String::from_utf8_lossy(&saved.body)
    );
    assert_eq!(
        saved.json(),
        json!({"v":1,"contact_id":CONTACT,"outcome":"saved"})
    );
    let file = std::fs::read(f.directory.join("contacts.adi")).unwrap();
    assert!(String::from_utf8_lossy(&file).contains("<call:5>K1ABC "));
    let (profile, boot) = ids(&f);
    let reserve = |id: &str| json!({"v":1,"profile_id":profile,"boot_id":boot,"import_id":id,"total_bytes":4,"sha256":"0".repeat(64)});
    assert_eq!(
        get(&f, "/contacts", Some(&g.cookie)).await.status,
        StatusCode::OK
    );
    for cookie in [None, Some(g.cookie.as_str())] {
        if cookie.is_some() {
            let revoked = f.post("/authorization/v1/revoke", json!({"version":1,"operation_id":profile::new_uuid().unwrap(),"scope":g.scope,"all_for_radio":false}), Some(&g.cookie)).await;
            assert_eq!(revoked.status, StatusCode::OK);
        }
        let second = save_body(&f, record("88888888-8888-4888-8888-888888888888"));
        assert_eq!(
            code(&f.post("/contacts", second, cookie).await).0,
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            f.post(
                "/contacts/imports",
                reserve(&profile::new_uuid().unwrap()),
                cookie
            )
            .await
            .status,
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            chunk(&f, CONTACT, 0, 4, b"abcd", cookie).await.status,
            StatusCode::UNAUTHORIZED
        );
        let cty = json!({"v":1,"profile_id":profile,"boot_id":boot,"text":null});
        assert_eq!(
            raw(
                &f,
                Method::PUT,
                "/dxcc",
                serde_json::to_vec(&cty).unwrap(),
                f.headers(cookie)
            )
            .await
            .status,
            StatusCode::UNAUTHORIZED
        );
        for path in [
            "/contacts",
            "/contacts/export.adi",
            format!("/contacts/imports/{CONTACT}").as_str(),
            "/dxcc",
        ] {
            assert_eq!(
                get(&f, path, cookie).await.status,
                StatusCode::UNAUTHORIZED,
                "{path}"
            );
        }
    }
    assert_eq!(
        std::fs::read(f.directory.join("contacts.adi")).unwrap(),
        file,
        "no effect after revocation"
    );
    // Wrong Origin precedes credentials.
    let mut headers = f.headers(None);
    headers.insert(header::ORIGIN, "https://evil.example".parse().unwrap());
    let wrong = raw(
        &f,
        Method::POST,
        "/contacts",
        serde_json::to_vec(&save_body(&f, record(CONTACT))).unwrap(),
        headers,
    )
    .await;
    assert_eq!(code(&wrong).1, "forbidden_origin");
}

// Proves: CL-010-04, CL-010-15; TC-007-004 a grant revoked after admission cannot publish.
#[tokio::test]
async fn revocation_between_admission_and_publication_wins_the_atomic_replace() {
    let f = HttpFixture::new("https://localhost:8091");
    ready(&f);
    let g = f.authorize().await;
    let state = f.app().profile.as_ref().unwrap().clone();
    // The held profile store is the barrier: admission (grant check) completes, then the
    // handler's blocking stage waits on the store before publication. A separate thread
    // holds it and revokes through the authority on request.
    let (locked_tx, locked_rx) = std::sync::mpsc::channel();
    let (go_tx, go_rx) = std::sync::mpsc::channel::<()>();
    let holder = {
        let state = state.clone();
        let grant = g.id.clone();
        std::thread::spawn(move || {
            let mut store = state.store.lock().unwrap();
            locked_tx.send(()).unwrap();
            go_rx.recv().unwrap();
            let mut owner = state.authorization.lock().unwrap();
            owner
                .as_mut()
                .unwrap()
                .authority
                .revoke(&mut store, &grant, &profile::new_uuid().unwrap(), false)
                .unwrap();
        })
    };
    locked_rx.recv().unwrap();
    let profile_id = f.app().profile_id.clone().unwrap();
    let request = {
        let app = f.app().clone();
        let headers = f.headers(Some(&g.cookie));
        let body =
            serde_json::to_vec(&save_body_with(&profile_id, &state.boot, record(CONTACT))).unwrap();
        tokio::spawn(async move {
            let mut request = axum::http::Request::builder()
                .method(Method::POST)
                .uri("/contacts")
                .body(axum::body::Body::from(body))
                .unwrap();
            *request.headers_mut() = headers;
            router(app).oneshot(request).await.unwrap().status()
        })
    };
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert!(
        !request.is_finished(),
        "request is queued behind the held store"
    );
    go_tx.send(()).unwrap();
    let status = tokio::time::timeout(Duration::from_secs(5), request)
        .await
        .unwrap()
        .unwrap();
    holder.join().unwrap();
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert!(
        !f.directory.join("contacts.adi").exists(),
        "nothing published with revoked authority"
    );
}

// Proves: CL-010-04, CL-010-15; TC-007-004 plaintext profile keeps the runtime token.
#[tokio::test]
async fn plaintext_profile_log_routes_require_runtime_token() {
    let mut f = HttpFixture::new("http://localhost:8092");
    ready(&f);
    let token = "PlaintextFixtureToken0123456789ab";
    f.app.as_mut().unwrap().token = Some(token.into());
    let good = format!("{}={}", cookie_name(f.app()), cookie_value(f.app(), token));
    assert_eq!(
        f.post("/contacts", save_body(&f, record(CONTACT)), None)
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        get(&f, "/contacts", None).await.status,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        f.post("/contacts", save_body(&f, record(CONTACT)), Some(&good))
            .await
            .status,
        StatusCode::CREATED
    );
    assert_eq!(get(&f, "/contacts", Some(&good)).await.json()["total"], 1);
}

// Proves: CL-010-15; TC-007-004 environment-only mode has no log routes.
#[tokio::test]
async fn environment_only_mode_answers_not_found() {
    let app = App {
        origin: "http://127.0.0.1:8093".into(),
        profile: None,
        profile_id: None,
        token: None,
        connections: Arc::new(Semaphore::new(16)),
        login_attempts: Arc::new(Mutex::new((Instant::now(), 0))),
    };
    for (method, path) in [
        (Method::GET, "/contacts"),
        (Method::POST, "/contacts"),
        (Method::GET, "/contacts/export.adi"),
        (Method::POST, "/contacts/imports"),
        (Method::GET, "/dxcc"),
        (Method::PUT, "/dxcc"),
    ] {
        let mut request = axum::http::Request::builder()
            .method(method)
            .uri(path)
            .body(axum::body::Body::empty())
            .unwrap();
        request
            .headers_mut()
            .insert(header::ORIGIN, "http://127.0.0.1:8093".parse().unwrap());
        assert_eq!(
            router(app.clone()).oneshot(request).await.unwrap().status(),
            StatusCode::NOT_FOUND,
            "{path}"
        );
    }
}

// Proves: CL-010-04, CL-010-15; TC-007-004/TC-011-001 SaveContact refusals, caps and idempotency.
#[tokio::test]
async fn save_contact_refusals_byte_cap_and_command_receipts() {
    let f = HttpFixture::new("http://localhost:8094");
    ready(&f);
    let post = |value: Value| f.post("/contacts", value, None);
    let base = save_body(&f, record(CONTACT));
    // Worst case: a 1024-character comment of quotes costs 2048 JSON bytes and fits.
    let mut exact = base.clone();
    exact["record"]["comment"] = json!("\"".repeat(1024));
    assert!(serde_json::to_vec(&exact).unwrap().len() < 8192);
    // Exactly 8192 bytes are admitted to parsing (refused only for its invalid field, no
    // effect); 8193 bytes are refused before parsing.
    let mut probe = exact.clone();
    probe["record"]["tx_pwr"] = json!("-1");
    let padded = |n: usize| {
        let mut bytes = serde_json::to_vec(&probe).unwrap();
        bytes.resize(n, b' ');
        bytes
    };
    let at = raw(&f, Method::POST, "/contacts", padded(8192), f.headers(None)).await;
    assert_eq!(
        code(&at),
        (
            StatusCode::BAD_REQUEST,
            json!("log_invalid_field"),
            json!("record.tx_pwr")
        )
    );
    let over = raw(&f, Method::POST, "/contacts", padded(8193), f.headers(None)).await;
    assert_eq!(
        code(&over),
        (
            StatusCode::PAYLOAD_TOO_LARGE,
            json!("request_too_large"),
            Value::Null
        )
    );
    let mut headers = f.headers(None);
    headers.insert(header::CONTENT_TYPE, "text/plain".parse().unwrap());
    assert_eq!(
        code(&raw(&f, Method::POST, "/contacts", b"{}".to_vec(), headers).await).1,
        "unsupported_media_type"
    );
    let mutate = |change: &dyn Fn(&mut Value)| {
        let mut value = base.clone();
        change(&mut value);
        value
    };
    let cases: Vec<(Value, StatusCode, &str, Value)> = vec![
        (
            mutate(&|v| {
                v.as_object_mut().unwrap().remove("command_id");
            }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!("command_id"),
        ),
        (
            mutate(&|v| {
                v["extra"] = json!(1);
            }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!("extra"),
        ),
        (
            mutate(&|v| {
                v["record"].as_object_mut().unwrap().remove("comment");
            }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!("record"),
        ),
        (
            mutate(&|v| {
                v["command_id"] = json!("x");
            }),
            StatusCode::BAD_REQUEST,
            "invalid_request",
            json!("command_id"),
        ),
        (
            mutate(&|v| {
                v["v"] = json!(2);
            }),
            StatusCode::BAD_REQUEST,
            "unsupported_version",
            json!("v"),
        ),
        (
            mutate(&|v| {
                v["profile_id"] = json!(profile::new_uuid().unwrap());
            }),
            StatusCode::FORBIDDEN,
            "wrong_profile",
            json!("profile_id"),
        ),
        (
            mutate(&|v| {
                v["boot_id"] = json!(profile::new_uuid().unwrap());
            }),
            StatusCode::CONFLICT,
            "state_conflict",
            json!("boot_id"),
        ),
        (
            mutate(&|v| {
                v["record"]["tx_pwr"] = json!("-1");
            }),
            StatusCode::BAD_REQUEST,
            "log_invalid_field",
            json!("record.tx_pwr"),
        ),
        (
            mutate(&|v| {
                v["record"]["comment"] = json!("a\nb");
            }),
            StatusCode::BAD_REQUEST,
            "log_invalid_field",
            json!("record.comment"),
        ),
    ];
    for (body, status, error, field) in cases {
        assert_eq!(
            code(&post(body.clone()).await),
            (status, json!(error), field),
            "{body}"
        );
    }
    assert!(
        !f.directory.join("contacts.adi").exists(),
        "refusals change nothing"
    );
    let created = post(exact.clone()).await;
    assert_eq!(created.status, StatusCode::CREATED);
    let replay = post(exact.clone()).await;
    assert_eq!(
        (replay.status, replay.body.clone()),
        (StatusCode::CREATED, created.body.clone()),
        "same receipt"
    );
    let mut reused = exact.clone();
    reused["record"]["tx_pwr"] = json!("5");
    assert_eq!(
        code(&post(reused.clone()).await),
        (
            StatusCode::CONFLICT,
            json!("state_conflict"),
            json!("command_id")
        )
    );
    let mut again = exact.clone();
    again["command_id"] = json!(profile::new_uuid().unwrap());
    let already = post(again).await;
    assert_eq!(
        (already.status, already.json()),
        (
            StatusCode::OK,
            json!({"v":1,"contact_id":CONTACT,"outcome":"already_saved"})
        )
    );
    reused["command_id"] = json!(profile::new_uuid().unwrap());
    assert_eq!(
        code(&post(reused).await),
        (StatusCode::CONFLICT, json!("log_conflict"), json!("record"))
    );
    let stored = std::fs::read_to_string(f.directory.join("contacts.adi")).unwrap();
    assert_eq!(
        stored.matches("<eor>").count(),
        1,
        "exactly one record per contact id"
    );
    // Storage failure leaves the review unsaved and a retry of the same identity succeeds.
    let state = f.app().profile.as_ref().unwrap();
    state.logbook.inject_fault(Some("replace"));
    let retry = save_body(&f, record("99999999-9999-4999-8999-999999999999"));
    assert_eq!(
        code(&post(retry.clone()).await),
        (
            StatusCode::SERVICE_UNAVAILABLE,
            json!("storage_unavailable"),
            Value::Null
        )
    );
    state.logbook.inject_fault(None);
    let mut retry = retry;
    retry["command_id"] = json!(profile::new_uuid().unwrap());
    assert_eq!(post(retry).await.status, StatusCode::CREATED);
}

// Proves: CL-010-04, CL-010-15; TC-011-002 history paging refusals, export headers, no coding.
#[tokio::test]
async fn history_and_export_routes_follow_the_wire_contract() {
    let f = HttpFixture::new("http://localhost:8095");
    ready(&f);
    for i in 0..11 {
        let mut r = record(&format!("{i:08x}-0000-4000-8000-000000000000"));
        r["comment"] = json!("x".repeat(1024));
        assert_eq!(
            f.post("/contacts", save_body(&f, r), None).await.status,
            StatusCode::CREATED
        );
    }
    let page = get(&f, "/contacts?cursor=0&limit=10", None).await;
    assert_eq!(page.status, StatusCode::OK);
    assert!(
        page.headers.get(header::CONTENT_ENCODING).is_none(),
        "never gzip-coded"
    );
    assert!(page.body.len() <= 16384);
    let v = page.json();
    let keys: Vec<_> = v.as_object().unwrap().keys().cloned().collect();
    assert_eq!(
        keys,
        [
            "cursor",
            "more",
            "next",
            "profile_id",
            "records",
            "total",
            "v"
        ]
    );
    assert_eq!(
        (v["total"].clone(), v["cursor"].clone()),
        (json!(11), json!(0))
    );
    let tail = get(&f, "/contacts?cursor=10&limit=1", None).await.json();
    assert_eq!(
        (tail["records"][0]["index"].clone(), tail["more"].clone()),
        (json!(10), json!(false))
    );
    assert_eq!(
        get(&f, "/contacts?cursor=11", None).await.json()["records"],
        json!([])
    );
    for (path, field) in [
        ("/contacts?limit=11", "limit"),
        ("/contacts?limit=0", "limit"),
        ("/contacts?cursor=12", "cursor"),
    ] {
        assert_eq!(
            code(&get(&f, path, None).await),
            (StatusCode::BAD_REQUEST, json!("out_of_range"), json!(field)),
            "{path}"
        );
    }
    for path in [
        "/contacts?offset=1",
        "/contacts?limit=1&limit=2",
        "/contacts?limit=-1",
    ] {
        assert_eq!(
            code(&get(&f, path, None).await).1,
            "invalid_request",
            "{path}"
        );
    }
    let export = get(&f, "/contacts/export.adi", None).await;
    assert_eq!(export.status, StatusCode::OK);
    assert_eq!(
        export.headers[header::CONTENT_TYPE],
        "application/octet-stream"
    );
    assert_eq!(
        export.headers[header::CONTENT_DISPOSITION],
        "attachment; filename=\"contacts.adi\""
    );
    assert!(export.headers.get(header::CONTENT_ENCODING).is_none());
    let text = String::from_utf8(export.body).unwrap();
    assert!(text.starts_with("ADIF Export\n<adif_ver:5>3.1.8\n"));
    assert_eq!(text.matches(" <eor>\n").count(), 11);
}

// Proves: CL-010-04, CL-010-15; TC-011-002 update reservation, chunks, retry and failure.
#[tokio::test]
async fn adi_import_over_http_reserves_chunks_retries_and_fails_atomically() {
    let f = HttpFixture::new("http://localhost:8096");
    ready(&f);
    let (profile, boot) = ids(&f);
    let bytes = b"<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <rst_sent:3>-10 <eor>\n".repeat(400);
    let id = profile::new_uuid().unwrap();
    let body = |id: &str, total: u64, sha: &str| json!({"v":1,"profile_id":profile,"boot_id":boot,"import_id":id,"total_bytes":total,"sha256":sha});
    let digest = sha(&bytes);
    let max = f
        .post(
            "/contacts/imports",
            body(&profile::new_uuid().unwrap(), 67_108_865, &digest),
            None,
        )
        .await;
    assert_eq!(
        code(&max),
        (
            StatusCode::PAYLOAD_TOO_LARGE,
            json!("request_too_large"),
            json!("total_bytes")
        )
    );
    let reserved = f
        .post(
            "/contacts/imports",
            body(&id, bytes.len() as u64, &digest),
            None,
        )
        .await;
    assert_eq!(reserved.status, StatusCode::CREATED);
    assert_eq!(
        reserved.json(),
        json!({"v":1,"id":id,"state":"receiving","received_bytes":0,"total_bytes":bytes.len(),"added":0,"present":0,"confirmed":0,"skipped":0,"reasons":[],"dropped":[],"error":null})
    );
    assert_eq!(
        f.post(
            "/contacts/imports",
            body(&id, bytes.len() as u64, &digest),
            None
        )
        .await
        .status,
        StatusCode::OK
    );
    assert_eq!(
        code(
            &f.post("/contacts/imports", body(&id, 5, &digest), None)
                .await
        )
        .1,
        "state_conflict"
    );
    assert_eq!(
        code(
            &f.post(
                "/contacts/imports",
                body(&profile::new_uuid().unwrap(), 5, &digest),
                None
            )
            .await
        )
        .1,
        "busy"
    );
    assert_eq!(
        code(&chunk(&f, &id, 0, bytes.len(), &bytes[..16385], None).await).1,
        "request_too_large"
    );
    let mut headers = f.headers(None);
    headers.insert(
        header::CONTENT_RANGE,
        format!("bytes 0-9/{}", bytes.len()).parse().unwrap(),
    );
    assert_eq!(
        code(
            &raw(
                &f,
                Method::PUT,
                &format!("/contacts/imports/{id}"),
                bytes[..10].to_vec(),
                headers
            )
            .await
        )
        .1,
        "unsupported_media_type"
    );
    assert_eq!(
        code(&chunk(&f, &id, 10, bytes.len(), &bytes[10..20], None).await).1,
        "state_conflict"
    );
    let mut start = 0;
    let mut last = None;
    for part in bytes.chunks(16384) {
        last = Some(chunk(&f, &id, start, bytes.len(), part, None).await);
        start += part.len();
    }
    let done = last.unwrap();
    assert_eq!(done.status, StatusCode::CREATED);
    assert_eq!(
        (done.json()["added"].clone(), done.json()["present"].clone()),
        (json!(1), json!(399))
    );
    assert_eq!(
        get(&f, &format!("/contacts/imports/{id}"), None)
            .await
            .json()["state"],
        "completed"
    );
    let file = std::fs::read(f.directory.join("contacts.adi")).unwrap();
    // A broken file publishes nothing and reports record/field context.
    let bad = b"<call:5>N0NEW <qso_date:8>20261031 <time_on:4>1300 <mode:3>FT8 <eor>\n<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <rst_sent:3>-01 <eor>\n<call:5>K1ABC <qso_date:8>20261031 <time_on:4>1230 <band:3>20m <mode:3>FT8 <rst_sent:3>-02 <eor";
    let bad_id = profile::new_uuid().unwrap();
    assert_eq!(
        f.post(
            "/contacts/imports",
            body(&bad_id, bad.len() as u64, &sha(bad)),
            None
        )
        .await
        .status,
        StatusCode::CREATED
    );
    let failed = chunk(&f, &bad_id, 0, bad.len(), bad, None).await;
    assert_eq!(
        code(&failed),
        (
            StatusCode::UNPROCESSABLE_ENTITY,
            json!("import_failed"),
            Value::Null
        )
    );
    let view = get(&f, &format!("/contacts/imports/{bad_id}"), None)
        .await
        .json();
    assert_eq!(view["state"], "failed");
    assert_eq!(
        view["error"],
        json!({"code":"malformed","record":2,"field":null})
    );
    assert_eq!(
        std::fs::read(f.directory.join("contacts.adi")).unwrap(),
        file
    );
}

// Proves: CL-010-04, CL-010-15; TC-011-001 an unreadable log answers 503 and stays untouched.
#[tokio::test]
async fn unreadable_contacts_file_makes_save_storage_unavailable() {
    let mut f = HttpFixture::new("http://localhost:8098");
    ready(&f);
    let path = f.directory.join("contacts.adi");
    std::fs::create_dir(&path).unwrap();
    f.reopen();
    let reply = f
        .post("/contacts", save_body(&f, record(CONTACT)), None)
        .await;
    assert_eq!(
        code(&reply),
        (
            StatusCode::SERVICE_UNAVAILABLE,
            json!("storage_unavailable"),
            Value::Null
        )
    );
    assert_eq!(
        code(&get(&f, "/contacts", None).await).1,
        "storage_unavailable"
    );
    assert!(path.is_dir(), "the unreadable path is not replaced");
    assert_eq!(std::fs::read_dir(&path).unwrap().count(), 0);
}

// Proves: CL-055-03; TC-055-003 the station's cty.dat: bundled by default, replaced by an
// upload that parses (and kept across a restart), refused uploads change nothing, null
// returns to the bundled file, an unreadable stored upload falls back without touching it.
#[tokio::test]
async fn cty_upload_replaces_the_country_table_and_refusals_change_nothing() {
    let mut f = HttpFixture::new("http://localhost:8099");
    ready(&f);
    let path = f.directory.join("cty.dat");
    async fn put(f: &HttpFixture, text: Value) -> HttpReply {
        let (profile, boot) = ids(f);
        let body = json!({"v":1,"profile_id":profile,"boot_id":boot,"text":text});
        raw(
            f,
            Method::PUT,
            "/dxcc",
            serde_json::to_vec(&body).unwrap(),
            f.headers(None),
        )
        .await
    }
    async fn entity(f: &HttpFixture) -> Value {
        let (profile, boot) = ids(f);
        let _ = (profile, boot);
        get(f, "/dxcc?call=HB9BLA", None).await.json()["entity"]["name"].clone()
    }
    let view = |f: &HttpFixture, source: &str, version: Value, entities: u64, unreadable: bool| {
        let (profile, boot) = ids(f);
        json!({"v":1,"profile_id":profile,"boot_id":boot,"source":source,"version":version,
            "entities":entities,"upload_unreadable":unreadable})
    };
    assert_eq!(
        get(&f, "/dxcc", None).await.json(),
        view(&f, "bundled", json!("VER20250115"), 346, false)
    );
    assert_eq!(entity(&f).await, "Switzerland");
    let look = |q: &'static str| get(&f, q, None);
    assert_eq!(
        look("/dxcc?call=DL/HB9BLA").await.json()["entity"]["name"],
        "Germany"
    );
    assert_eq!(
        look("/dxcc?call=K1ABC/MM").await.json()["entity"],
        Value::Null
    );
    for bad in [
        "/dxcc?call=",
        "/dxcc?call=HB9BLA%2FP",
        "/dxcc?x=HB9BLA",
        "/dxcc?call=ABCDEFGHIJKLMN",
    ] {
        assert_eq!(code(&look(bad).await).2, "call", "{bad}");
    }

    let text = "Testland:  14:  28:  EU:  1.00:  -2.00:  -1.0:  TT:\n    TT,HB,=VER20991231;\n";
    let reply = put(&f, json!(text)).await;
    assert_eq!(
        reply.status,
        StatusCode::OK,
        "{}",
        String::from_utf8_lossy(&reply.body)
    );
    assert_eq!(
        reply.json(),
        view(&f, "uploaded", json!("VER20991231"), 1, false)
    );
    assert_eq!(std::fs::read_to_string(&path).unwrap(), text);
    assert_eq!(entity(&f).await, "Testland");

    let invalid = json!({"error":{"code":"invalid_cty","field":"text","line":1}});
    let request = json!({"error":{"code":"invalid_request","field":"text"}});
    for (bad, expected) in [
        (
            json!("Nowhere: 1: 2: XX: 0: 0: 0: NW:\n NW;\n"),
            invalid.clone(),
        ),
        (json!(""), invalid),
        (json!(7), request.clone()),
        (json!("x".repeat(1_048_577)), request),
    ] {
        let reply = put(&f, bad).await;
        assert_eq!(
            (reply.status, reply.json()),
            (StatusCode::BAD_REQUEST, expected)
        );
    }
    let (profile, boot) = ids(&f);
    let stale =
        json!({"v":1,"profile_id":profile,"boot_id":profile::new_uuid().unwrap(),"text":null});
    let stale = raw(
        &f,
        Method::PUT,
        "/dxcc",
        serde_json::to_vec(&stale).unwrap(),
        f.headers(None),
    )
    .await;
    assert_eq!(code(&stale).1, "state_conflict");
    let mut evil = f.headers(None);
    evil.insert(header::ORIGIN, "https://evil.example".parse().unwrap());
    let body = json!({"v":1,"profile_id":profile,"boot_id":boot,"text":null});
    let wrong = raw(
        &f,
        Method::PUT,
        "/dxcc",
        serde_json::to_vec(&body).unwrap(),
        evil,
    )
    .await;
    assert_eq!(code(&wrong).1, "forbidden_origin");
    assert_eq!(
        std::fs::read_to_string(&path).unwrap(),
        text,
        "refusals leave the upload"
    );

    f.reopen();
    assert_eq!(
        get(&f, "/dxcc", None).await.json()["source"],
        "uploaded",
        "kept across restart"
    );
    assert_eq!(entity(&f).await, "Testland");
    let reply = put(&f, Value::Null).await;
    assert_eq!(reply.json()["source"], "bundled");
    assert!(!path.exists());
    assert_eq!(entity(&f).await, "Switzerland");

    std::fs::write(&path, b"not a country file").unwrap();
    f.reopen();
    let reply = get(&f, "/dxcc", None).await.json();
    assert_eq!(
        (reply["source"].clone(), reply["upload_unreadable"].clone()),
        (json!("bundled"), json!(true))
    );
    assert_eq!(std::fs::read(&path).unwrap(), b"not a country file");
}

// Proves: CL-010-04; TC-011-002 ExportAdi over HTTP is streamed (#10 2026-11-04): no
// Content-Length and no exact body size (chunked transfer), the 129 records arrive in two
// data frames (128, then 1), with the export headers unchanged and no content coding.
#[tokio::test]
async fn export_over_http_is_streamed_in_chunks_without_content_length() {
    use axum::body::HttpBody;
    let f = HttpFixture::new("http://localhost:8100");
    ready(&f);
    for i in 0..129 {
        let r = record(&format!("{i:08x}-0000-4000-8000-000000000000"));
        assert_eq!(
            f.post("/contacts", save_body(&f, r), None).await.status,
            StatusCode::CREATED
        );
    }
    let mut request = axum::http::Request::builder()
        .uri("/contacts/export.adi")
        .body(axum::body::Body::empty())
        .unwrap();
    *request.headers_mut() = f.headers(None);
    let response = router(f.app().clone()).oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let (parts, mut body) = response.into_parts();
    assert!(parts.headers.get(header::CONTENT_LENGTH).is_none());
    assert!(parts.headers.get(header::CONTENT_ENCODING).is_none());
    assert_eq!(
        parts.headers[header::CONTENT_DISPOSITION],
        "attachment; filename=\"contacts.adi\""
    );
    assert_eq!(body.size_hint().exact(), None, "not one sized document");
    let mut frames = Vec::new();
    while let Some(frame) =
        std::future::poll_fn(|cx| std::pin::Pin::new(&mut body).poll_frame(cx)).await
    {
        frames.push(String::from_utf8(frame.unwrap().into_data().unwrap().to_vec()).unwrap());
    }
    let counts: Vec<usize> = frames
        .iter()
        .map(|c| c.matches(" <eor>\n").count())
        .collect();
    assert_eq!(counts, [128, 1]);
    assert!(frames[0].starts_with("ADIF Export\n<adif_ver:5>3.1.8\n"));
}
