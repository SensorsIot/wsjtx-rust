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
/// #39 WstxStrategy::StrategyRun (operator decision, #39 comment 6685226511): with no
/// authenticated client for this long a strategy starts nothing new.
pub const CLIENT_GONE: Duration = Duration::from_secs(60);
/// #39 WstxStrategy::StrategyRun (operator decision 2026-11-06): the longest a strategy run lasts
/// from its selection, also with a browser open.
pub const STRATEGY_RUN_MAX: Duration = Duration::from_secs(8 * 3600);
/// #39 who is connected: open status WebSocket sessions (authenticated at the upgrade) and an
/// authenticated MCP request since the last run step (MCP has no sessions).
#[derive(Default)]
pub(crate) struct Clients {
    sessions: Arc<std::sync::atomic::AtomicUsize>,
    request: std::sync::atomic::AtomicBool,
}
/// Holds one status WebSocket session open.
pub(crate) struct ClientSession(Arc<std::sync::atomic::AtomicUsize>);
impl Drop for ClientSession {
    fn drop(&mut self) {
        self.0.fetch_sub(1, std::sync::atomic::Ordering::AcqRel);
    }
}
impl Clients {
    pub(crate) fn session(&self) -> ClientSession {
        self.sessions
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
        ClientSession(self.sessions.clone())
    }
    pub(crate) fn mcp_request(&self) {
        self.request
            .store(true, std::sync::atomic::Ordering::Release);
    }
    #[cfg(test)]
    pub(crate) fn sessions_open(&self) -> usize {
        self.sessions.load(std::sync::atomic::Ordering::Acquire)
    }
    /// A client is here now: a session is open, or a request came since the last call.
    fn present(&self) -> bool {
        let request = self
            .request
            .swap(false, std::sync::atomic::Ordering::AcqRel);
        request || self.sessions.load(std::sync::atomic::Ordering::Acquire) > 0
    }
}

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
    /// #39 WstxStrategy::StrategyRun: the active strategy chooses and orders; no bounds. Only
    /// a browser's selection sets it.
    pub strategy: bool,
    /// #42 WstxStrategy::Pounce: the one call this run waits for and answers.
    pub pounce: Option<String>,
}
impl Config {
    pub(crate) fn json(&self) -> Value {
        json!({"modes":self.modes,"ranking":self.ranking.name(),"min_snr_db":self.min_snr_db,
            "allowed_calls":self.allowed,"blocked_calls":self.blocked,
            "max_contacts":(!self.strategy).then_some(self.max_contacts),
            "max_unanswered_periods":self.max_unanswered,
            "completion_action":if self.next_candidate {"next_candidate"} else {"stop"},
            "max_run_minutes":(!self.strategy).then_some(self.max_run_minutes),
            "strategy":self.strategy,"pounce":self.pounce})
    }
}
/// The configuration of a strategy run (WstxStrategy::StrategyRun): no contact or time
/// limit, the list and the order are the strategy's.
fn strategy_config(mode: &'static str) -> Config {
    Config {
        modes: vec![mode],
        ranking: Ranking::FirstSeen,
        min_snr_db: None,
        allowed: Vec::new(),
        blocked: Vec::new(),
        max_contacts: 0,
        max_unanswered: 20,
        next_candidate: true,
        max_run_minutes: 0,
        strategy: true,
        pounce: None,
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
    // #39 a strategy run starts only by a browser's selection (WstxStrategy::StrategyRun).
    match o.get("strategy") {
        None | Some(Value::Bool(false)) => {}
        Some(Value::Bool(true)) => return Err(("operator_required", Some("strategy"))),
        Some(_) => return Err(bad("strategy")),
    }
    // #42 Pounce: one sane call, never a blocked call.
    let pounce = match o.get("pounce") {
        None | Some(Value::Null) => None,
        Some(c) => Some(
            c.as_str()
                .filter(|c| valid_call(c) && strategy::sane_call(c))
                .filter(|c| !blocked.iter().any(|b| b == c))
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
        strategy: false,
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
    ContactActive,
    /// #39 ManualIntervention: an operator's contact is on the engine; the strategy waits.
    Manual,
    /// #63 WstxContest::ContestRun: the run's own CQ is on the air.
    CallingCq,
    Stopped,
}
impl RunState {
    fn name(self) -> &'static str {
        match self {
            RunState::Waiting => "waiting",
            RunState::Manual => "manual",
            RunState::ContactActive => "contact_active",
            RunState::CallingCq => "calling_cq",
            RunState::Stopped => "stopped",
        }
    }
    /// The run armed what is on the engine.
    fn armed(self) -> bool {
        matches!(self, RunState::ContactActive | RunState::CallingCq)
    }
}
/// A call on the station band and mode it was worked or left on (a strategy run outlives both).
type OnBand = (String, Option<&'static str>, &'static str);
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
    worked: Vec<OnBand>,
    last_decision: Option<Value>,
    /// #39 strategy runs: the stations the operator cancelled or aborted (never again in
    /// this run), and the one left after calls_per_station (passed over once).
    given_up: Vec<String>,
    rested: Option<OnBand>,
    /// When a client was last there (WstxStrategy::StrategyRun; a selection counts).
    client_seen: Instant,
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
    /// #39 why the last selection started no run (the strategy stays selected).
    strategy_refusal: Option<&'static str>,
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
                "given_up":run.given_up,"rested":run.rested.as_ref().map(|c| &c.0),"tx_slot":run.tx_slot,
                "pounce":run.pounce.as_ref().map(|(call, band)| json!({"call":call,"band":band}))})
        });
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"policy_revision":inner.policy_revision,
            "run_revision":inner.run_revision,"configuration":inner.configuration.as_ref().map(Config::json),"run":run,
            "strategy_refusal":inner.strategy_refusal})
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
                // #39 only a browser's selection starts a strategy run (the configuration a
                // stopped one left stays until replaced; WstxStrategy::StrategyRun).
                if config.strategy {
                    return Err(("operator_required", Some("strategy")));
                }
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
                inner.strategy_refusal = None;
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
                    given_up: Vec::new(),
                    rested: None,
                    client_seen: self.now(),
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
                let (armed, own_cq) = (run.state.armed(), run.state == RunState::CallingCq);
                Self::finish(&mut inner, "stopped");
                if armed {
                    disarm(&contact, state);
                }
                // A run's CQ is never left behind (it would read as the operator's contact).
                if own_cq {
                    cancel(&contact, state);
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
    /// WstxStrategy::StrategyRun: a browser's PUT /strategy changed active (no strategy lock
    /// held). Any run ends: a contact it armed is disarmed, and cancelled when another
    /// strategy starts; when one is selected a run starts with the request's grant.
    pub(crate) fn selected(
        &self,
        contact: &contact_http::Station,
        state: &ProfileState,
        access: Option<(authorization::Access, String)>,
    ) {
        let r = &state.recording;
        // Colouring only starts no run (WstxContest::ContestSelection).
        let active = contact
            .strategy
            .config(state)
            .and_then(|c| c.run_strategy())
            .is_some();
        let mut inner = self.lock();
        let running = inner
            .run
            .as_ref()
            .filter(|run| run.state != RunState::Stopped)
            .map(|run| (run.state.armed(), run.state == RunState::CallingCq));
        if running.is_some() {
            Self::finish(&mut inner, "stopped");
        }
        if let Some((true, own_cq)) = running {
            if active || own_cq {
                cancel(contact, state);
            }
            disarm(contact, state);
        }
        inner.strategy_refusal = None;
        inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        if !active {
            return;
        }
        let started = (|| {
            let (access, token) = access.ok_or("transmit_unavailable")?;
            let transmit = r.transmit.get().ok_or("transmit_unavailable")?;
            let current = transmit
                .service
                .with(|c| c.hardware().context().safety_revision)
                .ok_or("transmit_unavailable")?;
            let id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
            // The selection is the operator's decision to transmit again after a Tx watchdog stop.
            transmit.service.with(|c| c.operator_restart());
            let mode = if r.operating_mode() == "ft4" {
                "ft4"
            } else {
                "ft8"
            };
            Ok(Run {
                id,
                state: RunState::Waiting,
                reason: None,
                mode,
                config: strategy_config(mode),
                identity: r
                    .live_identity()
                    .map_or_else(Default::default, |(s, j, g, _)| (s, j, g)),
                access,
                token,
                deadline: self.now() + STRATEGY_RUN_MAX,
                safety_revision: current,
                halts: transmit.service.halt_requests(),
                last_decode: r.latest_publication().map_or(0, |p| p.0),
                completed: 0,
                unanswered: 0,
                contact_id: None,
                progress: None,
                selected: None,
                worked: Vec::new(),
                last_decision: None,
                given_up: Vec::new(),
                rested: None,
                client_seen: self.now(),
                pounce: None,
                tx_slot: None,
                slot_band: None,
                slot_from: 0,
            })
        })();
        match started {
            Ok(run) => {
                inner.configuration = Some(run.config.clone());
                inner.policy_revision = inner.policy_revision.saturating_add(1).min(MAX_SAFE);
                inner.run = Some(run);
            }
            Err(reason) => inner.strategy_refusal = Some(reason),
        }
    }
    /// WstxStrategy::StrategyRun: re-identifies on the live identity and returns the reason
    /// the run cannot select now (a waiting reason); armed contact disarmed and cancelled.
    fn strategy_context(
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        contest: Option<&crate::contest::Selection>,
    ) -> Option<&'static str> {
        let r = &state.recording;
        let live = r
            .live_identity()
            .filter(|(_, _, _, m)| matches!(*m, "ft8" | "ft4") && r.operating_mode() == *m);
        let run = inner.run.as_mut().expect("checked");
        let changed = live.as_ref().map_or_else(
            || !run.identity.0.is_empty(),
            |(s, j, g, m)| {
                (s, j, *g) != (&run.identity.0, &run.identity.1, run.identity.2) || *m != run.mode
            },
        );
        if changed {
            let armed = run.state.armed();
            match &live {
                Some((s, j, g, m)) => {
                    run.identity = (s.clone(), j.clone(), *g);
                    run.mode = m;
                }
                None => run.identity = Default::default(),
            }
            // A new live job counts from its first record (WstxStrategy::FreeTxSlot).
            run.slot_from = 0;
            run.last_decode = r.latest_publication().map_or(0, |p| p.0);
            if armed {
                run.state = RunState::Waiting;
                run.contact_id = None;
                run.progress = None;
                run.unanswered = 0;
                cancel(contact, state);
                disarm(contact, state);
            }
            inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        }
        if live.is_none() {
            return Some("no_receive");
        }
        if !contact.facts().2 {
            return Some("auto_seq");
        }
        if contact_http::my_call(state).is_some_and(|c| !crate::contact::is_standard_call(&c)) {
            return Some("call");
        }
        // An award strategy waits in any activity, a contest for its own (WstxContest::ContestRun).
        let wanted = contest.map_or(crate::contact::Activity::None, |c| c.profile.activity);
        if contact.status_facts().activity != wanted {
            return Some("activity");
        }
        if let Some(c) = contest {
            if !strategy::station_band(r).is_some_and(|b| c.profile.bands.contains(&b)) {
                return Some("band");
            }
            let now = r.transmit.get().map_or_else(contact_http::wall_ms, |t| {
                t.service.with(|h| h.hardware().now_utc_ms())
            });
            if !c.in_period(now) {
                return Some("outside_period");
            }
        }
        None
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
        let armed = run.state.armed();
        let own_cq = run.state == RunState::CallingCq;
        let is_strategy = run.config.strategy;
        let stop = |inner: &mut Inner, reason: &'static str, disarm_now: bool| {
            Self::finish(inner, reason);
            if disarm_now {
                disarm(contact, state);
            }
            // A run's CQ is never left behind (it would read as the operator's contact).
            if own_cq {
                cancel(contact, state);
            }
        };
        // Halt (browser button, Alt+H or MCP) ends the run in every state.
        let halts = r.transmit.get().map(|t| t.service.halt_requests());
        if halts != Some(run.halts) {
            return stop(&mut inner, "halted", armed);
        }
        // A strategy run has no receive identity of its own: it re-identifies and waits.
        let saved_config = is_strategy
            .then(|| contact.strategy.config(state))
            .flatten();
        let contest = saved_config
            .as_ref()
            .and_then(strategy::Config::automatic_contest);
        let waiting_reason = if is_strategy {
            Self::strategy_context(&mut inner, contact, state, contest.as_ref())
        } else {
            let run = inner.run.as_ref().expect("checked");
            let live = r.live_identity();
            if live.as_ref().is_none_or(|(s, j, g, m)| {
                (s, j, *g) != (&run.identity.0, &run.identity.1, run.identity.2) || *m != run.mode
            }) || r.operating_mode() != run.mode
            {
                return stop(&mut inner, "context_changed", armed);
            }
            None
        };
        let run = inner.run.as_ref().expect("checked");
        let now = self.now();
        if !grant_current(state, &run.access, &run.token, is_strategy, now) {
            return stop(&mut inner, "authority_lost", armed);
        }
        if !is_strategy && now >= run.deadline {
            return stop(&mut inner, "time_limit", armed);
        }
        // #42 Pounce: a station band change ends it.
        if let Some((_, band)) = &run.pounce
            && strategy::station_band(r) != Some(band.as_str())
        {
            return stop(&mut inner, "band_changed", armed);
        }
        // #39: a strategy run reads the saved active strategy at every step (Save applies
        // at once); without one it stops.
        let chosen = if is_strategy {
            let saved = saved_config.and_then(|c| c.run_strategy().map(|s| (c, s)));
            if saved.is_none() {
                return stop(&mut inner, "strategy_missing", armed);
            }
            saved
        } else {
            None
        };
        // WstxStrategy::WorkedWindow: keeps the worked set current off the step.
        if let Some((_, s)) = &chosen {
            strategy::worked_of(state, s.window);
        }
        // WstxContest::ContestRun likewise: the next evaluation after a QSO counts that QSO.
        if let Some(c) = &contest {
            let (_, locator) = contact_http::profile_facts(state);
            contact
                .strategy
                .contest_log_latest(state, c, locator.as_deref());
        }
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
        if r.clients.present() {
            run.client_seen = now;
        }
        let no_client = is_strategy && now >= run.client_seen + CLIENT_GONE;
        let run_limit = is_strategy && now >= run.deadline;
        if is_strategy && run.state == RunState::Waiting && run.reason != waiting_reason {
            run.reason = waiting_reason;
            inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        }
        let run = inner.run.as_mut().expect("checked");
        match run.state {
            // WstxStrategy::ManualIntervention: resume when the operator's contact has ended.
            RunState::Manual => {
                if !facts.as_ref().is_some_and(|c| c.active) {
                    run.state = RunState::Waiting;
                    inner.run_revision += 1;
                }
            }
            // #63 WstxContest::ContestRun: the own CQ until a caller is worth answering.
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
                // Nothing new at the limit or with nobody here: the CQ ends at once.
                if run_limit || no_client {
                    return stop(
                        &mut inner,
                        if run_limit { "run_limit" } else { "no_client" },
                        true,
                    );
                }
                // The band, the activity or the period no longer fit: back to waiting.
                if waiting_reason.is_some() {
                    run.state = RunState::Waiting;
                    run.contact_id = None;
                    run.reason = waiting_reason;
                    inner.run_revision += 1;
                    disarm(contact, state);
                    cancel(contact, state);
                    return;
                }
                let Some((_, first, next, _)) = fresh.filter(|_| partner_period) else {
                    return;
                };
                let (Some((config, _)), Some(selection)) = (chosen.as_ref(), contest) else {
                    return;
                };
                let records = fresh_records(r, &run.identity, first, next);
                let st = strategy::station(state, config, strategy::Window::All);
                let log = contact.strategy.contest_log_latest(
                    state,
                    &selection,
                    st.my_locator.as_deref(),
                );
                let band = strategy::station_band(r);
                let best = crate::contest::evaluate(&selection, &records, &st, log.as_deref())
                    .into_iter()
                    .filter(|v| {
                        v.rank.is_some()
                            && v.kind == Some(strategy::Kind::Caller)
                            && eligible(run, &v.facts.from, band)
                    })
                    .collect::<Vec<_>>();
                run.last_decision = Some(
                    json!({"period_start_utc":records.first().map(|v| v["period_start_utc"].clone()),
                    "candidates":best.len(),"selected_call":best.first().map(|v| v.facts.from.clone())}),
                );
                inner.run_revision += 1;
                let run = inner.run.as_mut().expect("checked");
                let Some(caller) = best.into_iter().next() else {
                    return;
                };
                let row = json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":caller.facts.sequence});
                let (revision, _, _) = contact.facts();
                let held_tx = contact.status_facts().tx_hz;
                // Answer the caller: the armed CQ becomes this contact (no new arming).
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
                    // The operator's double-click won the race: the contact is theirs.
                    if contact.facts().1.is_some_and(|c| c.state != "calling") {
                        return manual(&mut inner);
                    }
                    disarm(contact, state);
                    return stop(&mut inner, "provider_error", false);
                };
                // A run stays on its frequency: the selection may have moved Tx to the caller.
                let revision = receipt["contact_revision"].as_u64().unwrap_or(revision);
                let called = contact.status_facts().rx_hz;
                if take_slot(
                    run,
                    contact,
                    state,
                    settled,
                    held_tx,
                    Some(called),
                    revision,
                )
                .is_none()
                {
                    return manual(&mut inner);
                }
                let (_, facts, _) = contact.facts();
                let run = inner.run.as_mut().expect("checked");
                run.progress = facts.as_ref().map(|c| (c.state.to_owned(), c.report_rcvd));
                run.contact_id = facts.map(|c| c.id);
                run.selected = Some(json!({"source_id":run.identity.0,"job_id":run.identity.1,
                    "generation":run.identity.2,"sequence":caller.facts.sequence,"call":caller.facts.from}));
                run.state = RunState::ContactActive;
                run.unanswered = 0;
                run.rested = None;
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
                        run.worked.push((call, strategy::station_band(r), run.mode));
                    }
                    // #42 a pounce ends on its success.
                    if run.pounce.is_some() {
                        return stop(&mut inner, "completed", false);
                    }
                    // WstxStrategy D4: a strategy goes on without a limit.
                    let (reached, next) = (
                        !is_strategy && run.completed >= run.config.max_contacts,
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
                        run.given_up.push(call);
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
                            .map_or(run.config.max_unanswered, |(_, s)| s.calls_per_station);
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
                            if chosen.is_none() {
                                return stop(&mut inner, "no_answer", true);
                            }
                            // WstxStrategy D6: on to the best other candidate of the next
                            // publication; it may come back (no skip, no stop).
                            run.rested = c
                                .dx_call
                                .map(|call| (call, strategy::station_band(r), run.mode));
                            run.state = RunState::Waiting;
                            run.contact_id = None;
                            run.progress = None;
                            run.unanswered = 0;
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
            RunState::Waiting => {
                // An operator's CQ or contact in progress is never taken over.
                if facts.as_ref().is_some_and(|c| c.active) {
                    if run.config.strategy {
                        return manual(&mut inner);
                    }
                    return stop(&mut inner, "contact_changed", false);
                }
                // At the run limit or with nobody connected nothing new is started. A contact in progress got
                // here by its normal end; a manual one waits in Manual first.
                if run_limit {
                    return stop(&mut inner, "run_limit", false);
                }
                if no_client {
                    return stop(&mut inner, "no_client", false);
                }
                if waiting_reason.is_some() {
                    return;
                }
                // #63 WstxContest::ContestRun: Run calls CQ from a free slot.
                if contest.is_some_and(|s| s.operation == crate::contest::Operation::Run) {
                    let (revision, _, _) = contact.facts();
                    let tx = contact.status_facts().tx_hz;
                    let Some(revision) =
                        take_slot(run, contact, state, settled, tx, None, revision)
                    else {
                        return manual(&mut inner);
                    };
                    return self.call_cq(&mut inner, contact, state, revision);
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
                        let st = strategy::station(state, &config, strategy::Window::All);
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
                    (None, None) => {
                        // A policy run: not again in this run, on any band.
                        let worked: Vec<String> = run.worked.iter().map(|w| w.0.clone()).collect();
                        candidates(&records, &run.config, &my, &worked)
                            .into_iter()
                            .map(|c| (c.call, c.sequence))
                            .collect()
                    }
                    (None, Some((config, s))) => {
                        let st = strategy::station(state, config, s.window);
                        let band = strategy::station_band(r);
                        // Callers, then candidates by value; one per call. Nobody the
                        // operator gave up, or completed on this band and mode in this run.
                        let mut seen: Vec<String> = Vec::new();
                        // WstxContest::ContestVerdict in a contest; the step never builds its log.
                        let verdicts = match &contest {
                            Some(c) => {
                                let log = contact.strategy.contest_log_latest(
                                    state,
                                    c,
                                    st.my_locator.as_deref(),
                                );
                                crate::contest::evaluate(c, &records, &st, log.as_deref())
                            }
                            None => strategy::evaluate(s, &records, &st),
                        };
                        let list: Vec<(String, u64, bool)> = verdicts
                            .into_iter()
                            .filter(|v| v.rank.is_some() && eligible(run, &v.facts.from, band))
                            .filter(|v| {
                                let first = !seen.contains(&v.facts.from);
                                seen.push(v.facts.from.clone());
                                first
                            })
                            .map(|v| {
                                let caller = v.kind == Some(strategy::Kind::Caller);
                                (v.facts.from, v.facts.sequence, caller)
                            })
                            .collect();
                        // D6: the candidate left after calls_per_station only when alone; a
                        // caller is always answered (D5).
                        let keep = |c: &(String, u64, bool)| {
                            c.2 || run
                                .rested
                                .as_ref()
                                .is_none_or(|r| r.0 != c.0 || r.1 != band || r.2 != run.mode)
                        };
                        let passed = list.iter().any(keep);
                        list.into_iter()
                            .filter(|c| !passed || keep(c))
                            .map(|c| (c.0, c.1))
                            .collect()
                    }
                };
                let chosen_row = list.first().cloned();
                run.last_decision = Some(json!({"period_start_utc":period,"candidates":list.len(),
                    "selected_call":chosen_row.as_ref().map(|c|c.0.clone())}));
                inner.run_revision += 1;
                let run = inner.run.as_mut().expect("checked");
                let Some((call, sequence)) = chosen_row else {
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
                run.rested = None;
            }
            RunState::Stopped => {}
        }
    }
    /// #63 WstxContest::ContestRun: the own CQ, through the same Enable Tx as any contact; the
    /// engine leaves its callers to this run (never Call 1st).
    fn call_cq(
        &self,
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        revision: u64,
    ) {
        let r = &state.recording;
        let run = inner.run.as_mut().expect("checked");
        self.before_enable();
        let body = contact_body(
            r,
            revision,
            "enable_tx",
            json!({"enabled":true,"safety_revision":run.safety_revision}),
        );
        if let Err((code, _)) = contact.operate_as(state, body, true, AUTOMATION) {
            if contact
                .facts()
                .1
                .is_some_and(|c| c.active && c.state != "calling")
            {
                return manual(inner);
            }
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
/// A call not completed in this run on this band and mode, nor given up by the operator for
/// the rest of the run (ManualIntervention).
fn eligible(run: &Run, call: &str, band: Option<&str>) -> bool {
    !run.worked
        .iter()
        .any(|w| w.0 == call && w.1 == band && w.2 == run.mode)
        && !run.given_up.iter().any(|w| w == call)
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
/// A policy run: the starting transport is still this grant's current, unexpired transport
/// (a revocation, safety edit, expiry or a newer proof of the grant ends it). A strategy run:
/// the grant itself is current (a revocation or safety edit ends it; a page load's new proof
/// or the transport's deadline does not, WstxStrategy::StrategyRun).
fn grant_current(
    state: &ProfileState,
    access: &authorization::Access,
    token: &str,
    is_strategy: bool,
    now: Instant,
) -> bool {
    state.authorization.lock().ok().is_some_and(|owner| {
        owner.as_ref().is_some_and(|s| {
            if is_strategy {
                return s.authority.current_grant(access).is_ok();
            }
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
