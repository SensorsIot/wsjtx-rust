#![forbid(unsafe_code)]
//! WstxMcp::OperatingAutomation: the station-owned configured FT4/FT8 automation policy.
//! It chooses one calling station per completed receive publication under an explicitly
//! configured policy and drives the one contact engine through the same ContactCommand
//! path as the browser (select_row, enable_tx). The engine alone progresses the contact;
//! the #9 owner alone transmits. Policy and run are volatile: every boot starts
//! unconfigured with no run, so nothing is armed by automation after a restart.
//! Routes: GET /automation (AutomationSnapshot), POST /automation/command.
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::empty;
use std::collections::VecDeque;

const MAX_SAFE: u64 = 9_007_199_254_740_991;
pub const RECEIPTS: usize = 16;
pub const CALLS_MAX: usize = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Ranking {
    FirstSeen,
    StrongestSnr,
    LowestFrequency,
}
impl Ranking {
    fn name(self) -> &'static str {
        match self {
            Ranking::FirstSeen => "first_seen",
            Ranking::StrongestSnr => "strongest_snr",
            Ranking::LowestFrequency => "lowest_frequency",
        }
    }
}
/// WstxMcp::AutomationConfiguration (every key required, no defaults).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Config {
    pub modes: Vec<&'static str>,
    pub ranking: Ranking,
    pub min_snr_db: Option<i64>,
    pub allowed: Vec<String>,
    pub blocked: Vec<String>,
    pub max_contacts: u64,
    pub max_unanswered: u64,
    pub next_candidate: bool,
}
impl Config {
    fn json(&self) -> Value {
        json!({"modes":self.modes,"ranking":self.ranking.name(),"min_snr_db":self.min_snr_db,
            "allowed_calls":self.allowed,"blocked_calls":self.blocked,"max_contacts":self.max_contacts,
            "max_unanswered_periods":self.max_unanswered,
            "completion_action":if self.next_candidate {"next_candidate"} else {"stop"}})
    }
}
type Refusal = (&'static str, Option<&'static str>);
fn bad(field: &'static str) -> Refusal {
    ("invalid_request", Some(field))
}
fn valid_call(c: &str) -> bool {
    (3..=13).contains(&c.len())
        && c.bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'/')
}
fn calls(v: &Value, field: &'static str) -> Result<Vec<String>, Refusal> {
    let list = v.as_array().ok_or(bad(field))?;
    let mut out: Vec<String> = Vec::new();
    for c in list {
        let c = c.as_str().filter(|c| valid_call(c)).ok_or(bad(field))?;
        if out.iter().any(|o| o == c) {
            return Err(bad(field));
        }
        out.push(c.to_owned());
    }
    if out.len() > CALLS_MAX {
        return Err(bad(field));
    }
    Ok(out)
}
fn bounded(
    v: &Value,
    field: &'static str,
    range: std::ops::RangeInclusive<u64>,
) -> Result<u64, Refusal> {
    v.as_u64().filter(|n| range.contains(n)).ok_or(bad(field))
}
/// Exact AutomationConfiguration parsing; null is the unconfigured state.
pub(crate) fn parse_config(v: &Value) -> Result<Option<Config>, Refusal> {
    if v.is_null() {
        return Ok(None);
    }
    let keys = [
        "modes",
        "ranking",
        "min_snr_db",
        "allowed_calls",
        "blocked_calls",
        "max_contacts",
        "max_unanswered_periods",
        "completion_action",
    ];
    let o = v.as_object().ok_or(bad("configuration"))?;
    if o.len() != keys.len() || !keys.iter().all(|k| o.contains_key(*k)) {
        return Err(bad("configuration"));
    }
    let mut modes = Vec::new();
    for m in v["modes"].as_array().ok_or(bad("modes"))? {
        let m = match m.as_str() {
            Some("ft8") => "ft8",
            Some("ft4") => "ft4",
            _ => return Err(bad("modes")),
        };
        if modes.contains(&m) {
            return Err(bad("modes"));
        }
        modes.push(m);
    }
    if modes.is_empty() {
        return Err(bad("modes"));
    }
    let ranking = match v["ranking"].as_str() {
        Some("first_seen") => Ranking::FirstSeen,
        Some("strongest_snr") => Ranking::StrongestSnr,
        Some("lowest_frequency") => Ranking::LowestFrequency,
        _ => return Err(bad("ranking")),
    };
    let min_snr_db = match &v["min_snr_db"] {
        Value::Null => None,
        n => Some(
            n.as_i64()
                .filter(|n| (-50..=49).contains(n))
                .ok_or(bad("min_snr_db"))?,
        ),
    };
    let allowed = calls(&v["allowed_calls"], "allowed_calls")?;
    let blocked = calls(&v["blocked_calls"], "blocked_calls")?;
    if allowed.iter().any(|a| blocked.contains(a)) {
        return Err(bad("blocked_calls"));
    }
    let next_candidate = match v["completion_action"].as_str() {
        Some("stop") => false,
        Some("next_candidate") => true,
        _ => return Err(bad("completion_action")),
    };
    Ok(Some(Config {
        modes,
        ranking,
        min_snr_db,
        allowed,
        blocked,
        max_contacts: bounded(&v["max_contacts"], "max_contacts", 1..=100)?,
        max_unanswered: bounded(
            &v["max_unanswered_periods"],
            "max_unanswered_periods",
            1..=20,
        )?,
        next_candidate,
    }))
}

