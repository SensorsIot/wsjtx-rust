#![forbid(unsafe_code)]
//! WstxContact (#10, FT4 #11): the server-owned standard FT8/FT4 contact engine. It owns contact
//! identity, the AutoSequence state, the next-message choice, completion and which
//! contacts are due for the log (WstxContact::DirectLog, #41); it never keys PTT, opens audio or touches a radio. Every transmission
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
/// FT4-NOTE: Tx4 is always RR73 in FT4 (MW send_rr73_for_tx4); RRR is the FT8 default.
pub fn tx4_default(mode: Mode) -> Tx4 {
    match mode {
        Mode::Ft8 => Tx4::Rrr,
        Mode::Ft4 => Tx4::Rr73,
    }
}
/// The 50 Hz rule of WSJT-X auto_sequence(decodedtext, 25, 50) (stopTolerance).
pub const STOP_TOLERANCE_HZ: f64 = 50.0;
/// A request is planned for the first period whose start window is still open this
/// long from now, so it never turns stale between admission and keying.
pub const LEAD_MS: i64 = 1000;
/// WstxContact::TxWatchdog: the stop waits this long into the due period, past the latest
/// live decode measured (#47: up to 1.1 s after the FT8 period start), so a partner
/// message that changes the next message still counts. Nothing is planned meanwhile.
const WATCHDOG_STOP_AFTER_DUE_MS: i64 = 1200;
const COUNTED_KEYS: usize = 4096;

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
    /// A hash the station filled in (`<CALL>`, WstxOfflineDecode::HashResolution, #24).
    Hashed(String),
    /// An unresolved hash (`<...>`).
    Hash,
}
impl Call {
    /// The call this slot names: a concrete or a filled-in hashed call.
    pub fn call(&self) -> Option<&str> {
        match self {
            Call::Sign(c) | Call::Hashed(c) => Some(c),
            _ => None,
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub enum Exchange {
    Grid(String),
    Report(i32),
    /// A Field Day or RTTY Roundup exchange, its last two words (#24 S2b, ContestExchange).
    Contest(ContestKind, String),
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
    /// A 0.1 DXpedition message "RR73_TO RR73; REPORT_TO <FOX> REPORT" (#24 S4b,
    /// HoundOperation); such a row is never a standard message.
    pub dxpedition: Option<Box<Dxpedition>>,
    /// An i3=5 EU VHF message (#99, EuVhfExchange); such a row is never a standard message.
    pub vhf: Option<Box<Vhf>>,
}
/// The fields of an EU VHF message: both calls hashed, with their received hashes.
#[derive(Clone, Debug, PartialEq)]
pub struct Vhf {
    pub to: Call,
    pub from: Call,
    /// The 12-bit hash of 'to' and the 22-bit hash of 'from' as received.
    pub to_h12: u32,
    pub from_h22: u32,
    pub ack: bool,
    /// The RS 52..59.
    pub report: u32,
    pub serial: u32,
    pub grid: String,
}
impl Vhf {
    /// Its last two words, "5nSSSS GRID6" (WSJT-X right(13)).
    pub fn exchange(&self) -> String {
        format!("{}{:04} {}", self.report, self.serial, self.grid)
    }
    /// Addressed to `my` call: its 'to' hash is the 12-bit hash of my call.
    pub fn to_me(&self, my: &str) -> bool {
        wstx_rust::decoder::ihashcall(my, 12) == Some(self.to_h12)
    }
    /// Sent by `dx`: its 'from' hash is the 22-bit hash of the DX call.
    pub fn sent_by(&self, dx: &str) -> bool {
        wstx_rust::decoder::ihashcall(dx, 22) == Some(self.from_h22)
    }
}
/// The fields of a 0.1 DXpedition multi-message (WstxOfflineDecode Dxpedition fields).
#[derive(Clone, Debug, PartialEq)]
pub struct Dxpedition {
    pub rr73_to: Call,
    pub report_to: Call,
    /// The hashed Fox call (10-bit hash, filled in from the DX call by hashdx10).
    pub fox: Call,
    pub report: i32,
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
/// The message family of a contest exchange (i3=0 n3=3/4 or i3=3).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContestKind {
    FieldDay,
    Rtty,
}
/// WstxContact::GridExchangeContest: the station's special operating activity (#24 S2a,
/// Field Day and RTTY Roundup #24 S2b).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Activity {
    #[default]
    None,
    NaVhf,
    /// EuVhfExchange (#99): the EU VHF contest message, i3=5.
    EuVhf,
    WwDigi,
    ArrlDigi,
    FieldDay,
    Rtty,
    /// HoundOperation (#24 S4b): the classic Hound, FT8 only.
    Hound,
}
impl Activity {
    pub fn name(self) -> &'static str {
        match self {
            Activity::None => "none",
            Activity::NaVhf => "na_vhf",
            Activity::EuVhf => "eu_vhf",
            Activity::WwDigi => "ww_digi",
            Activity::ArrlDigi => "arrl_digi",
            Activity::FieldDay => "field_day",
            Activity::Rtty => "rtty",
            Activity::Hound => "hound",
        }
    }
    pub fn parse(text: &str) -> Option<Self> {
        [
            Self::None,
            Self::NaVhf,
            Self::EuVhf,
            Self::WwDigi,
            Self::ArrlDigi,
            Self::FieldDay,
            Self::Rtty,
            Self::Hound,
        ]
        .into_iter()
        .find(|a| a.name() == text)
    }
    /// The contest exchange family of Field Day and RTTY Roundup (ContestExchange).
    pub fn contest(self) -> Option<ContestKind> {
        match self {
            Activity::FieldDay => Some(ContestKind::FieldDay),
            Activity::Rtty => Some(ContestKind::Rtty),
            _ => None,
        }
    }
    /// WSJT-X SpecialOperatingActivity value (UDP Status special operation).
    pub fn special_operation(self) -> u8 {
        match self {
            Activity::None => 0,
            Activity::NaVhf => 1,
            Activity::EuVhf => 2,
            Activity::WwDigi => 5,
            Activity::ArrlDigi => 8,
            Activity::FieldDay => 3,
            Activity::Rtty => 4,
            Activity::Hound => 7,
        }
    }
    /// A contest activity (not none, not hound): the contest serial counts, and Tx1 is
    /// disabled except in eu_vhf (MW ~8203).
    fn contest_like(self) -> bool {
        !matches!(self, Activity::None | Activity::Hound)
    }
    /// The CQ modifier of genCQMsg (m_cqStr).
    pub fn cq(self) -> Option<&'static str> {
        match self {
            Activity::None | Activity::Hound => None,
            Activity::NaVhf | Activity::EuVhf | Activity::ArrlDigi => Some("TEST"),
            Activity::WwDigi => Some("WW"),
            Activity::FieldDay => Some("FD"),
            Activity::Rtty => Some("RU"),
        }
    }
}
/// ContestExchange: the configured exchange of field_day ("nC SECTION") or rtty (a state,
/// province or multiplier, or DX/# for the serial), normalized; None when invalid. Other
/// activities take no exchange (Some(None) only without one).
pub fn contest_exchange(activity: Activity, text: Option<&str>) -> Option<Option<String>> {
    let Some(kind) = activity.contest() else {
        return text.is_none().then_some(None);
    };
    let text = text?;
    // Only ASCII can be an exchange (and slicing below needs char boundaries).
    if !text.is_ascii() {
        return None;
    }
    let text = text.to_ascii_uppercase();
    let words = text.split_whitespace().collect::<Vec<_>>();
    let ok = match (kind, words.as_slice()) {
        (ContestKind::FieldDay, [class, section]) => {
            let (count, c) = class.split_at(class.len().saturating_sub(1));
            !count.is_empty()
                && !count.starts_with('0')
                && count.bytes().all(|b| b.is_ascii_digit())
                && count.parse::<u32>().is_ok_and(|n| (1..=32).contains(&n))
                && matches!(c, "A" | "B" | "C" | "D" | "E" | "F")
                && crate::decoder::arrl_sections().iter().any(|s| s == section)
        }
        // RTTY_roundup_exchange_re: a multiplier, DX/# (serial) or a fixed 0001-7999.
        (ContestKind::Rtty, [x]) => {
            matches!(*x, "DX" | "#")
                || crate::decoder::rtty_exchanges().iter().any(|s| s == x)
                || (x.len() == 4
                    && x.bytes().all(|b| b.is_ascii_digit())
                    && x.parse::<u32>().is_ok_and(|n| (1..=7999).contains(&n)))
        }
        _ => false,
    };
    ok.then(|| Some(words.join(" ")))
}
/// The sent exchange of Tx2 (Tx3 adds R): the report, my grid in a grid-exchange
/// contest, the Field Day exchange, "5n9 X" in RTTY Roundup (MW genStdMsgs ~9741), or
/// "5nSSSS GRID6" in EU VHF (MW ~9774-9779, #99).
fn sent_exchange(
    activity: Activity,
    locator: &str,
    report: i32,
    exchange: &str,
    serial: u32,
) -> String {
    let grid4 = locator.get(..4).unwrap_or(locator);
    let n = ((report + 36) / 6).clamp(2, 9);
    match activity {
        Activity::None | Activity::Hound => render_report(report),
        Activity::NaVhf | Activity::WwDigi | Activity::ArrlDigi => grid4.to_owned(),
        Activity::FieldDay => exchange.to_owned(),
        Activity::Rtty => match exchange {
            "DX" | "#" => format!("5{n}9 {serial:04}"),
            x => format!("5{n}9 {x}"),
        },
        // A locator shorter than six characters gives no packable message.
        Activity::EuVhf => format!("5{n}{serial:04} {}", locator.get(..6).unwrap_or("")),
    }
}
/// ContestReceivedKind: in a grid-exchange contest a grid is the report and R+grid the
/// roger report (DecodedMessageReaction.cpp ~533-547, #24 S2a); not in eu_vhf, where a
/// grid stays a grid (DMR ~534, #99).
pub fn classify_in(standard: &Standard, activity: Activity) -> Received {
    match (&standard.exchange, activity) {
        // ContestExchange: an exchange of the activity's own family (#24 S2b).
        (Exchange::Contest(kind, _), a) if a.contest() == Some(*kind) => {
            if standard.ack {
                Received::RogerReport
            } else {
                Received::SignalReport
            }
        }
        (Exchange::Grid(_), a) if a.contest_like() && a != Activity::EuVhf => {
            if standard.ack {
                Received::RogerReport
            } else {
                Received::SignalReport
            }
        }
        _ => classify(standard),
    }
}
pub fn classify(standard: &Standard) -> Received {
    match standard.exchange {
        Exchange::Grid(_) => Received::Grid,
        Exchange::Report(_) if standard.ack => Received::RogerReport,
        Exchange::Report(_) => Received::SignalReport,
        Exchange::Rrr | Exchange::Rr73 => Received::Rogers,
        Exchange::SeventyThree => Received::SeventyThree,
        Exchange::Blank | Exchange::Contest(..) => Received::Other,
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
        // A partner who skips RR73 and signs off with 73 after my R+report is
        // answered with my 73 once, like an RR73 (#11).
        (S::RogerReport, R::Rogers | R::SeventyThree) => S::Signoff,
        // rogerAck (DMR ~585-600): a partner's RRR or RR73 before my 73 is answered with
        // my 73 once, also after my RRR and before any report reached me (#69).
        (S::Replying | S::Report | S::Rogers | S::Signoff, R::Rogers) => S::Signoff,
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
/// A generated message: standard, nonstandard or a Field Day / RTTY Roundup / EU VHF
/// exchange.
fn generated_text(text: &str) -> Option<String> {
    let packed = transmit::pack(text).ok()?;
    matches!(
        packed.family,
        Family::Standard
            | Family::Portable
            | Family::Nonstandard
            | Family::FieldDay
            | Family::RttyRoundup
            | Family::EuVhf
    )
    .then_some(packed.text)
}
/// An operator-edited slot text (StandardMessageSet): standard, nonstandard, a Field Day,
/// RTTY Roundup (#24 S2b) or EU VHF (#99) exchange or free text of at most 13 characters,
/// packed unaltered and normalized.
pub fn slot_text(text: &str) -> Option<String> {
    let packed = transmit::pack(text).ok()?;
    matches!(
        packed.family,
        Family::Standard
            | Family::Portable
            | Family::Nonstandard
            | Family::FreeText
            | Family::FieldDay
            | Family::RttyRoundup
            | Family::EuVhf
    )
    .then_some(packed.text)
}
/// Radio::is_standard_callsign (WSJT-X 3.3.0-beta5 Radio.cpp): a prefix of up to two
/// letters, a letter and a digit or a digit and a letter, then a digit and at most three
/// letters, optionally /R or /P.
pub fn is_standard_call(call: &str) -> bool {
    let base = call
        .strip_suffix("/R")
        .or_else(|| call.strip_suffix("/P"))
        .unwrap_or(call);
    let b = base.as_bytes();
    (0..=b.len().min(2)).any(|i| {
        let (prefix, rest) = b.split_at(i);
        let prefix_ok = match prefix {
            [] => true,
            [a] => a.is_ascii_uppercase(),
            [a, c] => {
                a.is_ascii_uppercase() && (c.is_ascii_uppercase() || c.is_ascii_digit())
                    || a.is_ascii_digit() && c.is_ascii_uppercase()
            }
            _ => false,
        };
        prefix_ok
            && rest.first().is_some_and(u8::is_ascii_digit)
            && rest.len() <= 4
            && rest[1..].iter().all(u8::is_ascii_uppercase)
    })
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
    generate_with(my_call, grid4, dx, report, tx4, Activity::None)
}
/// StandardMessageSet with the station's special activity (GridExchangeContest).
pub fn generate_with(
    my_call: &str,
    grid4: &str,
    dx: Option<&str>,
    report: i32,
    tx4: Tx4,
    activity: Activity,
) -> Option<[Option<String>; 6]> {
    generate_contest(my_call, grid4, dx, report, tx4, activity, None, 1)
}
/// StandardMessageSet with the activity's exchange (ContestExchange): Field Day and RTTY
/// Roundup need their configured exchange and both calls standard; EU VHF (#99) sends
/// both calls hashed in Tx2/Tx3 with the first six characters of `locator`.
#[allow(clippy::too_many_arguments)]
pub fn generate_contest(
    my_call: &str,
    locator: &str,
    dx: Option<&str>,
    report: i32,
    tx4: Tx4,
    activity: Activity,
    exchange: Option<&str>,
    serial: u32,
) -> Option<[Option<String>; 6]> {
    let exchange = match activity.contest() {
        Some(_) => exchange?,
        None => "",
    };
    let grid4 = locator.get(..4).unwrap_or(locator);
    let sent = sent_exchange(activity, locator, report, exchange, serial);
    let (r, rr) = match activity {
        Activity::None | Activity::Hound => (sent.clone(), format!("R{sent}")),
        _ => (sent.clone(), format!("R {sent}")),
    };
    let mut set: [Option<String>; 6] = Default::default();
    // MW genStdMsgs/genCQMsg, 77-bit: brackets mark the hashed nonstandard side (#24 S1b).
    let my_standard = is_standard_call(my_call);
    set[5] = Some(if my_standard {
        match activity.cq() {
            Some(cq) => format!("CQ {cq} {my_call} {grid4}"),
            None => format!("CQ {my_call} {grid4}"),
        }
    } else {
        format!("CQ {my_call}")
    });
    if let Some(dx) = dx {
        // (Tx1-Tx3 stem, Tx4/Tx5 stem)
        let (exchange, signoff) = match (my_standard, is_standard_call(dx)) {
            (true, true) => (format!("{dx} {my_call}"), format!("{dx} {my_call}")),
            (true, false) => (format!("<{dx}> {my_call}"), format!("{dx} <{my_call}>")),
            (false, true) => (format!("{dx} <{my_call}>"), format!("<{dx}> {my_call}")),
            (false, false) => return None,
        };
        set[0] = Some(if my_standard {
            format!("{exchange} {grid4}")
        } else {
            signoff.clone()
        });
        if activity == Activity::EuVhf {
            set[1] = Some(format!("<{dx}> <{my_call}> {r}"));
            set[2] = Some(format!("<{dx}> <{my_call}> {rr}"));
        } else {
            set[1] = Some(format!("{exchange} {r}"));
            set[2] = Some(format!("{exchange} {rr}"));
        }
        set[3] = Some(format!(
            "{signoff} {}",
            if tx4 == Tx4::Rr73 { "RR73" } else { "RRR" }
        ));
        set[4] = Some(format!("{signoff} 73"));
    }
    for text in set.iter().flatten() {
        if generated_text(text).as_deref() != Some(text.as_str()) {
            return None;
        }
    }
    Some(set)
}

// ---------------------------------------------------------------- state
#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub auto_seq: bool,
    /// WSJT-X Call 1st (cbFirst, #10): an own CQ answers its first caller.
    pub call_first: bool,
    pub tx1_skip: bool,
    pub rx_hz: u32,
    pub tx_hz: u32,
    pub hold_tx: bool,
    pub parity: Parity,
    pub report: i32,
    /// GridExchangeContest (#24 S2a): this boot's special activity, none by default.
    pub activity: Activity,
    /// ContestExchange (#24 S2b): the configured Field Day / RTTY Roundup exchange.
    pub exchange: Option<String>,
    /// ContestExchange: the contest serial number, 1 at boot.
    pub serial: u32,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            auto_seq: true,
            // #10 (operator 2026-11-02): on by default, operator-changeable.
            call_first: true,
            tx1_skip: false,
            rx_hz: 1500,
            tx_hz: 1500,
            // #39 CL-039-08 (operator 2026-11-04): on by default; a selection never moves Tx.
            hold_tx: true,
            // WSJT-X m_txFirst default false: transmit in the second (odd) period.
            parity: Parity::Odd,
            report: REPORT_DEFAULT,
            activity: Activity::None,
            exchange: None,
            serial: 1,
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
    /// ContestExchange (#24 S2b): the last two words of Tx2 once Tx2/Tx3 is sent, and
    /// the last two words of the partner's counted contest exchange.
    pub exchange_sent: Option<String>,
    pub exchange_rcvd: Option<String>,
    /// The activity the contact was prepared in (its log fields follow it).
    pub activity: Activity,
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
    /// Set at completion when the contact was handed to the log (once per contact).
    pub logged_on_completion: bool,
    /// With Auto Seq off: the message Auto Seq would send next after the latest counted
    /// partner message (e.g. Tx5 after their RR73), offered to the operator (#11).
    pub suggested: Option<Slot>,
    /// The latest partner message to my call (#37 QSO pane), with its repeat count.
    pub last_rcvd: Option<Heard>,
    /// The QSO dialogue (#37, ContactSnapshot dialogue): counted partner messages and
    /// this contact's started transmissions, oldest first, at most DIALOGUE_MAX.
    pub dialogue: VecDeque<Exchanged>,
}
/// At most this many dialogue entries are kept (the oldest is dropped).
pub const DIALOGUE_MAX: usize = 16;
/// One QSO dialogue entry: received from the partner (rx) or transmitted (tx).
#[derive(Clone, Debug, PartialEq)]
pub struct Exchanged {
    pub tx: bool,
    pub text: String,
    pub snr: Option<i32>,
    /// The first period of this entry (Unix ms).
    pub period_ms: i64,
    /// Repetitions merged into this entry: a message equal to the newest entry of its
    /// direction, also across a message of the other direction (shown as Rep).
    pub count: u32,
    /// An operator Enable Tx closed this entry: the next equal transmission opens a new
    /// one, so a station stopped by the Tx watchdog may send the same message again.
    pub closed: bool,
}
/// A partner message to my call as the QSO pane shows it (#37).
#[derive(Clone, Debug, PartialEq)]
pub struct Heard {
    pub text: String,
    pub snr: Option<i32>,
    pub period_ms: i64,
    /// Consecutive counted messages with this identical text.
    pub count: u32,
}
impl Contact {
    /// #81 WstxStrategy::StartedQso: a partner in progress, and the dialogue holds a message of the
    /// partner to my call and an own transmission that has started (keyed, also still on the air).
    pub fn started(&self) -> bool {
        self.state.active()
            && self.dialogue.iter().any(|e| !e.tx)
            && self.dialogue.iter().any(|e| e.tx)
    }
    fn exchanged(&mut self, tx: bool, text: &str, snr: Option<i32>, period_ms: i64) {
        if let Some(last) = self.dialogue.iter_mut().rev().find(|e| e.tx == tx)
            && last.text == text
            && !last.closed
        {
            last.count = last.count.saturating_add(1);
            // #60: the QSO pane shows the latest decode's SNR of a repeated message.
            if snr.is_some() {
                last.snr = snr;
            }
            return;
        }
        if self.dialogue.len() == DIALOGUE_MAX {
            self.dialogue.pop_front();
        }
        self.dialogue.push_back(Exchanged {
            tx,
            text: text.to_owned(),
            snr,
            period_ms,
            count: 1,
            closed: false,
        });
    }
    /// WstxContact::TxWatchdog: the Rep of the transmitted `text`, 0 when the next
    /// transmission of it opens a new entry.
    fn repetitions(&self, text: &str) -> u32 {
        self.dialogue
            .iter()
            .rev()
            .find(|e| e.tx)
            .filter(|e| e.text == text && !e.closed)
            .map_or(0, |e| e.count)
    }
    fn heard(&mut self, row: &Row, period_ms: i64) {
        let snr = row.snr_db.map(|s| s.round() as i32);
        self.exchanged(false, &row.text, snr, period_ms);
        let count = match &self.last_rcvd {
            Some(h) if h.text == row.text => h.count.saturating_add(1),
            _ => 1,
        };
        self.last_rcvd = Some(Heard {
            text: row.text.clone(),
            snr: row.snr_db.map(|s| s.round() as i32),
            period_ms,
            count,
        });
    }
    /// WstxContact::LogRecord start time (MW set_dateTimeQSO).
    pub fn start_utc_ms(&self) -> Option<i64> {
        self.first_tx2_period
            .or_else(|| self.first_tx3_period.map(|p| p - period_ms(self.mode)))
            .or(self.first_tx_period)
    }
}
/// Why a contact is handed to the log (WstxContact::DirectLog).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogKind {
    /// The contact completed (once per contact).
    Completion,
    /// The operator's Log QSO.
    LogQso,
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
    /// #39: the command comes from station automation (WstxMcp::OperatingAutomation),
    /// not from an operator: it never resets the Tx watchdog.
    pub automatic: bool,
}
impl Ctx {
    /// The whole profile locator (at least 4 characters), upper case: the messages send its
    /// first four, Tx2/Tx3 of eu_vhf its first six (EuVhfExchange, #99).
    fn grid(&self) -> Option<String> {
        self.locator
            .as_deref()
            .filter(|l| l.len() >= 4 && l.is_ascii())
            .map(str::to_ascii_uppercase)
    }
    fn mode(&self) -> Mode {
        self.mode.unwrap_or(Mode::Ft8)
    }
}
// One command per request, moved once: boxing its row would buy nothing.
#[allow(clippy::large_enum_variant)]
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
    /// #39 Abort QSO (Esc): Cancel, and the current transmission stops now.
    Abort,
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
    SetCallFirst(bool),
    /// set_activity (GridExchangeContest) with its ContestExchange exchange.
    SetContest {
        activity: Activity,
        exchange: Option<String>,
    },
    SetWatchdogs {
        tx_calls: u32,
        tune_seconds: u32,
    },
    /// Enable Tx on/off; Some(revision) is the CL-022 safety revision the operator saw.
    EnableTx(bool, Option<u64>),
    Tune(bool),
    Redecode,
    OpenLog,
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
    /// WstxStrategy::StrategyWatchdog: the strategy run's own contact, which sends past the
    /// Tx watchdog limit, and the repetitions left before LeaveRule leaves it (WD:n; None while
    /// no count applies). Set by the station before every step.
    pub repeat_exempt: Option<(String, Option<u32>)>,
    /// Contacts due for the log (completed, or Log QSO), taken by the station.
    to_log: Vec<(LogKind, Contact)>,
    /// The last request target refused without a disarm, never resubmitted as is.
    refused_target: Option<(i64, String, u32)>,
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
    /// The own CQ that station automation started: its callers are chosen by the
    /// automation strategy, never by Call 1st (WstxContact::CallFirst).
    automatic_cq: Option<String>,
    /// FT4 TU; (ContestExchange, MW ~9783): the start of the last transmission and the
    /// time the last partner RR73 was counted.
    last_tx_start_ms: Option<i64>,
    last_rr73_ms: Option<i64>,
    /// HoundOperation (#24 S4b): the HoundTransmissionPolicy state and its timers.
    pub hound: Hound,
    /// The random calling offset of ClassicTxStart: a value in lo..hi.
    pub random_hz: Box<dyn FnMut(u32, u32) -> u32 + Send>,
    /// The field of the last refused command, when its refusal names one (EuVhfExchange:
    /// locator, callsign, dx_call, serial; #99).
    pub refusal_field: Option<&'static str>,
}
/// A refusal code with its field.
type Refused = (&'static str, Option<&'static str>);
/// HoundTransmissionPolicy ReplyState.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum HoundReply {
    #[default]
    None,
    Pending,
    Sent,
}
/// HoundOperation state: the policy state (reply, Fox frequency), the period the last
/// ClassicTxStart decision was taken for, the reply timeout and when the operator last
/// turned Enable Tx on (the Hound watchdog, MW m_tAutoOn).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Hound {
    pub reply: HoundReply,
    pub fox_hz: Option<u32>,
    planned_period: Option<i64>,
    reply_deadline: Option<i64>,
    armed_at: Option<i64>,
}
/// MW guiUpdate Hound watchdog (HWD): Tx1 calling ends this long after Enable Tx went on.
pub const HOUND_WATCHDOG_MS: i64 = 300_000;
/// A uniform value in lo..hi from a time-seeded xorshift (QRandomGenerator stand-in).
fn time_random() -> Box<dyn FnMut(u32, u32) -> u32 + Send> {
    let mut x = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0x9E37_79B9_7F4A_7C15, |d| d.as_nanos() as u64)
        | 1;
    Box::new(move |lo, hi| {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        lo + (x % u64::from(hi.saturating_sub(lo).max(1))) as u32
    })
}
/// The Fox's message to my call (HoundOperation received rows).
enum FoxMessage {
    Report(i32),
    Rr73,
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
            to_log: Vec::new(),
            refused_target: None,
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
            automatic_cq: None,
            repeat_exempt: None,
            last_tx_start_ms: None,
            last_rr73_ms: None,
            hound: Hound::default(),
            random_hz: time_random(),
            refusal_field: None,
        }
    }
    /// The refusal `code`, remembering its field.
    fn refuse(&mut self, (code, field): Refused) -> Result<(), &'static str> {
        self.refusal_field = field;
        Err(code)
    }
    /// EuVhfExchange (#99): why `activity`'s Tx2/Tx3 to `dx` cannot be generated (the
    /// 37-character limit bounds the two hashed calls to 16 characters together); the
    /// pair refusal names `pair_field`. None outside eu_vhf or when it can be generated.
    fn eu_vhf_refusal(
        &self,
        ctx: &Ctx,
        activity: Activity,
        dx: Option<&str>,
        pair_field: Option<&'static str>,
    ) -> Option<Refused> {
        if activity != Activity::EuVhf {
            return None;
        }
        if ctx.grid().is_none_or(|l| l.len() < 6) {
            return Some(("profile_incomplete", Some("locator")));
        }
        let my = ctx.call.as_deref()?;
        if my.len() > 11 {
            return Some(("invalid_call", Some("callsign")));
        }
        let dx = dx?;
        if dx.len() > 11 || dx.len() + my.len() > 16 {
            return Some(("invalid_call", pair_field));
        }
        if !(1..=2047).contains(&self.settings.serial) {
            return Some(("out_of_range", Some("serial")));
        }
        None
    }
    /// The active contact's DX call (the partner whose messages a command regenerates).
    fn active_dx(&self) -> Option<String> {
        self.contact
            .as_ref()
            .filter(|c| c.state.active())
            .and_then(|c| c.dx_call.clone())
    }
    fn is_hound(&self) -> bool {
        self.settings.activity == Activity::Hound
    }
    /// The contacts due for the log since the last call (WstxContact::DirectLog).
    pub fn take_logs(&mut self) -> Vec<(LogKind, Contact)> {
        std::mem::take(&mut self.to_log)
    }
    /// The Tx offset domain: the transmitting contact's mode, else the station's.
    fn tx_max(&self, ctx: &Ctx) -> u32 {
        tx_max_hz(
            self.contact
                .as_ref()
                .filter(|c| c.state.transmits())
                .map_or(ctx.mode(), |c| c.mode),
        )
    }
    /// WstxContact::ModeChange: a calling or active contact of another mode than the
    /// station's operating mode is cancelled with Enable Tx off; the Tx offset is kept
    /// inside the station mode's domain.
    fn follow_mode<H: Hardware>(&mut self, core: Option<&mut Core<H>>, ctx: &Ctx) {
        let Some(mode) = ctx.mode else {
            return;
        };
        // HoundOperation: Hound is FT8 only (MW on_actionFT4_triggered sets none).
        if mode == Mode::Ft4 && self.is_hound() {
            self.settings.activity = Activity::None;
            self.hound = Hound::default();
            if let Some(c) = self.contact.as_mut() {
                c.activity = Activity::None;
            }
        }
        self.settings.tx_hz = self.settings.tx_hz.min(tx_max_hz(mode));
        let Some(c) = self.contact.as_mut() else {
            return;
        };
        if c.mode == mode || !c.state.transmits() {
            return;
        }
        Self::disarm(core, DisarmCause::ContactCancelled);
        c.state = if c.state == State::Calling {
            State::Idle
        } else {
            State::Cancelled
        };
        c.dx_call = None;
        c.dx_grid = None;
        c.dialogue.clear();
        for message in &mut c.messages[..5] {
            *message = None;
        }
        c.next = Slot::Tx6;
        self.pending = None;
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
        let (Some(call), Some(locator)) = (ctx.call.clone(), ctx.grid()) else {
            return Err("profile_incomplete");
        };
        // EuVhfExchange: no contact starts whose Tx2/Tx3 cannot be packed (#99).
        if let Some(refused) =
            self.eu_vhf_refusal(ctx, self.settings.activity, Some(dx.as_str()), None)
        {
            return self.refuse(refused);
        }
        // The same partner in the other mode is a different contact (ContactMode).
        let same = self
            .contact
            .as_ref()
            .is_some_and(|c| c.dx_call.as_deref() == Some(dx.as_str()) && c.mode == mode);
        let active = self.contact.as_ref().is_some_and(|c| c.state.active());
        // A report already sent to the same active partner stays: another SNR on a click
        // must not make a new message, whose Rep would restart the Tx watchdog.
        let report_sent = self
            .contact
            .as_ref()
            .filter(|_| active && same)
            .is_some_and(|c| {
                [Slot::Tx2, Slot::Tx3].iter().any(|slot| {
                    c.messages[slot.index()]
                        .as_deref()
                        .is_some_and(|m| c.dialogue.iter().any(|e| e.tx && e.text == m))
                })
            });
        let report = if report_sent {
            self.settings.report
        } else {
            report
        };
        // The same active partner keeps the chosen Tx4 form.
        let tx4 = self
            .contact
            .as_ref()
            .filter(|_| active && same)
            .map_or_else(|| tx4_default(mode), |c| c.tx4);
        let mut messages = self
            .generate(&call, &locator, Some(&dx), report, tx4)
            .ok_or("invalid_call")?;
        // A text already sent to the same active partner stays, also when it was edited:
        // regenerating it would make a new message, whose Rep restarts the Tx watchdog.
        if let Some(c) = self.contact.as_ref().filter(|_| active && same) {
            for (new, old) in messages.iter_mut().zip(&c.messages) {
                if let Some(old) = old
                    && c.dialogue.iter().any(|e| e.tx && e.text == *old)
                {
                    *new = Some(old.clone());
                }
            }
        }
        // Re-selecting a decoded row of the same partner without a grid (e.g. their
        // report) keeps the grid already known, as WSJT-X keeps its DX Grid (#11); a
        // manual entry sets exactly the grid entered.
        let grid = grid.or_else(|| {
            self.contact
                .as_ref()
                .filter(|_| same && origin == Origin::DecodedRow)
                .and_then(|c| c.dx_grid.clone())
        });
        if active && !same && !replace {
            return Err("contact_active");
        }
        // Re-preparing the same active partner keeps its contact identity.
        let id = match self.contact.as_ref().filter(|_| active && same) {
            Some(c) => c.id.clone(),
            None => {
                // HoundOperation: the reply state and its timeout belong to one contact.
                self.hound.reply = HoundReply::None;
                self.hound.reply_deadline = None;
                (self.new_id)().ok_or("storage_unavailable")?
            }
        };
        // ChangeContact (#50): the old contact is replaced and Enable Tx keeps its state;
        // submit() replaces the old contact's pending request with the new one.
        let _ = core;
        let tx1_skip = self.tx1_disabled();
        let first = if first == Slot::Tx1 && tx1_skip {
            Slot::Tx2
        } else {
            first
        };
        let state = State::of_slot(first);
        // The same active partner keeps its dialogue: its Rep is the Tx watchdog's count.
        let dialogue = self
            .contact
            .as_mut()
            .filter(|_| active && same)
            .map_or_else(VecDeque::new, |c| std::mem::take(&mut c.dialogue));
        self.contact = Some(Contact {
            id,
            origin,
            mode,
            dx_call: Some(dx),
            dx_grid: grid,
            report,
            report_rcvd: None,
            report_sent: None,
            exchange_sent: None,
            exchange_rcvd: None,
            activity: self.settings.activity,
            state,
            next: first,
            tx4,
            messages,
            started_tx1_skipped: tx1_skip && first == Slot::Tx2,
            prepared_utc_ms: ctx.now_utc_ms,
            first_tx_period: None,
            first_tx2_period: None,
            first_tx3_period: None,
            last_counted_end: None,
            logged_on_completion: false,
            suggested: None,
            last_rcvd: None,
            dialogue,
        });
        self.settings.report = report;
        Ok(())
    }
    /// StandardMessageSet with this boot's activity, exchange and serial.
    fn generate(
        &self,
        call: &str,
        locator: &str,
        dx: Option<&str>,
        report: i32,
        tx4: Tx4,
    ) -> Option<[Option<String>; 6]> {
        let s = &self.settings;
        generate_contest(
            call,
            locator,
            dx,
            report,
            tx4,
            s.activity,
            s.exchange.as_deref(),
            s.serial,
        )
    }
    /// WSJT-X disables Tx1 in every contest activity (MW ~8190) as Skip Tx1 does, except
    /// in eu_vhf (MW ~8203, #99). A Hound never skips Tx1 (MW elide_tx1_not_allowed).
    fn tx1_disabled(&self) -> bool {
        let a = self.settings.activity;
        !self.is_hound() && (self.settings.tx1_skip || (a.contest_like() && a != Activity::EuVhf))
    }
    /// ContestExchange: a contact handed to the log for the first time counts the serial.
    fn count_serial(&mut self) {
        if self.settings.activity.contest_like() {
            self.settings.serial = self.settings.serial.saturating_add(1);
        }
    }
    /// EuVhfExchange (#99): a command that regenerates the active contact's messages is
    /// refused, changing nothing, while its Tx2/Tx3 cannot be generated.
    fn check_regeneration(&mut self, ctx: &Ctx, activity: Activity) -> Result<(), &'static str> {
        let dx = self.active_dx();
        match dx.and_then(|dx| self.eu_vhf_refusal(ctx, activity, Some(&dx), Some("callsign"))) {
            Some(refused) => self.refuse(refused),
            None => Ok(()),
        }
    }
    fn regenerate(&mut self, ctx: &Ctx) {
        let (Some(call), Some(grid)) = (ctx.call.clone(), ctx.grid()) else {
            return;
        };
        let set = self
            .contact
            .as_ref()
            .and_then(|c| self.generate(&call, &grid, c.dx_call.as_deref(), c.report, c.tx4));
        if let (Some(c), Some(set)) = (self.contact.as_mut(), set) {
            c.messages[1..4].clone_from_slice(&set[1..4]);
        }
    }
    /// After an accepted selection of `row`: Rx follows the row, Tx too unless held, to me
    /// or a Hound; the parity is the row's opposite; the row is never counted again.
    fn follow_selection(&mut self, row: &Row, to_me: bool, hound: bool) {
        let rx = (row.frequency_hz.round().max(0.0) as u32).min(RX_MAX_HZ);
        let mode = row.mode;
        self.settings.rx_hz = rx;
        // A Hound selection never moves the Tx offset (DMR ~330).
        if !hound && !self.settings.hold_tx && !to_me && (TX_MIN_HZ..=tx_max_hz(mode)).contains(&rx)
        {
            self.settings.tx_hz = rx;
        }
        if let Some(p) = row.period_start_ms.filter(|_| !hound) {
            self.settings.parity = match transmit::parity(mode, p) {
                Parity::Even => Parity::Odd,
                Parity::Odd => Parity::Even,
            };
        }
        // The selected row itself is never counted again as a received message.
        if let Some(p) = row.period_start_ms {
            self.count(row.key.clone(), (p, row.text.clone()));
        }
    }
    /// SelectDecodedRow of an EU VHF row (EuVhfExchange, #99): while eu_vhf is set and its
    /// 'from' is filled in, the DX call is that call and the grid its locator; addressed to
    /// me (by the 12-bit hash of my call) it starts with Tx3 (Tx4 after R) and sets
    /// exchange_rcvd (D7), otherwise it replies with Tx1.
    fn select_vhf<H: Hardware>(
        &mut self,
        core: Option<&mut Core<H>>,
        ctx: &Ctx,
        row: Row,
        replace: bool,
    ) -> Result<(), &'static str> {
        let v = row.vhf.as_deref().ok_or("row_not_standard")?.clone();
        if self.settings.activity != Activity::EuVhf {
            return Err("row_not_standard");
        }
        let Call::Hashed(dx) = &v.from else {
            return Err("row_not_standard");
        };
        let my = ctx.call.clone().ok_or("profile_incomplete")?;
        let to_me = v.to_me(&my);
        let first = match (to_me, v.ack) {
            (true, false) => Slot::Tx3,
            (true, true) => Slot::Tx4,
            (false, _) => first_slot(false, Received::Other, self.tx1_disabled()),
        };
        let report = row.snr_db.map_or(self.settings.report, report_from_snr);
        self.prepare(
            core,
            ctx,
            Origin::DecodedRow,
            dx.clone(),
            Some(v.grid.clone()),
            report,
            first,
            replace,
            row.mode,
        )?;
        self.follow_selection(&row, to_me, false);
        if to_me && let Some(c) = self.contact.as_mut() {
            c.exchange_rcvd = Some(v.exchange());
            if let Some(p) = row.period_start_ms {
                c.last_counted_end = Some(p + period_ms(row.mode));
                c.heard(&row, p);
            }
        }
        Ok(())
    }
    /// Applies one accepted-or-refused operating command. Ok means accepted (the caller
    /// advances the revision); a refusal changes nothing.
    pub fn command<H: Hardware>(
        &mut self,
        command: Command,
        mut core: Option<&mut Core<H>>,
        ctx: &Ctx,
    ) -> Result<(), &'static str> {
        self.follow_mode(core.as_deref_mut(), ctx);
        let capability = core
            .as_ref()
            .map_or(Capability::Unsupported, |c| c.view().capability);
        let abort = matches!(command, Command::Abort);
        self.refusal_field = None;
        match command {
            // EuVhfExchange (#99): an EU VHF row, selectable only while eu_vhf is set.
            Command::SelectRow { row, replace } if row.standard.is_none() && row.vhf.is_some() => {
                self.select_vhf(core.as_deref_mut(), ctx, row, replace)?;
            }
            Command::SelectRow { row, replace } => {
                let Some(std) = row.standard.clone() else {
                    return Err("row_not_standard");
                };
                let Some(dx) = std.from.call().map(str::to_owned) else {
                    return Err("row_not_standard");
                };
                let hound = self.is_hound();
                // HoundOperation: select a Fox at :00 or :30 (MW ~9143), never another
                // Hound's R+report (DMR ~304).
                if hound
                    && (row.mode != Mode::Ft8
                        || row
                            .period_start_ms
                            .is_some_and(|p| p.div_euclid(1000).rem_euclid(30) == 15)
                        || (std.ack && matches!(std.exchange, Exchange::Report(_))))
                {
                    return Err("state_conflict");
                }
                let my = ctx.call.clone().ok_or("profile_incomplete")?;
                let to_me = std.to.call() == Some(my.as_str());
                let received = classify_in(&std, self.settings.activity);
                let report = row.snr_db.map_or(self.settings.report, report_from_snr);
                let grid = match &std.exchange {
                    Exchange::Grid(g) if valid_grid(g) => Some(g.clone()),
                    _ => None,
                };
                let first = match first_slot(to_me, received, self.tx1_disabled()) {
                    // A Hound transmits only Tx1 or Tx3 (MW ~7783).
                    Slot::Tx3 => Slot::Tx3,
                    _ if hound => Slot::Tx1,
                    slot => slot,
                };
                let mode = row.mode;
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
                self.follow_selection(&row, to_me, hound);
                // FT4 RTTY Roundup: the operator's selection right after an RR73 thanks the
                // previous partner with "TU; " in Tx3 (MW genStdMsgs ~9783).
                let tu = mode == Mode::Ft4
                    && self.settings.activity == Activity::Rtty
                    && !ctx.automatic
                    && self
                        .last_tx_start_ms
                        .is_some_and(|t| (ctx.now_utc_ms - t) / 1000 < 15)
                    && self
                        .last_rr73_ms
                        .is_some_and(|t| (ctx.now_utc_ms - t) / 1000 < 3);
                if tu
                    && let Some(c) = self.contact.as_mut()
                    && let Some(tx3) = c.messages[2].as_ref()
                {
                    let text = format!("TU; {tx3}");
                    if generated_text(&text).as_deref() == Some(text.as_str()) {
                        c.messages[2] = Some(text);
                    }
                }
                if to_me && let Some(c) = self.contact.as_mut() {
                    if let Exchange::Report(r) = std.exchange {
                        c.report_rcvd = Some(r.clamp(REPORT_MIN, REPORT_MAX));
                    }
                    if let Exchange::Contest(_, text) = &std.exchange
                        && matches!(received, Received::SignalReport | Received::RogerReport)
                    {
                        c.exchange_rcvd = Some(text.clone());
                    }
                    if let Some(p) = row.period_start_ms {
                        c.last_counted_end = Some(p + period_ms(mode));
                        c.heard(&row, p);
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
                // The DX call must give a message set with my call (StandardMessageSet).
                if generate(&my, "AA00", Some(&dx), self.settings.report, Tx4::Rrr).is_none() {
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
            Command::Cancel | Command::Abort => {
                if abort {
                    if let Some(core) = core.as_deref_mut() {
                        core.abort(DisarmCause::ContactCancelled);
                    }
                } else {
                    Self::disarm(core.as_deref_mut(), DisarmCause::ContactCancelled);
                }
                if let Some(c) = self.contact.as_mut() {
                    if c.state == State::Completed {
                        // A completed contact keeps its fields (Log QSO can re-log it);
                        // only Tx6 is selected.
                        c.next = Slot::Tx6;
                        self.pending = None;
                        if let Some(core) = core.filter(|_| !ctx.automatic) {
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
                    c.dialogue.clear();
                    for i in 0..5 {
                        c.messages[i] = None;
                    }
                    c.next = Slot::Tx6;
                }
                self.pending = None;
            }
            Command::ChooseNext(slot) => {
                if self.is_hound() && !matches!(slot, Slot::Tx1 | Slot::Tx3) {
                    return Err("state_conflict");
                }
                let disabled = self.tx1_disabled();
                let c = self.contact.as_mut().ok_or("no_contact")?;
                let slot = if slot == Slot::Tx1 && disabled {
                    Slot::Tx2
                } else {
                    slot
                };
                if c.messages[slot.index()].is_none() {
                    return Err("invalid_message");
                }
                c.next = slot;
                c.suggested = None;
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
                let normalized = slot_text(&text).ok_or("invalid_message")?;
                c.messages[slot.index()] = Some(normalized);
            }
            Command::SetReport(report) => {
                if !(REPORT_MIN..=REPORT_MAX).contains(&report) {
                    return Err("invalid_report");
                }
                self.check_regeneration(ctx, self.settings.activity)?;
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
                let c = self.contact.as_ref().ok_or("no_contact")?;
                if c.mode == Mode::Ft4 && form != Tx4::Rr73 {
                    return Err("out_of_range");
                }
                self.check_regeneration(ctx, self.settings.activity)?;
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
            Command::SetParity(parity) => {
                // HoundOperation: Tx even/1st is forced off (MW ~11352).
                if self.is_hound() && parity != Parity::Odd {
                    return Err("state_conflict");
                }
                self.settings.parity = parity;
            }
            Command::SetAutoSeq(enabled) => self.settings.auto_seq = enabled,
            Command::SetCallFirst(enabled) => self.settings.call_first = enabled,
            Command::SetContest { activity, exchange } => {
                let exchange =
                    contest_exchange(activity, exchange.as_deref()).ok_or("invalid_exchange")?;
                if activity == Activity::Hound && ctx.mode() != Mode::Ft8 {
                    return Err("state_conflict");
                }
                // EuVhfExchange (#99): a 6-character locator, a callsign of at most 11
                // characters, and an active contact whose Tx2/Tx3 can be packed.
                let dx = self.active_dx();
                if let Some(refused) =
                    self.eu_vhf_refusal(ctx, activity, dx.as_deref(), Some("dx_call"))
                {
                    return self.refuse(refused);
                }
                if activity == Activity::Hound {
                    // MW ~11352: Tx even/1st off, Hold Tx on, Tx1 unless Tx3.
                    self.settings.parity = Parity::Odd;
                    self.settings.hold_tx = true;
                    if let Some(c) = self.contact.as_mut()
                        && c.state.active()
                        && c.next != Slot::Tx3
                    {
                        c.next = Slot::Tx1;
                        c.state = State::Replying;
                    }
                }
                if activity != self.settings.activity {
                    self.hound = Hound::default();
                }
                self.settings.activity = activity;
                self.settings.exchange = exchange;
                // The current contact follows the activity (its messages and log fields).
                if let Some(c) = self.contact.as_mut() {
                    c.activity = activity;
                }
                self.regenerate(ctx);
                // The CQ message follows the activity (genCQMsg m_cqStr).
                let set = match (ctx.call.as_deref(), ctx.grid(), self.contact.as_ref()) {
                    (Some(call), Some(grid), Some(c)) => {
                        self.generate(call, &grid, None, c.report, c.tx4)
                    }
                    _ => None,
                };
                if let (Some(c), Some(set)) = (self.contact.as_mut(), set) {
                    c.messages[5].clone_from(&set[5]);
                }
            }
            Command::SetWatchdogs {
                tx_calls,
                tune_seconds,
            } => {
                // #39: only the operator in the browser may change the watchdogs; an MCP
                // or automation source could otherwise lengthen a spent watchdog.
                if ctx.automatic {
                    return Err("operator_required");
                }
                if !(1..=99).contains(&tx_calls) || !(1..=300).contains(&tune_seconds) {
                    return Err("out_of_range");
                }
                let core = core.as_deref_mut().ok_or("transmit_unavailable")?;
                core.set_watchdogs(tx_calls, tune_seconds)
                    .map_err(|_| "out_of_range")?;
            }
            Command::EnableTx(false, _) => {
                Self::disarm(core.as_deref_mut(), DisarmCause::Operator);
                self.pending = None;
                // MW on_autoButton_clicked: every Enable Tx click stops the reply timeout.
                self.hound.reply_deadline = None;
            }
            Command::EnableTx(true, shown) => {
                if capability == Capability::Unsupported {
                    return Err("transmit_unavailable");
                }
                let (Some(call), Some(grid)) = (ctx.call.clone(), ctx.grid()) else {
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
                // HoundOperation: a Hound never calls CQ.
                if needs_cq && self.is_hound() {
                    return Err("no_contact");
                }
                let cq = if needs_cq {
                    let set = self
                        .generate(&call, &grid, None, self.settings.report, Tx4::Rrr)
                        .ok_or("profile_incomplete")?;
                    Some((set, (self.new_id)().ok_or("storage_unavailable")?))
                } else {
                    None
                };
                // #39: automation arms only after an operator action this boot and never
                // after a watchdog stop.
                if ctx.automatic && core.watchdog_spent() {
                    return Err("tx_watchdog");
                }
                let was_armed = core.view().arm_state == ArmState::Armed;
                let armed = if ctx.automatic {
                    core.arm_automatic(revision)
                } else {
                    core.arm(revision)
                };
                armed.map_err(|r| match r {
                    TransmitRefusal::NotAuthorized => "stale_revision",
                    other => refusal_code(other),
                })?;
                self.last_arm = ArmState::Armed;
                self.transmit_problem = None;
                self.hound.armed_at = Some(ctx.now_utc_ms);
                self.hound.reply_deadline = None;
                if let Some((messages, id)) = cq {
                    self.automatic_cq = ctx.automatic.then(|| id.clone());
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
                        exchange_sent: None,
                        exchange_rcvd: None,
                        activity: self.settings.activity,
                        state: State::Calling,
                        next: Slot::Tx6,
                        tx4: tx4_default(ctx.mode()),
                        messages,
                        started_tx1_skipped: false,
                        prepared_utc_ms: ctx.now_utc_ms,
                        first_tx_period: None,
                        first_tx2_period: None,
                        first_tx3_period: None,
                        last_counted_end: None,
                        logged_on_completion: false,
                        suggested: None,
                        last_rcvd: None,
                        dialogue: VecDeque::new(),
                    });
                }
                if !ctx.automatic
                    && !was_armed
                    && let Some(last) = self
                        .contact
                        .as_mut()
                        .and_then(|c| c.dialogue.iter_mut().rev().find(|e| e.tx))
                {
                    last.closed = true;
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
                // Log QSO: log this contact now, in any state (DirectLog). An unfinished
                // contact is closed by it (#37): completed, Enable Tx off, nothing queued,
                // and this Log QSO is its only record.
                let c = self.contact.as_mut().ok_or("no_contact")?;
                if c.dx_call.is_none() {
                    return Err("no_contact");
                }
                if c.state.active() {
                    c.logged_on_completion = true;
                    self.complete(core.as_deref_mut(), ctx.now_utc_ms);
                    self.count_serial();
                } else if !c.logged_on_completion {
                    self.count_serial();
                }
                let c = self.contact.as_ref().expect("checked");
                self.to_log.push((LogKind::LogQso, c.clone()));
            }
        }
        // A human was seen (WstxContact::TxWatchdog); automation is no operator (#39).
        if let Some(core) = core {
            if !ctx.automatic {
                core.activity();
            }
            self.report_repetitions(core);
        }
        Ok(())
    }
    fn complete<H: Hardware>(&mut self, core: Option<&mut Core<H>>, now: i64) {
        Self::disarm(core, DisarmCause::ContactCompleted);
        self.pending = None;
        self.hound.reply_deadline = None;
        if let Some(c) = self.contact.as_mut() {
            c.state = State::Completed;
            c.next = Slot::Tx6;
            if c.last_counted_end.is_none() {
                c.last_counted_end = Some(now);
            }
            // A contact without a partner (an own CQ ended by a free-text Tx5, #24 S1b)
            // has nothing to log.
            if !c.logged_on_completion && c.dx_call.is_some() {
                c.logged_on_completion = true;
                self.to_log.push((LogKind::Completion, c.clone()));
                self.count_serial();
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
        self.follow_mode(core.as_deref_mut(), ctx);
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
                        self.last_tx_start_ms = Some(submitted.period);
                        // planClassicTxStart: a pending first reply is sent once it starts.
                        if mine
                            && self.settings.activity == Activity::Hound
                            && self.hound.reply == HoundReply::Pending
                        {
                            self.hound.reply = HoundReply::Sent;
                        }
                        if mine && let Some(c) = self.contact.as_mut() {
                            c.exchanged(true, &submitted.text, None, submitted.period);
                            c.first_tx_period.get_or_insert(submitted.period);
                            if submitted.slot == Slot::Tx2 {
                                c.first_tx2_period.get_or_insert(submitted.period);
                            }
                            if submitted.slot == Slot::Tx3 {
                                c.first_tx3_period.get_or_insert(submitted.period);
                            }
                            // A contest Tx2/Tx3 carries my grid, not a report (#24 S2a).
                            if matches!(submitted.slot, Slot::Tx2 | Slot::Tx3)
                                && matches!(
                                    self.settings.activity,
                                    Activity::None | Activity::Hound
                                )
                            {
                                c.report_sent = Some(submitted.report);
                            }
                            // ContestExchange: xSent is the last two words of Tx2 (MW ~8012),
                            // also in EU VHF (#99, MW ~8008).
                            if matches!(submitted.slot, Slot::Tx2 | Slot::Tx3)
                                && (c.activity.contest().is_some() || c.activity == Activity::EuVhf)
                                && let Some(tx2) = &c.messages[1]
                            {
                                let words = tx2.split(' ').collect::<Vec<_>>();
                                if words.len() > 3 {
                                    c.exchange_sent = Some(words[words.len() - 2..].join(" "));
                                }
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
                    OutcomeKind::Halted | OutcomeKind::Aborted => {
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
        let hound = self.is_hound();
        if hound {
            self.hound_rows(core.as_deref_mut(), ctx, rows);
        }
        // Received messages (DMR planProcessMessage, planAutoSequence); a Hound has its
        // own reactions instead (MW calls auto_sequence only outside FT8 Hound).
        for row in rows.iter().filter(|_| !hound) {
            let Some(c) = self.contact.as_ref() else {
                break;
            };
            let Some(dx) = c.dx_call.clone() else {
                continue;
            };
            // Only rows of the contact's own mode count (ContactMode isolation).
            if row.mode != c.mode || !c.state.active() {
                continue;
            }
            let Some(my) = ctx.call.clone() else {
                continue;
            };
            // EuVhfExchange (#99): an EU VHF message counts only in eu_vhf, by the hash of
            // my call and of the DX call, never by the call the table filled in.
            if let Some(v) = row.vhf.as_deref() {
                if self.settings.activity == Activity::EuVhf && v.to_me(&my) && v.sent_by(&dx) {
                    let received = if v.ack {
                        Received::RogerReport
                    } else {
                        Received::SignalReport
                    };
                    self.counted(core.as_deref_mut(), now, row, received, |c| {
                        c.exchange_rcvd = Some(v.exchange());
                        c.dx_grid = Some(v.grid.clone());
                    });
                }
                continue;
            }
            let Some(std) = row.standard.as_ref() else {
                continue;
            };
            if std.from.call() != Some(dx.as_str()) {
                continue;
            }
            match std.to.call() {
                Some(to) if to == my => {
                    let received = classify_in(std, self.settings.activity);
                    let counted = self.counted(core.as_deref_mut(), now, row, received, |c| {
                        if let Exchange::Report(r) = std.exchange {
                            c.report_rcvd = Some(r.clamp(REPORT_MIN, REPORT_MAX));
                        }
                        if let Exchange::Contest(_, text) = &std.exchange
                            && matches!(received, Received::SignalReport | Received::RogerReport)
                        {
                            c.exchange_rcvd = Some(text.clone());
                        }
                    });
                    if counted && std.exchange == Exchange::Rr73 {
                        self.last_rr73_ms = Some(ctx.now_utc_ms);
                    }
                }
                Some(_) => {
                    let c = self.contact.as_ref().expect("checked");
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
                        // Normal flow never halts (WstxTransmit::TransmitHaltUse): the
                        // transmission on top of the partner's QSO stops by an abort.
                        if view.transmitting {
                            core.abort(DisarmCause::Operator);
                        } else if view.arm_state == ArmState::Armed {
                            core.disarm(DisarmCause::Operator);
                        }
                        self.pending = None;
                    }
                }
                None => {}
            }
        }
        self.call_first(core.as_deref_mut(), ctx, rows);
        self.hound_timeouts(core.as_deref_mut(), now);
        // Arm transitions: halt and watchdog expiry end a CQ; other states are kept.
        if let Some(core) = core.as_deref_mut() {
            let view = core.view();
            if self.last_arm == ArmState::Armed && view.arm_state == ArmState::Disarmed {
                self.pending = None;
                // A Hound returns to Tx1 when the Tx watchdog expires (MW ~14664).
                if self.is_hound()
                    && view.tx_expired
                    && let Some(c) = self.contact.as_mut()
                    && c.state.active()
                {
                    c.next = Slot::Tx1;
                    c.state = State::Replying;
                }
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
            self.report_repetitions(core);
        }
        let fingerprint = self.fingerprint(core.as_deref());
        if fingerprint != self.fingerprint {
            self.fingerprint = fingerprint;
            self.revision += 1;
            return true;
        }
        false
    }
    /// A partner message to my call (receivedFromPartner): counted once, in the partner's
    /// period; `apply` takes its fields; then AutoSequence (or, with Auto Seq off, the
    /// suggestion). Returns whether it was counted.
    fn counted<H: Hardware>(
        &mut self,
        core: Option<&mut Core<H>>,
        now: i64,
        row: &Row,
        received: Received,
        apply: impl FnOnce(&mut Contact),
    ) -> bool {
        let Some(period) = row.period_start_ms else {
            return false;
        };
        // Decoded in the partner's period (the parity opposite to mine).
        if transmit::parity(row.mode, period) == self.settings.parity {
            return false;
        }
        if !self.count(row.key.clone(), (period, row.text.clone())) {
            return false;
        }
        let auto = self.settings.auto_seq;
        let Some(c) = self.contact.as_mut() else {
            return false;
        };
        c.heard(row, period);
        apply(c);
        c.last_counted_end = Some(
            c.last_counted_end
                .unwrap_or(i64::MIN)
                .max(period + period_ms(row.mode)),
        );
        if !auto {
            // Auto Seq off: nothing changes, but the step Auto Seq would take
            // is offered (e.g. Tx5 after an RR73), never silently dropped.
            if let Some(next) = transition(c.state, received)
                .filter(|s| *s != State::Completed && s.slot() != c.next)
            {
                c.suggested = Some(next.slot());
            }
            return true;
        }
        c.suggested = None;
        if let Some(next) = transition(c.state, received) {
            if next == State::Completed {
                self.complete(core, now);
            } else {
                c.state = next;
                c.next = next.slot();
            }
        }
        true
    }
    /// WstxContact::CallFirst (#10, MW readFromStdout cbFirst): while my own CQ runs
    /// with Auto Seq and Call 1st on, the first row of this step in decode order that
    /// calls me with a grid or a report (not R+report, RRR, RR73 or 73) is answered as a
    /// selection of that row (Enable Tx unchanged, not operator activity).
    fn call_first<H: Hardware>(&mut self, mut core: Option<&mut Core<H>>, ctx: &Ctx, rows: &[Row]) {
        if !self.settings.call_first || !self.settings.auto_seq {
            return;
        }
        let Some(c) = self.contact.as_ref() else {
            return;
        };
        if c.state != State::Calling || self.automatic_cq.as_ref() == Some(&c.id) {
            return;
        }
        // WSJT-X opens the respond period only while Enable Tx is on (observePeriod).
        if core
            .as_ref()
            .is_none_or(|core| core.view().arm_state != ArmState::Armed)
        {
            return;
        }
        let (Some(my), Some(mode)) = (ctx.call.as_deref(), ctx.mode) else {
            return;
        };
        let parity = self.settings.parity;
        let mut ordered: Vec<&Row> = rows.iter().collect();
        ordered.sort_by_key(|r| r.key.sequence);
        let callers: Vec<Row> = ordered
            .into_iter()
            .filter(|row| {
                let Some(std) = row.standard.as_ref() else {
                    return false;
                };
                row.mode == mode
                && std.to == Call::Sign(my.to_owned())
                && matches!(std.from, Call::Sign(_))
                // AutoRespondPeriod.cpp isDirectAutoRespondCandidate: an exchange that is
                // not a continuing one (R+report, RRR, RR73, 73), i.e. a grid or a report.
                && matches!(
                    classify_in(std, self.settings.activity),
                    Received::Grid | Received::SignalReport
                )
                && row
                    .period_start_ms
                    .is_some_and(|p| transmit::parity(row.mode, p) != parity)
                && !self.counted_rows.contains(&row.key)
            })
            .cloned()
            .collect();
        let automatic = Ctx {
            automatic: true,
            ..ctx.clone()
        };
        // A refusal (e.g. an incomplete profile, or in eu_vhf a pair of calls too long
        // for Tx3, #99) leaves the CQ running and goes on to the next caller.
        for row in callers {
            let selected = self.command(
                Command::SelectRow {
                    row,
                    replace: false,
                },
                core.as_deref_mut(),
                &automatic,
            );
            if selected.is_ok() {
                break;
            }
        }
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
                v.tx_remaining_calls,
                v.tune_remaining_seconds
            )
        });
        format!(
            "{:?}|{:?}|{:?}|{:?}|{:?}|{:?}",
            self.settings, self.contact, self.to_log, self.transmit_problem, view, self.last_arm
        )
    }
    /// Keeps exactly one pending request for the next period of the contact's parity
    /// with the current next text and Tx offset (WstxContact::TransmitSubmission).
    fn submit<H: Hardware>(&mut self, core: &mut Core<H>, ctx: &Ctx) {
        let hound = self.is_hound();
        let Some(c) = self.contact.as_mut() else {
            return;
        };
        if !c.state.transmits() {
            return;
        }
        // A Hound transmits only Tx1 or Tx3 (MW ~7783).
        if hound && !matches!(c.next, Slot::Tx1 | Slot::Tx3) {
            c.next = Slot::Tx1;
            c.state = State::Replying;
        }
        let Some(text) = c.messages[c.next.index()].clone() else {
            return;
        };
        let now = ctx.now_utc_ms;
        let mode = c.mode;
        let next = c.next;
        // WstxContact::TxWatchdog: nothing is planned for a send beyond the limit; a
        // partner message may still change the next message until 1.2 s into its period.
        // A request still pending would key, so it stops at once; after the Nth send none is.
        if c.repetitions(&text) >= core.tx_limit()
            && self.repeat_exempt.as_ref().map(|e| &e.0) != Some(&c.id)
        {
            let due = self.last_started_period.map_or(now, |p| {
                transmit::next_period(mode, p + period_ms(mode), self.settings.parity)
            });
            if self.pending.is_some() || now >= due + WATCHDOG_STOP_AFTER_DUE_MS {
                core.watchdog_stop();
            }
            return;
        }
        let floor = self
            .last_started_period
            .map_or(now + LEAD_MS, |p| (now + LEAD_MS).max(p + period_ms(mode)));
        let period = transmit::next_period(mode, floor, self.settings.parity);
        if hound && !core.view().tune && self.hound.planned_period != Some(period) {
            self.hound.planned_period = Some(period);
            self.classic_tx_start(next, mode);
        }
        let Some(c) = self.contact.as_ref() else {
            return;
        };
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

impl Engine {
    /// HoundTransmissionPolicy planClassicTxStart for a newly planned request: a Tx1 below
    /// 999 Hz calls at a random 1000..2998 Hz; a Tx3 after a sent first reply goes to
    /// Fox+300 Hz (Fox at or below 600 Hz) or Fox-300 Hz.
    fn classic_tx_start(&mut self, next: Slot, mode: Mode) {
        if next != Slot::Tx3 && self.settings.tx_hz < 999 {
            self.settings.tx_hz = (self.random_hz)(1000, 2999).clamp(1000, 2998);
        }
        if self.hound.reply == HoundReply::Sent
            && next == Slot::Tx3
            && let Some(fox) = self.hound.fox_hz
        {
            let hz = if fox <= 600 { fox + 300 } else { fox - 300 };
            if (TX_MIN_HZ..=tx_max_hz(mode)).contains(&hz) {
                self.settings.tx_hz = hz;
            }
        }
    }
    /// HoundOperation received rows: the Fox's report (standard, or the report slot of a
    /// 0.1 message carrying the DX call's hash) is FoxReportReply; its RR73 (standard, or
    /// the RR73 slot of such a 0.1 message) completes the contact.
    fn hound_rows<H: Hardware>(&mut self, mut core: Option<&mut Core<H>>, ctx: &Ctx, rows: &[Row]) {
        let Some(my) = ctx.call.clone() else {
            return;
        };
        let mine = |call: &Call| call.call() == Some(my.as_str());
        for row in rows {
            let Some(c) = self.contact.as_ref() else {
                break;
            };
            let Some(dx) = c.dx_call.clone() else {
                continue;
            };
            let Some(period) = row.period_start_ms else {
                continue;
            };
            if row.mode != c.mode
                || !c.state.active()
                || transmit::parity(row.mode, period) == self.settings.parity
            {
                continue;
            }
            let fox = |call: &Call| call.call() == Some(dx.as_str());
            let message = if let Some(d) = &row.dxpedition {
                if !fox(&d.fox) {
                    continue;
                }
                if mine(&d.rr73_to) {
                    FoxMessage::Rr73
                } else if mine(&d.report_to) {
                    FoxMessage::Report(d.report)
                } else {
                    continue;
                }
            } else if let Some(std) = &row.standard {
                if !fox(&std.from) || !mine(&std.to) {
                    continue;
                }
                match std.exchange {
                    Exchange::Rr73 => FoxMessage::Rr73,
                    Exchange::Report(r) if !std.ack => FoxMessage::Report(r),
                    _ => continue,
                }
            } else {
                continue;
            };
            if !self.count(row.key.clone(), (period, row.text.clone())) {
                continue;
            }
            let c = self.contact.as_mut().expect("checked");
            c.heard(row, period);
            c.last_counted_end = Some(
                c.last_counted_end
                    .unwrap_or(i64::MIN)
                    .max(period + period_ms(row.mode)),
            );
            match message {
                FoxMessage::Rr73 => self.complete(core.as_deref_mut(), ctx.now_utc_ms),
                FoxMessage::Report(r) => self.fox_report(core.as_deref(), ctx, row, r),
            }
        }
    }
    /// HoundTransmissionPolicy planFoxReportReply (MW hound_reply): the Fox frequency is
    /// noted; unless Tune is on, Tx3 with the Fox decode's SNR on the Fox's frequency, the
    /// first reply pending and the reply timeout of 11 T/R periods.
    fn fox_report<H: Hardware>(&mut self, core: Option<&Core<H>>, ctx: &Ctx, row: &Row, rcvd: i32) {
        let fox_hz = row.frequency_hz.round().max(0.0) as u32;
        self.hound.fox_hz = Some(fox_hz);
        if core.is_some_and(|core| core.view().tune) {
            return;
        }
        let report = row.snr_db.map_or(self.settings.report, report_from_snr);
        self.settings.report = report;
        let Some(c) = self.contact.as_mut() else {
            return;
        };
        let mode = c.mode;
        c.report_rcvd = Some(rcvd.clamp(REPORT_MIN, REPORT_MAX));
        c.report = report;
        c.next = Slot::Tx3;
        c.state = State::RogerReport;
        c.suggested = None;
        self.regenerate(ctx);
        if (TX_MIN_HZ..=tx_max_hz(mode)).contains(&fox_hz) {
            self.settings.tx_hz = fox_hz;
        }
        self.hound.reply = HoundReply::Pending;
        self.hound.reply_deadline = Some(ctx.now_utc_ms + 11 * period_ms(mode));
    }
    /// The Rep of the message due next (WstxContact::TxWatchdog).
    pub fn repetitions_due(&self) -> u32 {
        self.contact.as_ref().map_or(0, |c| {
            c.messages[c.next.index()]
                .as_deref()
                .map_or(0, |text| c.repetitions(text))
        })
    }
    /// WstxStrategy::StrategyWatchdog: the run's own contact is in a contest stay (no count: the
    /// snapshot's tx_remaining_calls is null, WD:∞).
    pub fn staying(&self) -> bool {
        self.repeat_exempt
            .as_ref()
            .is_some_and(|e| e.1.is_none() && self.contact.as_ref().is_some_and(|c| c.id == e.0))
    }
    /// tx_remaining_calls (limit - reported) reads the Rep of the message due next; a strategy
    /// run's own contact has no stop and counts down to the repetition at which LeaveRule
    /// leaves it (WstxStrategy::StrategyWatchdog).
    fn report_repetitions<H: Hardware>(&self, core: &mut Core<H>) {
        core.report_tx_repetitions(self.repetitions_due());
        let remaining = self
            .repeat_exempt
            .as_ref()
            .filter(|e| self.contact.as_ref().is_some_and(|c| c.id == e.0))
            .and_then(|e| e.1);
        core.report_tx_remaining(remaining);
    }
    /// The reply timeout (MW stopWRTimeout) and the Hound watchdog (HWD) turn Enable Tx off.
    fn hound_timeouts<H: Hardware>(&mut self, core: Option<&mut Core<H>>, now: i64) {
        if !self.is_hound() {
            return;
        }
        let Some(core) = core else {
            return;
        };
        let reply = self.hound.reply_deadline.is_some_and(|t| now >= t);
        if reply {
            self.hound.reply_deadline = None;
        }
        let calling = self
            .contact
            .as_ref()
            .is_some_and(|c| c.state.active() && c.next == Slot::Tx1);
        let watchdog = calling
            && self
                .hound
                .armed_at
                .is_some_and(|t| now - t >= HOUND_WATCHDOG_MS);
        if (reply || watchdog) && core.view().arm_state == ArmState::Armed {
            core.disarm(DisarmCause::TxWatchdog);
            self.pending = None;
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

/// A contact's log fields with its server-owned times (LogRecord).
pub struct LogFields {
    pub call: String,
    pub grid: Option<String>,
    pub mode: Mode,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
    /// ContestExchange ADIF fields (AdifQso::to_adif), (name, value) in LogRecord order.
    pub contest: Vec<(&'static str, String)>,
}
/// An EU VHF exchange "5nSSSS GRID6" as (RS "5n", serial "SSSS").
fn eu_vhf_exchange(x: &str) -> Option<(&str, &str)> {
    let first = x.split(' ').next()?;
    (first.len() == 6 && first.bytes().all(|b| b.is_ascii_digit())).then(|| first.split_at(2))
}
/// AdifQso::to_adif for the contest exchanges of `activity` (ContestExchange).
pub fn contest_fields(
    activity: Activity,
    sent: Option<&str>,
    rcvd: Option<&str>,
) -> Vec<(&'static str, String)> {
    let serial = |w: &str| w.parse::<u32>().is_ok_and(|n| n > 0);
    let mut out = Vec::new();
    // EU VHF (#99, AdifQso mid(2)): STX and SRX are the four serial digits of "5nSSSS".
    if activity == Activity::EuVhf {
        for (name, x) in [("stx", sent), ("srx", rcvd)] {
            if let Some((_, digits)) = x.and_then(eu_vhf_exchange) {
                out.push((name, digits.to_owned()));
            }
        }
        return out;
    }
    if let Some(x) = sent {
        let w = x.split(' ').collect::<Vec<_>>();
        if w.len() == 2 && serial(w[1]) {
            out.push(("stx", w[1].to_owned()));
        } else if w.len() > 1 {
            out.push(("stx_string", x.to_owned()));
        }
    }
    if let Some(x) = rcvd {
        let w = x.split(' ').collect::<Vec<_>>();
        if w.len() == 2 && serial(w[1]) {
            out.push(("srx", w[1].to_owned()));
        } else if w.len() == 2 && activity == Activity::FieldDay {
            out.push(("contest_id", "ARRL-FIELD-DAY".to_owned()));
            out.push(("srx_string", x.to_owned()));
            out.push(("class", w[0].to_owned()));
            out.push(("arrl_sect", w[1].to_owned()));
        } else if w.len() == 2 && activity == Activity::Rtty {
            out.push(("state", w[1].to_owned()));
        } else if w.len() > 1 {
            out.push(("srx_string", x.to_owned()));
        }
    }
    out
}
impl Contact {
    pub fn log_fields(&self, now_utc_ms: i64) -> Option<LogFields> {
        let c = self;
        let start = c.start_utc_ms().unwrap_or(c.prepared_utc_ms);
        let end = c.last_counted_end.unwrap_or(now_utc_ms).max(start);
        Some(LogFields {
            call: c.dx_call.clone()?,
            grid: c.dx_grid.clone(),
            mode: c.mode,
            // RTTY Roundup logs the 5n9 of each exchange as the RST (logqso.cpp ~396).
            // EU VHF logs the RS actually exchanged, "55" (#99, operator 2026-11-09).
            rst_sent: match (c.activity, &c.exchange_sent) {
                (Activity::Rtty, Some(x)) => x.split(' ').next().map(str::to_owned),
                (Activity::EuVhf, Some(x)) => eu_vhf_exchange(x).map(|(rs, _)| rs.to_owned()),
                _ => c.report_sent.map(render_report),
            },
            rst_rcvd: match (c.activity, &c.exchange_rcvd) {
                (Activity::Rtty, Some(x)) => x.split(' ').next().map(str::to_owned),
                (Activity::EuVhf, Some(x)) => eu_vhf_exchange(x).map(|(rs, _)| rs.to_owned()),
                _ => c.report_rcvd.map(render_report),
            },
            start_utc_ms: start,
            end_utc_ms: end,
            contest: contest_fields(
                c.activity,
                c.exchange_sent.as_deref(),
                c.exchange_rcvd.as_deref(),
            ),
        })
    }
}
