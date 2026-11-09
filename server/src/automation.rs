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
use strategy::Leave;
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
/// A call on the station band and mode it was worked on (a strategy run outlives both).
type OnBand = (String, Option<&'static str>, &'static str);
/// WstxStrategy::QuietTime: a left station on its band and mode, until its quiet time ends.
#[derive(Clone, Debug)]
struct Quiet {
    call: String,
    band: Option<&'static str>,
    mode: &'static str,
    until: Instant,
}
/// WstxStrategy::LeaveRule of the run's target: what it was selected as and what it did since.
#[derive(Clone, Debug, Default)]
struct Target {
    /// The text of the message it was selected on when it called my call: a repeat of it is no
    /// answer (#63 b9e7cb3b0).
    selected_on: Option<String>,
    /// It sent a message to my call in this contact (other than that repeat).
    answered: bool,
    /// The station band at its selection: a band change ends the contact at once.
    band: Option<&'static str>,
    /// Its WstxContest::ContestValueOrder value at the selection (a contest run).
    value: Option<crate::contest::ContestValue>,
    /// A contest stay (#97 LeaveRule contest: heard, decoded, nothing more valuable).
    staying: bool,
    /// The called station's frequency (FreeTxSlot keeps clear of it), from its last decode.
    hz: Option<u32>,
    /// #97 TxMoveRule: repetitions since the selection or the last move.
    move_count: u64,
    /// #97 LeaveRule contest: the Tx changes made.
    changes: u64,
    /// #97 LeaveRule until_logged: the period start (UTC ms) of his newest decoded message, and
    /// whether he is decoded in the latest publication of his parity (LeaveCountLabel).
    last_heard_ms: Option<i64>,
    decoded_last: bool,
    /// #97 BusyPause: the paused calls of the message due (at most N, the Tx watchdog limit).
    paused: u64,
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
    /// A policy run or pounce: periods without progress; a strategy run: LeaveRule's
    /// repetitions of its target.
    unanswered: u64,
    contact_id: Option<String>,
    progress: Option<(String, Option<i32>)>,
    selected: Option<Value>,
    worked: Vec<OnBand>,
    last_decision: Option<Value>,
    /// #39 strategy runs: the stations the operator cancelled or aborted (never again in
    /// this run).
    given_up: Vec<String>,
    /// WstxStrategy::LeaveRule: the last station left and why; QuietTime: who is quiet.
    left: Option<Value>,
    quiet: Vec<Quiet>,
    target: Target,
    /// When a client was last there (WstxStrategy::StrategyRun; a selection counts).
    client_seen: Instant,
    /// #42 Pounce: the call and the station band captured at start.
    pounce: Option<(String, String)>,
    /// No client or past the run limit: the stop at N is back, whatever else ends the contact.
    unattended: bool,
    /// WstxStrategy::StrategyWatchdog: the last slot check, and WD:n (None: no count, a stay).
    slot_check: Option<Value>,
    /// #97 WstxStrategy::LeaveCountLabel: the run snapshot's leave.
    leave_view: Option<Value>,
    /// WstxStrategy::FreeTxSlot: the last slot decision {hz, power_db, his_end}, and the station
    /// time from which periods count (Inner's).
    tx_slot: Option<Value>,
    slot_since_ms: i64,
    /// WstxStrategy::PskrUse: the run's own contact's target hearing us.
    hearing: Option<Value>,
    /// WstxStrategy::CqWhenNoTarget: consecutive fresh publications with nothing listed.
    empty_publications: u32,
    /// #97 WstxStrategy::BusyPause: the active strategy's busy_pause (a strategy run).
    busy_pause: bool,
}
impl Run {
    #[allow(
        clippy::too_many_arguments,
        reason = "The run's identity, grant, bounds and safety revision are separate authorities"
    )]
    fn new(
        id: String,
        mode: &'static str,
        config: Config,
        identity: (String, String, u64),
        (access, token): (authorization::Access, String),
        deadline: Instant,
        (safety_revision, halts): (u64, u64),
        last_decode: u64,
        now: Instant,
        pounce: Option<(String, String)>,
    ) -> Self {
        Self {
            id,
            state: RunState::Waiting,
            reason: None,
            mode,
            config,
            identity,
            access,
            token,
            deadline,
            safety_revision,
            halts,
            last_decode,
            completed: 0,
            unanswered: 0,
            contact_id: None,
            progress: None,
            selected: None,
            worked: Vec::new(),
            last_decision: None,
            given_up: Vec::new(),
            left: None,
            quiet: Vec::new(),
            target: Target::default(),
            client_seen: now,
            pounce,
            unattended: false,
            slot_check: None,
            leave_view: None,
            tx_slot: None,
            slot_since_ms: i64::MIN,
            hearing: None,
            empty_publications: 0,
            busy_pause: false,
        }
    }
    /// WstxStrategy::LeaveRule leaving: run.left, the left station's QuietTime on this band and
    /// mode, and waiting (the caller disarms and cancels).
    fn leave(
        &mut self,
        call: Option<String>,
        reason: &'static str,
        band: Option<&'static str>,
        quiet_minutes: u64,
        now: Instant,
    ) {
        self.left = Some(json!({"call":call,"reason":reason}));
        if let Some(call) = call {
            let mode = self.mode;
            self.quiet
                .retain(|q| !(q.call == call && q.band == band && q.mode == mode));
            self.quiet.push(Quiet {
                call,
                band,
                mode,
                until: now + Duration::from_secs(quiet_minutes.saturating_mul(60)),
            });
        }
        self.wait();
    }
    /// Back to waiting with no contact of its own.
    fn wait(&mut self) {
        self.state = RunState::Waiting;
        self.contact_id = None;
        self.progress = None;
        self.unanswered = 0;
        self.target = Target::default();
        self.leave_view = None;
        self.hearing = None;
        self.empty_publications = 0;
    }
}
/// #81 WstxStrategy::StartedQso finishing guard: a run's started QSO that a run end let finish, the
/// station band and mode at that end, the run's grant and the transmit owner's HALT count then
/// (memory only, in no snapshot). It never arms, selects, answers or moves a frequency.
struct Finishing {
    contact_id: String,
    band: Option<&'static str>,
    mode: &'static str,
    access: authorization::Access,
    halts: Option<u64>,
}
#[derive(Default)]
struct Inner {
    /// #81 the started QSO a run end let finish, until it has ended or a new run starts.
    finishing: Option<Finishing>,
    policy_revision: u64,
    run_revision: u64,
    configuration: Option<Config>,
    run: Option<Run>,
    receipts: VecDeque<(String, Value, Value)>,
    /// #39 why the last selection started no run (the strategy stays selected).
    strategy_refusal: Option<&'static str>,
    /// WstxStrategy::FreeTxSlot: the station band last seen and the station time from which the
    /// waterfall periods count (a retune keeps the live job), for every run.
    slot_band: Option<&'static str>,
    slot_since_ms: i64,
    /// #82 WstxStrategy::FreeTxSlots: the station's latest built value (null without a live
    /// receive) with its free_tx_slots.state cursor, None before the first build; and what that
    /// build judged, so that a new period, a QSO start or end, a new live job, mode or band
    /// builds again.
    free_tx_slots: Option<(u64, Value)>,
    free_tx_slots_key: Option<FreeKey>,
    /// The latest complete publication of a counted period's decodes the value was built on.
    free_tx_slots_decoded: Option<u64>,
}
/// What one open-slot build judges (#82 Built): the live job, its mode, a QSO, the judged parity,
/// the period in progress and the band change the periods count from.
type FreeKey = (
    (String, String, u64),
    &'static str,
    bool,
    wstx_rust::transmit::Parity,
    i64,
    i64,
);
/// The automation owner of one station (one per contact engine).
#[derive(Default)]
pub(crate) struct Owner {
    inner: Mutex<Inner>,
    /// #82 the free_tx_slots.state cursor: one more at each build of the station's value.
    free_tx_slots_builds: std::sync::atomic::AtomicU64,
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
    /// WstxStrategy::StrategyWatchdog: the strategy run's own contact, which sends past the
    /// Tx watchdog limit while the run is attended (#97: no WD for it; the leave count is the
    /// run's own label, LeaveCountLabel).
    pub(crate) fn repeat_exempt(&self) -> Option<String> {
        self.lock()
            .run
            .as_ref()
            .filter(|run| {
                run.config.strategy && run.state == RunState::ContactActive && !run.unattended
            })
            .and_then(|run| run.contact_id.clone())
    }
    /// #97 WstxContact::BusyPartner: the contact a run owns and how it treats a busy partner. A
    /// strategy or contest run whose strategy has busy_pause on takes the split move, and its sends
    /// pause while it is attended; a pounce, an MCP policy run and busy_pause off neither.
    pub(crate) fn busy_policy(&self) -> Option<crate::contact::Automated> {
        let inner = self.lock();
        let run = inner.run.as_ref()?;
        let contact_id = run.contact_id.clone()?;
        let split = run.config.strategy && run.pounce.is_none() && run.busy_pause;
        Some(crate::contact::Automated {
            contact_id,
            split,
            pause: split && !run.unattended,
        })
    }
    /// The strategy or contest run's own contact (attended or not): its target is the one
    /// the PSK Reporter feed subscribes to (WstxStrategy::HearingFeed).
    pub(crate) fn own_contact(&self) -> Option<String> {
        self.lock()
            .run
            .as_ref()
            .filter(|run| run.config.strategy && run.state == RunState::ContactActive)
            .and_then(|run| run.contact_id.clone())
    }
    /// AutomationSnapshot.
    pub(crate) fn snapshot(&self, r: &recording::Recording) -> Value {
        let now = self.now();
        let inner = self.lock();
        let run = inner.run.as_ref().map(|run| {
            let quiet: Vec<Value> = run
                .quiet
                .iter()
                .filter(|q| q.until > now)
                .map(|q| {
                    let remaining_s = (q.until - now).as_millis().div_ceil(1000);
                    json!({"call":q.call,"band":q.band,"mode":q.mode,"remaining_s":remaining_s})
                })
                .collect();
            json!({"id":run.id,"state":run.state.name(),"reason":run.reason,"mode":run.mode,
                "completed_contacts":run.completed,"unanswered_periods":run.unanswered,
                "contact_id":run.contact_id,"selected":run.selected,"last_decision":run.last_decision,
                "given_up":run.given_up,"left":run.left,"quiet":quiet,"hearing":run.hearing,
                "tx_slot":run.tx_slot,"slot_check":run.slot_check,"leave":run.leave_view,
                "pounce":run.pounce.as_ref().map(|(call, band)| json!({"call":call,"band":band}))})
        });
        let free_tx_slots = inner.free_tx_slots.as_ref().map(|(_, value)| value);
        json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"policy_revision":inner.policy_revision,
            "run_revision":inner.run_revision,"configuration":inner.configuration.as_ref().map(Config::json),"run":run,
            "strategy_refusal":inner.strategy_refusal,"free_tx_slots":free_tx_slots})
    }
    /// #82 free_tx_slots.state: the station's latest built value with its cursor and whether it
    /// is null, None before the first build (with or without a run) and while the peer holds
    /// build `seen` already.
    pub(crate) fn free_tx_slots_event(
        &self,
        r: &recording::Recording,
        seen: Option<u64>,
    ) -> Option<(u64, String, bool)> {
        let inner = self.lock();
        let (cursor, value) = inner.free_tx_slots.as_ref()?;
        (seen != Some(*cursor)).then(|| (*cursor, free_tx_slots_event(r, value), value.is_null()))
    }
    /// #82 WstxStrategy::FreeTxSlots Built (main.rs station timer, after the automation step):
    /// the station's open slots of my Rx parity, with or without a run, a QSO or Auto, built
    /// again at each period start, when the decodes of a counted period are published, and at
    /// once when a QSO starts or ends or the live job, its mode or the station band changes;
    /// null without a live receive.
    pub(crate) fn build_free_tx_slots(
        &self,
        contact: &contact_http::Station,
        state: &ProfileState,
    ) {
        let r = &state.recording;
        let mut inner = self.lock();
        let mode_name = r.operating_mode();
        let live = r
            .live_identity()
            .filter(|(_, _, _, m)| matches!(*m, "ft8" | "ft4") && *m == mode_name);
        let Some((source, job, generation, mode_name)) = live else {
            inner.free_tx_slots_key = None;
            if inner
                .free_tx_slots
                .as_ref()
                .is_some_and(|(_, v)| !v.is_null())
            {
                let cursor = self.next_free_tx_slots();
                inner.free_tx_slots = Some((cursor, Value::Null));
            }
            return;
        };
        let identity = (source, job, generation);
        let mode = contact_http::mode_of(mode_name);
        let now = utc_now(r);
        // D5: a QSO is Enable Tx on (my own CQ included) or a contact in progress; Tune alone
        // does not count.
        let armed = r.transmit.get().is_some_and(|t| {
            t.service.view().arm_state == wstx_rust::transmit::service::ArmState::Armed
        });
        let (_, facts, _) = contact.facts();
        let qso = armed
            || facts.as_ref().is_some_and(|c| {
                matches!(
                    c.state,
                    "replying" | "report" | "roger_report" | "rogers" | "signoff"
                )
            });
        let period = freeslot::period_ms(mode);
        let start = now.div_euclid(period) * period;
        // In a QSO the contact's Rx parity, the other of its Tx parity; only listening the parity
        // of the period in progress, the Rx parity for transmitting in the next period.
        let rx = if qso {
            match contact.status_facts().parity {
                wstx_rust::transmit::Parity::Even => wstx_rust::transmit::Parity::Odd,
                wstx_rust::transmit::Parity::Odd => wstx_rust::transmit::Parity::Even,
            }
        } else {
            wstx_rust::transmit::parity(mode, start)
        };
        let since = inner.slot_since_ms;
        // "Rebuild on decodes" (operator 2026-11-09): the build at a period start counts the
        // period just ended before its decodes exist; the publication of a counted period's
        // decodes builds again; #89 also the complete publication of the period in progress of
        // the judged parity, which makes it due.
        let published = published_start(r);
        let counted = freeslot::recent_starts(mode, rx, (now, published));
        let decoded = r
            .latest_publication()
            .filter(|p| p.3)
            .filter(|p| {
                p.4.as_deref()
                    .and_then(crate::contact::parse_utc)
                    .is_some_and(|s| s >= since && counted.contains(&s))
            })
            .map(|p| p.0);
        let fresh_decodes = decoded.is_some() && decoded != inner.free_tx_slots_decoded;
        if fresh_decodes {
            inner.free_tx_slots_decoded = decoded;
        }
        let key: FreeKey = (identity, mode_name, qso, rx, start, since);
        if !fresh_decodes && inner.free_tx_slots_key.as_ref() == Some(&key) {
            return;
        }
        let periods = r
            .waterfall
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .periods((&key.0.1, key.0.2), (now, published));
        let decodes = decodes_of(r, &key.0);
        let judged = freeslot::Judged::new(&periods, mode, rx, since, (now, published), &decodes);
        let open = freeslot::open_slots(mode, judged.decoded(), &|f| {
            judged.numbers(f).map(|n| n.rise)
        });
        let value = freeslot::value(
            now,
            mode,
            rx,
            qso,
            judged.count(),
            &freeslot::open_ranges(mode, &open),
        );
        let cursor = self.next_free_tx_slots();
        inner.free_tx_slots = Some((cursor, value));
        inner.free_tx_slots_key = Some(key);
    }
    fn next_free_tx_slots(&self) -> u64 {
        self.free_tx_slots_builds
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
            + 1
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
                // #81 a new run drops the finishing guard.
                inner.finishing = None;
                inner.run = Some(Run::new(
                    id,
                    mode,
                    config,
                    (source, job, generation),
                    (access, token),
                    deadline,
                    (current, transmit.service.halt_requests()),
                    last_decode,
                    self.now(),
                    pounce,
                ));
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
                // this run is disarmed through the same Enable Tx path (not a Halt), unless it
                // is a started QSO, which is finished (#81).
                let (armed, own_cq) = (run.state.armed(), run.state == RunState::CallingCq);
                let kept = Self::keep_started(&mut inner, &contact, state);
                Self::finish(&mut inner, "stopped");
                if armed && !kept {
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
    /// #81 WstxStrategy::StartedQso at a finishing end: true when the run's own contact is a
    /// started QSO (the contact engine's dialogue decides), which then stays armed and is finished
    /// as an ordinary contact under the finishing guard.
    fn keep_started(
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
    ) -> bool {
        let Some(run) = inner
            .run
            .as_ref()
            .filter(|run| run.state == RunState::ContactActive)
        else {
            return false;
        };
        let (_, facts, _) = contact.facts();
        let Some(id) = facts
            .filter(|c| c.started && Some(&c.id) == run.contact_id.as_ref())
            .map(|c| c.id)
        else {
            return false;
        };
        let r = &state.recording;
        inner.finishing = Some(Finishing {
            contact_id: id,
            band: strategy::station_band(r),
            mode: r.operating_mode(),
            access: run.access.clone(),
            halts: r.transmit.get().map(|t| t.service.halt_requests()),
        });
        true
    }
    /// #81 the finishing guard at each station step: the finished QSO's contact is disarmed and
    /// cancelled when the station band or mode differs from the run's end, the run's grant is no
    /// longer current or a HALT came from any source (StartedQso "Still at once": Enable Tx off and
    /// the contact cancelled); the guard ends with that contact.
    fn guard_finishing(inner: &mut Inner, contact: &contact_http::Station, state: &ProfileState) {
        let Some(g) = inner.finishing.as_ref() else {
            return;
        };
        let (_, facts, _) = contact.facts();
        if !facts.is_some_and(|c| c.id == g.contact_id && c.active) {
            inner.finishing = None;
            return;
        }
        let r = &state.recording;
        // The grant itself (revoked, or a safety edit), as for a strategy run.
        let current = grant_current(state, &g.access, "", true, Instant::now());
        let halted = r.transmit.get().map(|t| t.service.halt_requests()) != g.halts;
        if strategy::station_band(r) != g.band || r.operating_mode() != g.mode || !current || halted
        {
            inner.finishing = None;
            cancel(contact, state);
            disarm(contact, state);
        }
    }
    fn finish(inner: &mut Inner, reason: &'static str) {
        if let Some(run) = inner.run.as_mut() {
            run.state = RunState::Stopped;
            run.reason = Some(reason);
            inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        }
    }
    /// WstxStrategy::StrategyRun: a browser's selection change or Auto on (no strategy lock
    /// held). Any run ends: a contact it armed is disarmed and cancelled, except a started QSO,
    /// which is finished (#81, StartedQso); with `start` (Auto on) and a selection a run starts
    /// with the request's grant. True when a run started; a refused start names why in
    /// strategy_refusal.
    pub(crate) fn selected(
        &self,
        contact: &contact_http::Station,
        state: &ProfileState,
        access: Option<(authorization::Access, String)>,
        start: bool,
    ) -> bool {
        let r = &state.recording;
        // WstxStrategy::WatchdogFromOperator: a browser's selection or Auto on is the operator's
        // decision that ends a Tx watchdog stop (only the browser routes call this).
        if let Some(t) = r.transmit.get() {
            t.service.with(|c| c.operator_restart());
        }
        // WstxStrategy::AutoToggle: with Auto off a selection only marks.
        let active = start
            && contact
                .strategy
                .config(state)
                .and_then(|c| c.run_strategy())
                .is_some();
        let mut inner = self.lock();
        // Auto on ends any run (the operator wins over a pounce or MCP run); a selection with
        // Auto off ends only a strategy or contest run and leaves a pounce or MCP run and its
        // contact alone (WstxStrategy::AutoToggle, Pounce).
        let running = inner
            .run
            .as_ref()
            .filter(|run| run.state != RunState::Stopped && (start || run.config.strategy))
            .map(|run| (run.state.armed(), run.state == RunState::CallingCq));
        // #81 a started QSO is finished (WstxStrategy::StartedQso).
        let kept = running.is_some() && Self::keep_started(&mut inner, contact, state);
        if running.is_some() {
            Self::finish(&mut inner, "stopped");
        }
        // A selection change, None, a contest deselected: the run's contact that is no started
        // QSO is disarmed and cancelled at once (WstxStrategy::StrategyRun "Ends at once").
        if let Some((true, _)) = running
            && !kept
        {
            cancel(contact, state);
            disarm(contact, state);
        }
        inner.strategy_refusal = None;
        inner.run_revision = inner.run_revision.saturating_add(1).min(MAX_SAFE);
        if !active {
            return false;
        }
        let started = (|| {
            let (access, token) = access.ok_or("transmit_unavailable")?;
            let transmit = r.transmit.get().ok_or("transmit_unavailable")?;
            let current = transmit
                .service
                .with(|c| c.hardware().context().safety_revision)
                .ok_or("transmit_unavailable")?;
            let id = profile::new_uuid().map_err(|_| "storage_unavailable")?;
            let mode = if r.operating_mode() == "ft4" {
                "ft4"
            } else {
                "ft8"
            };
            Ok(Run::new(
                id,
                mode,
                strategy_config(mode),
                r.live_identity()
                    .map_or_else(Default::default, |(s, j, g, _)| (s, j, g)),
                (access, token),
                self.now() + STRATEGY_RUN_MAX,
                (current, transmit.service.halt_requests()),
                r.latest_publication().map_or(0, |p| p.0),
                self.now(),
                None,
            ))
        })();
        match started {
            Ok(run) => {
                // #81 a new run drops the finishing guard: it waits for the QSO as for the
                // operator's contact (ManualIntervention).
                inner.finishing = None;
                inner.configuration = Some(run.config.clone());
                inner.policy_revision = inner.policy_revision.saturating_add(1).min(MAX_SAFE);
                inner.run = Some(run);
                true
            }
            Err(reason) => {
                inner.strategy_refusal = Some(reason);
                false
            }
        }
    }
    /// A strategy or contest run that has not stopped (WstxStrategy::AutoToggle: every run end
    /// turns Auto off).
    pub(crate) fn strategy_running(&self) -> bool {
        self.lock()
            .run
            .as_ref()
            .is_some_and(|run| run.config.strategy && run.state != RunState::Stopped)
    }
    /// Why the last selection or Auto on started no run (the GET /strategy snapshot).
    pub(crate) fn strategy_refusal(&self) -> Option<&'static str> {
        self.lock().strategy_refusal
    }
    /// WstxStrategy::AutoToggle Auto off: the strategy or contest run ends at once, stopped; a
    /// contact it armed (its CQ too) is disarmed and cancelled, except a started QSO, which is
    /// finished as an ordinary contact (#81, StartedQso). A pounce or MCP run is not Auto's and is
    /// left alone.
    pub(crate) fn end_strategy_run(&self, contact: &contact_http::Station, state: &ProfileState) {
        let mut inner = self.lock();
        let Some(armed) = inner
            .run
            .as_ref()
            .filter(|run| run.config.strategy && run.state != RunState::Stopped)
            .map(|run| run.state.armed())
        else {
            return;
        };
        let kept = Self::keep_started(&mut inner, contact, state);
        Self::finish(&mut inner, "stopped");
        if armed && !kept {
            cancel(contact, state);
            disarm(contact, state);
        }
    }
    /// WstxStrategy::StrategyRun: re-identifies on the live identity and returns the reason
    /// the run cannot select now (a waiting reason); armed contact disarmed and cancelled.
    fn strategy_context(
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        contest: Option<&crate::contest::Selection>,
        bands: Option<&[String]>,
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
            // A new live job counts from its first period (WstxStrategy::FreeTxSlot: the
            // waterfall power starts empty with it). A mode change ends the contact at once,
            // with no quiet time (StrategyRun "Ends at once").
            run.last_decode = r.latest_publication().map_or(0, |p| p.0);
            if armed {
                run.wait();
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
        // #97 StrategyBands: off the strategy's bands (an unknown band is none of them).
        if let Some(bands) = bands
            && !strategy::station_band(r).is_some_and(|b| bands.iter().any(|x| x == b))
        {
            return Some("band");
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
        // WstxStrategy::FreeTxSlot: from a station band change on only the periods after it count.
        if let Some(b) = strategy::station_band(r) {
            if inner.slot_band.is_some_and(|seen| seen != b) {
                inner.slot_since_ms = utc_now(r);
            }
            inner.slot_band = Some(b);
        }
        // #81 a finishing QSO still ends at once on a band or mode change, a lost grant or a HALT.
        Self::guard_finishing(&mut inner, contact, state);
        let since = inner.slot_since_ms;
        let Some(run) = inner.run.as_mut() else {
            return;
        };
        run.slot_since_ms = since;
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
        // Halt (browser button, Alt+H or MCP) ends the run in every state; a strategy run's own
        // contact is disarmed and cancelled with it (StrategyRun "Ends at once").
        let halts = r.transmit.get().map(|t| t.service.halt_requests());
        if halts != Some(run.halts) {
            if is_strategy && armed && !own_cq {
                cancel(contact, state);
            }
            return stop(&mut inner, "halted", armed);
        }
        // A strategy run has no receive identity of its own: it re-identifies and waits.
        let saved_config = is_strategy
            .then(|| contact.strategy.config(state))
            .flatten();
        let contest = saved_config
            .as_ref()
            .and_then(strategy::Config::automatic_contest);
        let bands = saved_config
            .as_ref()
            .and_then(strategy::Config::active_strategy)
            .and_then(|s| s.bands.clone());
        let waiting_reason = if is_strategy {
            Self::strategy_context(
                &mut inner,
                contact,
                state,
                contest.as_ref(),
                bands.as_deref(),
            )
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
            // #81 a started QSO is finished.
            let kept = Self::keep_started(&mut inner, contact, state);
            return stop(&mut inner, "time_limit", armed && !kept);
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
        let fresh = publication
            .clone()
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
        let band = strategy::station_band(r);
        let run = inner.run.as_mut().expect("checked");
        if let Some((id, _, _, _)) = &fresh {
            run.last_decode = *id;
        }
        run.busy_pause = chosen.as_ref().is_some_and(|(_, s)| s.busy_pause);
        run.quiet.retain(|q| q.until > now);
        if r.clients.present() {
            run.client_seen = now;
        }
        let no_client = is_strategy && now >= run.client_seen + CLIENT_GONE;
        let run_limit = is_strategy && now >= run.deadline;
        run.unattended = no_client || run_limit;
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
            // WstxContest::ContestRun and WstxStrategy::CqWhenNoTarget: the own CQ until a
            // station is listed.
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
                    run.wait();
                    run.reason = waiting_reason;
                    inner.run_revision += 1;
                    disarm(contact, state);
                    cancel(contact, state);
                    return;
                }
                let Some((_, first, next, _)) = fresh.filter(|_| partner_period) else {
                    return;
                };
                let Some(chosen) = chosen.as_ref() else {
                    return;
                };
                let records = fresh_records(r, &run.identity, first, next);
                let list = picks(run, contact, state, chosen, contest.as_ref(), &records, now);
                run.last_decision = Some(
                    json!({"period_start_utc":records.first().map(|v| v["period_start_utc"].clone()),
                    "candidates":list.len(),"selected_call":list.first().map(|p| p.call.clone())}),
                );
                inner.run_revision += 1;
                let Some(pick) = list.into_iter().next() else {
                    return;
                };
                self.select(&mut inner, contact, state, pick, band, true);
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
                        run.worked.push((call, band, run.mode));
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
                    run.wait();
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
                    // Unattended the stop at N is back for this reason: the run names it.
                    let reason = match disarmed {
                        "tx_watchdog" if run_limit => "run_limit",
                        "tx_watchdog" if no_client => "no_client",
                        other => other,
                    };
                    return stop(&mut inner, reason, false);
                }
                let Some(chosen) = chosen.as_ref() else {
                    return self.policy_progress(
                        &mut inner,
                        contact,
                        state,
                        (c.state, c.report_rcvd),
                        partner_period,
                    );
                };
                // StrategyRun "Ends at once": a band change since the target's selection and the
                // end of a contest period disarm and cancel at the next step, with no quiet time;
                // at the period end a started QSO is finished, the run manual meanwhile (#81).
                if band == run.target.band && waiting_reason == Some("outside_period") && c.started
                {
                    Self::keep_started(&mut inner, contact, state);
                    return manual(&mut inner);
                }
                if band != run.target.band || waiting_reason == Some("outside_period") {
                    run.wait();
                    run.reason = waiting_reason;
                    inner.run_revision += 1;
                    drop(inner);
                    cancel(contact, state);
                    disarm(contact, state);
                    return;
                }
                let target = c.dx_call.clone();
                // WstxStrategy::PskrUse: whether the target hears us (unknown with Use off).
                let hearing = pskr::target_hearing(r, target.as_deref(), mode);
                let heard = hearing.hears_us();
                // #97 TxMoveRule: the PSK case (he reports: HearingFeed "He reports").
                let reports = heard || pskr::target_reports(r, target.as_deref(), mode);
                // LeaveRule: unattended no m, no stay and no caller exception.
                let hears = heard && !run.unattended;
                let mut hearing_json = hearing.json();
                hearing_json["reports"] = json!(reports);
                if run.hearing.as_ref() != Some(&hearing_json) {
                    run.hearing = Some(hearing_json);
                    inner.run_revision += 1;
                }
                let run = inner.run.as_mut().expect("checked");
                let leave = chosen.1.leave;
                // #97 BusyPause: paused calls in an attended run whose strategy has it on.
                let busy_pause = chosen.1.busy_pause && !run.unattended;
                let busy_now = contact.busy_facts().0;
                let tx_limit = u64::from(view.as_ref().map_or(6, |v| v.tx_calls));
                if let Some((_, first, next, _)) = fresh.filter(|_| partner_period) {
                    let records = fresh_records(r, &run.identity, first, next);
                    let seen = assess(
                        run,
                        contact,
                        state,
                        chosen,
                        contest.as_ref(),
                        &records,
                        (target.as_deref(), &my),
                        now,
                    );
                    if let Some(hz) = seen.hz {
                        run.target.hz = Some(hz);
                    }
                    if let Some(ms) = seen.heard_ms {
                        run.target.last_heard_ms =
                            Some(run.target.last_heard_ms.map_or(ms, |m| m.max(ms)));
                    }
                    run.target.decoded_last = seen.decoded;
                    inner.run_revision += 1;
                    let run = inner.run.as_mut().expect("checked");
                    let retry = chosen.1.retry_minutes;
                    // #97 LeaveRule until_logged: gone at the first publication of his parity
                    // whose period start is g minutes or more after his newest decode (also after
                    // his answer); attended only (unattended the stop at N is back).
                    let period_ms = records
                        .first()
                        .and_then(|v| v["period_start_utc"].as_str())
                        .and_then(contact::parse_utc);
                    if let (Leave::UntilLogged { gone_minutes }, Some(at), Some(last), false) =
                        (leave, period_ms, run.target.last_heard_ms, run.unattended)
                        && !seen.decoded
                        && at - last >= i64::try_from(gone_minutes * 60_000).unwrap_or(i64::MAX)
                    {
                        run.leave(target, "gone", band, retry, now);
                        inner.run_revision += 1;
                        drop(inner);
                        cancel(contact, state);
                        disarm(contact, state);
                        return;
                    }
                    if seen.answered {
                        // Progress, also a repeated message (the #63 fix): every count restarts.
                        run.target.answered = true;
                        run.target.staying = false;
                        run.target.move_count = 0;
                        run.target.changes = 0;
                        run.target.paused = 0;
                        run.unanswered = 0;
                    } else if seen.caller
                        && !run.target.answered
                        && !run.unattended
                        && chosen.1.callers_first
                    {
                        // The one exception before an exit criterion: a caller of my call is
                        // answered at once, selected from this publication.
                        run.leave(target, "caller", band, retry, now);
                        run.last_decode = run.last_decode.saturating_sub(1);
                        inner.run_revision += 1;
                        drop(inner);
                        cancel(contact, state);
                        disarm(contact, state);
                        return self.tick(contact, state, publication);
                    } else if busy_pause && busy_now && run.target.paused < tx_limit {
                        // #97 BusyPause: this repetition is a paused call (his publication comes
                        // before the stop point of the send it counts); it counts for nothing of
                        // the run: no leave count, no TxMoveRule count, no move.
                        run.target.paused += 1;
                    } else {
                        // #97 TxMoveRule: the PSK case and its k.
                        let (case, k) = if heard {
                            ("heard", chosen.1.tx_move_every.heard)
                        } else if reports {
                            ("not_heard", chosen.1.tx_move_every.not_heard)
                        } else {
                            ("no_reports", chosen.1.tx_move_every.no_reports)
                        };
                        let mut try_move = false;
                        let mut leaves = None;
                        match leave {
                            Leave::Calls { calls, heard: m } => {
                                run.unanswered += 1;
                                let leave_at = if hears { m } else { calls };
                                if run.unanswered >= leave_at {
                                    leaves = Some("repetitions");
                                }
                                run.target.move_count += 1;
                                try_move = k >= 1 && run.target.move_count >= k;
                            }
                            Leave::UntilLogged { .. } => {
                                run.unanswered += 1;
                                run.target.move_count += 1;
                                try_move = k >= 1 && run.target.move_count >= k;
                            }
                            Leave::Contest { tx_changes } => {
                                // Situation 1 while he hears us and nothing more valuable is
                                // listed: stay, with no count.
                                let stays = seen.decoded && hears && !seen.better;
                                run.target.staying = stays;
                                // unanswered_periods counts every repetition (the snapshot).
                                run.unanswered += 1;
                                if !stays {
                                    run.target.move_count += 1;
                                    let change_point = k == 0 || run.target.move_count >= k;
                                    // Unattended the stop at N ends it: Tx moves only.
                                    if run.unattended {
                                        try_move = k >= 1 && run.target.move_count >= k;
                                    } else if change_point {
                                        if run.target.changes >= tx_changes {
                                            leaves = Some("tx_changes");
                                        } else {
                                            run.target.changes += 1;
                                            run.target.move_count = 0;
                                            try_move = k >= 1;
                                        }
                                    }
                                }
                            }
                        }
                        if let Some(reason) = leaves {
                            run.leave(target, reason, band, retry, now);
                            inner.run_revision += 1;
                            drop(inner);
                            cancel(contact, state);
                            disarm(contact, state);
                            return;
                        }
                        let before = contact.status_facts().tx_hz;
                        // A target that has answered has proved the slot: no move. #97 BusyPause:
                        // no move while he is busy (the split move keeps Tx clear of him).
                        if try_move && !run.target.answered && !(chosen.1.busy_pause && busy_now) {
                            let (revision, _, _) = contact.facts();
                            let called = run.target.hz;
                            // A refused move or no candidate changes nothing: tried again at
                            // the next repetition (the count is kept).
                            let _ = take_slot(
                                run,
                                contact,
                                state,
                                before,
                                called,
                                revision,
                                SlotRule::Move,
                            );
                        }
                        let hz = contact.status_facts().tx_hz;
                        let moved = hz != before;
                        if moved && !matches!(leave, Leave::Contest { .. }) {
                            run.target.move_count = 0;
                        }
                        run.slot_check = Some(json!({"repetitions":run.unanswered,"case":case,
                            "hears_us":heard,"moved":moved,"hz":hz}));
                    }
                }
                // WstxStrategy::LeaveCountLabel: the run's leave {mode, remaining, busy, paused,
                // staying}; the Tx watchdog's WD:n is never used for it.
                let run = inner.run.as_mut().expect("checked");
                if !hears {
                    run.target.staying = false;
                }
                let utc = utc_now(r);
                let remaining: Option<u64> = match leave {
                    Leave::Calls { calls, heard: m } => {
                        let at = if hears { m } else { calls };
                        Some(at.saturating_sub(run.unanswered).max(1))
                    }
                    Leave::UntilLogged { gone_minutes } => run
                        .target
                        .last_heard_ms
                        .filter(|_| !run.target.decoded_last)
                        .map(|m| {
                            let gone = i64::try_from(gone_minutes * 60_000).unwrap_or(i64::MAX);
                            u64::try_from((m.saturating_add(gone) - utc).max(0))
                                .unwrap_or(0)
                                .div_ceil(60_000)
                        }),
                    Leave::Contest { tx_changes } => {
                        (!run.target.staying).then(|| tx_changes.saturating_sub(run.target.changes))
                    }
                };
                // #97 BusyPause: busy while the target is busy and the calls pause.
                let busy = busy_pause && busy_now;
                let view = json!({"mode":leave.mode(),"remaining":remaining,"busy":busy,
                    "paused":run.target.paused,"staying":run.target.staying});
                if run.leave_view.as_ref() != Some(&view) {
                    run.leave_view = Some(view);
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
                let Some((_, first, next, _)) = fresh else {
                    return;
                };
                let records = fresh_records(r, &run.identity, first, next);
                let period = records
                    .first()
                    .map(|v| v["period_start_utc"].clone())
                    .unwrap_or(Value::Null);
                let list: Vec<Pick> = match (&run.pounce, &chosen) {
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
                            .map(|f| Pick::plain(f.from, f.sequence))
                            .into_iter()
                            .collect()
                    }
                    (None, None) => {
                        // A policy run: not again in this run, on any band.
                        let worked: Vec<String> = run.worked.iter().map(|w| w.0.clone()).collect();
                        candidates(&records, &run.config, &my, &worked)
                            .into_iter()
                            .map(|c| Pick::plain(c.call, c.sequence))
                            .collect()
                    }
                    (None, Some(chosen)) => {
                        picks(run, contact, state, chosen, contest.as_ref(), &records, now)
                    }
                };
                run.last_decision = Some(json!({"period_start_utc":period,"candidates":list.len(),
                    "selected_call":list.first().map(|p| p.call.clone())}));
                inner.run_revision += 1;
                let run = inner.run.as_mut().expect("checked");
                let Some(pick) = list.into_iter().next() else {
                    // WstxStrategy::CqWhenNoTarget: after two fresh publications with nothing
                    // listed the run calls CQ (#97: a contest strategy too, D11).
                    if chosen.as_ref().is_some_and(|(_, s)| s.cq_when_idle) {
                        run.empty_publications += 1;
                        if run.empty_publications >= 2 {
                            return self.calling(&mut inner, contact, state);
                        }
                    }
                    return;
                };
                self.select(&mut inner, contact, state, pick, band, false);
            }
            RunState::Stopped => {}
        }
    }
    /// A policy run's or a pounce's contact: a partner period with no step of the contact counts
    /// as unanswered (WstxMcp::OperatingAutomation max_unanswered_periods).
    fn policy_progress(
        &self,
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        progress: (&'static str, Option<i32>),
        partner_period: bool,
    ) {
        if !partner_period {
            return;
        }
        let run = inner.run.as_mut().expect("checked");
        let progress = (progress.0.to_owned(), progress.1);
        if run.progress.as_ref() == Some(&progress) {
            run.unanswered += 1;
            if run.unanswered >= run.config.max_unanswered {
                if run.pounce.is_some() {
                    // #42 the pounce stays: wait again for the same call.
                    run.wait();
                    inner.run_revision += 1;
                    cancel(contact, state);
                    return;
                }
                Self::finish(inner, "no_answer");
                disarm(contact, state);
                return;
            }
        } else {
            run.progress = Some(progress);
            run.unanswered = 0;
        }
        inner.run_revision += 1;
    }
    /// The run's own CQ (WstxContest::ContestRun, WstxStrategy::CqWhenNoTarget): from a slot quiet
    /// in my Rx parity (FreeTxSlot, #66; no called station), then enable_tx with no partner.
    fn calling(&self, inner: &mut Inner, contact: &contact_http::Station, state: &ProfileState) {
        let run = inner.run.as_mut().expect("checked");
        let (revision, _, _) = contact.facts();
        let tx = contact.status_facts().tx_hz;
        let Some(revision) = take_slot(run, contact, state, tx, None, revision, SlotRule::Listen)
        else {
            return manual(inner);
        };
        self.call_cq(inner, contact, state, revision)
    }
    /// WstxStrategy::StrategyRun Waiting (and a station listed during the run's CQ): select the
    /// station, take its slot (FreeTxSlot) and arm, or from the CQ answer it with Enable Tx kept.
    fn select(
        &self,
        inner: &mut Inner,
        contact: &contact_http::Station,
        state: &ProfileState,
        pick: Pick,
        band: Option<&'static str>,
        from_cq: bool,
    ) {
        let r = &state.recording;
        let run = inner.run.as_mut().expect("checked");
        let row = json!({"source_id":run.identity.0,"job_id":run.identity.1,
            "generation":run.identity.2,"sequence":pick.sequence});
        let (revision, _, _) = contact.facts();
        let held_tx = contact.status_facts().tx_hz;
        // #97 CqTargetList: a strategy run's own select_row (never a pounce's).
        let own = run.config.strategy && run.pounce.is_none();
        contact
            .strategy_select
            .store(own, std::sync::atomic::Ordering::Release);
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
        contact
            .strategy_select
            .store(false, std::sync::atomic::Ordering::Release);
        let Ok((_, receipt)) = selected else {
            if from_cq {
                // The operator's double-click won the race: the contact is theirs.
                if contact.facts().1.is_some_and(|c| c.state != "calling") {
                    return manual(inner);
                }
                disarm(contact, state);
                return Self::finish(inner, "provider_error");
            }
            if run.config.strategy && contact.facts().1.is_some_and(|c| c.active) {
                return manual(inner);
            }
            return Self::finish(inner, "provider_error");
        };
        let prepared = contact.facts().1.map(|c| c.id);
        let mut revision = receipt["contact_revision"].as_u64().unwrap_or(revision);
        // #39 WstxStrategy::FreeTxSlot: the call goes out from the quietest slot, never from the
        // called station's frequency (the selection's Rx); Rx = Tx. With Hold Tx on (holdtx D16)
        // Tx stays and Rx stays on the station, unless the station is within 50 Hz of Tx.
        let called = contact.status_facts().rx_hz;
        if run.config.strategy || run.pounce.is_some() {
            let rule = if from_cq {
                SlotRule::KeepCq
            } else {
                SlotRule::Call
            };
            let taken = take_slot(run, contact, state, held_tx, Some(called), revision, rule);
            let Some(taken) = taken else {
                if from_cq {
                    return manual(inner);
                }
                // As for enable_tx: another contact is the operator's.
                if run.config.strategy
                    && contact
                        .facts()
                        .1
                        .is_some_and(|c| c.active && Some(&c.id) != prepared.as_ref())
                {
                    return manual(inner);
                }
                cancel(contact, state);
                return Self::finish(inner, "provider_error");
            };
            revision = taken;
        }
        if !from_cq {
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
                    return manual(inner);
                }
                // No unarmed selected contact is left behind.
                cancel(contact, state);
                return Self::finish(inner, refused(code));
            }
            if Self::raced_halt(inner, r) {
                return;
            }
        }
        // Progress is measured from the prepared contact: the next publication
        // without a partner step already counts as unanswered.
        let (_, facts, _) = contact.facts();
        let run = inner.run.as_mut().expect("checked");
        run.wait();
        run.progress = facts.as_ref().map(|c| (c.state.to_owned(), c.report_rcvd));
        run.contact_id = facts.map(|c| c.id);
        run.selected = Some(json!({"source_id":run.identity.0,"job_id":run.identity.1,
            "generation":run.identity.2,"sequence":pick.sequence,"call":pick.call}));
        run.state = RunState::ContactActive;
        run.target = Target {
            selected_on: pick.text.filter(|_| pick.caller),
            answered: false,
            band,
            value: pick.value,
            staying: false,
            hz: Some(called),
            move_count: 0,
            changes: 0,
            last_heard_ms: pick.period_ms,
            decoded_last: true,
            paused: 0,
        };
        inner.run_revision += 1;
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
/// One station a run may select: its call, record, whether it calls my call, its contest value
/// and the text of its message.
struct Pick {
    call: String,
    sequence: u64,
    caller: bool,
    value: Option<crate::contest::ContestValue>,
    text: Option<String>,
    /// #97 LeaveRule until_logged: the period start (UTC ms) of the message it was selected on.
    period_ms: Option<i64>,
}
impl Pick {
    fn plain(call: String, sequence: u64) -> Self {
        Self {
            call,
            sequence,
            caller: false,
            value: None,
            text: None,
            period_ms: None,
        }
    }
}
/// The period start (UTC ms) of the record with this sequence.
fn period_of(records: &[Value], sequence: u64) -> Option<i64> {
    records
        .iter()
        .find(|r| r["sequence"].as_u64() == Some(sequence))
        .and_then(|r| r["period_start_utc"].as_str())
        .and_then(contact::parse_utc)
}
/// The verdicts of `records` as the run's own evaluation reads them: WstxContest::ContestVerdict
/// in a contest (a dupe has no rank), WstxStrategy::Verdict otherwise. The step never builds the
/// contest log.
fn verdicts(
    contact: &contact_http::Station,
    state: &ProfileState,
    (config, s): &(strategy::Config, strategy::Strategy),
    contest: Option<&crate::contest::Selection>,
    records: &[Value],
) -> Vec<strategy::Verdict> {
    let st = strategy::station(state, config, s.window);
    match contest {
        Some(c) => {
            let log = contact
                .strategy
                .contest_log_latest(state, c, st.my_locator.as_deref());
            strategy::evaluate_contest(s, c, records, &st, log.as_deref())
        }
        None => strategy::evaluate(s, records, &st),
    }
}
/// WstxStrategy::StrategyRun Waiting: the verdicts with a rank, eligible (not completed in this
/// run on this band and mode, not given up, not in QuietTime), one per call, in value order.
fn picks(
    run: &Run,
    contact: &contact_http::Station,
    state: &ProfileState,
    chosen: &(strategy::Config, strategy::Strategy),
    contest: Option<&crate::contest::Selection>,
    records: &[Value],
    now: Instant,
) -> Vec<Pick> {
    let band = strategy::station_band(&state.recording);
    let mut seen: Vec<String> = Vec::new();
    verdicts(contact, state, chosen, contest, records)
        .into_iter()
        .filter(|v| v.rank.is_some() && eligible(run, &v.facts.from, band, now))
        .filter(|v| {
            let first = !seen.contains(&v.facts.from);
            seen.push(v.facts.from.clone());
            first
        })
        .map(|v| Pick {
            text: text_of(records, v.facts.sequence),
            period_ms: period_of(records, v.facts.sequence),
            caller: v.kind == Some(strategy::Kind::Caller),
            value: v.contest,
            sequence: v.facts.sequence,
            call: v.facts.from,
        })
        .collect()
}
/// What one publication of the target's parity says of it (WstxStrategy::LeaveRule).
struct Seen {
    /// The target is decoded (situation 1 without progress; else situation 2).
    decoded: bool,
    /// #97 the period start (UTC ms) of the target's decode in this publication.
    heard_ms: Option<i64>,
    /// Progress: a message of the target to my call, also a repeated one, except the message a
    /// caller was selected on.
    answered: bool,
    /// An eligible caller of my call other than the target (with a rank: never a contest dupe).
    caller: bool,
    /// A contest: a callable eligible station other than the target strictly before it by
    /// WstxContest::ContestValueOrder.
    better: bool,
    /// The target's frequency in this publication.
    hz: Option<u32>,
}
#[allow(
    clippy::too_many_arguments,
    reason = "The run, the engine, the strategy, the records and the calls are separate inputs"
)]
fn assess(
    run: &Run,
    contact: &contact_http::Station,
    state: &ProfileState,
    chosen: &(strategy::Config, strategy::Strategy),
    contest: Option<&crate::contest::Selection>,
    records: &[Value],
    (target, my): (Option<&str>, &str),
    now: Instant,
) -> Seen {
    let band = strategy::station_band(&state.recording);
    let list = verdicts(contact, state, chosen, contest, records);
    let is_target = |v: &strategy::Verdict| target.is_some_and(|t| v.facts.from == t);
    let decoded = list.iter().find(|v| is_target(v));
    let answered = list
        .iter()
        .filter(|v| is_target(v) && v.facts.to_call.as_deref() == Some(my))
        .any(|v| {
            run.target.selected_on.is_none()
                || text_of(records, v.facts.sequence) != run.target.selected_on
        });
    let caller = list.iter().any(|v| {
        v.rank.is_some()
            && v.kind == Some(strategy::Kind::Caller)
            && !is_target(v)
            && eligible(run, &v.facts.from, band, now)
    });
    // The target in this publication: its own verdict when it has a rank, else its decode with
    // the value it was selected on.
    let reference = list
        .iter()
        .find(|v| is_target(v) && v.rank.is_some())
        .cloned()
        .or_else(|| {
            decoded.cloned().map(|mut v| {
                v.kind = Some(strategy::Kind::Candidate);
                v.contest = run.target.value;
                v
            })
        });
    // #97 LeaveRule contest: a more valuable callable station strictly before the target by the
    // strategy's order (a contest strategy: ContestValueOrder; else the ranks of ValueOrder).
    let better = reference.as_ref().is_some_and(|t| {
        list.iter().any(|v| {
            v.rank.is_some()
                && !is_target(v)
                && eligible(run, &v.facts.from, band, now)
                && match contest {
                    Some(_) => {
                        crate::contest::order_by(v, t, chosen.1.callers_first)
                            == std::cmp::Ordering::Less
                    }
                    None => t.rank.is_none_or(|r| v.rank.is_some_and(|x| x < r)),
                }
        })
    });
    Seen {
        decoded: decoded.is_some(),
        heard_ms: decoded.and_then(|v| period_of(records, v.facts.sequence)),
        answered,
        caller,
        better,
        hz: decoded
            .and_then(|v| v.facts.hz)
            .map(|hz| hz.round().max(0.0) as u32),
    }
}
/// The text of the record with this sequence.
fn text_of(records: &[Value], sequence: u64) -> Option<String> {
    records
        .iter()
        .find(|r| r["sequence"].as_u64() == Some(sequence))
        .and_then(|r| r["text"].as_str())
        .map(str::to_owned)
}
/// The station clock (the transmit owner's UTC), else the wall clock.
fn utc_now(r: &recording::Recording) -> i64 {
    r.transmit.get().map_or_else(contact_http::wall_ms, |t| {
        t.service.with(|h| h.hardware().now_utc_ms())
    })
}
/// The period start of the latest complete receive publication (WstxStrategy::FreeTxSlot Due,
/// #89): a partial publication names none.
fn published_start(r: &recording::Recording) -> Option<i64> {
    r.latest_publication()
        .filter(|p| p.3)
        .and_then(|p| p.4.as_deref().and_then(crate::contact::parse_utc))
}
/// The decodes of the run's live job as (period start, audio frequency): WstxStrategy::FreeTxSlot
/// "decoded stations" (#66), of which the counted periods' count.
fn decodes_of(r: &recording::Recording, identity: &(String, String, u64)) -> Vec<(i64, f64)> {
    r.live_records_after(Some(identity), 0)
        .filter(|(current, _, _)| current == identity)
        .map(|(_, _, records)| {
            records
                .iter()
                .filter_map(|v| {
                    let start = crate::contact::parse_utc(v["period_start_utc"].as_str()?)?;
                    Some((start, v["frequency_hz"].as_f64()?))
                })
                .collect()
        })
        .unwrap_or_default()
}
/// How a run takes its Tx slot (WstxStrategy::FreeTxSlot).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SlotRule {
    /// Selecting a station to call: the quietest slot of my Rx parity, free at his end where
    /// known; with Hold Tx on the held Tx, moved only when within 50 Hz of the station.
    Call,
    /// #97 a move of TxMoveRule: another quiet slot of my Rx parity, never overlapping the current
    /// Tx nor within 50 Hz of his frequencies (no fallback; none left: Tx stays); with Hold Tx on
    /// Tx alone moves, clear of my Rx as well.
    Move,
    /// Its own CQ: the quietest slot of my Rx parity, the other of the CQ's (#66), no his end;
    /// with Hold Tx on the held Tx.
    Listen,
    /// Answering from its own CQ (CqWhenNoTarget, WstxContest::ContestRun): the CQ's slot stays
    /// unless it is within 50 Hz of the called station, then the nearest candidate away.
    KeepCq,
}
/// #39 WstxStrategy::FreeTxSlot: decide the slot by `rule`, name it in the run's status and move
/// there. Hold Tx off: Rx and Tx both, when either is not there. Hold Tx on (#39 holdtx D16): Tx
/// alone, Rx stays on the station. The next contact revision, or None when the engine refused the
/// command.
fn take_slot(
    run: &mut Run,
    contact: &contact_http::Station,
    state: &ProfileState,
    current: u32,
    called: Option<u32>,
    revision: u64,
    rule: SlotRule,
) -> Option<u64> {
    let listening = rule == SlotRule::Listen;
    let r = &state.recording;
    let mode = contact_http::mode_of(run.mode);
    let facts = contact.status_facts();
    let tx_parity = facts.parity;
    let rx_parity = match tx_parity {
        wstx_rust::transmit::Parity::Even => wstx_rust::transmit::Parity::Odd,
        wstx_rust::transmit::Parity::Odd => wstx_rust::transmit::Parity::Even,
    };
    let now = utc_now(r);
    // #89 Due: my newest Rx period counts once its complete publication is there, also while it
    // is in progress (its rows so far).
    let published = published_start(r);
    let periods = r
        .waterfall
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .periods((&run.identity.1, run.identity.2), (now, published));
    // #66: every decision judges my Rx periods only (a CQ's the other of its Tx parity), the
    // recent ones, by each slot's largest rise above the passband floor clamped at 0 (at or under
    // the floor a slot is free), clear of the stations
    // decoded in them.
    let decodes = decodes_of(r, &run.identity);
    let judged = freeslot::Judged::new(
        &periods,
        mode,
        rx_parity,
        run.slot_since_ms,
        (now, published),
        &decodes,
    );
    let decoded = judged.decoded();
    let power = |f: u32| judged.numbers(f).map(|n| n.rise);
    let hold = facts.hold_tx;
    // His end: the frequencies the target decodes from my Tx parity, only while the feed
    // follows this very target (a pounce, a plain run and a CQ have none).
    let target = facts.dx_call.as_deref().filter(|_| !listening);
    let his = target
        .filter(|t| {
            r.pskr
                .get()
                .and_then(|f| f.target())
                .is_some_and(|f| f == *t)
        })
        .and_then(|_| pskr::target_offsets(r, mode, tx_parity));
    // With Hold Tx on Rx stays on the station: Tx keeps 50 Hz from it as from the called station
    // ("never to the Rx frequency").
    let avoid: Vec<u32> = called
        .into_iter()
        .chain(hold.then_some(facts.rx_hz))
        .collect();
    let slot = match (rule, hold) {
        // Hold Tx on, a CQ: on the held Tx, no decision (round 1 Q3); its value is shown.
        (SlotRule::Listen, true) => freeslot::Slot {
            hz: current,
            power_db: power(current).map(freeslot::compared),
            his_end: freeslot::HisEnd::Unknown,
        },
        // Hold Tx on, a selection: Tx stays unless within 50 Hz of the station (Q1, Q2, D7).
        (SlotRule::Call | SlotRule::KeepCq, true) => {
            freeslot::held(mode, current, &avoid, decoded, his.as_deref(), &power)
        }
        (SlotRule::Move, _) => {
            match freeslot::moved(mode, current, &avoid, decoded, his.as_deref(), &power) {
                Some(slot) => slot,
                // No candidate left: Tx stays, tried again at the next repetition.
                None => return Some(revision),
            }
        }
        (SlotRule::KeepCq, false) => {
            // The rule without power keeps the current slot or moves it nearest away from him
            // (clear of the decoded stations while one is free, #66 D4); its value is still shown.
            let mut slot =
                freeslot::quietest(mode, current, called, decoded, his.as_deref(), &|_| None);
            slot.power_db = power(slot.hz).map(freeslot::compared);
            slot
        }
        _ => freeslot::quietest_clear(mode, current, &avoid, decoded, his.as_deref(), &power),
    };
    // Auto's own ranking (#82 D18: not on screen; the station's open slots are built apart).
    run.tx_slot = Some(slot.json());
    let unchanged = if hold {
        facts.tx_hz == slot.hz
    } else {
        facts.tx_hz == slot.hz && facts.rx_hz == slot.hz
    };
    if unchanged {
        return Some(revision);
    }
    contact.automation.before_slot_move();
    let frequencies = if hold {
        json!({"rx_hz":null,"tx_hz":slot.hz})
    } else {
        json!({"rx_hz":slot.hz,"tx_hz":slot.hz})
    };
    let body = contact_body(r, revision, "set_frequency", frequencies);
    let (_, receipt) = contact.operate_as(state, body, true, AUTOMATION).ok()?;
    Some(receipt["contact_revision"].as_u64().unwrap_or(revision))
}
/// A call not completed in this run on this band and mode, not given up by the operator for the
/// rest of the run (ManualIntervention) and not in its QuietTime on this band and mode.
fn eligible(run: &Run, call: &str, band: Option<&str>, now: Instant) -> bool {
    !run.worked
        .iter()
        .any(|w| w.0 == call && w.1 == band && w.2 == run.mode)
        && !run.given_up.iter().any(|w| w == call)
        && !run
            .quiet
            .iter()
            .any(|q| q.call == call && q.band == band && q.mode == run.mode && q.until > now)
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
/// #82 free_tx_slots.state: carries its state, the station's latest built value (at most 1024
/// bytes).
pub(crate) fn free_tx_slots_event(r: &recording::Recording, value: &Value) -> String {
    json!({"v":1,"type":"free_tx_slots.state","data":{"profile_id":r.profile,"boot_id":r.boot,
        "free_tx_slots":value}})
    .to_string()
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
