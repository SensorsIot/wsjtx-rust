#![forbid(unsafe_code)]
//! WstxMcp::McpEndpoint: the station's MCP Streamable HTTP endpoint (POST /mcp).
//! Dual-era: modern 2026-07-28 (per-request `_meta`, `server/discover`) and legacy
//! 2025-11-25/2025-06-18 (`initialize`, stateless: no Mcp-Session-Id). 2025-03-26 is not
//! offered: it requires JSON-RPC batches, which this endpoint refuses.
//! Every tool is one existing versioned station operation, dispatched in-process
//! through the station router with the caller's validated auth-v1 grant transport;
//! the adapter keeps no station state, modem, QSO engine or transmit authority.
//! Authorization is `Authorization: Bearer <grant transport>` only: cookies sent to
//! /mcp are never read, so a browser session cannot authorize MCP by accident.
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
/// The bearer of exactly one `Authorization: Bearer <43-character token>` field.
fn bearer(headers: &HeaderMap) -> Option<String> {
    let mut fields = headers.get_all(header::AUTHORIZATION).iter();
    let value = fields.next()?.to_str().ok()?;
    if fields.next().is_some() {
        return None;
    }
    let token = value.strip_prefix("Bearer ")?;
    authorization::decode::<32>(token).ok()?;
    Some(token.to_owned())
}
/// Marks a station request dispatched in-process for an MCP tool call (a request
/// extension, which no network client can set). It is never an operator action for the
/// Tx watchdog (#39, WstxStrategy::WatchdogFromOperator).
#[derive(Clone, Copy, Debug)]
pub(crate) struct Dispatched;
/// The station credential the in-process dispatch presents: exactly the validated grant
/// transport, under the station's own cookie name, and nothing from the MCP request.
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