/// One eligible calling station of a completed publication.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Candidate {
    pub call: String,
    pub sequence: u64,
    pub snr_db: Option<f64>,
    pub frequency_hz: f64,
}
/// WstxMcp::CandidateSelection over the records of one completed publication.
/// Eligible: decoded standard plain "CQ" from a resolved call that is not mine, not
/// worked in this run, allowed (empty list: any) and not blocked, meeting min_snr_db
/// (unknown SNR then excluded); strongest_snr also needs a numeric SNR. One candidate per
/// call (its lowest sequence). Order: first_seen by sequence; strongest_snr by SNR
/// descending; lowest_frequency by frequency ascending; ties by call (ASCII), then
/// sequence. Exact published values are compared; no tolerance.
pub(crate) fn candidates(
    records: &[Value],
    config: &Config,
    my_call: &str,
    worked: &[String],
) -> Vec<Candidate> {
    let mut out: Vec<Candidate> = Vec::new();
    for r in records {
        let f = &r["fields"];
        if r["status"] != "decoded"
            || f["type"] != "standard"
            || f["to"]["kind"] != "token"
            || f["to"]["text"] != "CQ"
            || f["from"]["kind"] != "call"
        {
            continue;
        }
        let (Some(call), Some(sequence), Some(frequency_hz)) = (
            f["from"]["text"].as_str(),
            r["sequence"].as_u64(),
            r["frequency_hz"].as_f64(),
        ) else {
            continue;
        };
        let snr_db = r["snr_db"].as_f64();
        if call == my_call
            || worked.iter().any(|w| w == call)
            || (!config.allowed.is_empty() && !config.allowed.iter().any(|a| a == call))
            || config.blocked.iter().any(|b| b == call)
            || config
                .min_snr_db
                .is_some_and(|m| snr_db.is_none_or(|s| s < m as f64))
            || (config.ranking == Ranking::StrongestSnr && snr_db.is_none())
        {
            continue;
        }
        match out.iter_mut().find(|c| c.call == call) {
            Some(existing) if existing.sequence <= sequence => {}
            Some(existing) => {
                *existing = Candidate {
                    call: call.into(),
                    sequence,
                    snr_db,
                    frequency_hz,
                }
            }
            None => out.push(Candidate {
                call: call.into(),
                sequence,
                snr_db,
                frequency_hz,
            }),
        }
    }
    let tie = |a: &Candidate, b: &Candidate| a.call.cmp(&b.call).then(a.sequence.cmp(&b.sequence));
    match config.ranking {
        Ranking::FirstSeen => out.sort_by_key(|c| c.sequence),
        Ranking::StrongestSnr => out.sort_by(|a, b| {
            b.snr_db
                .unwrap_or(f64::MIN)
                .total_cmp(&a.snr_db.unwrap_or(f64::MIN))
                .then_with(|| tie(a, b))
        }),
        Ranking::LowestFrequency => out.sort_by(|a, b| {
            a.frequency_hz
                .total_cmp(&b.frequency_hz)
                .then_with(|| tie(a, b))
        }),
    }
    out
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RunState {
    Waiting,
    ContactActive,
    Stopped,
}
impl RunState {
    fn name(self) -> &'static str {
        match self {
            RunState::Waiting => "waiting",
            RunState::ContactActive => "contact_active",
            RunState::Stopped => "stopped",
        }
    }
}
struct Run {
    id: String,
    state: RunState,
    reason: Option<&'static str>,
    mode: &'static str,
    config: Config,
    identity: (String, String, u64),
    access: authorization::Access,
    safety_revision: u64,
    halts: u64,
    last_decode: u64,
    completed: u64,
    unanswered: u64,
    contact_id: Option<String>,
    progress: Option<(String, Option<i32>)>,
    selected: Option<Value>,
    worked: Vec<String>,
    last_decision: Option<Value>,
}
#[derive(Default)]
struct Inner {
    policy_revision: u64,
    run_revision: u64,
    configuration: Option<Config>,
    run: Option<Run>,
    receipts: VecDeque<(String, Value, Value)>,
}
/// The automation owner of one station (one per contact engine).
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
}

