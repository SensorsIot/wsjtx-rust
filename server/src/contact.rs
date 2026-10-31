#![forbid(unsafe_code)]
//! WstxContact (#10): the server-owned standard FT8 contact engine. It owns contact
//! identity, the AutoSequence state, the next-message choice, completion and the log
//! review offer; it never keys PTT, opens audio or touches a radio. Every transmission
//! is a WstxTransmit::TransmitRequest submitted in-process to the #9 slice B transmit
//! owner (`transmit::service::Core`), whose arming, halt, watchdogs and outcomes it
//! consumes. The browser renders the snapshot and sends commands (contact_http).
use std::collections::{HashSet, VecDeque};
use wstx_rust::decoder::Mode;
use wstx_rust::transmit::service::{
    ArmState, Capability, Core, DisarmCause, Hardware, OutcomeKind, Request, TransmitRefusal,
};
use wstx_rust::transmit::{self, Family, Parity};

/// WstxContact::ReportRange.
pub const REPORT_MIN: i32 = -50;
pub const REPORT_MAX: i32 = 49;
pub const REPORT_DEFAULT: i32 = -15;
/// WstxContact::FrequencyControls (FT8; FT4-NOTE 2916).
pub const RX_MAX_HZ: u32 = 3000;
pub const TX_MIN_HZ: u32 = 200;
pub fn tx_max_hz(mode: Mode) -> u32 {
    match mode {
        Mode::Ft8 => 2950,
        Mode::Ft4 => 2916,
    }
}
/// The 50 Hz rule of WSJT-X auto_sequence(decodedtext, 25, 50) (stopTolerance).
pub const STOP_TOLERANCE_HZ: f64 = 50.0;
/// A request is planned for the first period whose start window is still open this
/// long from now, so it never turns stale between admission and keying.
pub const LEAD_MS: i64 = 1000;
const COUNTED_KEYS: usize = 4096;
/// Unsaved log reviews retained per station session.
pub const REVIEWS_MAX: usize = 8;

pub fn period_ms(mode: Mode) -> i64 {
    match mode {
        Mode::Ft8 => 15_000,
        Mode::Ft4 => 7_500,
    }
}
/// asprintf("%+2.2d"): sign plus at least two digits (-05, +03, +00, -15, +49).
pub fn render_report(db: i32) -> String {
    format!("{db:+03}")
}
/// Round half away from zero, clamped to ReportRange.
pub fn report_from_snr(snr_db: f64) -> i32 {
    (snr_db.round() as i32).clamp(REPORT_MIN, REPORT_MAX)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Slot {
    Tx1,
    Tx2,
    Tx3,
    Tx4,
    Tx5,
    Tx6,
}
impl Slot {
    pub const ALL: [Slot; 6] = [
        Slot::Tx1,
        Slot::Tx2,
        Slot::Tx3,
        Slot::Tx4,
        Slot::Tx5,
        Slot::Tx6,
    ];
    pub fn index(self) -> usize {
        self as usize
    }
    pub fn name(self) -> &'static str {
        ["tx1", "tx2", "tx3", "tx4", "tx5", "tx6"][self.index()]
    }
    pub fn parse(text: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.name() == text)
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tx4 {
    Rrr,
    Rr73,
}
impl Tx4 {
    pub fn name(self) -> &'static str {
        match self {
            Tx4::Rrr => "rrr",
            Tx4::Rr73 => "rr73",
        }
    }
}
/// WstxContact::SequenceStateName.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Idle,
    Calling,
    Replying,
    Report,
    RogerReport,
    Rogers,
    Signoff,
    Completed,
    Cancelled,
}
impl State {
    pub fn name(self) -> &'static str {
        match self {
            State::Idle => "idle",
            State::Calling => "calling",
            State::Replying => "replying",
            State::Report => "report",
            State::RogerReport => "roger_report",
            State::Rogers => "rogers",
            State::Signoff => "signoff",
            State::Completed => "completed",
            State::Cancelled => "cancelled",
        }
    }
    /// Next message per state (AutoSequence doc).
    pub fn slot(self) -> Slot {
        match self {
            State::Replying => Slot::Tx1,
            State::Report => Slot::Tx2,
            State::RogerReport => Slot::Tx3,
            State::Rogers => Slot::Tx4,
            State::Signoff => Slot::Tx5,
            _ => Slot::Tx6,
        }
    }
    /// A contact with a partner in progress (replying..signoff): ChangeContact needed.
    pub fn active(self) -> bool {
        matches!(
            self,
            State::Replying | State::Report | State::RogerReport | State::Rogers | State::Signoff
        )
    }
    /// States in which the next message is transmitted while Enable Tx is on.
    fn transmits(self) -> bool {
        self == State::Calling || self.active()
    }
    fn of_slot(slot: Slot) -> State {
        match slot {
            Slot::Tx1 => State::Replying,
            Slot::Tx2 => State::Report,
            Slot::Tx3 => State::RogerReport,
            Slot::Tx4 => State::Rogers,
            Slot::Tx5 => State::Signoff,
            Slot::Tx6 => State::Calling,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    DecodedRow,
    ManualEntry,
    OwnCq,
}
impl Origin {
    pub fn name(self) -> &'static str {
        match self {
            Origin::DecodedRow => "decoded_row",
            Origin::ManualEntry => "manual_entry",
            Origin::OwnCq => "own_cq",
        }
    }
}

