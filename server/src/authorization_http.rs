//! Strict auth-v1 adapter; the selected profile retains one serialized authority owner.
use crate::authorization::{
    self as auth, Access, AttemptBudget, Authority, Error, Scope, WireScope,
};
use crate::*;
use axum::extract::RawQuery;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::Deserialize;

struct Bootstrap {
    handle: String,
    scope: Option<Scope>,
    origin: String,
    deadline: Instant,
}
pub(crate) struct Service {
    pub(crate) authority: Authority,
    bootstraps: Vec<Bootstrap>,
    attempts: AttemptBudget,
}

impl Service {
    pub(crate) fn initialize(
        store: &mut profile::Store,
        origin: &str,
    ) -> Result<Option<Self>, Error> {
        if !origin.starts_with("https://") {
            return Ok(None);
        }
        let scope = WireScope {
            profile_id: store.document.profile_id.clone(),
            radio_id: profile::new_uuid().map_err(|_| Error::PersistenceFailed)?,
            safety_revision: 1,
        }
        .in_validated_origin(origin)?;
        Ok(Some(Self {
            authority: Authority::load(store, scope)?,
            bootstraps: Vec::new(),
            attempts: AttemptBudget::new(),
        }))
    }
    fn bootstrap(&mut self, origin: &str, now: Instant) -> Result<String, Error> {
        self.bootstraps.retain(|b| now < b.deadline);
        if self.bootstraps.len() >= 10 {
            return Err(Error::Saturated);
        }
        let mut bytes = [0; 32];
        use ring::rand::SecureRandom;
        ring::rand::SystemRandom::new()
            .fill(&mut bytes)
            .map_err(|_| Error::PersistenceFailed)?;
        let handle = URL_SAFE_NO_PAD.encode(bytes);
        self.bootstraps.push(Bootstrap {
            handle: handle.clone(),
            scope: self.authority.record().current_scope.clone(),
            origin: origin.into(),
            deadline: now + Duration::from_secs(60),
        });
        Ok(handle)
    }
    fn bootstrap_context(
        &self,
        handle: &str,
        origin: &str,
        now: Instant,
    ) -> Result<&Bootstrap, Error> {
        auth::decode::<32>(handle).map_err(|_| Error::Unauthorized)?;
        self.bootstraps
            .iter()
            .find(|b| now < b.deadline && b.origin == origin && equal_secret(&b.handle, handle))
            .ok_or(Error::Unauthorized)
    }
}

fn cookie(headers: &HeaderMap, name: &str) -> Result<String, Error> {
    let mut found = None;
    for field in headers.get_all(header::COOKIE) {
        let field = field.to_str().map_err(|_| Error::Unauthorized)?;
        for part in field.split(';').map(str::trim) {
            if part == name {
                return Err(Error::Unauthorized);
            }
            if let Some((key, value)) = part.split_once('=')
                && key == name
            {
                if found.is_some() || auth::decode::<32>(value).is_err() {
                    return Err(Error::Unauthorized);
                }
                found = Some(value.to_owned());
            }
        }
    }
    found.ok_or(Error::Unauthorized)
}
pub(crate) fn access(headers: &HeaderMap, app: &App) -> Result<Access, Error> {
    let state = app.profile.as_ref().ok_or(Error::Unauthorized)?;
    let token = cookie(headers, &cookie_name(app))?;
    state
        .authorization
        .lock()
        .map_err(|_| Error::PersistenceFailed)?
        .as_ref()
        .ok_or(Error::Unauthorized)?
        .authority
        .access(&token, &app.origin, Instant::now())
}

pub(crate) fn bootstrap_session(headers: &HeaderMap, app: &App, body: &str) -> Response {
    if !allowed_origin(headers, app) || !app.origin.starts_with("https://") {
        return failure(StatusCode::FORBIDDEN, "forbidden_origin");
    }
    let Some(state) = &app.profile else {
        return failure(StatusCode::UNAUTHORIZED, "unauthorized");
    };
    let Ok(mut service) = state.authorization.lock() else {
        return mapped(Error::PersistenceFailed);
    };
    let Some(service) = service.as_mut() else {
        return mapped(Error::Unauthorized);
    };
    let now = Instant::now();
    if let Err(e) = service.attempts.admit(now) {
        return mapped(e);
    }
    if app
        .token
        .as_ref()
        .is_none_or(|token| !equal_secret(body, token))
    {
        return mapped(Error::Unauthorized);
    }
    let handle = match service.bootstrap(&app.origin, now) {
        Ok(h) => h,
        Err(e) => return mapped(e),
    };
    let name = format!("wstx_bootstrap_{}", app.profile_id.as_deref().unwrap_or(""));
    (
        StatusCode::NO_CONTENT,
        [(
            header::SET_COOKIE,
            format!("{name}={handle}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=60"),
        )],
    )
        .into_response()
}

