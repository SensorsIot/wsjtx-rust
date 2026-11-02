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
    /// Refused MCP client tokens (#58): 10 per 60 s, then 429; valid tokens never wait.
    mcp_failures: AttemptBudget,
    /// The most recent MCP token uses (#58 audit), newest last; the file keeps them all.
    mcp_audit: std::collections::VecDeque<Value>,
}
/// Recent MCP token uses shown in Settings.
const MCP_AUDIT_RECENT: usize = 32;
/// The durable audit log of MCP token uses (JSON lines) in the profile directory; at this
/// size it moves to `mcp-audit.1.log` (one older file kept).
pub(crate) const MCP_AUDIT_FILE: &str = "mcp-audit.log";
const MCP_AUDIT_ROTATE_BYTES: u64 = 1 << 20;
pub(crate) fn utc_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
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
            mcp_failures: AttemptBudget::new(),
            mcp_audit: std::collections::VecDeque::new(),
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

/// CL-022-03 precondition for the station's automatic read-only CAT lifecycle.
/// Plaintext profiles have no grant authority and therefore never open CAT.
pub(crate) fn cat_gate(
    store: &profile::Store,
    service: Option<&Service>,
) -> crate::cat_lifecycle::Gate {
    use crate::cat_lifecycle::{Gate, Key};
    let control = &store.document.control;
    if control.mode != "cat" {
        return Gate::Disabled;
    }
    let Some(service) = service else {
        return Gate::Unauthorized;
    };
    match service.authority.automatic_cat(control) {
        None => Gate::Unauthorized,
        Some(false) => Gate::CommissioningRequired,
        Some(true) => {
            let scope = &service
                .authority
                .record()
                .current_scope
                .as_ref()
                .unwrap()
                .wire;
            let endpoint = control.endpoint.clone().unwrap_or_default();
            match wstx_rust::radio_control::Configuration::parse(&endpoint) {
                Ok(configuration) => Gate::Eligible {
                    key: Key {
                        radio_id: scope.radio_id.clone(),
                        safety_revision: scope.safety_revision,
                        profile_revision: store.document.revision,
                        endpoint,
                    },
                    configuration,
                },
                Err(_) => Gate::InvalidConfiguration,
            }
        }
    }
}
/// One lifecycle tick under the documented lock order store -> authorization -> recording.
pub(crate) fn cat_tick(state: &ProfileState, now: Instant) {
    let Ok(store) = state.store.lock() else {
        return;
    };
    let Ok(owner) = state.authorization.lock() else {
        return;
    };
    let gate = cat_gate(&store, owner.as_ref());
    state.recording.cat_maintain(&gate, now);
    // The transmit owner reads, never drives, the lifecycle's actor and gate.
    if let Some(transmit) = state.recording.transmit.get() {
        transmit.update(&store.document, &gate, state.recording.radio_actor());
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
/// The grant transport handle of a selected HTTPS profile request (cookie), for an owner
/// that must outlive the request no longer than that transport (WstxMcp D7).
pub(crate) fn transport_token(headers: &HeaderMap, app: &App) -> Option<String> {
    cookie(headers, &cookie_name(app)).ok()
}
/// Operating HTTP/WS authority. A selected HTTPS profile requires its durable grant
/// transport, validated (scope, grant, current revocation generation) under the one
/// authority lock; a plaintext profile keeps the runtime-token contract with no grant.
pub(crate) fn operating_access(headers: &HeaderMap, app: &App) -> Result<Option<Access>, Error> {
    let state = app.profile.as_ref().ok_or(Error::Unauthorized)?;
    let owner = state
        .authorization
        .lock()
        .map_err(|_| Error::PersistenceFailed)?;
    configuration_access(headers, app, owner.as_ref())
}
/// Potential mutex waits stay wholly on Tokio's blocking pool. A busy writer
/// remains a pending authority check, never a fabricated unauthorized result.
pub(crate) async fn operating_access_async(
    headers: &HeaderMap,
    app: &App,
) -> Result<Option<Access>, Error> {
    let headers = headers.clone();
    let app = app.clone();
    tokio::task::spawn_blocking(move || operating_access(&headers, &app))
        .await
        .map_err(|_| Error::PersistenceFailed)?
}
pub(crate) fn configuration_access(
    headers: &HeaderMap,
    app: &App,
    service: Option<&Service>,
) -> Result<Option<Access>, Error> {
    if app.profile_id.is_some() && app.origin.starts_with("https://") {
        let service = service.ok_or(Error::Unauthorized)?;
        let token = cookie(headers, &cookie_name(app))?;
        return service
            .authority
            .access(&token, &app.origin, Instant::now())
            .map(Some);
    }
    if authenticated(headers, app) {
        Ok(None)
    } else {
        Err(Error::Unauthorized)
    }
}
/// Why POST /mcp refused a bearer (#58).
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum McpRefusal {
    /// Not an MCP client token (the station access token or a browser grant transport,
    /// as configured before #58): refused with the hint to create an MCP client token.
    NotMcpToken,
    /// An unknown or revoked MCP client token.
    Unknown,
    RateLimited,
    Unavailable,
}
/// The validated caller of one MCP request.
pub(crate) struct McpCaller {
    /// The internal MCP-principal station transport for the in-process dispatch.
    pub(crate) transport: String,
    pub(crate) client_id: String,
    pub(crate) name: String,
}
/// Validates an MCP client token under the one store -> authorization lock order.
pub(crate) fn mcp_access(app: &App, bearer: &str) -> Result<McpCaller, McpRefusal> {
    let state = app.profile.as_ref().ok_or(McpRefusal::Unknown)?;
    let mut store = state.store.lock().map_err(|_| McpRefusal::Unavailable)?;
    let mut owner = state
        .authorization
        .lock()
        .map_err(|_| McpRefusal::Unavailable)?;
    // A plaintext profile has no grant authority and therefore no MCP access.
    let service = owner.as_mut().ok_or(McpRefusal::Unknown)?;
    let now = Instant::now();
    let refused = |service: &mut Service, refusal| {
        if service.mcp_failures.admit(now).is_err() {
            McpRefusal::RateLimited
        } else {
            refusal
        }
    };
    if !bearer.starts_with(auth::MCP_TOKEN_PREFIX) {
        return Err(refused(service, McpRefusal::NotMcpToken));
    }
    let (transport, client) = match service.authority.mcp_transport(bearer, &app.origin, now) {
        Ok(found) => found,
        Err(Error::Unauthorized | Error::Invalid) => {
            return Err(refused(service, McpRefusal::Unknown));
        }
        Err(_) => return Err(McpRefusal::Unavailable),
    };
    service
        .authority
        .mcp_used(&mut store, &client.id, utc_ms())
        .map_err(|_| McpRefusal::Unavailable)?;
    Ok(McpCaller {
        transport,
        client_id: client.id,
        name: client.name,
    })
}
/// One audit entry per MCP token use: client, name, action, outcome status and time.
pub(crate) fn mcp_audit(app: &App, caller: &McpCaller, action: &str, status: u16) {
    let Some(state) = app.profile.as_ref() else {
        return;
    };
    let entry = json!({"utc_ms":utc_ms(),"client_id":caller.client_id,"name":caller.name,
        "action":action,"status":status});
    let Ok(mut store) = state.store.lock() else {
        return;
    };
    let _ = store.append_log_line(MCP_AUDIT_FILE, &entry.to_string(), MCP_AUDIT_ROTATE_BYTES);
    let Ok(mut owner) = state.authorization.lock() else {
        return;
    };
    if let Some(service) = owner.as_mut() {
        if service.mcp_audit.len() == MCP_AUDIT_RECENT {
            service.mcp_audit.pop_front();
        }
        service.mcp_audit.push_back(entry);
    }
}
pub(crate) async fn bootstrap_session_async(
    headers: &HeaderMap,
    app: &App,
    body: &str,
) -> Response {
    let headers = headers.clone();
    let app = app.clone();
    let body = body.to_owned();
    tokio::task::spawn_blocking(move || bootstrap_session(&headers, &app, &body))
        .await
        .unwrap_or_else(|_| mapped(Error::PersistenceFailed))
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
pub(crate) fn mapped(error: Error) -> Response {
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
struct McpCreateRequest {
    version: u8,
    name: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct McpRevokeRequest {
    version: u8,
    client_id: String,
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
    McpCreate,
    McpRevoke,
}

async fn finish_operation(job: tokio::task::JoinHandle<Result<Response, Error>>) -> Response {
    match job.await {
        Ok(Ok(response)) => response,
        Ok(Err(e)) => mapped(e),
        Err(_) => mapped(Error::PersistenceFailed),
    }
}

// Transaction/HTTP-completion fault seam only; Router admission is tested separately.
#[cfg(test)]
pub(crate) async fn commission_with_fault(
    app: App,
    headers: HeaderMap,
    body: Bytes,
    stage: &'static str,
) -> Response {
    finish_operation(tokio::task::spawn_blocking(move || {
        profile::tests::with_fault(stage, || operate(Operation::Commission, app, headers, body))
    }))
    .await
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
            finish_operation(tokio::task::spawn_blocking(move || {
                operate(Operation::$kind, app, headers, body)
            }))
            .await
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
/// GET /authorization/v1/mcp-clients: the MCP clients and their recent use (read-only).
pub(crate) async fn mcp_clients(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
) -> Response {
    if (headers.contains_key(header::ORIGIN) && !strict_origin(&headers, &app))
        || !app.origin.starts_with("https://")
    {
        return failure(StatusCode::FORBIDDEN, "forbidden_origin");
    }
    if query.is_some() {
        return mapped(Error::Invalid);
    }
    finish_operation(tokio::task::spawn_blocking(move || {
        let state = app.profile.as_ref().ok_or(Error::Unauthorized)?;
        let owner = state
            .authorization
            .lock()
            .map_err(|_| Error::PersistenceFailed)?;
        let service = owner.as_ref().ok_or(Error::Unauthorized)?;
        browser_access(service, &headers, &app, Instant::now())?;
        mcp_listing(service)
    }))
    .await
}
handler!(mcp_create, McpCreate);
handler!(mcp_revoke, McpRevoke);

/// The caller's current browser grant access. An MCP-principal transport is never one:
/// the auth-v1 operations and MCP client management belong to the browser (#58).
fn browser_access(
    service: &Service,
    headers: &HeaderMap,
    app: &App,
    now: Instant,
) -> Result<Access, Error> {
    let handle = cookie(headers, &cookie_name(app))?;
    let access = service.authority.access(&handle, &app.origin, now)?;
    if !access.principal.is_operator() {
        return Err(Error::Unauthorized);
    }
    Ok(access)
}
fn mcp_listing(service: &Service) -> Result<Response, Error> {
    let clients: Vec<Value> = service
        .authority
        .mcp_clients()
        .iter()
        .map(|c| {
            json!({"client_id":c.id,"name":c.name,"created_utc_ms":c.created_utc_ms,
                "last_used_utc_ms":c.last_used_utc_ms})
        })
        .collect();
    let recent: Vec<&Value> = service.mcp_audit.iter().rev().collect();
    let bytes = serde_json::to_vec(
        &json!({"version":1,"max_clients":auth::MCP_CAP,"clients":clients,"recent":recent}),
    )
    .map_err(|_| Error::Invalid)?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/json"),
            (header::CACHE_CONTROL, "no-store"),
        ],
        bytes,
    )
        .into_response())
}

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
    // The 10/60 budget bounds setup (token/bootstrap) attempts only. Grant operations are
    // bounded by the 64 one-use 60 s challenges, one transport per grant and grant auth.
    if matches!(operation, Operation::BootstrapScope | Operation::Enroll) {
        service.attempts.admit(now)?;
    }
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
            bounded(
                json!({"version":1,"current_scope":service.authority.record().current_scope.as_ref().map(|s| &s.wire)}),
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
            let access = browser_access(service, &headers, &app, now)?;
            let gate = cat_gate(&store, Some(service));
            let commissioned =
                service.authority.automatic_cat(&store.document.control) == Some(true);
            // Before the lifecycle policy observes an eligible gate it reports waiting,
            // never a fabricated ready/readback.
            let (condition, error, retry_after_ms) = match &gate {
                crate::cat_lifecycle::Gate::Disabled => ("disabled", None, None),
                crate::cat_lifecycle::Gate::Unauthorized => ("unauthorized", None, None),
                crate::cat_lifecycle::Gate::CommissioningRequired => {
                    ("commissioningRequired", None, None)
                }
                _ => match state.recording.cat_status(&gate) {
                    ("disabled" | "unauthorized" | "commissioningRequired", _, _) => {
                        ("waitingForDevice", None, None)
                    }
                    current => current,
                },
            };
            let receive = state.recording.receive_snapshot();
            bounded(
                json!({"version":1,"scope":access.scope.wire,"condition":condition,"error":error,"retry_after_ms":retry_after_ms,"commissioned":commissioned,
                "receive_state":{"audio":receive["audio"]["state"],"decoder":receive["job"]["state"]}}),
            )
        }
        Operation::Revoke => {
            let r: RevokeRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.operation_id) {
                return Err(Error::Invalid);
            }
            let scope = r.scope.in_validated_origin(&app.origin)?;
            let access = browser_access(service, &headers, &app, now)?;
            if scope != access.scope {
                return Err(Error::Conflict);
            }
            let mut response = bounded(receipt(&service.authority.revoke(
                &mut store,
                &access.grant_id,
                &r.operation_id,
                r.all_for_radio,
            )?))?;
            // The revoked transport is dead server-side; also clear the browser copy.
            response.headers_mut().insert(
                header::SET_COOKIE,
                format!(
                    "{}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0",
                    cookie_name(&app)
                )
                .parse()
                .map_err(|_| Error::Invalid)?,
            );
            Ok(response)
        }
        Operation::Commission => {
            let r: CommissionRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.operation_id) || !r.receive_only_confirmed
            {
                return Err(Error::Invalid);
            }
            let scope = r.scope.in_validated_origin(&app.origin)?;
            let access = browser_access(service, &headers, &app, now)?;
            if access.scope != scope {
                return Err(Error::Conflict);
            }
            bounded(receipt(&service.authority.commission(
                &mut store,
                &access,
                &r.operation_id,
            )?))
        }
        Operation::McpCreate => {
            let r: McpCreateRequest = auth::parse_request(&body)?;
            if r.version != 1 {
                return Err(Error::Invalid);
            }
            browser_access(service, &headers, &app, now)?;
            let (client, token) =
                service
                    .authority
                    .create_mcp_client(&mut store, &r.name, utc_ms())?;
            // The token is in this response only; the station keeps its SHA-256.
            let mut response = bounded(json!({"version":1,"client_id":client.id,
                "name":client.name,"created_utc_ms":client.created_utc_ms,"token":token}))?;
            response.headers_mut().insert(
                header::CACHE_CONTROL,
                "no-store".parse().map_err(|_| Error::Invalid)?,
            );
            Ok(response)
        }
        Operation::McpRevoke => {
            let r: McpRevokeRequest = auth::parse_request(&body)?;
            if r.version != 1 || !profile::valid_uuid(&r.client_id) {
                return Err(Error::Invalid);
            }
            browser_access(service, &headers, &app, now)?;
            service
                .authority
                .revoke_mcp_client(&mut store, &r.client_id)?;
            mcp_listing(service)
        }
    }
}