// ---------------------------------------------------------------- decoded rows
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct RowKey {
    pub source_id: String,
    pub job_id: String,
    pub generation: u64,
    pub sequence: u64,
}
#[derive(Clone, Debug, PartialEq)]
pub enum Call {
    /// A concrete call sign.
    Sign(String),
    /// CQ, DE, QRZ and directed CQ tokens.
    Token(String),
    /// An unresolved hash (`<...>`).
    Hash,
}
#[derive(Clone, Debug, PartialEq)]
pub enum Exchange {
    Grid(String),
    Report(i32),
    Rrr,
    Rr73,
    SeventyThree,
    Blank,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Standard {
    pub to: Call,
    pub from: Call,
    pub ack: bool,
    pub exchange: Exchange,
}
/// A validated live result row (WstxOfflineDecode::StandardFields when standard).
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub key: RowKey,
    pub mode: Mode,
    pub period_start_ms: Option<i64>,
    pub frequency_hz: f64,
    pub snr_db: Option<f64>,
    pub text: String,
    pub standard: Option<Standard>,
}
/// WstxContact::ReceivedKind for a partner message addressed to my call.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Received {
    Grid,
    SignalReport,
    RogerReport,
    Rogers,
    SeventyThree,
    Other,
}
pub fn classify(standard: &Standard) -> Received {
    match standard.exchange {
        Exchange::Grid(_) => Received::Grid,
        Exchange::Report(_) if standard.ack => Received::RogerReport,
        Exchange::Report(_) => Received::SignalReport,
        Exchange::Rrr | Exchange::Rr73 => Received::Rogers,
        Exchange::SeventyThree => Received::SeventyThree,
        Exchange::Blank => Received::Other,
    }
}
/// WstxContact::AutoSequence transitions on a counted partner message (receivedFromPartner).
pub fn transition(state: State, received: Received) -> Option<State> {
    use Received as R;
    use State as S;
    Some(match (state, received) {
        (S::Replying, R::Grid) => S::Report,
        (S::Replying | S::Report, R::SignalReport) => S::RogerReport,
        (S::Replying | S::Report | S::RogerReport, R::RogerReport) => S::Rogers,
        (S::RogerReport, R::Rogers) => S::Signoff,
        (S::Signoff, R::Rogers) => S::Signoff,
        (S::Rogers, R::SignalReport) => S::RogerReport,
        (S::Rogers, R::SeventyThree) => S::Completed,
        _ => return None,
    })
}
/// WstxContact::FirstSlotOnSelection.
pub fn first_slot(to_is_my_call: bool, received: Received, tx1_skipped: bool) -> Slot {
    if !to_is_my_call {
        return if tx1_skipped { Slot::Tx2 } else { Slot::Tx1 };
    }
    match received {
        Received::Grid | Received::Other => Slot::Tx2,
        Received::SignalReport => Slot::Tx3,
        Received::RogerReport => Slot::Tx4,
        Received::Rogers | Received::SeventyThree => Slot::Tx5,
    }
}

// ---------------------------------------------------------------- messages
/// The packed, normalized text when `text` is a standard (i3=1/2) message that packs
/// unaltered.
pub fn standard_text(text: &str) -> Option<String> {
    let packed = transmit::pack(text).ok()?;
    matches!(packed.family, Family::Standard | Family::Portable).then_some(packed.text)
}
/// Maidenhead 4 or 6 characters (AA00..RR99[AA..XX]).
pub fn valid_grid(grid: &str) -> bool {
    let b = grid.as_bytes();
    (b.len() == 4 || b.len() == 6)
        && (b'A'..=b'R').contains(&b[0])
        && (b'A'..=b'R').contains(&b[1])
        && b[2].is_ascii_digit()
        && b[3].is_ascii_digit()
        && (b.len() == 4 || ((b'A'..=b'X').contains(&b[4]) && (b'A'..=b'X').contains(&b[5])))
}
/// WstxContact::StandardMessageSet; None when a generated text would not pack unaltered.
pub fn generate(
    my_call: &str,
    grid4: &str,
    dx: Option<&str>,
    report: i32,
    tx4: Tx4,
) -> Option<[Option<String>; 6]> {
    let r = render_report(report);
    let mut set: [Option<String>; 6] = Default::default();
    set[5] = Some(format!("CQ {my_call} {grid4}"));
    if let Some(dx) = dx {
        set[0] = Some(format!("{dx} {my_call} {grid4}"));
        set[1] = Some(format!("{dx} {my_call} {r}"));
        set[2] = Some(format!("{dx} {my_call} R{r}"));
        set[3] = Some(format!(
            "{dx} {my_call} {}",
            if tx4 == Tx4::Rr73 { "RR73" } else { "RRR" }
        ));
        set[4] = Some(format!("{dx} {my_call} 73"));
    }
    for text in set.iter().flatten() {
        if standard_text(text).as_deref() != Some(text.as_str()) {
            return None;
        }
    }
    Some(set)
}