fn failure(status: StatusCode, code: &str) -> Response {
    profile_error(status, code, None)
}
fn strict_origin(headers: &HeaderMap, app: &App) -> bool {
    headers.get_all(header::ORIGIN).iter().count() == 1 && allowed_origin(headers, app)
}
fn mapped(error: Error) -> Response {
    match error {
        Error::Invalid => failure(StatusCode::BAD_REQUEST, "invalid_request"),
        Error::Unauthorized => failure(StatusCode::UNAUTHORIZED, "unauthorized"),
        Error::Conflict => failure(StatusCode::CONFLICT, "state_conflict"),
        Error::Saturated => failure(StatusCode::TOO_MANY_REQUESTS, "rate_limited"),
        Error::PersistenceFailed => failure(StatusCode::SERVICE_UNAVAILABLE, "storage_unavailable"),
    }
}
fn bounded(value: Value) -> Result<Response, Error> {
    let bytes = serde_json::to_vec(&value).map_err(|_| Error::Invalid)?;
    if bytes.len() > 1024 {
        return Err(Error::PersistenceFailed);
    }
    Ok(([(header::CONTENT_TYPE, "application/json")], bytes).into_response())
}
fn receipt(entry: &auth::JournalEntry) -> Value {
    json!({"version":1,"operation_id":entry.operation_id,"scope":entry.scope.wire,"outcome":"committed","grant_id":entry.grant_id})
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BootstrapRead {
    version: u8,
    #[serde(default, deserialize_with = "optional_non_null_string")]
    operation_id: Option<String>,
}
fn optional_non_null_string<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<String>, D::Error> {
    String::deserialize(d).map(Some)
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StatusRequest {
    version: u8,
}
#[derive(Deserialize)]
#[serde(untagged)]
enum ChallengeRequest {
    Ordinary(OrdinaryChallenge),
    Receipt(ReceiptChallenge),
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OrdinaryChallenge {
    version: u8,
    grant_id: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReceiptChallenge {
    version: u8,
    operation_id: String,
    scope: WireScope,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReceiptRequest {
    version: u8,
    operation_id: String,
    scope: WireScope,
    grant_id: String,
    nonce: String,
    signature: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RevokeRequest {
    version: u8,
    operation_id: String,
    scope: WireScope,
    all_for_radio: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CommissionRequest {
    version: u8,
    operation_id: String,
    scope: WireScope,
    receive_only_confirmed: bool,
}

#[derive(Clone, Copy)]
enum Operation {
    BootstrapScope,
    Enroll,
    Challenge,
    Proof,
    Status,
    Receipt,
    Revoke,
    Commission,
    RadioIdentity,
}

macro_rules! handler {
    ($name:ident, $kind:ident) => {
        pub(crate) async fn $name(
            State(app): State<App>,
            headers: HeaderMap,
            RawQuery(query): RawQuery,
            body: Result<Bytes, BytesRejection>,
        ) -> Response {
            if !strict_origin(&headers, &app) || !app.origin.starts_with("https://") {
                return failure(StatusCode::FORBIDDEN, "forbidden_origin");
            }
            if query.is_some() {
                return mapped(Error::Invalid);
            }
            if !json_media_type(&headers)
                || headers.get_all(header::CONTENT_TYPE).iter().count() != 1
                || headers.contains_key(header::CONTENT_ENCODING)
            {
                return failure(StatusCode::UNSUPPORTED_MEDIA_TYPE, "unsupported_media_type");
            }
            let body = match body {
                Ok(b) if b.len() <= 1024 => b,
                _ => return failure(StatusCode::PAYLOAD_TOO_LARGE, "request_too_large"),
            };
            match tokio::task::spawn_blocking(move || operate(Operation::$kind, app, headers, body))
                .await
            {
                Ok(Ok(response)) => response,
                Ok(Err(e)) => mapped(e),
                Err(_) => mapped(Error::PersistenceFailed),
            }
        }
    };
}
handler!(bootstrap_scope, BootstrapScope);
handler!(enroll, Enroll);
handler!(challenge, Challenge);
handler!(proof, Proof);
handler!(status, Status);
handler!(reconcile_receipt, Receipt);
handler!(revoke, Revoke);
handler!(commission, Commission);
handler!(radio_identity, RadioIdentity);

fn operate(
    operation: Operation,
    app: App,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Response, Error> {
    let state = app.profile.as_ref().ok_or(Error::Unauthorized)?;
    // One lock order: profile configuration/writer -> authorization -> recording.
    let mut store = state.store.lock().map_err(|_| Error::PersistenceFailed)?;
    let mut owner = state
        .authorization
        .lock()
        .map_err(|_| Error::PersistenceFailed)?;
    let service = owner.as_mut().ok_or(Error::Unauthorized)?;
    let now = Instant::now();
    service.attempts.admit(now)?;
    match operation {
        Operation::BootstrapScope => {
            let request: BootstrapRead = auth::parse_request(&body)?;
            if request.version != 1 {
                return Err(Error::Invalid);
            }
            let token = cookie(
                &headers,
                &format!("wstx_bootstrap_{}", store.document.profile_id),
            )?;
            service.bootstrap_context(&token, &app.origin, now)?;
            let entry = if let Some(id) = request.operation_id {
                if !profile::valid_uuid(&id) {
                    return Err(Error::Invalid);
                }
                Some(
                    service
                        .authority
                        .record()
                        .operation_receipts
                        .iter()
                        .find(|e| {
                            e.operation_id == id && e.kind == auth::OperationKind::RadioIdentity
                        })
                        .ok_or(Error::Conflict)?,
                )
            } else {
                None
            };
            bounded(
                json!({"version":1,"current_scope":service.authority.record().current_scope.as_ref().map(|s| &s.wire),"identity_receipt":entry.map(receipt)}),
            )
        }
        Operation::Enroll => {
            let request: auth::EnrollmentRequest = auth::parse_request(&body)?;
            let verifier = request.verifier(&app.origin)?;
            let token = cookie(
                &headers,
                &format!("wstx_bootstrap_{}", store.document.profile_id),
            )?;
            let context = service.bootstrap_context(&token, &app.origin, now)?;
            if context.scope.as_ref() != Some(&verifier.scope) {
                return Err(Error::Conflict);
            }
            let entry = service.authority.enroll(&mut store, verifier)?;
            bounded(receipt(&entry))
        }
        Operation::Challenge => {
            let request: ChallengeRequest = auth::parse_request(&body)?;
            let (grant_id, operation_id) = match request {
                ChallengeRequest::Ordinary(r) => {
                    if r.version != 1 {
                        return Err(Error::Invalid);
                    }
                    auth::decode::<32>(&r.grant_id)?;
                    (r.grant_id, None)
                }
                ChallengeRequest::Receipt(r) => {
                    if r.version != 1 || !profile::valid_uuid(&r.operation_id) {
                        return Err(Error::Invalid);
                    }
                    let reconstructed = r.scope.in_validated_origin(&app.origin)?;
                    let entry = service
                        .authority
                        .record()
                        .operation_receipts
                        .iter()
                        .find(|e| e.operation_id == r.operation_id && e.scope == reconstructed)
                        .ok_or(Error::Conflict)?;
                    let verifier = entry.owner_verifier.as_ref().ok_or(Error::Unauthorized)?;
                    (verifier.grant_id.clone(), Some(r.operation_id))
                }
            };
            let nonce = service.authority.challenge(
                &grant_id,
                &app.origin,
                operation_id.as_deref(),
                now,
            )?;
            let (scope, verifier) = service
                .authority
                .challenge_details(&nonce)
                .ok_or(Error::Unauthorized)?;
            bounded(
                json!({"version":1,"grant_id":grant_id,"scope":scope.wire,"public_key":verifier.public_key,"nonce":nonce,"lifetime_seconds":60}),
            )
        }
        Operation::Proof => {
            let request: auth::ProofRequest = auth::parse_request(&body)?;
            let mut prepared = None;
            service
                .authority
                .prove_transport(&request, &app.origin, now, |handle| {
                    prepared = Some(
                        format!(
                            "{}={handle}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=28800",
                            cookie_name(&app)
                        )
                        .parse::<axum::http::HeaderValue>()
                        .map_err(|_| Error::Invalid)?,
                    );
                    Ok(())
                })?;
            let mut response = StatusCode::NO_CONTENT.into_response();
            response
                .headers_mut()
                .insert(header::SET_COOKIE, prepared.ok_or(Error::Invalid)?);
            Ok(response)
        }
        Operation::Receipt => {
            let r: ReceiptRequest = auth::parse_request(&body)?;
            if !profile::valid_uuid(&r.operation_id) {
                return Err(Error::Invalid);
            }
            let scope = r.scope.in_validated_origin(&app.origin)?;
            if !service
                .authority
                .record()
                .operation_receipts
                .iter()
                .any(|e| e.operation_id == r.operation_id && e.scope == scope)
            {
                return Err(Error::Conflict);
            }
            let request = auth::ProofRequest {
                version: r.version,
                grant_id: r.grant_id,
                nonce: r.nonce,
                signature: r.signature,
            };
            bounded(receipt(&service.authority.prove_receipt(
                &request,
                &r.operation_id,
                &app.origin,
                now,
            )?))
        }
        Operation::Status => {
            let r: StatusRequest = auth::parse_request(&body)?;
            if r.version != 1 {
                return Err(Error::Invalid);
            }
            let handle = cookie(&headers, &cookie_name(&app))?;
            let access = service.authority.access(&handle, &app.origin, now)?;
            let record = service.authority.record();
            let commissioned = record.commissioning.as_ref().is_some_and(|c| {
                c.scope == access.scope
                    && c.receive_only_confirmed
                    && c.control == store.document.control
            });
            // Automatic CAT lifecycle is a pending slice. Without its durable
            // commissioning, this adapter never fabricates ready/readback/retry.
            let condition = if store.document.control.mode == "disabled" {
                "disabled"
            } else if !commissioned {
                "commissioningRequired"
            } else {
                "waitingForDevice"
            };
            let receive = state.recording.receive_snapshot();
            bounded(
                json!({"version":1,"scope":access.scope.wire,"condition":condition,"error":null,"retry_after_ms":null,"commissioned":commissioned,
                "receive_state":{"audio":receive["audio"]["state"],"decoder":receive["job"]["state"]}}),
            )
        }
        Operation::Revoke => {
            let r: RevokeRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.operation_id) {
                return Err(Error::Invalid);
            }
            let scope = r.scope.in_validated_origin(&app.origin)?;
            let handle = cookie(&headers, &cookie_name(&app))?;
            let access = service.authority.access(&handle, &app.origin, now)?;
            if scope != access.scope {
                return Err(Error::Conflict);
            }
            service.authority.recheck_dispatch(&access)?;
            bounded(receipt(&service.authority.revoke(
                &mut store,
                &access.grant_id,
                &r.operation_id,
                r.all_for_radio,
            )?))
        }
        Operation::Commission => {
            let r: CommissionRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.operation_id) || !r.receive_only_confirmed
            {
                return Err(Error::Invalid);
            }
            let scope = r.scope.in_validated_origin(&app.origin)?;
            let handle = cookie(&headers, &cookie_name(&app))?;
            if service.authority.access(&handle, &app.origin, now)?.scope != scope {
                return Err(Error::Conflict);
            }
            // No success/acknowledgement until the exact safety/close transaction is wired.
            Err(Error::Conflict)
        }
        Operation::RadioIdentity => {
            let r: auth::IdentityRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.operation_id) {
                return Err(Error::Invalid);
            }
            if let Some(scope) = r.expected_scope {
                scope.in_validated_origin(&app.origin)?;
            }
            let token = cookie(
                &headers,
                &format!("wstx_bootstrap_{}", store.document.profile_id),
            )?;
            service.bootstrap_context(&token, &app.origin, now)?;
            // A pending confirmed-release transaction is never represented as committed.
            Err(Error::Conflict)
        }
    }
}
