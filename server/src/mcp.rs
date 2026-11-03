#![forbid(unsafe_code)]
//! WstxMcp::McpEndpoint: the station's MCP Streamable HTTP endpoint (POST /mcp).
//! Dual-era: modern 2026-07-28 (per-request `_meta`, `server/discover`) and legacy
//! 2025-11-25/2025-06-18 (`initialize`, stateless: no Mcp-Session-Id). 2025-03-26 is not
//! offered: it requires JSON-RPC batches, which this endpoint refuses.
//! Every tool is one existing versioned station operation, dispatched in-process
//! through the station router with an internal MCP-principal transport of the caller's
//! validated MCP client token; the adapter keeps no station state, modem, QSO engine or
//! transmit authority. Authorization is `Authorization: Bearer <MCP client token>` only
//! (#58): cookies sent to /mcp are never read, and a browser grant transport or the
//! station access token is refused, so MCP never acts as the browser operator.
use crate::*;
use axum::extract::RawQuery;
use axum::http::Method;
use tower::ServiceExt;

pub const BODY_MAX: usize = 8192;
pub const MODERN: &str = "2026-07-28";
pub const LEGACY: [&str; 2] = ["2025-11-25", "2025-06-18"];
/// Station responses carried in one tool result (the largest is a results page).
const STATION_BYTES_MAX: usize = 65536;

fn supported() -> Value {
    json!([MODERN, LEGACY[0], LEGACY[1]])
}
fn rpc_error(
    status: StatusCode,
    id: Value,
    code: i64,
    message: &str,
    data: Option<Value>,
) -> Response {
    let mut error = json!({"code":code,"message":message});
    if let Some(d) = data {
        error["data"] = d;
    }
    (status, Json(json!({"jsonrpc":"2.0","id":id,"error":error}))).into_response()
}
pub async fn not_allowed() -> Response {
    (StatusCode::METHOD_NOT_ALLOWED, [(header::ALLOW, "POST")]).into_response()
}
/// The bearer text of exactly one `Authorization: Bearer <token>` field (1..=128 bytes).
fn bearer(headers: &HeaderMap) -> Option<String> {
    let mut fields = headers.get_all(header::AUTHORIZATION).iter();
    let value = fields.next()?.to_str().ok()?;
    if fields.next().is_some() {
        return None;
    }
    let token = value.strip_prefix("Bearer ")?;
    (1..=128).contains(&token.len()).then(|| token.to_owned())
}
/// The migration hint for a bearer that is not an MCP client token (#58).
pub const TOKEN_HINT: &str = "POST /mcp accepts only an MCP client token (wstx_mcp_...). \
Create one in Settings > General > Access & grants > MCP clients and configure it as \
Authorization: Bearer <token>; the station access token and browser grants are not accepted.";
/// The station status of a tools/call, carried to the audit entry.
#[derive(Clone, Copy)]
struct ToolStatus(u16);
/// The audited action of an MCP request: method, tool and its view or command action.
fn audit_action(body: &Result<Bytes, BytesRejection>) -> String {
    let Some(v) = body
        .as_ref()
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(b).ok())
    else {
        return "invalid_request".into();
    };
    let p = &v["params"];
    let a = &p["arguments"];
    let parts = [
        &v["method"],
        &p["name"],
        &a["view"],
        &a["command"]["action"],
    ];
    let text = parts
        .iter()
        .filter_map(|v| v.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    let text: String = text
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || " _/.-".contains(*c))
        .take(80)
        .collect();
    if text.is_empty() {
        "invalid_request".into()
    } else {
        text
    }
}
/// The station credential the in-process dispatch presents: exactly the internal
/// MCP-principal transport, under the station's own cookie name, and nothing from the
/// MCP request.
fn station_headers(app: &App, token: &str) -> HeaderMap {
    let mut h = HeaderMap::new();
    if let Ok(v) = app.origin.parse() {
        h.insert(header::ORIGIN, v);
    }
    if let Ok(v) = format!("{}={token}", cookie_name(app)).parse() {
        h.insert(header::COOKIE, v);
    }
    h
}
fn header_text<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    headers.get(name).and_then(|v| v.to_str().ok())
}
/// Mcp-Name value, decoding the `=?base64?...?=` sentinel form.
fn mcp_name(headers: &HeaderMap) -> Option<String> {
    let raw = header_text(headers, "mcp-name")?;
    if let Some(inner) = raw
        .strip_prefix("=?base64?")
        .and_then(|r| r.strip_suffix("?="))
    {
        use base64::Engine as _;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(inner)
            .ok()?;
        return String::from_utf8(bytes).ok();
    }
    Some(raw.to_owned())
}