// ---------------------------------------------------------------- state
#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub auto_seq: bool,
    pub tx1_skip: bool,
    pub rx_hz: u32,
    pub tx_hz: u32,
    pub hold_tx: bool,
    pub parity: Parity,
    pub report: i32,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            auto_seq: true,
            tx1_skip: false,
            rx_hz: 1500,
            tx_hz: 1500,
            hold_tx: false,
            // WSJT-X m_txFirst default false: transmit in the second (odd) period.
            parity: Parity::Odd,
            report: REPORT_DEFAULT,
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct Contact {
    pub id: String,
    pub origin: Origin,
    pub mode: Mode,
    pub dx_call: Option<String>,
    pub dx_grid: Option<String>,
    /// The report value of Tx2/Tx3.
    pub report: i32,
    pub report_rcvd: Option<i32>,
    /// RST_SENT: the report of the last transmitted Tx2/Tx3.
    pub report_sent: Option<i32>,
    pub state: State,
    pub next: Slot,
    pub tx4: Tx4,
    pub messages: [Option<String>; 6],
    pub started_tx1_skipped: bool,
    pub prepared_utc_ms: i64,
    pub first_tx_period: Option<i64>,
    pub first_tx2_period: Option<i64>,
    pub first_tx3_period: Option<i64>,
    pub last_counted_end: Option<i64>,
    pub offered_for_log: bool,
}
impl Contact {
    /// WstxContact::LogRecord start time (MW set_dateTimeQSO).
    pub fn start_utc_ms(&self) -> Option<i64> {
        self.first_tx2_period
            .or_else(|| self.first_tx3_period.map(|p| p - period_ms(self.mode)))
            .or(self.first_tx_period)
    }
}
/// The log review offered for a contact (WstxContact::OfferLogReview).
#[derive(Clone, Debug, PartialEq)]
pub struct Review {
    pub contact: Contact,
    pub automatic: bool,
}
/// Station facts the engine reads at each command and step.
#[derive(Clone, Debug, Default)]
pub struct Ctx {
    pub call: Option<String>,
    pub locator: Option<String>,
    pub now_utc_ms: i64,
    /// A current CL-022 grant of the requesting browser (transmit authority).
    pub granted: bool,
    pub mode: Option<Mode>,
}
impl Ctx {
    fn grid4(&self) -> Option<String> {
        self.locator
            .as_deref()
            .filter(|l| l.len() >= 4)
            .map(|l| l[..4].to_ascii_uppercase())
    }
    fn mode(&self) -> Mode {
        self.mode.unwrap_or(Mode::Ft8)
    }
}
#[derive(Clone, Debug, PartialEq)]
pub enum Command {
    SelectRow {
        row: Row,
        replace: bool,
    },
    EnterDx {
        call: String,
        grid: Option<String>,
        replace: bool,
    },
    Cancel,
    ChooseNext(Slot),
    EditMessage(Slot, String),
    SetReport(i32),
    SetTx1Skip(bool),
    SetTx4(Tx4),
    SetFrequency {
        rx: Option<u32>,
        tx: Option<u32>,
    },
    SetHoldTx(bool),
    SetParity(Parity),
    SetAutoSeq(bool),
    SetWatchdogs {
        tx_minutes: u32,
        tune_seconds: u32,
    },
    /// Enable Tx on/off; Some(revision) is the CL-022 safety revision the operator saw.
    EnableTx(bool, Option<u64>),
    Tune(bool),
    Redecode,
    OpenLog,
    DiscardReview(String),
}
#[derive(Clone, Debug)]
struct Submitted {
    slot: Slot,
    text: String,
    period: i64,
    tx_hz: u32,
    contact_id: String,
    report: i32,
}

/// The contact engine of one station profile.
pub struct Engine {
    pub revision: u64,
    pub settings: Settings,
    pub contact: Option<Contact>,
    /// Offered, not yet saved or discarded reviews, oldest first (bounded).
    reviews: VecDeque<Review>,
    /// The last request target refused without a disarm, never resubmitted as is.
    refused_target: Option<(i64, String, u32)>,
    /// A completed, unsaved contact that found the review queue full; until it is
    /// queued, saved or discarded no other contact or CQ may replace it.
    unqueued: Option<String>,
    /// The last visible refusal or failure of a transmit outcome (snake_case).
    pub transmit_problem: Option<String>,
    sequence: u64,
    pending: Option<(u64, Submitted)>,
    requests: VecDeque<(u64, Submitted)>,
    outcome_cursor: u64,
    last_started_period: Option<i64>,
    last_arm: ArmState,
    counted_rows: HashSet<RowKey>,
    counted_messages: HashSet<(i64, String)>,
    counted_order: VecDeque<(RowKey, (i64, String))>,
    fingerprint: String,
    new_id: Box<dyn FnMut() -> Option<String> + Send>,
}

fn refusal_code(r: TransmitRefusal) -> &'static str {
    match r {
        TransmitRefusal::TransmitUnsupported
        | TransmitRefusal::RadioUnavailable
        | TransmitRefusal::NotAuthorized => "transmit_unavailable",
        TransmitRefusal::Busy => "busy",
        TransmitRefusal::FrequencyOutOfRange => "out_of_range",
        _ => "state_conflict",
    }
}

