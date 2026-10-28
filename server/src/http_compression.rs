//! H1 is a representation adapter for the six existing fixed, bounded Json handlers.
//! Handler/auth/error/cap publication happens once before standard negotiation.
use axum::{
    body::{Body, HttpBody},
    extract::Request,
    http::{Extensions, HeaderMap, HeaderValue, Method, StatusCode, Version, header},
    middleware::Next,
    response::Response,
};
use std::{convert::Infallible, future::ready};
use tower::{Layer, ServiceExt, service_fn};
use tower_http::compression::CompressionLayer;

pub(crate) fn logical_cap(path: &str) -> Option<u64> {
    match path {
        "/receive/selection" => Some(3072),
        "/radio" => Some(2048),
        "/profile" | "/recording" | "/receive" => Some(8192),
        "/receive/results" => Some(16384),
        _ => None,
    }
}

pub(crate) async fn encode(request: Request, next: Next) -> Response {
    let method = request.method().clone();
    let path = request.uri().path().to_owned();
    let mut negotiation = HeaderMap::new();
    for value in request.headers().get_all(header::ACCEPT_ENCODING) {
        negotiation.append(header::ACCEPT_ENCODING, value.clone());
    }
    // Never run a second handler, authentication dispatch or device operation.
    let response = next.run(request).await;
    encode_response(&method, &path, negotiation, response).await
}

fn vary_tokens(headers: &HeaderMap, token: &[u8]) -> bool {
    headers.get_all(header::VARY).iter().any(|value| {
        value
            .as_bytes()
            .split(|b| *b == b',')
            .any(|part| part.trim_ascii().eq_ignore_ascii_case(token))
    })
}

fn snapshot_failure(original: &Response) -> Response {
    // Existing bounded 503 mapping, not a new error code or stream-buffering policy.
    let mut failure = crate::selection_http::error("snapshot_limit");
    for (name, value) in original.headers() {
        if name != header::CONTENT_LENGTH && name != header::CONTENT_TYPE && name != header::ETAG {
            failure.headers_mut().append(name.clone(), value.clone());
        }
    }
    failure
}

pub(crate) async fn encode_response(
    method: &Method,
    path: &str,
    negotiation: HeaderMap,
    mut response: Response,
) -> Response {
    let Some(cap) = logical_cap(path) else {
        return response;
    };
    let json = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(';').next())
        .is_some_and(|v| v.trim().eq_ignore_ascii_case("application/json"));
    if method != Method::GET
        || !response.status().is_success()
        || !json
        || matches!(
            response.status(),
            StatusCode::NO_CONTENT | StatusCode::RESET_CONTENT
        )
        || response.headers().contains_key(header::CONTENT_ENCODING)
        || response.headers().contains_key(header::CONTENT_RANGE)
    {
        return response;
    }
    let size = response.body().size_hint();
    if size.exact() == Some(0) {
        return response;
    }
    // Current typed Json handlers guarantee this without polling or buffering the body.
    // Unknown/excess cannot prove its logical contract and must fail before negotiation.
    if size.exact().is_none_or(|len| len > cap) {
        return snapshot_failure(&response);
    }

    let star = vary_tokens(response.headers(), b"*");
    let original_vary = star.then(|| {
        response
            .headers()
            .get_all(header::VARY)
            .iter()
            .cloned()
            .collect::<Vec<_>>()
    });
    if !star && !vary_tokens(response.headers(), b"accept-encoding") {
        response
            .headers_mut()
            .append(header::VARY, HeaderValue::from_static("Accept-Encoding"));
    }
    // Only an already-created eligible success reaches the standard library. Its
    // unsatisfiable-encoding branch must never replace an original authentication/error.
    let mut existing = Some(response);
    let service = service_fn(move |_: Request| {
        ready(Ok::<_, Infallible>(
            existing.take().expect("one-shot response adapter"),
        ))
    });
    let request = Request::builder()
        .body(Body::empty())
        .expect("fixed empty request");
    let (mut parts, body) = request.into_parts();
    parts.headers = negotiation;
    let response = CompressionLayer::new()
        .gzip(true)
        .compress_when(|_: StatusCode, _: Version, _: &HeaderMap, _: &Extensions| true)
        .layer(service)
        .oneshot(Request::from_parts(parts, body))
        .await;
    let mut response = match response {
        Ok(response) => response.map(Body::new),
        Err(never) => match never {},
    };
    if let Some(values) = original_vary {
        // Upstream adds Accept-Encoding even beside Vary:*. The exact-token contract
        // preserves the original dominating star fields instead of introducing extras.
        response.headers_mut().remove(header::VARY);
        for value in values {
            response.headers_mut().append(header::VARY, value);
        }
    }
    if response
        .headers()
        .get(header::CONTENT_ENCODING)
        .is_some_and(|v| v == "gzip")
        && response
            .headers()
            .get_all(header::ETAG)
            .iter()
            .any(|v| !v.as_bytes().starts_with(b"W/"))
    {
        response.headers_mut().remove(header::ETAG);
    }
    response
}