const VIEWS: [(&str, &str); 9] = [
    ("profile", "/profile"),
    ("receive", "/receive"),
    ("selection", "/receive/selection"),
    ("radio", "/radio"),
    ("transmit", "/transmit"),
    ("contact", "/contact"),
    ("automation", "/automation"),
    ("strategy", "/strategy"),
    ("alerts", "/strategy/alerts"),
];
/// The station routes an MCP tool call dispatches to (WstxMcp::ToolCatalog).
fn tool_route(method: &Method, path: &str) -> bool {
    match *method {
        Method::GET => path == "/receive/results" || VIEWS.iter().any(|(_, p)| *p == path),
        Method::POST => matches!(
            path,
            "/contact/command" | "/transmit/halt" | "/automation/command" | "/strategy/evaluate"
        ),
        _ => false,
    }
}
/// #58 boundary guard for every station route: a request whose session credential is an
/// MCP-principal transport is refused 401 on every route that no MCP tool dispatches to
/// (POST /transmit/command, PUT /profile, PUT /strategy, logbook, WS, settings, receive and radio
/// control ...), so the principal never depends on that handle staying in-process.
pub(crate) async fn principal_guard(
    State(app): State<App>,
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> Response {
    if app.profile.is_some()
        && request.headers().contains_key(header::COOKIE)
        && !tool_route(request.method(), request.uri().path())
        && let Ok(Some(access)) =
            authorization_http::operating_access_async(request.headers(), &app).await
        && !access.principal.is_operator()
    {
        return authorization_http::mapped(authorization::Error::Unauthorized);
    }
    next.run(request).await
}
/// WstxMcp::ToolCatalog, in this fixed order.
pub fn tools() -> Value {
    let output = json!({"type":"object","properties":{"v":{"const":1},"tool":{"type":"string"},
        "status":{"type":"integer"},"result":{}},"required":["v","tool","status","result"],"additionalProperties":false});
    let object = |d: &str| json!({"type":"object","description":d});
    let uuid = json!({"type":"string","format":"uuid"});
    let safe = json!({"type":"integer","minimum":0,"maximum":9_007_199_254_740_991u64});
    json!([
        {"name":"wstx_read","title":"Read station state",
         "description":"Read one station view exactly as the browser receives it: profile (GET /profile), receive (GET /receive), selection (GET /receive/selection), radio (GET /radio), transmit (GET /transmit), contact (GET /contact, the ContactSnapshot with contact_revision and transmit.safety_revision), automation (GET /automation), strategy (GET /strategy: the saved strategies, the active one and my continent; editing stays in the browser) or alerts (GET /strategy/alerts: the station's alert history of strategy rules marked alert; clearing stays in the browser). No effect.",
         "inputSchema":{"type":"object","properties":{"view":{"type":"string","enum":VIEWS.map(|v|v.0)}},"required":["view"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"readOnlyHint":true}},
        {"name":"wstx_results","title":"Read decoded results",
         "description":"Read one page of live decoded results of the receive job (GET /receive/results): source_id, job_id and generation from wstx_read receive, cursor 0 or the previous next_cursor, limit 1..16 (default 16). No effect.",
         "inputSchema":{"type":"object","properties":{"source_id":uuid,"job_id":uuid,"generation":safe,"cursor":safe,
            "limit":{"type":"integer","minimum":1,"maximum":16}},"required":["source_id","job_id","generation","cursor"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"readOnlyHint":true}},
        {"name":"wstx_contact_command","title":"Contact command",
         "description":"Send one ContactCommand (POST /contact/command), the same request the browser sends: {v:1,profile_id,boot_id,command_id (new UUID per intent, reuse it only to retry the same body),contact_revision,action,...}. Actions: select_row {row:{source_id,job_id,generation,sequence},replace}, enter_dx {dx_call,dx_grid,replace}, cancel, choose_next {slot}, edit_message {slot,text}, set_report {report}, set_tx1_skip|set_hold_tx|set_auto_seq|set_call_first|tune {enabled}, set_activity {activity: none|na_vhf|ww_digi|arrl_digi|field_day|rtty|hound, exchange (field_day e.g. 1A EMA; rtty a state/province, DX or #; none for hound)}, enable_tx {enabled,safety_revision}, set_tx4 {form}, set_frequency {rx_hz,tx_hz}, set_parity {parity}, set_watchdogs {tx_minutes,tune_seconds}, redecode, open_log (Log QSO: logs the current contact now; completed contacts log themselves). Selecting never transmits; enable_tx needs this credential's transmit grant.",
         "inputSchema":{"type":"object","properties":{"command":object("ContactCommand body")},"required":["command"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}},
        {"name":"wstx_transmit_halt","title":"Halt transmission",
         "description":"Halt Tx now (POST /transmit/halt): {v:1,profile_id,boot_id,command_id}. Stops any transmission, disarms and ends a running automation.",
         "inputSchema":{"type":"object","properties":{"halt":object("HaltTransmit body")},"required":["halt"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}},
        {"name":"wstx_automation_command","title":"Automation command",
         "description":"Configure, start or stop the station's FT4/FT8 automation (POST /automation/command): {v:1,profile_id,boot_id,command_id,action,...}. configure {expected_policy_revision,configuration:null|{modes:[\"ft8\"|\"ft4\"],ranking:\"first_seen\"|\"strongest_snr\"|\"lowest_frequency\",min_snr_db:null|-50..49,allowed_calls:[],blocked_calls:[],max_contacts:1..100,max_unanswered_periods:1..20,completion_action:\"stop\"|\"next_candidate\",max_run_minutes:1..480 (optional, default 120),strategy:true|false (optional, default false; true: the active strategy of wstx_read strategy chooses, calls CQ and answers),pounce:null|\"CALL\" (optional, default null; with strategy false: wait on the current band for this one call and answer its CQ or 73)}}; start {expected_policy_revision,expected_run_revision,mode,safety_revision}; stop {run_id}. Unconfigured and stopped by default; start needs this credential's transmit grant.",
         "inputSchema":{"type":"object","properties":{"command":object("AutomationCommand body")},"required":["command"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}},
        {"name":"wstx_strategy_evaluate","title":"Strategy verdicts",
         "description":"The verdicts the browser shows for decoded rows (POST /strategy/evaluate): {v:1,profile_id,boot_id,source_id,job_id,generation,first_sequence,next_sequence (at most 2048 rows),strategy:null (the saved active strategy) or a draft strategy,explain}. In display order: rank (the matched rule) and grey (a directed CQ not for my continent, never answered); with explain every row and why. No effect.",
         "inputSchema":{"type":"object","properties":{"request":object("StrategyEvaluate body")},"required":["request"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"readOnlyHint":true}}
    ])
}
const INSTRUCTIONS: &str = "WSTX station: read state with wstx_read, wstx_results and wstx_strategy_evaluate; operate through \
wstx_contact_command and wstx_automation_command with the profile_id/boot_id and revisions from wstx_read; \
use a new command_id per intent and never retry a mutation with a new command_id after an unknown outcome \
(read the state first). wstx_transmit_halt stops transmission at once.";

/// Exact argument keys; returns the refused field.
fn exact(
    args: &serde_json::Map<String, Value>,
    required: &[&str],
    optional: &[&str],
) -> Result<(), String> {
    if let Some(k) = args
        .keys()
        .find(|k| !required.contains(&k.as_str()) && !optional.contains(&k.as_str()))
    {
        return Err(k.clone());
    }
    if let Some(k) = required.iter().find(|k| !args.contains_key(**k)) {
        return Err((*k).to_owned());
    }
    Ok(())
}
/// (method, path and query, body) of the one station operation a tool maps to.
fn operation(
    name: &str,
    args: &serde_json::Map<String, Value>,
) -> Result<(Method, String, Option<Value>), String> {
    let object = |k: &str| {
        args.get(k)
            .filter(|v| v.is_object())
            .cloned()
            .ok_or_else(|| k.to_owned())
    };
    match name {
        "wstx_read" => {
            exact(args, &["view"], &[])?;
            let path = VIEWS
                .iter()
                .find(|(v, _)| args["view"] == *v)
                .ok_or("view")?
                .1;
            Ok((Method::GET, path.into(), None))
        }
        "wstx_results" => {
            exact(
                args,
                &["source_id", "job_id", "generation", "cursor"],
                &["limit"],
            )?;
            let uuid = |k: &str| {
                args[k]
                    .as_str()
                    .filter(|s| profile::valid_uuid(s))
                    .ok_or_else(|| k.to_owned())
            };
            let number = |k: &str| args[k].as_u64().ok_or_else(|| k.to_owned());
            let mut query = format!(
                "source_id={}&job_id={}&generation={}&cursor={}",
                uuid("source_id")?,
                uuid("job_id")?,
                number("generation")?,
                number("cursor")?
            );
            if args.contains_key("limit") {
                query.push_str(&format!("&limit={}", number("limit")?));
            }
            Ok((Method::GET, format!("/receive/results?{query}"), None))
        }
        "wstx_contact_command" => {
            exact(args, &["command"], &[])?;
            Ok((
                Method::POST,
                "/contact/command".into(),
                Some(object("command")?),
            ))
        }
        "wstx_transmit_halt" => {
            exact(args, &["halt"], &[])?;
            Ok((Method::POST, "/transmit/halt".into(), Some(object("halt")?)))
        }
        "wstx_strategy_evaluate" => {
            exact(args, &["request"], &[])?;
            Ok((
                Method::POST,
                "/strategy/evaluate".into(),
                Some(object("request")?),
            ))
        }
        _ => {
            exact(args, &["command"], &[])?;
            Ok((
                Method::POST,
                "/automation/command".into(),
                Some(object("command")?),
            ))
        }
    }
}
/// The station operation's HTTP status and JSON body (an argument refusal makes no call).
async fn call_tool(
    app: &App,
    token: &str,
    name: &str,
    args: &serde_json::Map<String, Value>,
) -> (u16, Value) {
    let (method, uri, body) = match operation(name, args) {
        Ok(op) => op,
        Err(field) => {
            return (
                400,
                json!({"error":{"code":"invalid_request","field":field}}),
            );
        }
    };
    let mut builder = axum::http::Request::builder().method(method).uri(uri);
    for (k, v) in &station_headers(app, token) {
        builder = builder.header(k, v);
    }
    let request = match body {
        Some(b) => builder
            .header(header::CONTENT_TYPE, "application/json")
            .body(axum::body::Body::from(
                serde_json::to_vec(&b).unwrap_or_default(),
            )),
        None => builder.body(axum::body::Body::empty()),
    };
    let unavailable = (
        503,
        json!({"error":{"code":"storage_unavailable","field":null}}),
    );
    let Ok(request) = request else {
        return unavailable;
    };
    let Ok(response) = crate::router(app.clone()).oneshot(request).await;
    let status = response.status().as_u16();
    match axum::body::to_bytes(response.into_body(), STATION_BYTES_MAX).await {
        Ok(bytes) if bytes.is_empty() => (status, Value::Null),
        Ok(bytes) => (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        ),
        Err(_) => (503, json!({"error":{"code":"snapshot_limit","field":null}})),
    }
}

pub async fn endpoint(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    if app.profile.is_none() {
        return StatusCode::NOT_FOUND.into_response();
    }
    // DNS-rebinding barrier: a present Origin must be exactly the station's.
    if headers.contains_key(header::ORIGIN) && !allowed_origin(&headers, &app) {
        return rpc_error(
            StatusCode::FORBIDDEN,
            Value::Null,
            -32600,
            "forbidden_origin",
            None,
        );
    }
    let unauthorized = |data: Option<Value>| {
        let mut r = rpc_error(
            StatusCode::UNAUTHORIZED,
            Value::Null,
            -32001,
            "unauthorized",
            data,
        );
        r.headers_mut().insert(
            header::WWW_AUTHENTICATE,
            "Bearer realm=\"wstx\"".parse().unwrap(),
        );
        r
    };
    let Some(token) = bearer(&headers) else {
        return unauthorized(None);
    };
    // Only an MCP client token (#58), checked by the station's authority owner; a
    // plaintext profile has no grant authority and therefore no MCP access.
    let checked = {
        let app = app.clone();
        tokio::task::spawn_blocking(move || authorization_http::mcp_access(&app, &token)).await
    };
    use authorization_http::McpRefusal;
    let caller = match checked {
        Ok(Ok(caller)) => caller,
        Ok(Err(McpRefusal::NotMcpToken)) => {
            return unauthorized(Some(
                json!({"reason":"mcp_token_required","hint":TOKEN_HINT}),
            ));
        }
        Ok(Err(McpRefusal::Unknown)) => {
            return unauthorized(Some(json!({"reason":"mcp_token_invalid"})));
        }
        Ok(Err(McpRefusal::RateLimited)) => {
            return rpc_error(
                StatusCode::TOO_MANY_REQUESTS,
                Value::Null,
                -32001,
                "rate_limited",
                None,
            );
        }
        Ok(Err(McpRefusal::Unavailable)) | Err(_) => {
            return rpc_error(
                StatusCode::SERVICE_UNAVAILABLE,
                Value::Null,
                -32603,
                "storage_unavailable",
                None,
            );
        }
    };
    let action = audit_action(&body);
    let response = dispatch(&app, &caller.transport, &headers, query, body).await;
    let status = response
        .extensions()
        .get::<ToolStatus>()
        .map_or(response.status().as_u16(), |s| s.0);
    let audited = app.clone();
    let _ = tokio::task::spawn_blocking(move || {
        authorization_http::mcp_audit(&audited, &caller, &action, status)
    })
    .await;
    response
}

/// One authorized MCP request (after Origin and credential).
async fn dispatch(
    app: &App,
    token: &str,
    headers: &HeaderMap,
    query: Option<String>,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    if query.is_some() {
        return rpc_error(
            StatusCode::BAD_REQUEST,
            Value::Null,
            -32600,
            "invalid_request",
            None,
        );
    }
    if !json_media_type(headers) {
        return rpc_error(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            Value::Null,
            -32600,
            "unsupported_media_type",
            None,
        );
    }
    let Ok(bytes) = body else {
        return rpc_error(
            StatusCode::PAYLOAD_TOO_LARGE,
            Value::Null,
            -32600,
            "request_too_large",
            None,
        );
    };
    let Ok(message) = serde_json::from_slice::<Value>(&bytes) else {
        return rpc_error(
            StatusCode::BAD_REQUEST,
            Value::Null,
            -32700,
            "Parse error",
            None,
        );
    };
    let invalid =
        |id: Value| rpc_error(StatusCode::BAD_REQUEST, id, -32600, "Invalid Request", None);
    let Some(object) = message.as_object() else {
        return invalid(Value::Null);
    };
    let id = object.get("id").cloned();
    if id
        .as_ref()
        .is_some_and(|id| !(id.is_string() || id.is_i64() || id.is_u64()))
    {
        return invalid(Value::Null);
    }
    let (Some("2.0"), Some(method)) = (
        object.get("jsonrpc").and_then(Value::as_str),
        object.get("method").and_then(Value::as_str),
    ) else {
        return invalid(id.unwrap_or(Value::Null));
    };
    let params = object.get("params").cloned().unwrap_or(json!({}));
    if !params.is_object() {
        return invalid(id.unwrap_or(Value::Null));
    }
    let Some(id) = id else {
        // Notifications (initialized, cancelled) carry no station effect.
        return if method.starts_with("notifications/") {
            StatusCode::ACCEPTED.into_response()
        } else {
            invalid(Value::Null)
        };
    };
    let header_version = header_text(headers, "mcp-protocol-version");
    let modern = match params["_meta"].get("io.modelcontextprotocol/protocolVersion") {
        Some(version) => {
            let Some(version) = version.as_str() else {
                return rpc_error(StatusCode::BAD_REQUEST, id, -32602, "Invalid params", None);
            };
            if version != MODERN {
                return rpc_error(
                    StatusCode::BAD_REQUEST,
                    id,
                    -32022,
                    "Unsupported protocol version",
                    Some(json!({"supported":supported(),"requested":version})),
                );
            }
            let mismatch = header_version != Some(version)
                || header_text(headers, "mcp-method") != Some(method)
                || (method == "tools/call"
                    && mcp_name(headers).as_deref() != params["name"].as_str());
            if mismatch {
                return rpc_error(StatusCode::BAD_REQUEST, id, -32020, "Header mismatch", None);
            }
            true
        }
        None if method == "initialize" => {
            let requested = params["protocolVersion"].as_str().unwrap_or("");
            let chosen = LEGACY
                .iter()
                .find(|v| **v == requested)
                .unwrap_or(&LEGACY[0]);
            return Json(
                json!({"jsonrpc":"2.0","id":id,"result":{"protocolVersion":chosen,
                "capabilities":{"tools":{"listChanged":false}},
                "serverInfo":{"name":"wstx-rust","version":env!("CARGO_PKG_VERSION")},
                "instructions":INSTRUCTIONS}}),
            )
            .into_response();
        }
        None => {
            // Both supported legacy versions send the header after initialize.
            let Some(version) = header_version else {
                return rpc_error(StatusCode::BAD_REQUEST, id, -32020, "Header mismatch", None);
            };
            if version == MODERN {
                return rpc_error(StatusCode::BAD_REQUEST, id, -32020, "Header mismatch", None);
            }
            if !LEGACY.contains(&version) {
                return rpc_error(
                    StatusCode::BAD_REQUEST,
                    id,
                    -32022,
                    "Unsupported protocol version",
                    Some(json!({"supported":supported(),"requested":version})),
                );
            }
            false
        }
    };
    let ok = |mut result: Value| {
        if modern {
            result["resultType"] = json!("complete");
        }
        Json(json!({"jsonrpc":"2.0","id":id,"result":result})).into_response()
    };
    match method {
        "server/discover" if modern => ok(json!({"supportedVersions":supported(),
            "capabilities":{"tools":{"listChanged":false}},
            "_meta":{"io.modelcontextprotocol/serverInfo":{"name":"wstx-rust","version":env!("CARGO_PKG_VERSION")}},
            "instructions":INSTRUCTIONS})),
        "ping" => ok(json!({})),
        "tools/list" => ok(json!({"tools":tools()})),
        "tools/call" => {
            let known = tools();
            let name = params["name"].as_str().unwrap_or("");
            if !known
                .as_array()
                .is_some_and(|t| t.iter().any(|t| t["name"] == name))
            {
                let status = if modern {
                    StatusCode::BAD_REQUEST
                } else {
                    StatusCode::OK
                };
                return rpc_error(status, id, -32602, "Unknown tool", None);
            }
            let args = match &params["arguments"] {
                Value::Null => serde_json::Map::new(),
                Value::Object(o) => o.clone(),
                _ => {
                    let status = if modern {
                        StatusCode::BAD_REQUEST
                    } else {
                        StatusCode::OK
                    };
                    return rpc_error(status, id, -32602, "Invalid params", None);
                }
            };
            let (status, result) = call_tool(app, token, name, &args).await;
            let structured = json!({"v":1,"tool":name,"status":status,"result":result});
            let mut response = ok(
                json!({"content":[{"type":"text","text":structured.to_string()}],
                "structuredContent":structured,"isError":status >= 400}),
            );
            response.extensions_mut().insert(ToolStatus(status));
            response
        }
        _ => {
            let status = if modern {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::OK
            };
            rpc_error(status, id, -32601, "Method not found", None)
        }
    }
}
