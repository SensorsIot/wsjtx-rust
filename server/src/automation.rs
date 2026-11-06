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
use wstx_rust::transmit::service::DisarmCause;

const MAX_SAFE: u64 = 9_007_199_254_740_991;
/// Run commands are the station's own automation: never an operator action (#39, #58).
const AUTOMATION: authorization::Principal = authorization::Principal::Automation;
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
/// The run duration when the configuration omits max_run_minutes (D7).
pub const RUN_MINUTES_DEFAULT: u64 = 120;
/// WstxMcp::AutomationConfiguration (every policy key required; only the run duration
/// bound has a default).
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
    pub max_run_minutes: u64,
    /// #39: the station's active WstxStrategy chooses and orders (Auto).
    pub strategy: bool,
    /// #42 WstxStrategy::Pounce: the one call this run waits for and answers.
    pub pounce: Option<String>,
}
impl Config {
    pub(crate) fn json(&self) -> Value {
        json!({"modes":self.modes,"ranking":self.ranking.name(),"min_snr_db":self.min_snr_db,
            "allowed_calls":self.allowed,"blocked_calls":self.blocked,"max_contacts":self.max_contacts,
            "max_unanswered_periods":self.max_unanswered,
            "completion_action":if self.next_candidate {"next_candidate"} else {"stop"},
            "max_run_minutes":self.max_run_minutes,"strategy":self.strategy,"pounce":self.pounce})
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
    let optional = ["max_run_minutes", "strategy", "pounce"]
        .iter()
        .filter(|k| o.contains_key(**k))
        .count();
    if o.len() != keys.len() + optional || !keys.iter().all(|k| o.contains_key(*k)) {
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
    let strategy = match o.get("strategy") {
        None => false,
        Some(b) => b.as_bool().ok_or(bad("strategy"))?,
    };
    // #42 Pounce: one sane call, never with a strategy run nor a blocked call.
    let pounce = match o.get("pounce") {
        None | Some(Value::Null) => None,
        Some(c) => Some(
            c.as_str()
                .filter(|c| valid_call(c) && strategy::sane_call(c))
                .filter(|c| !strategy && !blocked.iter().any(|b| b == c))
                .ok_or(bad("pounce"))?
                .to_owned(),
        ),
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
        max_run_minutes: match o.get("max_run_minutes") {
            None => RUN_MINUTES_DEFAULT,
            Some(m) => bounded(m, "max_run_minutes", 1..=480)?,
        },
        strategy,
        pounce,
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
    /// #39 Auto CQ: the run's own CQ is called (WstxStrategy::AutoRoles).
    CallingCq,
    ContactActive,
    /// #39 ManualIntervention: an operator's contact is on the engine; the strategy waits.
    Manual,
    Stopped,
}
impl RunState {
    fn name(self) -> &'static str {
        match self {
            RunState::Waiting => "waiting",
            RunState::Manual => "manual",
            RunState::CallingCq => "calling_cq",
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
    /// The starting request's grant transport (memory only, never serialized): the run
    /// lives no longer than it (D7).
    token: String,
    deadline: Instant,
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
    /// #39 strategy runs: the current role (Call or Cq; None for a plain MCP policy),
    /// consecutive tries without a contact, and calls skipped after no answer.
    role: Option<strategy::Role>,
    tries: u64,
    skipped: Vec<String>,
    /// #42 Pounce: the call and the station band captured at start.
    pounce: Option<(String, String)>,
    /// #39 WstxStrategy::FreeTxSlot: the last slot decision {hz, free}, for the status; the
    /// station band last seen on a fresh publication, and the first sequence of that band
    /// (a retune on the radio keeps the live job).
    tx_slot: Option<Value>,
    slot_band: Option<&'static str>,
    slot_from: u64,
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
    /// Test seam: added to the monotonic clock of every automation step.
    #[cfg(test)]
    pub(crate) skew: Mutex<Duration>,
    /// Test seam: runs between select_row and enable_tx (a racing Halt).
    #[cfg(test)]
    pub(crate) before_enable: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    /// Test seam: runs before a run moves Tx to its free slot (a racing operator).
    #[cfg(test)]
    pub(crate) before_slot_move: Mutex<Option<Box<dyn FnOnce() + Send>>>,
}

/// The descriptor of the latest receive publication, read before the contact step so
/// that the engine has already consumed every record of a publication it reports.
/// (id, first_sequence, next_sequence, complete, period_start_utc).
pub(crate) type Publication = Option<(u64, u64, u64, bool, Option<String>)>;

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
    fn now(&self) -> Instant {
        #[cfg(test)]
        let skew = *self.skew.lock().unwrap_or_else(|p| p.into_inner());
        #[cfg(not(test))]
        let skew = Duration::ZERO;
        Instant::now() + skew
    }
    #[cfg(test)]
    fn before_enable(&self) {
        let hook = self
            .before_enable
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .take();
        if let Some(hook) = hook {
            hook();
        }
    }
    #[cfg(not(test))]
    fn before_enable(&self) {}
    #[cfg(test)]
    fn before_slot_move(&self) {
        let hook = self
            .before_slot_move
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(hook) = hook {
            hook();
        }
    }
    #[cfg(not(test))]
    fn before_slot_move(&self) {}
    /// (policy_revision, run_revision): the automation.state event cursor.
    pub(crate) fn revisions(&self) -> (u64, u64) {
        let inner = self.lock();
        (inner.policy_revision, inner.run_revision)
    }
    /// AutomationSnapshot.
    pub(crate) fn snapshot(&self, r: &recording::Recording) -> Value {
        let inner = self.lock();
        let run = inner.run.as_ref().map(|run| {
            json!({"id":run.id,"state":run.state.name(),"reason":run.reason,"mode":run.mode,
                "completed_contacts":run.completed,"unanswered_periods":run.unanswered,
                "contact_id":run.contact_id,"selected":run.selected,"last_decision":run.last_decision,
                "role":run.role.map(|r| if r == strategy::Role::Cq {"cq"} else {"call"}),"tries":run.tries,
                "skipped":run.skipped,"tx_slot":run.tx_slot,
                "pounce":run.pounce.as_ref().map(|(call, band)| json!({"call":call,"band":band}))})
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
        access: Option<(authorization::Access, String)>,
        operator: bool,
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
                let (source, job, generation, live_mode) =
                    r.live_identity().ok_or(("not_ready", Some("receive")))?;
                if live_mode != mode || r.operating_mode() != mode {
                    return Err(("not_ready", Some("mode")));
                }
                let (_, facts, auto_seq) = contact.facts();
                if !auto_seq {
                    return Err(("not_ready", Some("auto_seq")));
                }
                // #24 S1b: station automation stays standard-only; a nonstandard own call
                // would call CQ without ever recognizing a caller's <MYCALL>.
                if contact_http::my_call(state)
                    .is_some_and(|c| !crate::contact::is_standard_call(&c))
                {
                    return Err(("not_ready", Some("call")));
                }
                // #24 S2a: in a contest activity automation only observes (scope default).
                if contact.status_facts().activity != crate::contact::Activity::None {
                    return Err(("not_ready", Some("activity")));
                }
                // #42 Pounce waits on the current band: it must be known.
                let pounce = match &config.pounce {
                    None => None,
                    Some(call) => Some((
                        call.clone(),
                        strategy::station_band(r)
                            .ok_or(("not_ready", Some("band")))?
                            .to_owned(),
                    )),
                };
                if facts.as_ref().is_some_and(|c| c.active) {
                    return Err(("state_conflict", Some("contact")));
                }
                // #39 Auto never runs unfiltered: a strategy run needs the active strategy.
                let role = if config.strategy {
                    let s = contact
                        .strategy
                        .config(state)
                        .and_then(|c| c.active_strategy().cloned())
                        .ok_or(("not_configured", Some("strategy")))?;
                    Some(if s.role == strategy::Role::Cq {
                        strategy::Role::Cq
                    } else {
                        strategy::Role::Call
                    })
                } else {
                    None
                };
                // Transmit authority: a current CL-022 grant transport of this request
                // (no grant, no automation), rechecked at every automation step.
                let (access, token) = access.ok_or(("transmit_unavailable", None))?;
                let transmit = r.transmit.get().ok_or(("transmit_unavailable", None))?;
                // The safety revision the operator acknowledged must be the current one,
                // so a run never selects a contact it then cannot arm.
                let current = transmit
                    .service
                    .with(|c| c.hardware().context().safety_revision)
                    .ok_or(("transmit_unavailable", None))?;
                if body["safety_revision"].as_u64() != Some(current) {
                    return Err(("stale_revision", Some("safety_revision")));
                }
                if inner.run_revision >= MAX_SAFE {
                    return Err(("counter_exhausted", None));
                }
                let id = profile::new_uuid().map_err(|_| ("storage_unavailable", None))?;
                // A start from the browser is the operator's decision to transmit again
                // after a Tx watchdog stop; an MCP start never is (#39).
                if operator {
                    transmit.service.with(|c| c.operator_restart());
                }
                let last_decode = r.latest_publication().map_or(0, |p| p.0);
                let deadline = self.now() + Duration::from_secs(config.max_run_minutes * 60);
                inner.run = Some(Run {
                    id,
                    state: RunState::Waiting,
                    reason: None,
                    mode,
                    config,
                    identity: (source, job, generation),
                    access,
                    token,
                    deadline,
                    safety_revision: current,
                    halts: transmit.service.halt_requests(),
                    last_decode,
                    completed: 0,
                    unanswered: 0,
                    contact_id: None,
                    progress: None,
                    selected: None,
                    worked: Vec::new(),
                    last_decision: None,
                    role,
                    tries: 0,
                    skipped: Vec::new(),
                    pounce,
                    tx_slot: None,
                    slot_band: None,
                    slot_from: 0,
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
                let armed = matches!(run.state, RunState::ContactActive | RunState::CallingCq);
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
        let armed = matches!(run.state, RunState::ContactActive | RunState::CallingCq);
        let stop = |inner: &mut Inner, reason: &'static str, disarm_now: bool| {
            Self::finish(inner, reason);
            if disarm_now {
                disarm(contact, state);
            }
        };
        // Halt (browser button, Alt+H, MCP or UDP) ends the run in every state.
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
        let now = self.now();
        if !grant_current(state, &run.access, &run.token, now) {
            return stop(&mut inner, "authority_lost", armed);
        }
        if now >= run.deadline {
            return stop(&mut inner, "time_limit", armed);
        }
        // #42 Pounce: a station band change ends it.
        if let Some((_, band)) = &run.pounce
            && strategy::station_band(r) != Some(band.as_str())
        {
            return stop(&mut inner, "band_changed", armed);
        }
        // #39: a strategy run reads the saved active strategy at every step (Save applies
        // at once); without one it stops: Auto never runs unfiltered.
        let chosen = if run.config.strategy {
            let saved = contact
                .strategy
                .config(state)
                .and_then(|c| c.active_strategy().cloned().map(|s| (c, s)));
            if saved.is_none() {
                return stop(&mut inner, "strategy_missing", armed);
            }
            saved
        } else {
            None
        };
        // The records before this sequence belong to complete publications.
        let settled = publication.as_ref().map(|p| if p.3 { p.2 } else { p.1 });
        let fresh = publication
            .filter(|p| p.3 && p.0 > run.last_decode)
            .map(|p| (p.0, p.1, p.2, p.4));
        let (_, facts, _) = contact.facts();
        let view = r.transmit.get().map(|t| t.service.view());
        let arm = view.as_ref().map(|v| v.arm_state);
        // A disarm by the Tx watchdog is named as such (#39).
        let disarmed = if view
            .as_ref()
            .is_some_and(|v| v.last_disarm_cause == DisarmCause::TxWatchdog)
        {
            "tx_watchdog"
        } else {
            "transmit_stopped"
        };
        let my = contact_http::my_call(state).unwrap_or_default();
        let mode = contact_http::mode_of(run.mode);
        let partner_period = facts.as_ref().is_some_and(|c| {
            fresh
                .as_ref()
                .and_then(|f| f.3.as_deref())
                .and_then(contact::parse_utc)
                .is_some_and(|ms| wstx_rust::transmit::parity(mode, ms) != c.parity)
        });
        let run = inner.run.as_mut().expect("checked");
        if let Some((id, _, next, _)) = &fresh {
            run.last_decode = *id;
            if let Some(band) = strategy::station_band(r) {
                // The publication that shows the change may hold either band: not counted.
                if run.slot_band.is_some_and(|seen| seen != band) {
                    run.slot_from = *next;
                }
                run.slot_band = Some(band);
            }
        }
        if let Some((_, s)) = &chosen
            && s.role != strategy::Role::Alternate
        {
            run.role = Some(s.role);
        }
        match run.state {
            // WstxStrategy::ManualIntervention: resume when the operator's contact has ended.
            RunState::Manual => {
                if !facts.as_ref().is_some_and(|c| c.active) {
                    run.state = RunState::Waiting;
                    inner.run_revision += 1;
                }
            }
            RunState::ContactActive => {
                let Some(c) = facts.filter(|c| Some(&c.id) == run.contact_id.as_ref()) else {
                    if run.config.strategy {
                        return manual(&mut inner);
                    }
                    return stop(&mut inner, "contact_changed", true);
                };
                if c.state == "completed" {
                    run.completed += 1;
                    if let Some(call) = c.dx_call {
                        run.worked.push(call);
                    }
                    // #42 a pounce ends on its success.
                    if run.pounce.is_some() {
                        return stop(&mut inner, "completed", false);
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
                    // Waiting again; in the CQ role the next step calls CQ again.
                    run.state = RunState::Waiting;
                    run.contact_id = None;
                    run.progress = None;
                    run.unanswered = 0;
                    run.tries = 0;
                    inner.run_revision += 1;
                    return;
                }
                if c.state == "cancelled" || c.state == "idle" {
                    if !run.config.strategy {
                        return stop(&mut inner, "contact_changed", false);
                    }
                    // The operator gave this station up: the strategy goes on without it.
                    if let Some(call) = run
                        .selected
                        .as_ref()
                        .and_then(|s| s["call"].as_str())
                        .map(str::to_owned)
                    {
                        run.skipped.push(call);
                    }
                    return manual(&mut inner);
                }
                if arm != Some(wstx_rust::transmit::service::ArmState::Armed) {
                    return stop(&mut inner, disarmed, false);
                }
                // Only a publication of the partner's period parity can answer.
                if partner_period {
                    let progress = (c.state.to_owned(), c.report_rcvd);
                    if run.progress.as_ref() == Some(&progress) {
                        run.unanswered += 1;
                        let limit = chosen
                            .as_ref()
                            .map_or(run.config.max_unanswered, |(_, s)| s.skip_after);
                        if run.unanswered >= limit {
                            if chosen.is_none() && run.pounce.is_some() {
                                // #42 the pounce stays: wait again for the same call.
                                run.state = RunState::Waiting;
                                run.contact_id = None;
                                run.progress = None;
                                run.unanswered = 0;
                                inner.run_revision += 1;
                                drop(inner);
                                cancel(contact, state);
                                return;
                            }
                            let Some((_, s)) = &chosen else {
                                return stop(&mut inner, "no_answer", true);
                            };
                            // #39 skip after N unanswered calls: give this station up
                            // for the rest of the run and carry on (no stop).
                            if let Some(call) = c.dx_call {
                                run.skipped.push(call);
                            }
                            run.state = RunState::Waiting;
                            run.contact_id = None;
                            run.progress = None;
                            run.unanswered = 0;
                            run.tries += 1;
                            switch(run, s);
                            inner.run_revision += 1;
                            drop(inner);
                            cancel(contact, state);
                            return;
                        }
                    } else {
                        run.progress = Some(progress);
                        run.unanswered = 0;
                    }
                    inner.run_revision += 1;
                }
            }
            RunState::CallingCq => {
                let Some(c) = facts.filter(|c| Some(&c.id) == run.contact_id.as_ref()) else {
                    return manual(&mut inner);
                };
                // Before the arm check: an operator's cancel also disarms.
                if c.state != "calling" {
                    return manual(&mut inner);
                }
                if arm != Some(wstx_rust::transmit::service::ArmState::Armed) {
                    return stop(&mut inner, disarmed, false);
                }
                let Some((config, s)) = chosen else {
                    return stop(&mut inner, "strategy_missing", true);
                };
                if run.role != Some(strategy::Role::Cq) {
                    // The saved role changed to Call: end the CQ and wait for candidates.
                    run.state = RunState::Waiting;
                    run.contact_id = None;
                    run.tries = 0;
                    inner.run_revision += 1;
                    drop(inner);
                    cancel(contact, state);
                    return;
                }
                let Some((_, first, next, _)) = fresh.filter(|_| partner_period) else {
                    return;
                };
                let records = fresh_records(r, &run.identity, first, next);
                let st = strategy::station(state, &config, &records);
                let mut callers: Vec<strategy::Verdict> = strategy::evaluate(&s, &records, &st)
                    .into_iter()
                    .filter(|v| {
                        v.facts.to_call.as_deref() == Some(my.as_str())
                            && !v.facts.signoff
                            && !v.ignored
                            && strategy::sane_call(&v.facts.from)
                            && eligible(run, &v.facts.from)
                            && (!s.apply_to_callers || v.rank.is_some())
                    })
                    .map(|mut v| {
                        if !s.apply_to_callers {
                            v.rank = Some(0);
                        }
                        v
                    })
                    .collect();
                strategy::order(&mut callers, s.sort);
                run.last_decision = Some(
                    json!({"period_start_utc":records.first().map(|v| v["period_start_utc"].clone()),
                    "candidates":callers.len(),"selected_call":callers.first().map(|c| c.facts.from.clone())}),
                );
                inner.run_revision += 1;
                let run = inner.run.as_mut().expect("checked");
                let Some(caller) = callers.into_iter().next() else {
                    run.tries += 1;
                    switch(run, &s);
                    if run.role != Some(strategy::Role::Cq) {
                        run.state = RunState::Waiting;
                        run.contact_id = None;
                        run.tries = 0;
                        drop(inner);
                        cancel(contact, state);
                    }
                    return;
                };
                // Answer the caller: the armed CQ becomes this contact (no new arming).
                let row = json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":caller.facts.sequence});
                let (revision, _, _) = contact.facts();
                let body = contact_body(
                    r,
                    revision,
                    "select_row",
                    json!({"row":row,"replace":false}),
                );
                if contact.operate_as(state, body, true, AUTOMATION).is_err() {
                    // The operator's double-click won the race: the contact is theirs.
                    if contact.facts().1.is_some_and(|c| c.state != "calling") {
                        return manual(&mut inner);
                    }
                    return stop(&mut inner, "provider_error", true);
                }
                let (_, facts, _) = contact.facts();
                let run = inner.run.as_mut().expect("checked");
                run.progress = facts.as_ref().map(|c| (c.state.to_owned(), c.report_rcvd));
                run.contact_id = facts.map(|c| c.id);
                run.selected = Some(json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":caller.facts.sequence,"call":caller.facts.from}));
                run.state = RunState::ContactActive;
                run.unanswered = 0;
                run.tries = 0;
            }
            RunState::Waiting => {
                // An operator's CQ or contact in progress is never taken over.
                if facts.as_ref().is_some_and(|c| c.active) {
                    if run.config.strategy {
                        return manual(&mut inner);
                    }
                    return stop(&mut inner, "contact_changed", false);
                }
                if run.role == Some(strategy::Role::Cq) {
                    return self.call_cq(&mut inner, contact, state, settled);
                }
                let Some((_, first, next, _)) = fresh else {
                    return;
                };
                let records = fresh_records(r, &run.identity, first, next);
                let period = records
                    .first()
                    .map(|v| v["period_start_utc"].clone())
                    .unwrap_or(Value::Null);
                let list: Vec<(String, u64)> = match (&run.pounce, &chosen) {
                    // #42 Pounce: the chosen call's CQ (not greyed) or RR73/73 to another
                    // call, never when ignored; the first by sequence.
                    (Some((target, _)), _) => {
                        let config = contact.strategy.config(state).unwrap_or_default();
                        let st = strategy::station(state, &config, &records);
                        records
                            .iter()
                            .filter_map(strategy::facts)
                            .filter(|f| {
                                f.from == *target
                                    && f.from != my
                                    && !st.ignored.contains_key(&f.from)
                                    && !st.greyed(f)
                                    && st.cq_like(f, true)
                            })
                            .min_by_key(|f| f.sequence)
                            .map(|f| (f.from, f.sequence))
                            .into_iter()
                            .collect()
                    }
                    (None, None) => candidates(&records, &run.config, &my, &run.worked)
                        .into_iter()
                        .map(|c| (c.call, c.sequence))
                        .collect(),
                    (None, Some((config, s))) => {
                        let st = strategy::station(state, config, &records);
                        let mut v: Vec<strategy::Verdict> = strategy::evaluate(s, &records, &st)
                            .into_iter()
                            .filter(|v| {
                                v.rank.is_some()
                                    && st.cq_like(&v.facts, s.treat_73_as_cq)
                                    && strategy::sane_call(&v.facts.from)
                                    && v.facts.from != my
                                    && eligible(run, &v.facts.from)
                            })
                            .collect();
                        strategy::order(&mut v, s.sort);
                        let mut seen: Vec<String> = Vec::new();
                        v.into_iter()
                            .filter(|v| {
                                let first = !seen.contains(&v.facts.from);
                                seen.push(v.facts.from.clone());
                                first
                            })
                            .map(|v| (v.facts.from, v.facts.sequence))
                            .collect()
                    }
                };
                let chosen_row = list.first().cloned();
                run.last_decision = Some(json!({"period_start_utc":period,"candidates":list.len(),
                    "selected_call":chosen_row.as_ref().map(|c|c.0.clone())}));
                inner.run_revision += 1;
                let run = inner.run.as_mut().expect("checked");
                let Some((call, sequence)) = chosen_row else {
                    if let Some((_, s)) = &chosen {
                        run.tries += 1;
                        switch(run, s);
                    }
                    return;
                };
                let row = json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":sequence});
                let (revision, _, _) = contact.facts();
                let held_tx = contact.status_facts().tx_hz;
                let selected = contact.operate_as(
                    state,
                    contact_body(
                        r,
                        revision,
                        "select_row",
                        json!({"row":row,"replace":false}),
                    ),
                    true,
                    AUTOMATION,
                );
                let Ok((_, receipt)) = selected else {
                    if run.config.strategy && contact.facts().1.is_some_and(|c| c.active) {
                        return manual(&mut inner);
                    }
                    return stop(&mut inner, "provider_error", false);
                };
                let prepared = contact.facts().1.map(|c| c.id);
                let mut revision = receipt["contact_revision"].as_u64().unwrap_or(revision);
                // #39 WstxStrategy::FreeTxSlot: the call goes out from a free slot, never
                // from the called station's frequency (the selection's Rx).
                if run.config.strategy || run.pounce.is_some() {
                    let called = contact.status_facts().rx_hz;
                    let taken = take_slot(
                        run,
                        contact,
                        state,
                        settled,
                        held_tx,
                        Some(called),
                        revision,
                    );
                    let Some(taken) = taken else {
                        // As for enable_tx: another contact is the operator's.
                        if run.config.strategy
                            && contact
                                .facts()
                                .1
                                .is_some_and(|c| c.active && Some(&c.id) != prepared.as_ref())
                        {
                            return manual(&mut inner);
                        }
                        cancel(contact, state);
                        return stop(&mut inner, "provider_error", false);
                    };
                    revision = taken;
                }
                self.before_enable();
                let enabled = contact.operate_as(
                    state,
                    contact_body(
                        r,
                        revision,
                        "enable_tx",
                        json!({"enabled":true,"safety_revision":run.safety_revision}),
                    ),
                    true,
                    AUTOMATION,
                );
                if let Err((code, _)) = enabled {
                    // WstxStrategy::ManualIntervention: another contact than the one the run
                    // prepared is the operator's: it is left alone.
                    if run.config.strategy
                        && contact
                            .facts()
                            .1
                            .is_some_and(|c| c.active && Some(&c.id) != prepared.as_ref())
                    {
                        return manual(&mut inner);
                    }
                    // No unarmed selected contact is left behind.
                    cancel(contact, state);
                    return stop(&mut inner, refused(code), false);
                }
                if Self::raced_halt(&mut inner, r) {
                    return;
                }
                // Progress is measured from the prepared contact: the next publication
                // without a partner step already counts as unanswered.
                let (_, facts, _) = contact.facts();
                let run = inner.run.as_mut().expect("checked");
                run.progress = facts.as_ref().map(|c| (c.state.to_owned(), c.report_rcvd));
                run.contact_id = facts.map(|c| c.id);
                run.selected = Some(json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":sequence,"call":call}));
                run.state = RunState::ContactActive;
                run.unanswered = 0;
                run.tries = 0;
            }
            RunState::Stopped => {}
        }
    }
    /// A Halt that raced an arming wins: halt again (not merely disarm), so an Enable Tx
    /// admitted after the operator's Halt never keys; the run stops halted.
    fn raced_halt(inner: &mut Inner, r: &recording::Recording) -> bool {
        let run = inner.run.as_mut().expect("checked");
        let halts = r.transmit.get().map(|t| t.service.halt_requests());
        if halts == Some(run.halts) {
            return false;
        }
        if let (Some(t), Ok(id)) = (r.transmit.get(), profile::new_uuid()) {
            t.service.halt(&id);
        }
        let current = r.transmit.get().map(|t| t.service.halt_requests());
        run.halts = current.unwrap_or(run.halts);
        Self::finish(inner, "halted");
        true
    }
    /// #39 Auto CQ: arm a new own CQ through Enable Tx (the contact engine generates it).
    fn call_cq(
        &self,
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        settled: Option<u64>,
    ) {
        let r = &state.recording;
        let run = inner.run.as_mut().expect("checked");
        let (revision, _, _) = contact.facts();
        // #39 WstxStrategy::FreeTxSlot: a new CQ goes out from a free slot.
        let current = contact.status_facts().tx_hz;
        let Some(revision) = take_slot(run, contact, state, settled, current, None, revision)
        else {
            return Self::finish(inner, "provider_error");
        };
        self.before_enable();
        let body = contact_body(
            r,
            revision,
            "enable_tx",
            json!({"enabled":true,"safety_revision":run.safety_revision}),
        );
        if let Err((code, _)) = contact.operate_as(state, body, true, AUTOMATION) {
            return Self::finish(inner, refused(code));
        }
        if Self::raced_halt(inner, r) {
            return;
        }
        let (_, facts, _) = contact.facts();
        let run = inner.run.as_mut().expect("checked");
        run.contact_id = facts.map(|c| c.id);
        run.progress = None;
        run.unanswered = 0;
        run.state = RunState::CallingCq;
        inner.run_revision += 1;
    }
    /// An Auto strategy run is waiting, calling CQ or in a contact (its strategy cannot be
    /// switched or removed meanwhile).
    pub(crate) fn strategy_run_active(&self) -> bool {
        self.lock()
            .run
            .as_ref()
            .is_some_and(|run| run.config.strategy && run.state != RunState::Stopped)
    }
}
/// #39 WstxStrategy::ManualIntervention: leave the operator's contact alone.
fn manual(inner: &mut Inner) {
    if let Some(run) = inner.run.as_mut() {
        run.state = RunState::Manual;
        run.contact_id = None;
        run.progress = None;
        run.unanswered = 0;
        inner.run_revision += 1;
    }
}
/// The enable_tx refusal as a stop reason (#39: the Tx watchdog has its own).
fn refused(code: &str) -> &'static str {
    if code == "tx_watchdog" {
        "tx_watchdog"
    } else {
        "transmit_refused"
    }
}
/// The records of a slot decision: 8 periods of up to 128 decodes (the live job retains
/// up to 2048).
const SLOT_RECORDS: u64 = 1024;
/// #39 WstxStrategy::FreeTxSlot: decide the slot, name it in the run's status and set the
/// Tx there when it is not there. The next contact revision, or None when the engine refused
/// the command.
fn take_slot(
    run: &mut Run,
    contact: &contact_http::Station,
    state: &ProfileState,
    settled: Option<u64>,
    current: u32,
    called: Option<u32>,
    revision: u64,
) -> Option<u64> {
    let r = &state.recording;
    let mode = contact_http::mode_of(run.mode);
    let facts = contact.status_facts();
    let records = settled.map_or_else(Vec::new, |next| {
        let first = next.saturating_sub(SLOT_RECORDS).max(run.slot_from);
        fresh_records(r, &run.identity, first, next)
    });
    let (hz, free) = freeslot::decide(&records, mode, facts.parity, current, called);
    run.tx_slot = Some(json!({"hz":hz,"free":free}));
    if facts.tx_hz == hz {
        return Some(revision);
    }
    contact.automation.before_slot_move();
    let body = contact_body(
        r,
        revision,
        "set_frequency",
        json!({"rx_hz":null,"tx_hz":hz}),
    );
    let (_, receipt) = contact.operate_as(state, body, true, AUTOMATION).ok()?;
    Some(receipt["contact_revision"].as_u64().unwrap_or(revision))
}
/// A call not completed nor given up in this run.
fn eligible(run: &Run, call: &str) -> bool {
    !run.worked.iter().any(|w| w == call) && !run.skipped.iter().any(|w| w == call)
}
/// #39 alternate role: after switch_after consecutive tries without a contact the run
/// switches between Auto Call and Auto CQ.
fn switch(run: &mut Run, s: &strategy::Strategy) {
    if s.role == strategy::Role::Alternate && run.tries >= s.switch_after {
        run.role = Some(if run.role == Some(strategy::Role::Cq) {
            strategy::Role::Call
        } else {
            strategy::Role::Cq
        });
        run.tries = 0;
    }
}
/// The records [first, next) of the run's live job.
fn fresh_records(
    r: &recording::Recording,
    identity: &(String, String, u64),
    first: u64,
    next: u64,
) -> Vec<Value> {
    r.live_records_after(Some(identity), first)
        .map(|(_, _, records)| records)
        .unwrap_or_default()
        .into_iter()
        .filter(|v| {
            v["sequence"]
                .as_u64()
                .is_some_and(|s| s >= first && s < next)
        })
        .collect()
}
/// automation.state: announces a policy or run change; the browser then reads GET
/// /automation for its station-bar indicator.
pub(crate) fn state_event(r: &recording::Recording, (policy, run): (u64, u64)) -> String {
    json!({"v":1,"type":"automation.state","data":{"profile_id":r.profile,"boot_id":r.boot,
        "policy_revision":policy,"run_revision":run}})
    .to_string()
}
fn contact_body(r: &recording::Recording, revision: u64, action: &str, extra: Value) -> Value {
    let mut b = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,
        "command_id":profile::new_uuid().unwrap_or_default(),"contact_revision":revision,"action":action});
    if let (Some(o), Some(e)) = (b.as_object_mut(), extra.as_object()) {
        o.extend(e.clone());
    }
    b
}
/// Contact cancel through the same contact command path (automatic: no watchdog reset).
fn cancel(contact: &contact_http::Station, state: &ProfileState) {
    let (revision, _, _) = contact.facts();
    let body = contact_body(&state.recording, revision, "cancel", json!({}));
    let _ = contact.operate_as(state, body, false, AUTOMATION);
}
/// Enable Tx off through the same contact command path (never a Halt; automatic).
fn disarm(contact: &contact_http::Station, state: &ProfileState) {
    let (revision, _, _) = contact.facts();
    let body = contact_body(
        &state.recording,
        revision,
        "enable_tx",
        json!({"enabled":false,"safety_revision":null}),
    );
    let _ = contact.operate_as(state, body, false, AUTOMATION);
}
/// The starting transport is still this grant's current, unexpired transport (a
/// revocation, safety edit, expiry or a newer proof of the grant ends it).
fn grant_current(
    state: &ProfileState,
    access: &authorization::Access,
    token: &str,
    now: Instant,
) -> bool {
    state.authorization.lock().ok().is_some_and(|owner| {
        owner.as_ref().is_some_and(|s| {
            s.authority
                .access(token, &access.scope.https_origin, now)
                .is_ok_and(|current| current.grant_id == access.grant_id)
        })
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
    let checked = authorization_http::operating_access_async(&headers, &app).await;
    // A start from the browser is the operator action the Tx watchdog needs; an MCP
    // client's start never is (#58: the principal comes from the credential).
    let operator = match &checked {
        Ok(Some(a)) => a.principal.is_operator(),
        Ok(None) => true,
        Err(_) => false,
    };
    let access = checked
        .ok()
        .flatten()
        .zip(authorization_http::transport_token(&headers, &app));
    let (Ok(contact), Some(state)) = (owner(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    match tokio::task::spawn_blocking(move || {
        contact.automation.command(&state, body, access, operator)
    })
    .await
    {
        Ok(Ok((status, reply))) => (status, Json(reply)).into_response(),
        Ok(Err((c, f))) => refusal(c, f),
        Err(_) => refusal("storage_unavailable", None),
    }
}