/// The descriptor of the latest receive publication, read before the contact step so
/// that the engine has already consumed every record of a publication it reports.
pub(crate) type Publication = Option<(u64, u64, u64, bool)>;

fn refusal(code: &str, field: Option<&str>) -> Response {
    let status = match code {
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "not_found" => StatusCode::NOT_FOUND,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "invalid_request" | "unsupported_version" => StatusCode::BAD_REQUEST,
        "storage_unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, field)
}
fn owner(r: &recording::Recording) -> Result<Arc<contact_http::Station>, &'static str> {
    r.contact.get().cloned().ok_or("not_found")
}

impl Owner {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    /// AutomationSnapshot.
    pub(crate) fn snapshot(&self, r: &recording::Recording) -> Value {
        let inner = self.lock();
        let run = inner.run.as_ref().map(|run| {
            json!({"id":run.id,"state":run.state.name(),"reason":run.reason,"mode":run.mode,
                "completed_contacts":run.completed,"unanswered_periods":run.unanswered,
                "contact_id":run.contact_id,"selected":run.selected,"last_decision":run.last_decision})
        });
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"policy_revision":inner.policy_revision,
            "run_revision":inner.run_revision,"configuration":inner.configuration.as_ref().map(Config::json),"run":run})
    }
    fn receipt(r: &recording::Recording, inner: &Inner, command_id: &str) -> Value {
        let (run_id, state) = inner.run.as_ref().map_or((Value::Null, "off"), |run| {
            (json!(run.id), run.state.name())
        });
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"command_id":command_id,"accepted":true,
            "policy_revision":inner.policy_revision,"run_revision":inner.run_revision,"run_id":run_id,"state":state})
    }
    /// AutomationCommand: configure, start or stop (validated in WstxOperatingReceive S2
    /// order after the route's Origin/auth/size/media checks).
    pub(crate) fn command(
        &self,
        state: &ProfileState,
        body: Value,
        access: Option<authorization::Access>,
    ) -> Result<(StatusCode, Value), Refusal> {
        let r = &state.recording;
        let o = body.as_object().ok_or(("invalid_request", None))?;
        let action = o
            .get("action")
            .and_then(Value::as_str)
            .ok_or(bad("action"))?
            .to_owned();
        let extra: &[&str] = match action.as_str() {
            "configure" => &["expected_policy_revision", "configuration"],
            "start" => &[
                "expected_policy_revision",
                "expected_run_revision",
                "mode",
                "safety_revision",
            ],
            "stop" => &["run_id"],
            _ => return Err(bad("action")),
        };
        let base = ["v", "profile_id", "boot_id", "command_id", "action"];
        if o.keys()
            .any(|k| !base.contains(&k.as_str()) && !extra.contains(&k.as_str()))
        {
            return Err(("invalid_request", None));
        }
        if let Some(k) = base.iter().chain(extra).find(|k| !o.contains_key(**k)) {
            return Err(("invalid_request", Some(k)));
        }
        if body["v"].as_u64() != Some(1) {
            return Err(if body["v"].is_u64() {
                ("unsupported_version", Some("v"))
            } else {
                bad("v")
            });
        }
        for k in ["profile_id", "boot_id", "command_id"] {
            if !body[k].as_str().is_some_and(profile::valid_uuid) {
                return Err(bad(k));
            }
        }
        let safe = |k: &'static str| body[k].as_u64().filter(|n| *n <= MAX_SAFE).ok_or(bad(k));
        let parsed = match action.as_str() {
            "configure" => {
                safe("expected_policy_revision")?;
                Some(parse_config(&body["configuration"])?)
            }
            "start" => {
                safe("expected_policy_revision")?;
                safe("expected_run_revision")?;
                if !matches!(body["mode"].as_str(), Some("ft8" | "ft4")) {
                    return Err(bad("mode"));
                }
                if safe("safety_revision")? == 0 {
                    return Err(bad("safety_revision"));
                }
                None
            }
            _ => {
                if !body["run_id"].as_str().is_some_and(profile::valid_uuid) {
                    return Err(bad("run_id"));
                }
                None
            }
        };
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id")));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id")));
        }
        let command_id = body["command_id"].as_str().unwrap_or("").to_owned();
        let contact = owner(r).map_err(|e| (e, None))?;
        let mut inner = self.lock();
        if let Some((_, prior, receipt)) =
            inner.receipts.iter().find(|(id, _, _)| *id == command_id)
        {
            return if *prior == body {
                Ok((StatusCode::OK, receipt.clone()))
            } else {
                Err(("state_conflict", Some("command_id")))
            };
        }
        let active = inner
            .run
            .as_ref()
            .is_some_and(|run| run.state != RunState::Stopped);
        match action.as_str() {
            "configure" => {
                if body["expected_policy_revision"].as_u64() != Some(inner.policy_revision) {
                    return Err(("stale_revision", Some("expected_policy_revision")));
                }
                if active {
                    return Err(("state_conflict", Some("run")));
                }
                if inner.policy_revision >= MAX_SAFE {
                    return Err(("counter_exhausted", None));
                }
                inner.configuration = parsed.flatten();
                inner.policy_revision += 1;
            }
            "start" => {
                if body["expected_policy_revision"].as_u64() != Some(inner.policy_revision) {
                    return Err(("stale_revision", Some("expected_policy_revision")));
                }
                if body["expected_run_revision"].as_u64() != Some(inner.run_revision) {
                    return Err(("stale_revision", Some("expected_run_revision")));
                }
                if active {
                    return Err(("state_conflict", Some("run")));
                }
                let config = inner
                    .configuration
                    .clone()
                    .ok_or(("not_configured", Some("configuration")))?;
                let mode = if body["mode"] == "ft4" { "ft4" } else { "ft8" };
                if !config.modes.contains(&mode) {
                    return Err(("not_ready", Some("mode")));
                }
                // Transmit authority: a current CL-022 grant of this request (no grant,
                // no automation); the grant is rechecked at every automation step.
                let access = access.ok_or(("transmit_unavailable", None))?;
                let (source, job, generation, live_mode) =
                    r.live_identity().ok_or(("not_ready", Some("receive")))?;
                if live_mode != mode || r.operating_mode() != mode {
                    return Err(("not_ready", Some("mode")));
                }
                let (_, facts, auto_seq) = contact.facts();
                if !auto_seq {
                    return Err(("not_ready", Some("auto_seq")));
                }
                if facts.as_ref().is_some_and(|c| c.active) {
                    return Err(("state_conflict", Some("contact")));
                }
                let transmit = r.transmit.get().ok_or(("transmit_unavailable", None))?;
                if inner.run_revision >= MAX_SAFE {
                    return Err(("counter_exhausted", None));
                }
                let id = profile::new_uuid().map_err(|_| ("storage_unavailable", None))?;
                let last_decode = r.latest_publication().map_or(0, |p| p.0);
                inner.run = Some(Run {
                    id,
                    state: RunState::Waiting,
                    reason: None,
                    mode,
                    config,
                    identity: (source, job, generation),
                    access,
                    safety_revision: body["safety_revision"].as_u64().unwrap_or(0),
                    halts: transmit.service.halt_requests(),
                    last_decode,
                    completed: 0,
                    unanswered: 0,
                    contact_id: None,
                    progress: None,
                    selected: None,
                    worked: Vec::new(),
                    last_decision: None,
                });
                inner.run_revision += 1;
            }
            _ => {
                let run = inner
                    .run
                    .as_ref()
                    .ok_or(("stale_request", Some("run_id")))?;
                if run.id != body["run_id"] {
                    return Err(("stale_request", Some("run_id")));
                }
                if run.state == RunState::Stopped {
                    return Err(("stale_request", Some("run_id")));
                }
                // Future dispatch ends before the acknowledgement; a contact armed by
                // this run is disarmed through the same Enable Tx path (not a Halt).
                let armed = run.state == RunState::ContactActive;
                Self::finish(&mut inner, "stopped");
                if armed {
                    disarm(&contact, state);
                }
            }
        }
        let receipt = Self::receipt(r, &inner, &command_id);
        if inner.receipts.len() == RECEIPTS {
            inner.receipts.pop_front();
        }
        inner
            .receipts
            .push_back((command_id, body, receipt.clone()));
        Ok((StatusCode::ACCEPTED, receipt))
    }
    fn finish(inner: &mut Inner, reason: &'static str) {
        if let Some(run) = inner.run.as_mut() {
            run.state = RunState::Stopped;
            run.reason = Some(reason);
            inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        }
    }
    /// One automation step after the contact step (main.rs station timer).
    pub(crate) fn tick(
        &self,
        contact: &contact_http::Station,
        state: &ProfileState,
        publication: Publication,
    ) {
        let r = &state.recording;
        let mut inner = self.lock();
        let Some(run) = inner.run.as_ref() else {
            return;
        };
        if run.state == RunState::Stopped {
            return;
        }
        let armed = run.state == RunState::ContactActive;
        let stop = |inner: &mut Inner, reason: &'static str, disarm_now: bool| {
            Self::finish(inner, reason);
            if disarm_now {
                disarm(contact, state);
            }
        };
        // Halt (browser button, Esc or MCP) ends the run in every state.
        let halts = r.transmit.get().map(|t| t.service.halt_requests());
        if halts != Some(run.halts) {
            return stop(&mut inner, "halted", armed);
        }
        let live = r.live_identity();
        if live.as_ref().is_none_or(|(s, j, g, m)| {
            (s, j, *g) != (&run.identity.0, &run.identity.1, run.identity.2) || *m != run.mode
        }) || r.operating_mode() != run.mode
        {
            return stop(&mut inner, "context_changed", armed);
        }
        if !grant_current(state, &run.access) {
            return stop(&mut inner, "authority_lost", armed);
        }
        let fresh = publication
            .filter(|p| p.3 && p.0 > run.last_decode)
            .map(|p| (p.0, p.1, p.2));
        let (_, facts, _) = contact.facts();
        let arm = r.transmit.get().map(|t| t.service.view().arm_state);
        let run = inner.run.as_mut().expect("checked");
        if let Some((id, _, _)) = fresh {
            run.last_decode = id;
        }
        match run.state {
            RunState::ContactActive => {
                let Some(c) = facts.filter(|c| Some(&c.id) == run.contact_id.as_ref()) else {
                    return stop(&mut inner, "contact_changed", true);
                };
                if c.state == "completed" {
                    run.completed += 1;
                    if let Some(call) = c.dx_call {
                        run.worked.push(call);
                    }
                    let (reached, next) = (
                        run.completed >= run.config.max_contacts,
                        run.config.next_candidate,
                    );
                    if reached {
                        return stop(&mut inner, "limit_reached", false);
                    }
                    if !next {
                        return stop(&mut inner, "completed", false);
                    }
                    run.state = RunState::Waiting;
                    run.contact_id = None;
                    run.progress = None;
                    run.unanswered = 0;
                    inner.run_revision += 1;
                    return;
                }
                if c.state == "cancelled" || c.state == "idle" {
                    return stop(&mut inner, "contact_changed", false);
                }
                if arm != Some(wstx_rust::transmit::service::ArmState::Armed) {
                    return stop(&mut inner, "transmit_stopped", false);
                }
                if fresh.is_some() {
                    let progress = (c.state.to_owned(), c.report_rcvd);
                    if run.progress.as_ref() == Some(&progress) {
                        run.unanswered += 1;
                        if run.unanswered >= run.config.max_unanswered {
                            return stop(&mut inner, "no_answer", true);
                        }
                    } else {
                        run.progress = Some(progress);
                        run.unanswered = 0;
                    }
                    inner.run_revision += 1;
                }
            }
            RunState::Waiting => {
                let Some((_, first, next)) = fresh else {
                    return;
                };
                let my = contact_http::my_call(state).unwrap_or_default();
                let records: Vec<Value> = r
                    .live_records_after(Some(&run.identity), first)
                    .map(|(_, _, records)| records)
                    .unwrap_or_default()
                    .into_iter()
                    .filter(|v| {
                        v["sequence"]
                            .as_u64()
                            .is_some_and(|s| s >= first && s < next)
                    })
                    .collect();
                let list = candidates(&records, &run.config, &my, &run.worked);
                let period = records
                    .first()
                    .map(|v| v["period_start_utc"].clone())
                    .unwrap_or(Value::Null);
                let chosen = list.first().cloned();
                run.last_decision = Some(json!({"period_start_utc":period,"candidates":list.len(),
                    "selected_call":chosen.as_ref().map(|c|c.call.clone())}));
                inner.run_revision += 1;
                let Some(chosen) = chosen else {
                    return;
                };
                let run = inner.run.as_mut().expect("checked");
                let row = json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":chosen.sequence});
                let (revision, _, _) = contact.facts();
                let selected = contact.operate(
                    state,
                    contact_body(
                        r,
                        revision,
                        "select_row",
                        json!({"row":row,"replace":false}),
                    ),
                    true,
                );
                let Ok((_, receipt)) = selected else {
                    return stop(&mut inner, "provider_error", false);
                };
                let revision = receipt["contact_revision"].as_u64().unwrap_or(revision);
                let enabled = contact.operate(
                    state,
                    contact_body(
                        r,
                        revision,
                        "enable_tx",
                        json!({"enabled":true,"safety_revision":run.safety_revision}),
                    ),
                    true,
                );
                if enabled.is_err() {
                    return stop(&mut inner, "transmit_refused", false);
                }
                // Progress is measured from the prepared contact: the next publication
                // without a partner step already counts as unanswered.
                let (_, facts, _) = contact.facts();
                run.progress = facts.as_ref().map(|c| (c.state.to_owned(), c.report_rcvd));
                run.contact_id = facts.map(|c| c.id);
                run.selected = Some(json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":chosen.sequence,"call":chosen.call}));
                run.state = RunState::ContactActive;
                run.unanswered = 0;
            }
            RunState::Stopped => {}
        }
    }
}
fn contact_body(r: &recording::Recording, revision: u64, action: &str, extra: Value) -> Value {
    let mut b = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,
        "command_id":profile::new_uuid().unwrap_or_default(),"contact_revision":revision,"action":action});
    if let (Some(o), Some(e)) = (b.as_object_mut(), extra.as_object()) {
        o.extend(e.clone());
    }
    b
}
/// Enable Tx off through the same contact command path (never a Halt).
fn disarm(contact: &contact_http::Station, state: &ProfileState) {
    let (revision, _, _) = contact.facts();
    let body = contact_body(
        &state.recording,
        revision,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    );
    let _ = contact.operate(state, body, false);
}
fn grant_current(state: &ProfileState, access: &authorization::Access) -> bool {
    state.authorization.lock().ok().is_some_and(|owner| {
        owner
            .as_ref()
            .is_some_and(|s| s.authority.current_grant(access).is_ok())
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
        Err(e) => return refusal(e, None),
    };
    if let Err(e) = empty(query, body) {
        return refusal(e, None);
    }
    match owner(&r) {
        Ok(c) => Json(c.automation.snapshot(&r)).into_response(),
        Err(e) => refusal(e, None),
    }
}
pub async fn command(
    State(app): State<App>,
    headers: HeaderMap,
    RawQuery(query): RawQuery,
    body: Result<Bytes, BytesRejection>,
) -> Response {
    let r = match authorize(&app, &headers, true).await {
        Ok(r) => r,
        Err(e) => return refusal(e, None),
    };
    if query.is_some() {
        return refusal("invalid_request", None);
    }
    let body: Value = match recording_http::parse(&headers, body) {
        Ok(v) => v,
        Err(e) => return refusal(e, None),
    };
    let access = authorization_http::operating_access_async(&headers, &app)
        .await
        .ok()
        .flatten();
    let (Ok(contact), Some(state)) = (owner(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    match tokio::task::spawn_blocking(move || contact.automation.command(&state, body, access))
        .await
    {
        Ok(Ok((status, reply))) => (status, Json(reply)).into_response(),
        Ok(Err((c, f))) => refusal(c, f),
        Err(_) => refusal("storage_unavailable", None),
    }
}