const VIEWS: [(&str, &str); 7] = [
    ("profile", "/profile"),
    ("receive", "/receive"),
    ("selection", "/receive/selection"),
    ("radio", "/radio"),
    ("transmit", "/transmit"),
    ("contact", "/contact"),
    ("automation", "/automation"),
];
/// WstxMcp::ToolCatalog, in this fixed order.
pub fn tools() -> Value {
    let output = json!({"type":"object","properties":{"v":{"const":1},"tool":{"type":"string"},
        "status":{"type":"integer"},"result":{}},"required":["v","tool","status","result"],"additionalProperties":false});
    let object = |d: &str| json!({"type":"object","description":d});
    let uuid = json!({"type":"string","format":"uuid"});
    let safe = json!({"type":"integer","minimum":0,"maximum":9_007_199_254_740_991u64});
    json!([
        {"name":"wstx_read","title":"Read station state",
         "description":"Read one station view exactly as the browser receives it: profile (GET /profile), receive (GET /receive), selection (GET /receive/selection), radio (GET /radio), transmit (GET /transmit), contact (GET /contact, the ContactSnapshot with contact_revision and transmit.safety_revision) or automation (GET /automation). No effect.",
         "inputSchema":{"type":"object","properties":{"view":{"type":"string","enum":VIEWS.map(|v|v.0)}},"required":["view"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"readOnlyHint":true}},
        {"name":"wstx_results","title":"Read decoded results",
         "description":"Read one page of live decoded results of the receive job (GET /receive/results): source_id, job_id and generation from wstx_read receive, cursor 0 or the previous next_cursor, limit 1..16 (default 16). No effect.",
         "inputSchema":{"type":"object","properties":{"source_id":uuid,"job_id":uuid,"generation":safe,"cursor":safe,
            "limit":{"type":"integer","minimum":1,"maximum":16}},"required":["source_id","job_id","generation","cursor"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"readOnlyHint":true}},
        {"name":"wstx_contact_command","title":"Contact command",
         "description":"Send one ContactCommand (POST /contact/command), the same request the browser sends: {v:1,profile_id,boot_id,command_id (new UUID per intent, reuse it only to retry the same body),contact_revision,action,...}. Actions: select_row {row:{source_id,job_id,generation,sequence},replace}, enter_dx {dx_call,dx_grid,replace}, cancel, choose_next {slot}, edit_message {slot,text}, set_report {report}, set_tx1_skip|set_hold_tx|set_auto_seq|tune {enabled}, enable_tx {enabled,safety_revision}, set_tx4 {form}, set_frequency {rx_hz,tx_hz}, set_parity {parity}, set_watchdogs {tx_minutes,tune_seconds}, discard_review {contact_id}, redecode, open_log. Selecting never transmits; enable_tx needs this credential's transmit grant.",
         "inputSchema":{"type":"object","properties":{"command":object("ContactCommand body")},"required":["command"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}},
        {"name":"wstx_transmit_halt","title":"Halt transmission",
         "description":"Halt Tx now (POST /transmit/halt): {v:1,profile_id,boot_id,command_id}. Stops any transmission, disarms and ends a running automation.",
         "inputSchema":{"type":"object","properties":{"halt":object("HaltTransmit body")},"required":["halt"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}},
        {"name":"wstx_automation_command","title":"Automation command",
         "description":"Configure, start or stop the station's FT4/FT8 automation (POST /automation/command): {v:1,profile_id,boot_id,command_id,action,...}. configure {expected_policy_revision,configuration:null|{modes:[\"ft8\"|\"ft4\"],ranking:\"first_seen\"|\"strongest_snr\"|\"lowest_frequency\",min_snr_db:null|-50..49,allowed_calls:[],blocked_calls:[],max_contacts:1..100,max_unanswered_periods:1..20,completion_action:\"stop\"|\"next_candidate\"}}; start {expected_policy_revision,expected_run_revision,mode,safety_revision}; stop {run_id}. Unconfigured and stopped by default; start needs this credential's transmit grant.",
         "inputSchema":{"type":"object","properties":{"command":object("AutomationCommand body")},"required":["command"],"additionalProperties":false},
         "outputSchema":output,"annotations":{"destructiveHint":true,"idempotentHint":true}}
    ])
}
const INSTRUCTIONS: &str = "WSTX station: read state with wstx_read and wstx_results; operate through \
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
    let Ok(mut request) = request else {
        return unavailable;
    };
    request.extensions_mut().insert(Dispatched);
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
    let unauthorized = || {
        let mut r = rpc_error(
            StatusCode::UNAUTHORIZED,
            Value::Null,
            -32001,
            "unauthorized",
            None,
        );
        r.headers_mut().insert(
            header::WWW_AUTHENTICATE,
            "Bearer realm=\"wstx\"".parse().unwrap(),
        );
        r
    };
    let Some(token) = bearer(&headers) else {
        return unauthorized();
    };
    // Same auth-v1 owner and check as every browser operation; a plaintext profile has
    // no grant authority and therefore no MCP access.
    match authorization_http::operating_access_async(&station_headers(&app, &token), &app).await {
        Ok(Some(_)) => {}
        Ok(None) | Err(authorization::Error::Unauthorized) => return unauthorized(),
        Err(_) => {
            return rpc_error(
                StatusCode::SERVICE_UNAVAILABLE,
                Value::Null,
                -32603,
                "storage_unavailable",
                None,
            );
        }
    }
    if query.is_some() {
        return rpc_error(
            StatusCode::BAD_REQUEST,
            Value::Null,
            -32600,
            "invalid_request",
            None,
        );
    }
    if !json_media_type(&headers) {
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
    let header_version = header_text(&headers, "mcp-protocol-version");
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
                || header_text(&headers, "mcp-method") != Some(method)
                || (method == "tools/call"
                    && mcp_name(&headers).as_deref() != params["name"].as_str());
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
            let (status, result) = call_tool(&app, &token, name, &args).await;
            let structured = json!({"v":1,"tool":name,"status":status,"result":result});
            ok(
                json!({"content":[{"type":"text","text":structured.to_string()}],
                "structuredContent":structured,"isError":status >= 400}),
            )
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
