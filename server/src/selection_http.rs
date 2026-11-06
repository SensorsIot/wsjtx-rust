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
    let r = match authorize(&app, &headers, false).await {
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
/// The fields of a snapshot that stand in every selection.state, not in its `changed`.
const STATE_IDENTITY: [&str; 5] = [
    "v",
    "profile_id",
    "boot_id",
    "snapshot_sequence",
    "monotonic_ms",
];
/// WstxOperatingReceive::SelectionStateEvent: the snapshot GET /receive/selection gives this
/// station now.
pub(crate) fn pushed_view(state: &ProfileState) -> Option<Value> {
    let cat = state.store.lock().ok()?.document.control.mode == "cat";
    state.recording.selection_snapshot(cat).ok()
}
/// The top-level fields of `now` that the peer holding `sent` lacks.
pub(crate) fn state_changes(sent: &Value, now: &Value) -> serde_json::Map<String, Value> {
    now.as_object()
        .into_iter()
        .flatten()
        .filter(|(k, v)| !STATE_IDENTITY.contains(&k.as_str()) && sent.get(k.as_str()) != Some(*v))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}
fn radio_without_dates(view: &Value) -> Value {
    let mut radio = view["radio"].clone();
    if let Some(facts) = radio["observations"].as_object_mut() {
        for fact in facts.values_mut().filter_map(Value::as_object_mut) {
            fact.remove("query_sequence");
            fact.remove("observed_at_ms");
        }
    }
    radio
}
/// Whether a change goes now. Each CAT poll (1 s) dates the radio facts anew with no new value:
/// that alone goes at most every 2 s on Detailed and every 30 s below it.
pub(crate) fn state_due(
    display_profile: &str,
    changed: &serde_json::Map<String, Value>,
    sent: &Value,
    now: &Value,
    since_last: Duration,
) -> bool {
    let dates_only = changed.len() == 1
        && changed.contains_key("radio")
        && radio_without_dates(sent) == radio_without_dates(now);
    !dates_only
        || since_last >= Duration::from_secs(if display_profile == "detail" { 2 } else { 30 })
}
/// The selection.state with as many of the changed fields as fit 2048 B, and what the peer then
/// holds: a snapshot near its 3072 B cap goes in two events, the rest at the next check.
pub(crate) fn state_event(
    sent: &Value,
    now: &Value,
    changed: serde_json::Map<String, Value>,
) -> (String, Value) {
    let text = |fields: &serde_json::Map<String, Value>| {
        json!({"v":1,"type":"selection.state","data":{"profile_id":now["profile_id"],"boot_id":now["boot_id"],
            "snapshot_sequence":now["snapshot_sequence"],"monotonic_ms":now["monotonic_ms"],"changed":fields}})
        .to_string()
    };
    let mut fields = serde_json::Map::new();
    let mut holds = if sent.is_null() {
        json!({})
    } else {
        sent.clone()
    };
    for (key, value) in changed {
        fields.insert(key.clone(), value.clone());
        if text(&fields).len() > 2048 {
            fields.remove(&key);
        } else {
            holds[key] = value;
        }
    }
    (text(&fields), holds)
}
pub async fn select(
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
    // Capture settings, then release before actor reservation, snapshots or worker I/O.
    let (device, cat) = {
        let store = state.store.lock().unwrap();
        if store.document.revision != intent.profile_revision {
            return error("state_conflict");
        }
        (
            store.document.audio.input_device.clone(),
            store.document.control.mode == "cat",
        )
    };
    // WstxContact::ModeChange: no mode change while #9 keys the radio, transmits or
    // tunes (WSJT-X disables the mode controls while transmitting); nothing changes.
    // The owner lock can wait on a CAT exchange: read the view off the async runtime.
    if intent.action == "mode"
        && let Some(t) = r.transmit.get().cloned()
    {
        let keyed = tokio::task::spawn_blocking(move || {
            let v = t.service.view();
            v.transmitting || v.tune || v.ptt != wstx_rust::transmit::service::PttState::Released
        })
        .await
        .unwrap_or(true);
        if keyed {
            return error("busy");
        }
    }
    // The CAT lease can take seconds to come free (CL-044-16): off the async runtime.
    let begin = r.clone();
    let begun = tokio::task::spawn_blocking(move || begin.selection_begin(intent, device, cat))
        .await
        .unwrap_or(Err("radio_unavailable"));
    match begun {
        Ok(v) => {
            receive_http::contact_step(state.clone()).await;
            (StatusCode::ACCEPTED, Json(v)).into_response()
        }
        Err(e) => error(e),
    }
}