impl Engine {
    pub fn new(new_id: Box<dyn FnMut() -> Option<String> + Send>) -> Self {
        Self {
            revision: 0,
            settings: Settings::default(),
            contact: None,
            reviews: VecDeque::new(),
            refused_target: None,
            unqueued: None,
            transmit_problem: None,
            sequence: 0,
            pending: None,
            requests: VecDeque::new(),
            outcome_cursor: 0,
            last_started_period: None,
            last_arm: ArmState::Disarmed,
            counted_rows: HashSet::new(),
            counted_messages: HashSet::new(),
            counted_order: VecDeque::new(),
            fingerprint: String::new(),
            new_id,
        }
    }
    /// The review offered first (the oldest unsaved one).
    pub fn review(&self) -> Option<&Review> {
        self.reviews.front()
    }
    #[cfg(test)]
    pub fn reviews(&self) -> impl Iterator<Item = &Review> {
        self.reviews.iter()
    }
    /// Drops offered reviews whose contact is durably saved.
    pub fn prune_saved(&mut self, saved: impl Fn(&str) -> bool) {
        self.reviews.retain(|r| !saved(&r.contact.id));
        if self.unqueued.as_deref().is_some_and(&saved) {
            self.unqueued = None;
        }
    }
    fn guard_unqueued(&self) -> Result<(), &'static str> {
        if self.unqueued.is_some() {
            return Err("state_conflict");
        }
        Ok(())
    }
    /// Offers a review: the same contact replaces its own offer in place; another
    /// contact queues behind every unsaved one (CancelContact/ChangeContact keep a
    /// completed unsaved contact until saved or discarded). Full queue: refused.
    fn offer(&mut self, review: Review) -> Result<(), &'static str> {
        if let Some(r) = self
            .reviews
            .iter_mut()
            .find(|r| r.contact.id == review.contact.id)
        {
            *r = review;
            return Ok(());
        }
        if self.reviews.len() == REVIEWS_MAX {
            return Err("state_conflict");
        }
        if self.unqueued.as_deref() == Some(review.contact.id.as_str()) {
            self.unqueued = None;
        }
        self.reviews.push_back(review);
        Ok(())
    }
    fn tx_max(&self, ctx: &Ctx) -> u32 {
        tx_max_hz(self.contact.as_ref().map_or(ctx.mode(), |c| c.mode))
    }
    fn count(&mut self, key: RowKey, message: (i64, String)) -> bool {
        if self.counted_rows.contains(&key) || self.counted_messages.contains(&message) {
            return false;
        }
        if self.counted_order.len() == COUNTED_KEYS
            && let Some((k, m)) = self.counted_order.pop_front()
        {
            self.counted_rows.remove(&k);
            self.counted_messages.remove(&m);
        }
        self.counted_rows.insert(key.clone());
        self.counted_messages.insert(message.clone());
        self.counted_order.push_back((key, message));
        true
    }
    fn disarm<H: Hardware>(core: Option<&mut Core<H>>, cause: DisarmCause) {
        if let Some(core) = core
            && core.view().arm_state == ArmState::Armed
        {
            core.disarm(cause);
        }
    }
    /// Prepares a partner (SelectDecodedRow / EnterDxStation) after ChangeContact rules.
    #[allow(clippy::too_many_arguments)]
    fn prepare<H: Hardware>(
        &mut self,
        core: Option<&mut Core<H>>,
        ctx: &Ctx,
        origin: Origin,
        dx: String,
        grid: Option<String>,
        report: i32,
        first: Slot,
        replace: bool,
        mode: Mode,
    ) -> Result<(), &'static str> {
        self.guard_unqueued()?;
        let (Some(call), Some(grid4)) = (ctx.call.clone(), ctx.grid4()) else {
            return Err("profile_incomplete");
        };
        let messages =
            generate(&call, &grid4, Some(&dx), report, Tx4::Rrr).ok_or("invalid_call")?;
        let same = self
            .contact
            .as_ref()
            .is_some_and(|c| c.dx_call.as_deref() == Some(dx.as_str()));
        let active = self.contact.as_ref().is_some_and(|c| c.state.active());
        if active && !same && !replace {
            return Err("contact_active");
        }
        // Re-preparing the same active partner keeps its contact identity.
        let id = match self.contact.as_ref().filter(|_| active && same) {
            Some(c) => c.id.clone(),
            None => (self.new_id)().ok_or("storage_unavailable")?,
        };
        if active && !same {
            // ChangeContact: the old contact is cancelled and Enable Tx turns off.
            Self::disarm(core, DisarmCause::ContactCancelled);
        }
        let tx1_skip = self.settings.tx1_skip;
        let first = if first == Slot::Tx1 && tx1_skip {
            Slot::Tx2
        } else {
            first
        };
        let state = State::of_slot(first);
        self.contact = Some(Contact {
            id,
            origin,
            mode,
            dx_call: Some(dx),
            dx_grid: grid,
            report,
            report_rcvd: None,
            report_sent: None,
            state,
            next: first,
            tx4: Tx4::Rrr,
            messages,
            started_tx1_skipped: tx1_skip && first == Slot::Tx2,
            prepared_utc_ms: ctx.now_utc_ms,
            first_tx_period: None,
            first_tx2_period: None,
            first_tx3_period: None,
            last_counted_end: None,
            offered_for_log: false,
        });
        self.settings.report = report;
        Ok(())
    }
    fn regenerate(&mut self, ctx: &Ctx) {
        let (Some(call), Some(grid4)) = (ctx.call.clone(), ctx.grid4()) else {
            return;
        };
        if let Some(c) = self.contact.as_mut()
            && let Some(set) = generate(&call, &grid4, c.dx_call.as_deref(), c.report, c.tx4)
        {
            c.messages[1..4].clone_from_slice(&set[1..4]);
        }
    }
    /// Applies one accepted-or-refused operating command. Ok means accepted (the caller
    /// advances the revision); a refusal changes nothing.
    pub fn command<H: Hardware>(
        &mut self,
        command: Command,
        mut core: Option<&mut Core<H>>,
        ctx: &Ctx,
    ) -> Result<(), &'static str> {
        let capability = core
            .as_ref()
            .map_or(Capability::Unsupported, |c| c.view().capability);
        match command {
            Command::SelectRow { row, replace } => {
                let Some(std) = row.standard.clone() else {
                    return Err("row_not_standard");
                };
                let Call::Sign(dx) = std.from.clone() else {
                    return Err("row_not_standard");
                };
                let my = ctx.call.clone().ok_or("profile_incomplete")?;
                let to_me = std.to == Call::Sign(my);
                let received = classify(&std);
                let report = row.snr_db.map_or(self.settings.report, report_from_snr);
                let grid = match &std.exchange {
                    Exchange::Grid(g) if valid_grid(g) => Some(g.clone()),
                    _ => None,
                };
                let first = first_slot(to_me, received, self.settings.tx1_skip);
                let rx = (row.frequency_hz.round().max(0.0) as u32).min(RX_MAX_HZ);
                let mode = row.mode;
                let tx_max = tx_max_hz(mode);
                self.prepare(
                    core.as_deref_mut(),
                    ctx,
                    Origin::DecodedRow,
                    dx,
                    grid,
                    report,
                    first,
                    replace,
                    mode,
                )?;
                self.settings.rx_hz = rx;
                if !self.settings.hold_tx && !to_me && (TX_MIN_HZ..=tx_max).contains(&rx) {
                    self.settings.tx_hz = rx;
                }
                if let Some(p) = row.period_start_ms {
                    self.settings.parity = match transmit::parity(mode, p) {
                        Parity::Even => Parity::Odd,
                        Parity::Odd => Parity::Even,
                    };
                }
                // The selected row itself is never counted again as a received message.
                if let Some(p) = row.period_start_ms {
                    self.count(row.key.clone(), (p, row.text.clone()));
                }
                if to_me && let Some(c) = self.contact.as_mut() {
                    if let Exchange::Report(r) = std.exchange {
                        c.report_rcvd = Some(r.clamp(REPORT_MIN, REPORT_MAX));
                    }
                    if let Some(p) = row.period_start_ms {
                        c.last_counted_end = Some(p + period_ms(mode));
                    }
                }
            }
            Command::EnterDx {
                call,
                grid,
                replace,
            } => {
                let dx = call.trim().to_ascii_uppercase();
                let grid = grid.map(|g| g.trim().to_ascii_uppercase());
                if dx.is_empty() || dx.len() > 13 || dx.contains(['<', '>']) {
                    return Err("invalid_call");
                }
                if let Some(g) = &grid
                    && !valid_grid(g)
                {
                    return Err("invalid_grid");
                }
                let my = ctx.call.clone().ok_or("profile_incomplete")?;
                // The DX call must pack as the 'to' call of the standard family.
                if standard_text(&format!("{dx} {my} 73")).as_deref()
                    != Some(format!("{dx} {my} 73").as_str())
                {
                    return Err("invalid_call");
                }
                let report = self.settings.report;
                self.prepare(
                    core.as_deref_mut(),
                    ctx,
                    Origin::ManualEntry,
                    dx,
                    grid,
                    report,
                    Slot::Tx1,
                    replace,
                    ctx.mode(),
                )?;
            }
            Command::Cancel => {
                Self::disarm(core.as_deref_mut(), DisarmCause::ContactCancelled);
                if let Some(c) = self.contact.as_mut() {
                    if c.state == State::Completed {
                        // A completed contact keeps its fields (Log QSO still works and a
                        // held, unqueued contact is never stranded); only Tx6 is selected.
                        c.next = Slot::Tx6;
                        self.pending = None;
                        if let Some(core) = core {
                            core.activity();
                        }
                        return Ok(());
                    }
                    c.state = if c.state == State::Calling || c.state == State::Idle {
                        State::Idle
                    } else {
                        State::Cancelled
                    };
                    c.dx_call = None;
                    c.dx_grid = None;
                    for i in 0..5 {
                        c.messages[i] = None;
                    }
                    c.next = Slot::Tx6;
                }
                self.pending = None;
            }
            Command::ChooseNext(slot) => {
                let c = self.contact.as_mut().ok_or("no_contact")?;
                let slot = if slot == Slot::Tx1 && self.settings.tx1_skip {
                    Slot::Tx2
                } else {
                    slot
                };
                if c.messages[slot.index()].is_none() {
                    return Err("invalid_message");
                }
                c.next = slot;
                // A finished (completed or cancelled) contact is never reopened by a
                // slot choice; Enable Tx then starts a fresh own-CQ contact.
                if !matches!(c.state, State::Completed | State::Cancelled) {
                    c.state = State::of_slot(slot);
                }
            }
            Command::EditMessage(slot, text) => {
                let c = self.contact.as_mut().ok_or("no_contact")?;
                if text.chars().count() > 37 {
                    return Err("invalid_message");
                }
                let normalized = standard_text(&text).ok_or("invalid_message")?;
                c.messages[slot.index()] = Some(normalized);
            }
            Command::SetReport(report) => {
                if !(REPORT_MIN..=REPORT_MAX).contains(&report) {
                    return Err("invalid_report");
                }
                self.settings.report = report;
                if let Some(c) = self.contact.as_mut() {
                    c.report = report;
                }
                self.regenerate(ctx);
            }
            Command::SetTx1Skip(enabled) => {
                self.settings.tx1_skip = enabled;
                if enabled
                    && let Some(c) = self.contact.as_mut()
                    && c.next == Slot::Tx1
                {
                    c.next = Slot::Tx2;
                    if c.state == State::Replying {
                        c.state = State::Report;
                    }
                }
            }
            Command::SetTx4(form) => {
                let c = self.contact.as_mut().ok_or("no_contact")?;
                c.tx4 = form;
                self.regenerate(ctx);
            }
            Command::SetFrequency { rx, tx } => {
                if rx.is_none() && tx.is_none() {
                    return Err("invalid_request");
                }
                if rx.is_some_and(|hz| hz > RX_MAX_HZ)
                    || tx.is_some_and(|hz| !(TX_MIN_HZ..=self.tx_max(ctx)).contains(&hz))
                {
                    return Err("out_of_range");
                }
                if let Some(rx) = rx {
                    self.settings.rx_hz = rx;
                }
                if let Some(tx) = tx {
                    self.settings.tx_hz = tx;
                }
            }
            Command::SetHoldTx(enabled) => self.settings.hold_tx = enabled,
            Command::SetParity(parity) => self.settings.parity = parity,
            Command::SetAutoSeq(enabled) => self.settings.auto_seq = enabled,
            Command::SetWatchdogs {
                tx_minutes,
                tune_seconds,
            } => {
                if !(1..=99).contains(&tx_minutes) || !(1..=300).contains(&tune_seconds) {
                    return Err("out_of_range");
                }
                let core = core.as_deref_mut().ok_or("transmit_unavailable")?;
                core.set_watchdogs(tx_minutes, tune_seconds)
                    .map_err(|_| "out_of_range")?;
            }
            Command::EnableTx(false, _) => {
                Self::disarm(core.as_deref_mut(), DisarmCause::Operator);
                self.pending = None;
            }
            Command::EnableTx(true, shown) => {
                if capability == Capability::Unsupported {
                    return Err("transmit_unavailable");
                }
                let (Some(call), Some(grid4)) = (ctx.call.clone(), ctx.grid4()) else {
                    return Err("profile_incomplete");
                };
                if !ctx.granted {
                    return Err("transmit_unavailable");
                }
                let core = core.as_deref_mut().ok_or("transmit_unavailable")?;
                if core.hardware().context().safety_revision.is_none() {
                    return Err("transmit_unavailable");
                }
                // #9 arms only with the revision the operator saw; it refuses a changed
                // one itself (NotAuthorized), so there is no check-then-arm race.
                let revision = shown.ok_or("stale_revision")?;
                let needs_cq = self.contact.as_ref().is_none_or(|c| !c.state.transmits());
                if needs_cq {
                    self.guard_unqueued()?;
                }
                let cq = if needs_cq {
                    let set = generate(&call, &grid4, None, self.settings.report, Tx4::Rrr)
                        .ok_or("profile_incomplete")?;
                    Some((set, (self.new_id)().ok_or("storage_unavailable")?))
                } else {
                    None
                };
                core.arm(revision).map_err(|r| match r {
                    TransmitRefusal::NotAuthorized => "stale_revision",
                    other => refusal_code(other),
                })?;
                self.last_arm = ArmState::Armed;
                self.transmit_problem = None;
                if let Some((messages, id)) = cq {
                    // With no partner, Tx6 means calling CQ.
                    self.contact = Some(Contact {
                        id,
                        origin: Origin::OwnCq,
                        mode: ctx.mode(),
                        dx_call: None,
                        dx_grid: None,
                        report: self.settings.report,
                        report_rcvd: None,
                        report_sent: None,
                        state: State::Calling,
                        next: Slot::Tx6,
                        tx4: Tx4::Rrr,
                        messages,
                        started_tx1_skipped: false,
                        prepared_utc_ms: ctx.now_utc_ms,
                        first_tx_period: None,
                        first_tx2_period: None,
                        first_tx3_period: None,
                        last_counted_end: None,
                        offered_for_log: false,
                    });
                }
            }
            Command::Tune(enabled) => {
                if enabled && (capability == Capability::Unsupported || !ctx.granted) {
                    return Err("transmit_unavailable");
                }
                let tx = self.settings.tx_hz;
                let core = core.as_deref_mut().ok_or("transmit_unavailable")?;
                core.set_tune(enabled, tx).map_err(|r| match r {
                    TransmitRefusal::NotArmed => "state_conflict",
                    other => refusal_code(other),
                })?;
            }
            Command::Redecode => return Err("redecode_unavailable"),
            Command::OpenLog => {
                let c = self.contact.as_ref().ok_or("no_contact")?;
                if c.dx_call.is_none() {
                    return Err("no_contact");
                }
                let review = Review {
                    contact: c.clone(),
                    automatic: false,
                };
                self.offer(review)?;
            }
            Command::DiscardReview(id) => {
                let before = self.reviews.len();
                self.reviews.retain(|r| r.contact.id != id);
                if self.unqueued.as_deref() == Some(id.as_str()) {
                    self.unqueued = None;
                } else if self.reviews.len() == before {
                    return Err("not_found");
                }
            }
        }
        // Accepted operating activity resets the Tx watchdog (WstxContact::TxWatchdog).
        if let Some(core) = core {
            core.activity();
        }
        Ok(())
    }
    fn complete<H: Hardware>(&mut self, core: Option<&mut Core<H>>, now: i64) {
        Self::disarm(core, DisarmCause::ContactCompleted);
        self.pending = None;
        if let Some(c) = self.contact.as_mut() {
            c.state = State::Completed;
            c.next = Slot::Tx6;
            if c.last_counted_end.is_none() {
                c.last_counted_end = Some(now);
            }
            if !c.offered_for_log {
                c.offered_for_log = true;
                let id = c.id.clone();
                let review = Review {
                    contact: c.clone(),
                    automatic: true,
                };
                if self.offer(review).is_err() {
                    self.unqueued = Some(id);
                    // Eight unsaved reviews already wait; the contact stays completed
                    // and can still be offered with Log QSO once one is resolved.
                    self.transmit_problem = Some("review_queue_full".into());
                }
            }
        }
    }
    /// One engine step: transmit outcomes, new decoded rows, arm transitions and the
    /// pending TransmitSubmission. Returns true when the revision advanced.
    pub fn step<H: Hardware>(
        &mut self,
        mut core: Option<&mut Core<H>>,
        ctx: &Ctx,
        rows: &[Row],
    ) -> bool {
        let now = ctx.now_utc_ms;
        // Outcomes of my requests.
        if let Some(core) = core.as_deref_mut() {
            for outcome in core.outcomes_since(self.outcome_cursor) {
                self.outcome_cursor = self.outcome_cursor.max(outcome.outcome_sequence);
                let Some(position) = self
                    .requests
                    .iter()
                    .position(|(s, _)| *s == outcome.request_sequence)
                else {
                    continue;
                };
                let submitted = self.requests[position].1.clone();
                let mine = self
                    .contact
                    .as_ref()
                    .is_some_and(|c| c.id == submitted.contact_id);
                match outcome.kind {
                    OutcomeKind::Accepted | OutcomeKind::Replaced => {}
                    OutcomeKind::Started => {
                        self.last_started_period = Some(submitted.period);
                        if mine && let Some(c) = self.contact.as_mut() {
                            c.first_tx_period.get_or_insert(submitted.period);
                            if submitted.slot == Slot::Tx2 {
                                c.first_tx2_period.get_or_insert(submitted.period);
                            }
                            if submitted.slot == Slot::Tx3 {
                                c.first_tx3_period.get_or_insert(submitted.period);
                            }
                            if matches!(submitted.slot, Slot::Tx2 | Slot::Tx3) {
                                c.report_sent = Some(submitted.report);
                            }
                            if c.dx_call.is_some() {
                                c.last_counted_end = Some(
                                    c.last_counted_end
                                        .unwrap_or(i64::MIN)
                                        .max(submitted.period + period_ms(c.mode)),
                                );
                            }
                        }
                        if self
                            .pending
                            .as_ref()
                            .is_some_and(|(s, _)| *s == outcome.request_sequence)
                        {
                            self.pending = None;
                        }
                    }
                    OutcomeKind::Completed => {
                        let signoff = submitted.slot == Slot::Tx5
                            || (submitted.slot == Slot::Tx4 && submitted.text.ends_with(" RR73"));
                        let state = self.contact.as_ref().map(|c| c.state);
                        if mine
                            && signoff
                            && matches!(state, Some(State::Signoff | State::Rogers))
                            && (submitted.slot == Slot::Tx5 || state == Some(State::Rogers))
                        {
                            self.complete(Some(&mut *core), now);
                        }
                        self.requests.remove(position);
                    }
                    OutcomeKind::Halted => {
                        self.requests.remove(position);
                        self.pending = None;
                    }
                    OutcomeKind::Refused | OutcomeKind::Failed => {
                        let refusal = outcome.refusal;
                        if !matches!(
                            refusal,
                            Some(
                                TransmitRefusal::DuplicateSequence
                                    | TransmitRefusal::AudioStarted
                                    | TransmitRefusal::NotArmed
                            )
                        ) {
                            self.transmit_problem = outcome
                                .refusal
                                .map(|r| snake(&format!("{r:?}")))
                                .or_else(|| outcome.failure.map(|f| snake(&format!("{f:?}"))));
                        }
                        self.requests.remove(position);
                        if self
                            .pending
                            .as_ref()
                            .is_some_and(|(s, _)| *s == outcome.request_sequence)
                        {
                            self.pending = None;
                        }
                    }
                }
            }
        }
        // Received messages (DMR planProcessMessage, planAutoSequence).
        for row in rows {
            let Some(c) = self.contact.as_ref() else {
                break;
            };
            let (Some(dx), Some(std)) = (c.dx_call.clone(), row.standard.as_ref()) else {
                continue;
            };
            if std.from != Call::Sign(dx) || !c.state.active() {
                continue;
            }
            let Some(my) = ctx.call.as_deref() else {
                continue;
            };
            match &std.to {
                Call::Sign(to) if to == my => {
                    let Some(period) = row.period_start_ms else {
                        continue;
                    };
                    // Decoded in the partner's period (the parity opposite to mine).
                    if transmit::parity(row.mode, period) == self.settings.parity {
                        continue;
                    }
                    if !self.count(row.key.clone(), (period, row.text.clone())) {
                        continue;
                    }
                    let received = classify(std);
                    let auto = self.settings.auto_seq;
                    let c = self.contact.as_mut().expect("checked");
                    if let Exchange::Report(r) = std.exchange {
                        c.report_rcvd = Some(r.clamp(REPORT_MIN, REPORT_MAX));
                    }
                    c.last_counted_end = Some(
                        c.last_counted_end
                            .unwrap_or(i64::MIN)
                            .max(period + period_ms(row.mode)),
                    );
                    if !auto {
                        continue;
                    }
                    if let Some(next) = transition(c.state, received) {
                        if next == State::Completed {
                            self.complete(core.as_deref_mut(), now);
                        } else {
                            c.state = next;
                            c.next = next.slot();
                        }
                    }
                }
                Call::Sign(_) => {
                    // partnerWorksOther: the 50 Hz rule (MW auto_sequence 25/50).
                    let applies = c.state == State::Replying
                        || (c.state == State::Report && c.started_tx1_skipped);
                    if self.settings.auto_seq
                        && applies
                        && (row.frequency_hz - f64::from(self.settings.tx_hz)).abs()
                            <= STOP_TOLERANCE_HZ
                        && let Some(core) = core.as_deref_mut()
                    {
                        let view = core.view();
                        if view.transmitting {
                            core.halt();
                        } else if view.arm_state == ArmState::Armed {
                            core.disarm(DisarmCause::Operator);
                        }
                        self.pending = None;
                    }
                }
                _ => {}
            }
        }
        // Arm transitions: halt and watchdog expiry end a CQ; other states are kept.
        if let Some(core) = core.as_deref_mut() {
            let view = core.view();
            if self.last_arm == ArmState::Armed && view.arm_state == ArmState::Disarmed {
                self.pending = None;
                if matches!(
                    view.last_disarm_cause,
                    DisarmCause::Halt | DisarmCause::TxWatchdog
                ) && let Some(c) = self.contact.as_mut()
                    && c.state == State::Calling
                {
                    c.state = State::Idle;
                }
            }
            self.last_arm = view.arm_state;
            if view.arm_state == ArmState::Armed {
                self.submit(core, ctx);
            }
        }
        let fingerprint = self.fingerprint(core.as_deref());
        if fingerprint != self.fingerprint {
            self.fingerprint = fingerprint;
            self.revision += 1;
            return true;
        }
        false
    }
    /// The material state a revision covers (sequence, transmit and watchdog view).
    pub fn fingerprint<H: Hardware>(&self, core: Option<&Core<H>>) -> String {
        let view = core.map(|c| {
            let v = c.view();
            format!(
                "{:?}{:?}{:?}{:?}{:?}{:?}{:?}{}{}{}{}",
                v.capability,
                v.arm_state,
                v.last_disarm_cause,
                v.pending_sequence,
                v.last_text,
                v.halt_state,
                v.refusal,
                v.tune,
                v.tx_expired,
                v.tx_remaining_minutes,
                v.tune_remaining_seconds
            )
        });
        format!(
            "{:?}|{:?}|{:?}|{:?}|{:?}|{:?}",
            self.settings, self.contact, self.reviews, self.transmit_problem, view, self.last_arm
        )
    }
    /// Keeps exactly one pending request for the next period of the contact's parity
    /// with the current next text and Tx offset (WstxContact::TransmitSubmission).
    fn submit<H: Hardware>(&mut self, core: &mut Core<H>, ctx: &Ctx) {
        let Some(c) = self.contact.as_ref() else {
            return;
        };
        if !c.state.transmits() {
            return;
        }
        let Some(text) = c.messages[c.next.index()].clone() else {
            return;
        };
        let now = ctx.now_utc_ms;
        let mode = c.mode;
        let floor = self
            .last_started_period
            .map_or(now + LEAD_MS, |p| (now + LEAD_MS).max(p + period_ms(mode)));
        let period = transmit::next_period(mode, floor, self.settings.parity);
        let tx_hz = self.settings.tx_hz;
        if self.refused_target.as_ref() == Some(&(period, text.clone(), tx_hz)) {
            return;
        }
        if let Some((_, s)) = &self.pending
            && s.period == period
            && s.text == text
            && s.tx_hz == tx_hz
            && s.contact_id == c.id
        {
            return;
        }
        let submitted = Submitted {
            slot: c.next,
            text: text.clone(),
            period,
            tx_hz,
            contact_id: c.id.clone(),
            report: c.report,
        };
        let floor_sequence = u64::try_from(now.max(0)).unwrap_or(0).saturating_mul(1000);
        let sequence = (self.sequence + 1).max(floor_sequence);
        self.sequence = sequence;
        let outcome = core.submit(Request {
            contact_id: Some(c.id.clone()),
            request_sequence: sequence,
            mode,
            period_start_utc_ms: period,
            message_text: text,
            tx_offset_hz: tx_hz,
        });
        if self.requests.len() == 64 {
            self.requests.pop_front();
        }
        self.requests.push_back((sequence, submitted.clone()));
        if outcome.kind == OutcomeKind::Accepted {
            self.pending = Some((sequence, submitted));
        } else {
            self.pending = None;
            self.transmit_problem = outcome.refusal.map(|r| snake(&format!("{r:?}")));
            // Never resubmit a refused target as is; a refusal #9 does not disarm for
            // (duplicateSequence: this boot's sequences are exhausted) disarms here, so
            // the refusal is visible and the 20 Hz step does not repeat it.
            self.refused_target = Some((period, submitted.text.clone(), tx_hz));
            if outcome.refusal == Some(TransmitRefusal::DuplicateSequence)
                && core.view().arm_state == ArmState::Armed
            {
                core.disarm(DisarmCause::Refused);
            }
        }
    }
}

