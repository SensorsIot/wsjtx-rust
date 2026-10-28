use crate::*;
use axum::extract::RawQuery;
use recording_http::{authorize, parse, syntax};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
enum Select {
    Mode {
        v: u64,
        profile_id: String,
        boot_id: String,
        command_id: String,
        profile_revision: u64,
        generation: u64,
        operating_revision: u64,
        mode: String,
    },
    Band {
        v: u64,
        profile_id: String,
        boot_id: String,
        command_id: String,
        profile_revision: u64,
        generation: u64,
        operating_revision: u64,
        band: String,
    },
    Cancel {
        v: u64,
        profile_id: String,
        boot_id: String,
        command_id: String,
        operating_revision: u64,
        target_command_id: String,
    },
}
pub(crate) fn error(code: &str) -> Response {
    if code == "snapshot_limit" {
        return profile_error(StatusCode::SERVICE_UNAVAILABLE, code, None);
    }
    recording_http::error(code)
}
pub(crate) fn empty(
    query: Option<String>,
    body: Result<Bytes, BytesRejection>,
) -> Result<(), &'static str> {
    if query.is_some() {
        return Err("invalid_request");
    }
    match body {
        Ok(b) if b.is_empty() => Ok(()),
        Ok(_) => Err("invalid_request"),
        Err(_) => Err("request_too_large"),
    }
}
pub async fn snapshot(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, false) {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if let Err(e) = empty(query, body) {
        return error(e);
    }
    let cat = app
        .profile
        .as_ref()
        .unwrap()
        .store
        .lock()
        .unwrap()
        .document
        .control
        .mode
        == "cat";
    match r.selection_snapshot(cat) {
        Ok(v) => Json(v).into_response(),
        Err(e) => error(e),
    }
}
pub async fn select(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true) {
        Ok(r) => r,
        Err(e) => return error(e),
    };
    if query.is_some() {
        return error("invalid_request");
    }
    let request: Select = match parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return error(e),
    };
    let intent = match request {
        Select::Cancel {
            v,
            profile_id,
            boot_id,
            command_id,
            operating_revision,
            target_command_id,
        } => {
            if let Err(e) = syntax(v, &profile_id, &boot_id, operating_revision) {
                return error(e);
            }
            if !profile::valid_uuid(&command_id) || !profile::valid_uuid(&target_command_id) {
                return error("invalid_request");
            }
            return match r.selection_cancel(
                &profile_id,
                &boot_id,
                command_id,
                target_command_id,
                operating_revision,
            ) {
                Ok((v, repeated)) => (
                    if repeated {
                        StatusCode::OK
                    } else {
                        StatusCode::ACCEPTED
                    },
                    Json(v),
                )
                    .into_response(),
                Err(e) => error(e),
            };
        }
        Select::Mode {
            v,
            profile_id,
            boot_id,
            command_id,
            profile_revision,
            generation,
            operating_revision,
            mode,
        } => {
            if let Err(e) = syntax(v, &profile_id, &boot_id, generation) {
                return error(e);
            }
            let mode = match mode.as_str() {
                "ft4" => "ft4",
                "ft8" => "ft8",
                _ => return error("invalid_request"),
            };
            selection::Intent {
                profile_id,
                boot_id,
                command_id,
                profile_revision,
                generation,
                revision: operating_revision,
                action: "mode",
                mode: Some(mode),
                band: None,
            }
        }
        Select::Band {
            v,
            profile_id,
            boot_id,
            command_id,
            profile_revision,
            generation,
            operating_revision,
            band,
        } => {
            if let Err(e) = syntax(v, &profile_id, &boot_id, generation) {
                return error(e);
            }
            if !selection::BANDS.contains(&band.as_str()) {
                return error("invalid_request");
            }
            selection::Intent {
                profile_id,
                boot_id,
                command_id,
                profile_revision,
                generation,
                revision: operating_revision,
                action: "band",
                mode: None,
                band: Some(band),
            }
        }
    };
    if !profile::valid_uuid(&intent.command_id)
        || intent.profile_revision > profile::MAX_REVISION
        || intent.revision > profile::MAX_REVISION
    {
        return error("invalid_request");
    }
    if intent.profile_id != r.profile {
        return error("wrong_profile");
    }
    let state = app.profile.as_ref().unwrap();
    let store = state.store.lock().unwrap();
    if store.document.revision != intent.profile_revision {
        return error("state_conflict");
    }
    let device = store.document.audio.input_device.clone();
    let cat = store.document.control.mode == "cat";
    // Capture settings, then release before actor reservation, snapshots or worker I/O.
    drop(store);
    match r.selection_begin(intent, device, cat) {
        Ok(v) => (StatusCode::ACCEPTED, Json(v)).into_response(),
        Err(e) => error(e),
    }
}
