use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, parse, syntax};
use selection_http::{empty, error};
use serde::Deserialize;
use wstx_rust::radio_control::{Operation, Sideband};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Connect {
    v: u64,
    profile_id: String,
    boot_id: String,
    profile_revision: u64,
    receive_only_verified: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Disconnect {
    v: u64,
    profile_id: String,
    boot_id: String,
    connection_generation: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Execute {
    v: u64,
    profile_id: String,
    boot_id: String,
    connection_generation: u64,
    operation: String,
    parameters: Parameters,
}
#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
enum Parameters {
    Query {},
    Frequency {
        frequency_hz: u64,
    },
    Mode {
        mode: Sideband,
        filter: u8,
    },
    Data {
        enabled: bool,
        filter: u8,
    },
    Setup {
        frequency_hz: u64,
        mode: Sideband,
        filter: u8,
        data: bool,
        data_filter: u8,
    },
}
fn operation(name: &str, p: Parameters) -> Result<Operation, &'static str> {
    Ok(match (name, p) {
        ("read_frequency", Parameters::Query {}) => Operation::ReadFrequency,
        ("read_mode", Parameters::Query {}) => Operation::ReadMode,
        ("read_data", Parameters::Query {}) => Operation::ReadData,
        ("read_rx_tx", Parameters::Query {}) => Operation::ReadRxTx,
        ("read_split", Parameters::Query {}) => Operation::ReadSplit,
        ("set_frequency", Parameters::Frequency { frequency_hz }) => {
            Operation::SetFrequency { frequency_hz }
        }
        ("set_mode", Parameters::Mode { mode, filter }) => Operation::SetMode { mode, filter },
        ("set_data", Parameters::Data { enabled, filter }) => Operation::SetData {
            data: enabled,
            filter,
        },
        (
            "receive_setup",
            Parameters::Setup {
                frequency_hz,
                mode,
                filter,
                data,
                data_filter,
            },
        ) => Operation::ReceiveSetup {
            frequency_hz,
            mode,
            filter,
            data,
            data_filter,
        },
        _ => return Err("invalid_request"),
    })
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if let Err(e) = empty(query, body) {
        return error(e);
    }
    Json(r.radio_view()).into_response()
}
pub async fn connect(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let b: Connect = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.profile_revision) {
        return error(e);
    }
    if b.profile_id != r.profile {
        return error("wrong_profile");
    }
    if b.boot_id != r.boot {
        return error("state_conflict");
    }
    // CL-022-03/04: the automatic lifecycle alone opens CAT. This deprecated route
    // keeps its strict validation and refuses with zero CAT I/O.
    let _ = (b.profile_revision, b.receive_only_verified);
    error("automatic_lifecycle")
}
pub async fn disconnect(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let b: Disconnect = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.connection_generation) {
        return error(e);
    }
    if b.profile_id != r.profile {
        return error("wrong_profile");
    }
    if b.boot_id != r.boot {
        return error("state_conflict");
    }
    let _ = (r, b.connection_generation);
    error("automatic_lifecycle")
}
pub async fn execute(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let b: Execute = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if let Err(e) = syntax(b.v, &b.profile_id, &b.boot_id, b.connection_generation) {
        return error(e);
    }
    if b.profile_id != r.profile {
        return error("wrong_profile");
    }
    if b.boot_id != r.boot {
        return error("state_conflict");
    }
    let op = match operation(&b.operation, b.parameters) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    if op.validate().is_err() {
        return error("invalid_request");
    }
    // Direct setters stay unsupported until their complete shared RF-context barrier
    // is admitted. Operating mode/band uses that barrier through /receive/select.
    if matches!(
        op,
        Operation::SetFrequency { .. }
            | Operation::SetMode { .. }
            | Operation::SetData { .. }
            | Operation::ReceiveSetup { .. }
    ) {
        return error("selection_unavailable");
    }
    match tokio::task::spawn_blocking(move || r.radio_execute(b.connection_generation, op)).await {
        Ok(Ok(v)) => Json(v).into_response(),
        Ok(Err(e)) => error(e),
        Err(_) => error("radio_unavailable"),
    }
}
