use super::*;

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
    assert!(authenticated(&headers, &app));
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