/// CamelCase variant name to the wire's snake_case.
pub fn snake(text: &str) -> String {
    let mut out = String::new();
    for (i, c) in text.chars().enumerate() {
        if c.is_ascii_uppercase() {
            if i > 0 {
                out.push('_');
            }
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

// ---------------------------------------------------------------- UTC text
/// Civil date (proleptic Gregorian UTC) of a Unix millisecond instant.
pub fn civil(utc_ms: i64) -> (i64, u32, u32, u32, u32, u32) {
    let seconds = utc_ms.div_euclid(1000);
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (
        year,
        month,
        day,
        (rest / 3600) as u32,
        (rest % 3600 / 60) as u32,
        (rest % 60) as u32,
    )
}
/// Unix milliseconds of `YYYY-MM-DDTHH:MM:SS(.f*)Z` (the result period_start_utc form).
pub fn parse_utc(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() < 20 || !text.ends_with('Z') || b[4] != b'-' || b[7] != b'-' || b[10] != b'T' {
        return None;
    }
    let n = |r: std::ops::Range<usize>| text.get(r)?.parse::<i64>().ok();
    let (y, m, d, h, mi, s) = (
        n(0..4)?,
        n(5..7)?,
        n(8..10)?,
        n(11..13)?,
        n(14..16)?,
        n(17..19)?,
    );
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) || h > 23 || mi > 59 || s > 59 {
        return None;
    }
    let fraction = &text[19..text.len() - 1];
    let millis = if fraction.is_empty() {
        0
    } else {
        let digits = fraction.strip_prefix('.')?;
        if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        format!("{digits:0<3}")[..3].parse::<i64>().ok()?
    };
    let (yy, mm) = if m <= 2 { (y - 1, m + 9) } else { (y, m - 3) };
    let era = yy.div_euclid(400);
    let yoe = yy - era * 400;
    let doy = (153 * mm + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(((days * 86_400 + h * 3600 + mi * 60 + s) * 1000) + millis)
}
pub fn utc_text(utc_ms: i64) -> String {
    let (y, mo, d, h, mi, s) = civil(utc_ms);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}
pub fn adif_date(utc_ms: i64) -> String {
    let (y, mo, d, ..) = civil(utc_ms);
    format!("{y:04}{mo:02}{d:02}")
}
pub fn adif_time(utc_ms: i64) -> String {
    let (.., h, mi, s) = civil(utc_ms);
    format!("{h:02}{mi:02}{s:02}")
}

/// A contact prepared for log review with its server-owned times (LogRecord).
pub struct LogFields {
    pub call: String,
    pub grid: Option<String>,
    pub mode: Mode,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
}
impl Review {
    pub fn fields(&self, now_utc_ms: i64) -> Option<LogFields> {
        let c = &self.contact;
        let start = c.start_utc_ms().unwrap_or(c.prepared_utc_ms);
        let end = c.last_counted_end.unwrap_or(now_utc_ms).max(start);
        Some(LogFields {
            call: c.dx_call.clone()?,
            grid: c.dx_grid.clone(),
            mode: c.mode,
            rst_sent: c.report_sent.map(render_report),
            rst_rcvd: c.report_rcvd.map(render_report),
            start_utc_ms: start,
            end_utc_ms: end,
        })
    }
}
