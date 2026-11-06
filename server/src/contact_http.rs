#![forbid(unsafe_code)]
//! WstxContact::ContactWire for the contact engine: GET /contact (ContactSnapshot) and
//! POST /contact/command (ContactCommand, CommandReceipt), the station step of the
//! engine, its direct log (WstxContact::DirectLog, #41) and the contact.state /
//! station.tick WebSocket event payloads. Validation
//! order is WstxOperatingReceive S2: route, Origin, TLS/session, size/media/syntax,
//! version/enums/UUIDs/safe integers, profile, boot/revision, capability, state.
use crate::contact::{
    self, Call, Command, Ctx, Engine, Exchange, Row, RowKey, Slot, Standard, Tx4,
};
use crate::*;
use axum::extract::RawQuery;
use recording_http::authorize;
use selection_http::empty;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use wstx_rust::transmit::Parity;
use wstx_rust::transmit::service::{Core, HaltState, Hardware, View};

pub const SNAPSHOT_BYTES_MAX: usize = 4096;
pub const RECEIPTS: usize = 16;
const MAX_SAFE: u64 = 9_007_199_254_740_991;
/// DirectLog: records kept for retry after a failed write, and the retry interval.
pub const LOG_PENDING_MAX: usize = 64;
const LOG_RETRY: Duration = Duration::from_secs(5);

/// The latest DirectLog attempt as ContactSnapshot log shows it.
#[derive(Clone, Debug, PartialEq)]
struct LogView {
    contact_id: String,
    call: String,
    saved: bool,
    error: Option<&'static str>,
}
struct Inner {
    engine: Engine,
    rows: Option<((String, String, u64), u64)>,
    receipts: VecDeque<(String, Value, Value)>,
    snapshot: (u64, Value),
    /// Records not yet stored (oldest first; one per contact id).
    unlogged: VecDeque<logbook::Record>,
    retry_at: Option<Instant>,
    log: Option<LogView>,
    /// Newly saved records for the UDP targets, sent by the station tick only, after the
    /// station lock is released (a command reached from a UDP Reply holds the UDP lock).
    outbox: Vec<logbook::Record>,
    /// WstxStationDecode::APrioriContext of the next decode window, refreshed every tick.
    a_priori: decoder::APriori,
    /// The last tick (UTC ms) at which the station transmitted, tuned or had Enable Tx on
    /// (WSJT-X m_dateTimeLastTX, refreshed while m_transmitting, m_auto or m_tune).
    last_tx: Option<i64>,
}
/// lapcqonly: without a transmission for this long only the CQ a-priori type runs.
const CQ_ONLY_AFTER_MS: i64 = 300_000;
/// The contact engine of one station (one per process, like the transmit owner).
pub(crate) struct Station {
    inner: Mutex<Inner>,
    revision: AtomicU64,
    started: Instant,
    /// WstxMcp::OperatingAutomation of this station (drives this engine only through
    /// the ContactCommand path).
    pub(crate) automation: crate::automation::Owner,
    /// WstxStrategy store of this station (#39), read on first use.
    pub(crate) strategy: crate::strategy::Owner,
    /// Test seam only: stands in for the CL-022 grant a plaintext test router lacks.
    #[cfg(test)]
    pub(crate) grant: std::sync::atomic::AtomicBool,
}
type Tx = Core<Box<dyn Hardware>>;

fn refusal(code: &str, field: Option<&str>) -> Response {
    let status = match code {
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "forbidden_origin" | "wrong_profile" => StatusCode::FORBIDDEN,
        "not_found" => StatusCode::NOT_FOUND,
        "request_too_large" => StatusCode::PAYLOAD_TOO_LARGE,
        "unsupported_media_type" => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        "invalid_request"
        | "unsupported_version"
        | "row_not_standard"
        | "invalid_call"
        | "invalid_grid"
        | "invalid_report"
        | "invalid_message"
        | "out_of_range" => StatusCode::BAD_REQUEST,
        "storage_unavailable" | "snapshot_limit" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::CONFLICT,
    };
    profile_error(status, code, field)
}

fn station_of(r: &recording::Recording) -> Result<Arc<Station>, &'static str> {
    r.contact.get().cloned().ok_or("not_found")
}
/// The profile locator as the station uses it: upper case, None when empty.
pub(crate) fn station_locator(locator: &str) -> Option<String> {
    Some(locator.trim().to_ascii_uppercase()).filter(|l| !l.is_empty())
}
pub(crate) fn profile_facts(state: &ProfileState) -> (Option<String>, Option<String>) {
    let store = state.store.lock().unwrap_or_else(|p| p.into_inner());
    let d = &store.document;
    (
        Some(d.callsign.trim().to_ascii_uppercase()).filter(|c| !c.is_empty()),
        station_locator(&d.locator),
    )
}
/// The selected profile's callsign (upper case), as the contact engine uses it.
pub(crate) fn my_call(state: &ProfileState) -> Option<String> {
    profile_facts(state).0
}
/// What automation reads of the current contact.
pub(crate) struct Facts {
    pub id: String,
    pub state: &'static str,
    pub dx_call: Option<String>,
    pub report_rcvd: Option<i32>,
    pub active: bool,
    /// The engine's own transmit period parity.
    pub parity: Parity,
}
pub(crate) struct StatusFacts {
    pub dx_call: Option<String>,
    pub dx_grid: Option<String>,
    pub report: i32,
    pub rx_hz: u32,
    pub tx_hz: u32,
    pub next_message: Option<String>,
    /// GridExchangeContest (#24 S2a).
    pub activity: contact::Activity,
}
pub(crate) fn mode_of(text: &str) -> decoder::Mode {
    if text == "ft4" {
        decoder::Mode::Ft4
    } else {
        decoder::Mode::Ft8
    }
}
fn call_of(v: &Value) -> Option<Call> {
    match v["kind"].as_str()? {
        "call" => Some(Call::Sign(v["text"].as_str()?.to_owned())),
        "token" => Some(Call::Token(v["text"].as_str()?.to_owned())),
        // A hash the station filled in names its call (HashResolution, #24 S1b).
        "hash" => Some(match v["text"].as_str() {
            Some(t) => Call::Hashed(t.to_owned()),
            None => Call::Hash,
        }),
        _ => None,
    }
}
/// A nonstandard i3=4 record as an engine message (WstxContact::SelectDecodedRow, #24
/// S1b): 'to' and 'from' are the hashed and the full call in hash_second order, a CQ
/// has 'to' CQ, the roger is the exchange (none: blank).
fn nonstandard_of(f: &Value) -> Option<Standard> {
    let full = call_of(&f["full_call"])?;
    let hashed = call_of(&f["hashed_call"])?;
    let exchange = match f["roger"].as_str()? {
        "" => Exchange::Blank,
        "RRR" => Exchange::Rrr,
        "RR73" => Exchange::Rr73,
        "73" => Exchange::SeventyThree,
        _ => return None,
    };
    let (to, from) = if f["cq"].as_bool()? {
        (Call::Token("CQ".into()), full)
    } else if f["hash_second"].as_bool()? {
        (full, hashed)
    } else {
        (hashed, full)
    };
    Some(Standard {
        to,
        from,
        ack: false,
        exchange,
    })
}
/// A Field Day or RTTY Roundup record as an engine message (ContestExchange, #24 S2b):
/// the exchange is its last two words ("6A WI", "579 MA", "559 0013"); TU; is ignored.
fn contest_of(f: &Value) -> Option<Standard> {
    let (kind, text) = match f["type"].as_str()? {
        "field_day" => (
            contact::ContestKind::FieldDay,
            format!(
                "{}{} {}",
                f["transmitters"].as_u64()?,
                f["class"].as_str()?,
                f["section"].as_str()?
            ),
        ),
        "rtty" => {
            let value = match (f["exchange"]["kind"].as_str()?, &f["exchange"]["value"]) {
                ("serial", v) => format!("{:04}", v.as_u64()?),
                ("state", v) => v.as_str()?.to_owned(),
                _ => return None,
            };
            (
                contact::ContestKind::Rtty,
                format!("{} {value}", f["report"].as_u64()?),
            )
        }
        _ => return None,
    };
    Some(Standard {
        to: call_of(&f["to"])?,
        from: call_of(&f["from"])?,
        ack: f["ack"].as_bool()?,
        exchange: Exchange::Contest(kind, text),
    })
}
/// A published live result record as an engine row (WstxOfflineDecode::StandardFields).
pub(crate) fn row_of(record: &Value, identity: &(String, String, u64), mode: &str) -> Option<Row> {
    let f = &record["fields"];
    let nonstandard = (record["status"] == "decoded" && f["type"] == "nonstandard")
        .then(|| nonstandard_of(f))
        .flatten();
    let contest = (record["status"] == "decoded")
        .then(|| contest_of(f))
        .flatten();
    // HoundOperation (#24 S4b): a 0.1 DXpedition record keeps its fields.
    let dxpedition = (record["status"] == "decoded" && f["type"] == "dxpedition")
        .then(|| {
            Some(Box::new(contact::Dxpedition {
                rr73_to: call_of(&f["first"])?,
                report_to: call_of(&f["second"])?,
                fox: call_of(&f["hashed"])?,
                report: i32::try_from(f["report"].as_i64()?).ok()?,
            }))
        })
        .flatten();
    let standard = (record["status"] == "decoded" && f["type"] == "standard")
        .then(|| {
            let exchange = match (f["exchange"]["kind"].as_str()?, &f["exchange"]["value"]) {
                ("grid", v) => Exchange::Grid(v.as_str()?.to_owned()),
                ("report", v) => Exchange::Report(i32::try_from(v.as_i64()?).ok()?),
                ("roger", v) => match v.as_str()? {
                    "RRR" => Exchange::Rrr,
                    "RR73" => Exchange::Rr73,
                    "73" => Exchange::SeventyThree,
                    _ => return None,
                },
                ("blank", _) => Exchange::Blank,
                _ => return None,
            };
            Some(Standard {
                to: call_of(&f["to"])?,
                from: call_of(&f["from"])?,
                ack: f["ack"].as_bool()?,
                exchange,
            })
        })
        .flatten();
    Some(Row {
        key: RowKey {
            source_id: identity.0.clone(),
            job_id: identity.1.clone(),
            generation: identity.2,
            sequence: record["sequence"].as_u64()?,
        },
        mode: mode_of(mode),
        period_start_ms: record["period_start_utc"]
            .as_str()
            .and_then(contact::parse_utc),
        frequency_hz: record["frequency_hz"].as_f64()?,
        snr_db: record["snr_db"].as_f64(),
        text: record["text"].as_str().unwrap_or("").to_owned(),
        standard: standard.or(nonstandard).or(contest),
        dxpedition,
    })
}
pub(crate) fn confirmed_dial(r: &recording::Recording) -> Option<u64> {
    let snapshot = r.radio_actor()?.snapshot().ok()?;
    (snapshot.state == wstx_rust::radio_control::State::Ready && snapshot.facts.frequency.confirmed)
        .then_some(snapshot.facts.frequency.value)
        .flatten()
}

impl Station {
    pub(crate) fn start() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(Inner {
                engine: Engine::new(Box::new(|| profile::new_uuid().ok())),
                rows: None,
                receipts: VecDeque::new(),
                snapshot: (0, Value::Null),
                unlogged: VecDeque::new(),
                retry_at: None,
                log: None,
                outbox: Vec::new(),
                a_priori: decoder::APriori::default(),
                last_tx: None,
            }),
            revision: AtomicU64::new(0),
            started: Instant::now(),
            automation: crate::automation::Owner::default(),
            strategy: crate::strategy::Owner::default(),
            #[cfg(test)]
            grant: std::sync::atomic::AtomicBool::new(false),
        })
    }
    pub(crate) fn revision(&self) -> u64 {
        self.revision.load(Ordering::Acquire)
    }
    /// (contact_revision, current contact, Auto Seq) for WstxMcp::OperatingAutomation.
    pub(crate) fn facts(&self) -> (u64, Option<Facts>, bool) {
        let inner = self.lock();
        let e = &inner.engine;
        let facts = e.contact.as_ref().map(|c| Facts {
            id: c.id.clone(),
            state: c.state.name(),
            dx_call: c.dx_call.clone(),
            report_rcvd: c.report_rcvd,
            active: c.state.active() || c.state == contact::State::Calling,
            parity: e.settings.parity,
        });
        (e.revision, facts, e.settings.auto_seq)
    }
    /// WstxStationDecode::APrioriContext for the next live decode window (#56 slice 5).
    pub(crate) fn a_priori(&self) -> decoder::APriori {
        self.lock().a_priori.clone()
    }
    /// The context from the profile callsign, the current contact and the transmit owner
    /// (lapcqonly after CQ_ONLY_AFTER_MS without transmitting, tuning or Enable Tx).
    fn refresh_a_priori(inner: &mut Inner, call: Option<&str>, active: bool, now: i64) {
        use decoder::QsoProgress as P;
        if active {
            inner.last_tx = Some(now);
        }
        let e = &inner.engine;
        let c = e.contact.as_ref();
        let progress = match c.map(|c| c.state) {
            Some(contact::State::Replying) => P::Replying,
            Some(contact::State::Report) => P::Report,
            Some(contact::State::RogerReport) => P::RogerReport,
            Some(contact::State::Rogers) => P::Rogers,
            Some(contact::State::Signoff | contact::State::Completed) => P::Signoff,
            _ => P::Calling,
        };
        let (my_call, dx_call) = call.map_or((None, None), |call| {
            wstx_rust::transmit::a_priori_calls(call, c.and_then(|c| c.dx_call.as_deref()))
        });
        inner.a_priori = decoder::APriori {
            my_call,
            dx_call,
            progress,
            rx_hz: f64::from(e.settings.rx_hz),
            tx_hz: f64::from(e.settings.tx_hz),
            cq_only: inner.last_tx.is_none_or(|at| now - at > CQ_ONLY_AFTER_MS),
        };
    }
    /// What the WstxUdp Status message reads: (DX call, DX grid, report, Rx Hz, Tx Hz,
    /// the contact's next message).
    pub(crate) fn status_facts(&self) -> StatusFacts {
        let inner = self.lock();
        let e = &inner.engine;
        let c = e.contact.as_ref();
        StatusFacts {
            dx_call: c.and_then(|c| c.dx_call.clone()),
            dx_grid: c.and_then(|c| c.dx_grid.clone()),
            report: c.map_or(e.settings.report, |c| c.report),
            rx_hz: e.settings.rx_hz,
            tx_hz: e.settings.tx_hz,
            next_message: c.and_then(|c| c.messages[c.next.index()].clone()),
            activity: e.settings.activity,
        }
    }
    /// One ContactCommand body through exactly the browser's validation and execution
    /// (WstxContact::ContactCommand) as a browser operator action; `granted` is the
    /// caller's current CL-022 grant. Station code uses `operate_as` with its source.
    #[cfg(test)]
    pub(crate) fn operate(
        &self,
        state: &ProfileState,
        body: Value,
        granted: bool,
    ) -> Result<(StatusCode, Value), Refusal> {
        self.operate_as(state, body, granted, authorization::Principal::Browser)
    }
    /// The ContactCommand path with the request's principal (#58). Every principal that
    /// is not the browser (automation, MCP, UDP) is automatic: it never resets the Tx
    /// watchdog and arms only within the watchdog time of the last browser action (#39).
    pub(crate) fn operate_as(
        &self,
        state: &ProfileState,
        body: Value,
        granted: bool,
        principal: authorization::Principal,
    ) -> Result<(StatusCode, Value), Refusal> {
        let automatic = !principal.is_operator();
        let (command_id, revision, action) = envelope(&body)?;
        let parsed = parse_command(&body, &action)?;
        let r = &state.recording;
        if body["profile_id"] != r.profile.as_str() {
            return Err(("wrong_profile", Some("profile_id")));
        }
        if body["boot_id"] != r.boot.as_str() {
            return Err(("state_conflict", Some("boot_id")));
        }
        self.execute(
            state, body, command_id, revision, &action, parsed, granted, automatic,
        )
    }
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
    fn run<R>(r: &recording::Recording, f: impl FnOnce(Option<&mut Tx>, i64) -> R) -> R {
        match r.transmit.get() {
            Some(t) => t.service.with(|core| {
                let now = core.hardware().now_utc_ms();
                f(Some(core), now)
            }),
            None => f(None, wall_ms()),
        }
    }
    /// One engine step: new live rows, transmit outcomes, arm transitions, submission.
    pub(crate) fn tick(&self, state: &ProfileState) {
        let r = &state.recording;
        let (call, locator) = profile_facts(state);
        let mut guard = self.lock();
        let inner = &mut *guard;
        let cursor = inner.rows.clone();
        let mut rows = Vec::new();
        let mode = Some(mode_of(r.operating_mode()));
        if let Some((identity, live_mode, records)) = r.live_records_after(
            cursor.as_ref().map(|c| &c.0),
            cursor.as_ref().map_or(0, |c| c.1),
        ) {
            let mut next = cursor
                .as_ref()
                .filter(|c| c.0 == identity)
                .map_or(0, |c| c.1);
            for record in &records {
                if let Some(row) = row_of(record, &identity, live_mode) {
                    next = next.max(row.key.sequence + 1);
                    rows.push(row);
                }
            }
            inner.rows = Some((identity, next));
        }
        Self::run(r, |mut core, now| {
            // Belt and braces for WstxTransmit::StationModeGate (set at every change).
            if let Some(c) = core.as_deref_mut() {
                c.set_station_mode(mode);
            }
            let ctx = Ctx {
                call,
                locator,
                now_utc_ms: now,
                granted: false,
                mode,
                automatic: false,
            };
            inner.engine.step(core.as_deref_mut(), &ctx, &rows);
            // HashResolution's DX-call rule reads the current contact's DX call (#24 S1b).
            r.hashes
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .set_dx_call(
                    inner
                        .engine
                        .contact
                        .as_ref()
                        .and_then(|c| c.dx_call.as_deref()),
                );
            let active = core.as_deref().is_some_and(|c| {
                let v = c.view();
                v.transmitting
                    || v.tune
                    || v.arm_state == wstx_rust::transmit::service::ArmState::Armed
            });
            Self::refresh_a_priori(inner, ctx.call.as_deref(), active, now);
            Self::collect_logs(
                inner,
                state,
                now,
                ctx.call.as_deref(),
                ctx.locator.as_deref(),
            );
        });
        Self::store_logs(inner, state);
        let sent = std::mem::take(&mut inner.outbox);
        self.revision
            .store(inner.engine.revision, Ordering::Release);
        drop(guard);
        for record in &sent {
            crate::udp::logged(state, record);
        }
    }
    /// Test seam: ends the retry backoff of failed log writes.
    #[cfg(test)]
    pub(crate) fn retry_logs_now(&self) {
        self.lock().retry_at = None;
    }
    /// The LogRecord of a contact at `now` (WstxContact::DirectLog): FREQ = confirmed
    /// dial + Tx offset, BAND from the dial, MY_GRIDSQUARE the effective locator.
    pub(crate) fn record_of(
        c: &contact::Contact,
        now: i64,
        dial: Option<u64>,
        tx_hz: u32,
        call: &str,
        locator: Option<&str>,
    ) -> Option<logbook::Record> {
        let f = c.log_fields(now)?;
        let contest = f.contest.clone();
        let (mode, submode) = match f.mode {
            decoder::Mode::Ft8 => ("FT8", None),
            decoder::Mode::Ft4 => ("MFSK", Some("FT4")),
        };
        let freq = dial.map(|d| {
            let hz = d + u64::from(tx_hz);
            format!("{}.{:06}", hz / 1_000_000, hz % 1_000_000)
        });
        let mut record = logbook::Record {
            contact_id: c.id.clone(),
            values: [
                Some(f.call),
                f.grid,
                Some(mode.into()),
                submode.map(String::from),
                f.rst_sent,
                f.rst_rcvd,
                Some(contact::adif_date(f.start_utc_ms)),
                Some(contact::adif_time(f.start_utc_ms)),
                Some(contact::adif_date(f.end_utc_ms)),
                Some(contact::adif_time(f.end_utc_ms)),
                dial.and_then(logbook::band_of_hz).map(String::from),
                freq,
                Some(call.to_owned()),
                locator.map(String::from),
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
                None,
            ],
            source: None,
            unknown: Vec::new(),
        };
        for (name, value) in contest {
            record.set(name, value);
        }
        Some(record)
    }
    /// Takes the engine's contacts due for the log into the pending records: a newer
    /// record of a pending contact id replaces it; over LOG_PENDING_MAX the oldest is
    /// dropped (log_queue_full); an invalid record is never stored (log_invalid_field).
    /// A completed contact already logged at completion keeps that record (its dial, Tx
    /// offset and location of completion): Log QSO on it changes nothing.
    fn collect_logs(
        inner: &mut Inner,
        state: &ProfileState,
        now: i64,
        call: Option<&str>,
        locator: Option<&str>,
    ) {
        let contacts = inner.engine.take_logs();
        if contacts.is_empty() {
            return;
        }
        let dial = confirmed_dial(&state.recording);
        let tx_hz = inner.engine.settings.tx_hz;
        for (kind, c) in contacts {
            let held = inner.unlogged.iter().any(|p| p.contact_id == c.id);
            if kind == contact::LogKind::LogQso
                && c.logged_on_completion
                && (held || state.logbook.saved(&c.id))
            {
                continue;
            }
            let view = |error| LogView {
                contact_id: c.id.clone(),
                call: c.dx_call.clone().unwrap_or_default(),
                saved: false,
                error,
            };
            let station = call.unwrap_or("");
            let record = Self::record_of(&c, now, dial, tx_hz, station, locator).filter(|record| {
                logbook::validate_record(record, station, locator.unwrap_or("")).is_ok()
            });
            let Some(record) = record else {
                inner.log = Some(view(Some("log_invalid_field")));
                continue;
            };
            inner.log = Some(view(None));
            inner.unlogged.retain(|p| p.contact_id != record.contact_id);
            if inner.unlogged.len() == LOG_PENDING_MAX
                && let Some(dropped) = inner.unlogged.pop_front()
            {
                inner.log = Some(LogView {
                    call: dropped.get("call").unwrap_or("").to_owned(),
                    contact_id: dropped.contact_id,
                    saved: false,
                    error: Some("log_queue_full"),
                });
            }
            inner.unlogged.push_back(record);
            inner.retry_at = None;
        }
        inner.engine.revision += 1;
    }
    /// Stores the pending records (now, or at the retry time after a failure) under the
    /// station's authorization lock. Only the first store of a contact id goes to the
    /// UDP targets (outbox), so each contact reaches the external programs once.
    fn store_logs(inner: &mut Inner, state: &ProfileState) {
        if inner.unlogged.is_empty() || inner.retry_at.is_some_and(|t| Instant::now() < t) {
            return;
        }
        let gate = |publish: &mut dyn FnMut() -> std::io::Result<()>| {
            let _owner = state
                .authorization
                .lock()
                .map_err(|_| crate::authorization::Error::PersistenceFailed)?;
            Ok(publish())
        };
        while let Some(record) = inner.unlogged.front().cloned() {
            let mut view = LogView {
                contact_id: record.contact_id.clone(),
                call: record.get("call").unwrap_or("").to_owned(),
                saved: true,
                error: None,
            };
            match state.logbook.put(record.clone(), &gate) {
                Ok(outcome) => {
                    inner.unlogged.pop_front();
                    if outcome == logbook::LogOutcome::Saved {
                        inner.outbox.push(record);
                    }
                    inner.log = Some(view);
                }
                Err(_) => {
                    view.saved = false;
                    view.error = Some("storage_unavailable");
                    // A dropped record (log_queue_full) stays shown until a store succeeds.
                    if inner
                        .log
                        .as_ref()
                        .is_none_or(|l| l.error != Some("log_queue_full"))
                    {
                        inner.log = Some(view);
                    }
                    inner.retry_at = Some(Instant::now() + LOG_RETRY);
                    break;
                }
            }
        }
        if inner.unlogged.is_empty() {
            inner.retry_at = None;
        }
        // The stored outcome (contact.saved, log) is a material change of the snapshot.
        inner.engine.revision += 1;
    }
    /// ContactSnapshot: exact keys, at most SNAPSHOT_BYTES_MAX encoded bytes.
    pub(crate) fn snapshot(&self, state: &ProfileState) -> Result<Vec<u8>, &'static str> {
        let r = &state.recording;
        let view = r.transmit.get().map(|t| t.service.view());
        let safety = r
            .transmit
            .get()
            .and_then(|t| t.service.with(|c| c.hardware().context().safety_revision));
        let mut inner = self.lock();
        let e = &inner.engine;
        let now = view.as_ref().map_or_else(wall_ms, |_| {
            r.transmit
                .get()
                .map_or_else(wall_ms, |t| t.service.with(|c| c.hardware().now_utc_ms()))
        });
        let contact = e.contact.as_ref().map(|c| {
            json!({"id":c.id,"origin":c.origin.name(),"dx_call":c.dx_call,"dx_grid":c.dx_grid,
                "report_sent":c.report_sent.map(contact::render_report),"report_rcvd":c.report_rcvd.map(contact::render_report),
                "exchange_sent":c.exchange_sent,"exchange_rcvd":c.exchange_rcvd,
                "state":c.state.name(),"next_slot":c.next.name(),"tx4":c.tx4.name(),"messages":c.messages,
                "start_utc":c.start_utc_ms().map(contact::utc_text),"end_utc":c.last_counted_end.map(contact::utc_text),
                "saved":state.logbook.saved(&c.id),
                "suggested_slot":c.suggested.filter(|_| c.state.active()).map(Slot::name),
                "last_rcvd":c.last_rcvd.as_ref().map(|h| json!({"text":h.text,"snr":h.snr,
                    "period_utc_ms":h.period_ms,"count":h.count})),
                "dialogue":c.dialogue.iter().map(|d| json!({"dir":if d.tx {"tx"} else {"rx"},"text":d.text,
                    "snr":d.snr,"period_utc_ms":d.period_ms,"count":d.count})).collect::<Vec<_>>()})
        });
        let log = inner.log.as_ref().map(|l| {
            json!({"contact_id":l.contact_id,"call":l.call,"outcome":if l.saved {"saved"} else {"unsaved"},"error":l.error})
        });
        let transmit = match &view {
            Some(v) => transmit_view(v, e.transmit_problem.as_deref(), safety),
            None => {
                json!({"capability":"unsupported","arm_state":"disarmed","last_disarm_cause":"startup",
                "tune":false,"pending_sequence":null,"last_text":null,"last_period_utc":null,"halt_state":"idle","safety_revision":null,"refusal":null})
            }
        };
        let s = &e.settings;
        let settings = json!({"auto_seq":s.auto_seq,"call_first":s.call_first,"tx1_skip":s.tx1_skip,
            "tx_calls":view.as_ref().map_or(6,|v|v.tx_calls),"tune_seconds":view.as_ref().map_or(90,|v|v.tune_seconds),
            "rx_hz":s.rx_hz,"tx_hz":s.tx_hz,"hold_tx":s.hold_tx,"parity":parity_name(s.parity),"report":s.report,
            "activity":s.activity.name(),"exchange":s.exchange,"serial":s.serial});
        let watchdog = json!({"tx_remaining_calls":view.as_ref().map_or(0,|v|v.tx_remaining_calls),
            "tx_expired":view.as_ref().is_some_and(|v|v.tx_expired),
            "tune_remaining_seconds":view.as_ref().map_or(0,|v|v.tune_remaining_seconds)});
        let material = json!([transmit, settings, contact, log, watchdog]);
        if inner.snapshot.1 != material {
            inner.snapshot = (inner.snapshot.0 + 1, material);
        }
        let [transmit, settings, contact, log, watchdog] = inner
            .snapshot
            .1
            .as_array()
            .cloned()
            .unwrap_or_default()
            .try_into()
            .unwrap_or_default();
        let value = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"contact_revision":inner.engine.revision,
            "snapshot_sequence":inner.snapshot.0,"monotonic_ms":self.started.elapsed().as_millis() as u64,"utc_ms":now,
            "transmit":transmit,"settings":settings,"contact":contact,"log":log,"watchdog":watchdog});
        admit(&value)
    }
}
/// Never truncated: over the cap is 503 snapshot_limit.
pub(crate) fn admit(value: &Value) -> Result<Vec<u8>, &'static str> {
    let bytes = serde_json::to_vec(value).map_err(|_| "snapshot_limit")?;
    if bytes.len() > SNAPSHOT_BYTES_MAX {
        return Err("snapshot_limit");
    }
    Ok(bytes)
}
fn wall_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}
fn parity_name(p: Parity) -> &'static str {
    match p {
        Parity::Even => "even",
        Parity::Odd => "odd",
    }
}
/// The #9 read view WstxContact::ContactSnapshot carries (refusal: the latest #9
/// refusal, or the contact's last refused/failed transmit outcome).
fn transmit_view(v: &View, problem: Option<&str>, safety_revision: Option<u64>) -> Value {
    let name = |t: String| contact::snake(&t);
    let halt = match v.halt_state {
        HaltState::Idle => "idle",
        HaltState::Pending => "pending",
        HaltState::Stopped => "stopped",
    };
    json!({"capability":name(format!("{:?}",v.capability)),"arm_state":name(format!("{:?}",v.arm_state)),
        "last_disarm_cause":name(format!("{:?}",v.last_disarm_cause)),"tune":v.tune,"pending_sequence":v.pending_sequence,
        "last_text":v.last_text,"last_period_utc":v.last_period_utc_ms,"halt_state":halt,"safety_revision":safety_revision,
        "refusal":v.refusal.map(|r|name(format!("{r:?}"))).or(problem.map(String::from))})
}
pub(crate) fn state_event(r: &recording::Recording, revision: u64) -> String {
    json!({"v":1,"type":"contact.state","data":{"profile_id":r.profile,"boot_id":r.boot,"contact_revision":revision}}).to_string()
}
/// station.tick: (text, transmitting).
pub(crate) fn tick_event(r: &recording::Recording) -> (String, bool) {
    let (utc, transmitting) = r.transmit.get().map_or((wall_ms(), false), |t| {
        t.service
            .with(|c| (c.hardware().now_utc_ms(), c.view().transmitting))
    });
    let period = contact::period_ms(mode_of(r.operating_mode()));
    (
        json!({"v":1,"type":"station.tick","data":{"profile_id":r.profile,"boot_id":r.boot,"utc_ms":utc,
            "period_ms":period,"transmitting":transmitting,"rx_level_db":r.rx_level()}})
        .to_string(),
        transmitting,
    )
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
    let (Ok(s), Some(state)) = (station_of(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    match tokio::task::spawn_blocking(move || s.snapshot(&state)).await {
        Ok(Ok(bytes)) => ([(header::CONTENT_TYPE, "application/json")], bytes).into_response(),
        Ok(Err(e)) => refusal(e, None),
        Err(_) => refusal("storage_unavailable", None),
    }
}

/// Exactly the parameter keys of each ContactAction.
fn params(action: &str) -> Option<&'static [&'static str]> {
    Some(match action {
        "select_row" => &["row", "replace"],
        "enter_dx" => &["dx_call", "dx_grid", "replace"],
        "cancel" | "redecode" | "open_log" => &[],
        "choose_next" => &["slot"],
        "edit_message" => &["slot", "text"],
        "set_report" => &["report"],
        "set_tx1_skip" | "set_hold_tx" | "set_auto_seq" | "set_call_first" | "tune" => &["enabled"],
        "set_activity" => &["activity", "exchange"],
        "enable_tx" => &["enabled", "safety_revision"],
        "set_tx4" => &["form"],
        "set_frequency" => &["rx_hz", "tx_hz"],
        "set_parity" => &["parity"],
        "set_watchdogs" => &["tx_calls", "tune_seconds"],
        _ => return None,
    })
}
pub(crate) type Refusal = (&'static str, Option<&'static str>);
fn boolean(b: &Value, k: &'static str) -> Result<bool, Refusal> {
    b[k].as_bool().ok_or(("invalid_request", Some(k)))
}
fn safe(b: &Value, k: &'static str) -> Result<u64, Refusal> {
    b[k].as_u64()
        .filter(|n| *n <= MAX_SAFE)
        .ok_or(("invalid_request", Some(k)))
}
fn text<'a>(b: &'a Value, k: &'static str) -> Result<&'a str, Refusal> {
    b[k].as_str().ok_or(("invalid_request", Some(k)))
}
fn slot(b: &Value) -> Result<Slot, Refusal> {
    Slot::parse(text(b, "slot")?).ok_or(("invalid_request", Some("slot")))
}
fn hz(b: &Value, k: &'static str) -> Result<Option<u32>, Refusal> {
    if b[k].is_null() {
        return Ok(None);
    }
    let n = safe(b, k)?;
    Ok(Some(u32::try_from(n).unwrap_or(u32::MAX)))
}
/// The typed command of a syntactically valid body (row lookup is done later).
fn parse_command(b: &Value, action: &str) -> Result<Option<Command>, Refusal> {
    Ok(Some(match action {
        "select_row" => {
            let row = &b["row"];
            let keys = ["source_id", "job_id", "generation", "sequence"];
            if !row
                .as_object()
                .is_some_and(|o| o.len() == 4 && keys.iter().all(|k| o.contains_key(*k)))
            {
                return Err(("invalid_request", Some("row")));
            }
            for k in ["source_id", "job_id"] {
                if !row[k].as_str().is_some_and(profile::valid_uuid) {
                    return Err(("invalid_request", Some("row")));
                }
            }
            if safe(row, "generation").is_err() || safe(row, "sequence").is_err() {
                return Err(("invalid_request", Some("row")));
            }
            boolean(b, "replace")?;
            return Ok(None);
        }
        "enter_dx" => {
            let grid = match &b["dx_grid"] {
                Value::Null => None,
                Value::String(g) => Some(g.clone()),
                _ => return Err(("invalid_request", Some("dx_grid"))),
            };
            Command::EnterDx {
                call: text(b, "dx_call")?.to_owned(),
                grid,
                replace: boolean(b, "replace")?,
            }
        }
        "cancel" => Command::Cancel,
        "redecode" => Command::Redecode,
        "open_log" => Command::OpenLog,
        "choose_next" => Command::ChooseNext(slot(b)?),
        "edit_message" => Command::EditMessage(slot(b)?, text(b, "text")?.to_owned()),
        "set_report" => {
            let n = b["report"]
                .as_i64()
                .ok_or(("invalid_request", Some("report")))?;
            Command::SetReport(i32::try_from(n).unwrap_or(i32::MAX))
        }
        "set_tx1_skip" => Command::SetTx1Skip(boolean(b, "enabled")?),
        "set_hold_tx" => Command::SetHoldTx(boolean(b, "enabled")?),
        "set_auto_seq" => Command::SetAutoSeq(boolean(b, "enabled")?),
        "set_call_first" => Command::SetCallFirst(boolean(b, "enabled")?),
        "set_activity" => {
            let activity = b["activity"]
                .as_str()
                .and_then(contact::Activity::parse)
                .ok_or(("invalid_request", Some("activity")))?;
            let exchange = match &b["exchange"] {
                Value::Null => None,
                Value::String(x) => Some(x.as_str()),
                _ => return Err(("invalid_request", Some("exchange"))),
            };
            // ContestExchange (#24 S2b): field_day and rtty need their exchange.
            let exchange = contact::contest_exchange(activity, exchange)
                .ok_or(("invalid_request", Some("exchange")))?;
            Command::SetContest { activity, exchange }
        }
        "enable_tx" => {
            if !b["safety_revision"].is_null() {
                safe(b, "safety_revision")?;
            }
            Command::EnableTx(boolean(b, "enabled")?, b["safety_revision"].as_u64())
        }
        "tune" => Command::Tune(boolean(b, "enabled")?),
        "set_tx4" => Command::SetTx4(match text(b, "form")? {
            "rrr" => Tx4::Rrr,
            "rr73" => Tx4::Rr73,
            _ => return Err(("invalid_request", Some("form"))),
        }),
        "set_frequency" => Command::SetFrequency {
            rx: hz(b, "rx_hz")?,
            tx: hz(b, "tx_hz")?,
        },
        "set_parity" => Command::SetParity(match text(b, "parity")? {
            "even" => Parity::Even,
            "odd" => Parity::Odd,
            _ => return Err(("invalid_request", Some("parity"))),
        }),
        "set_watchdogs" => {
            let m = safe(b, "tx_calls")?;
            let s = safe(b, "tune_seconds")?;
            Command::SetWatchdogs {
                tx_calls: u32::try_from(m).unwrap_or(u32::MAX),
                tune_seconds: u32::try_from(s).unwrap_or(u32::MAX),
            }
        }
        _ => return Err(("invalid_request", Some("action"))),
    }))
}
/// Syntax, version, UUIDs and safe integers; returns (command_id, revision, action).
fn envelope(b: &Value) -> Result<(String, u64, String), Refusal> {
    let object = b.as_object().ok_or(("invalid_request", None))?;
    let action = object
        .get("action")
        .and_then(Value::as_str)
        .ok_or(("invalid_request", Some("action")))?;
    let extra = params(action).ok_or(("invalid_request", Some("action")))?;
    let base = [
        "v",
        "profile_id",
        "boot_id",
        "command_id",
        "contact_revision",
        "action",
    ];
    if let Some(k) = object
        .keys()
        .find(|k| !base.contains(&k.as_str()) && !extra.contains(&k.as_str()))
    {
        let _ = k;
        return Err(("invalid_request", None));
    }
    // set_activity's exchange is optional (ContestExchange, #24 S2b).
    let optional = |k: &str| action == "set_activity" && k == "exchange";
    if let Some(k) = base
        .iter()
        .chain(extra)
        .find(|k| !object.contains_key(**k) && !optional(k))
    {
        return Err(("invalid_request", Some(k)));
    }
    if b["v"].as_u64() != Some(1) {
        return Err(if b["v"].is_u64() {
            ("unsupported_version", Some("v"))
        } else {
            ("invalid_request", Some("v"))
        });
    }
    for k in ["profile_id", "boot_id", "command_id"] {
        if !b[k].as_str().is_some_and(profile::valid_uuid) {
            return Err(("invalid_request", Some(k)));
        }
    }
    let revision = safe(b, "contact_revision")?;
    Ok((
        text(b, "command_id")?.to_owned(),
        revision,
        action.to_owned(),
    ))
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
    if let Err((c, f)) = envelope(&body).and_then(|(_, _, action)| parse_command(&body, &action)) {
        return refusal(c, f);
    }
    if body["profile_id"] != r.profile.as_str() {
        return refusal("wrong_profile", Some("profile_id"));
    }
    if body["boot_id"] != r.boot.as_str() {
        return refusal("state_conflict", Some("boot_id"));
    }
    // Transmit authority needs a current CL-022 grant (selected HTTPS profile). The
    // principal comes from the credential (#58): an MCP client's transport is never the
    // browser, whichever route carried it; an unreadable one is never an operator.
    let access = authorization_http::operating_access_async(&headers, &app).await;
    #[allow(unused_mut)]
    let mut granted = matches!(access, Ok(Some(_)));
    let principal = match &access {
        Ok(Some(a)) => a.principal,
        Ok(None) => authorization::Principal::Browser,
        Err(_) => authorization::Principal::Automation,
    };
    let (Ok(station), Some(state)) = (station_of(&r), app.profile.clone()) else {
        return refusal("not_found", None);
    };
    #[cfg(test)]
    {
        granted |= station.grant.load(Ordering::Acquire);
    }
    // #39: only a human action in the browser is an operator action for the Tx
    // watchdog; an MCP tool call runs like automation (no reset, arms only within it).
    let outcome =
        tokio::task::spawn_blocking(move || station.operate_as(&state, body, granted, principal))
            .await;
    match outcome {
        Ok(Ok((status, reply))) => (status, Json(reply)).into_response(),
        Ok(Err((c, f))) => refusal(c, f),
        Err(_) => refusal("storage_unavailable", None),
    }
}

impl Station {
    #[allow(clippy::too_many_arguments)]
    fn execute(
        &self,
        state: &ProfileState,
        body: Value,
        command_id: String,
        revision: u64,
        action: &str,
        parsed: Option<Command>,
        granted: bool,
        automatic: bool,
    ) -> Result<(StatusCode, Value), Refusal> {
        let r = &state.recording;
        let (call, locator) = profile_facts(state);
        let mut guard = self.lock();
        let inner = &mut *guard;
        if let Some((_, prior, receipt)) =
            inner.receipts.iter().find(|(id, _, _)| *id == command_id)
        {
            return if *prior == body {
                Ok((StatusCode::OK, receipt.clone()))
            } else {
                Err(("state_conflict", Some("command_id")))
            };
        }
        let current = inner.engine.revision;
        let relaxed = action == "cancel"
            || (matches!(action, "enable_tx" | "tune") && body["enabled"] == false);
        if revision > current || (revision != current && !relaxed) {
            return Err(("stale_revision", Some("contact_revision")));
        }
        if current >= MAX_SAFE {
            return Err(("counter_exhausted", None));
        }
        // Enable Tx carries the CL-022 safety revision the operator saw in the snapshot;
        // a different current revision is the stale-revision refusal.
        if action == "enable_tx" && body["enabled"] == true {
            let current_safety = r
                .transmit
                .get()
                .and_then(|t| t.service.with(|c| c.hardware().context().safety_revision));
            if current_safety.is_some() && body["safety_revision"].as_u64() != current_safety {
                return Err(("stale_revision", Some("safety_revision")));
            }
        }
        let command = match parsed {
            Some(c) => c,
            None => {
                let row = &body["row"];
                let (source, job) = (
                    row["source_id"].as_str().unwrap_or(""),
                    row["job_id"].as_str().unwrap_or(""),
                );
                let (generation, sequence) = (
                    row["generation"].as_u64().unwrap_or(0),
                    row["sequence"].as_u64().unwrap_or(0),
                );
                let (record, mode) = r
                    .live_record(source, job, generation, sequence)
                    .ok_or(("row_unavailable", Some("row")))?;
                let identity = (source.to_owned(), job.to_owned(), generation);
                let row =
                    row_of(&record, &identity, mode).ok_or(("row_not_standard", Some("row")))?;
                Command::SelectRow {
                    row,
                    replace: body["replace"] == true,
                }
            }
        };
        let mode = Some(mode_of(r.operating_mode()));
        Self::run(r, |mut core, now| {
            let ctx = Ctx {
                call,
                locator,
                now_utc_ms: now,
                granted,
                mode,
                automatic,
            };
            inner
                .engine
                .command(command, core.as_deref_mut(), &ctx)
                .map_err(|code| {
                    let field = match code {
                        "stale_revision" => Some("safety_revision"),
                        "out_of_range" if action == "set_tx4" => Some("form"),
                        _ => None,
                    };
                    (code, field)
                })?;
            // An accepted command always advances the revision; the immediate step
            // folds its own consequences (a new pending request) into the receipt.
            inner.engine.revision += 1;
            inner.engine.step(core, &ctx, &[]);
            Self::collect_logs(
                inner,
                state,
                now,
                ctx.call.as_deref(),
                ctx.locator.as_deref(),
            );
            Ok::<_, Refusal>(())
        })?;
        // Log QSO is stored before its receipt (a failed write stays pending, retried);
        // its UDP messages leave with the next station tick.
        Self::store_logs(inner, state);
        let revision = inner.engine.revision;
        self.revision.store(revision, Ordering::Release);
        let receipt = json!({"v":1,"profile_id":r.profile,"boot_id":r.boot,"command_id":command_id,
            "contact_revision":revision,"accepted":true});
        if inner.receipts.len() == RECEIPTS {
            inner.receipts.pop_front();
        }
        inner
            .receipts
            .push_back((command_id, body, receipt.clone()));
        Ok((StatusCode::ACCEPTED, receipt))
    }
}

/// The station-wide contact step (main.rs timer, every 50 ms).
pub(crate) fn station_tick(state: &ProfileState) {
    if let Some(s) = state.recording.contact.get() {
        // Read before the contact step: the engine then has every record of it.
        let publication = state.recording.latest_publication();
        // #42 IgnoreLists: a station band change empties the session list before Auto.
        s.strategy
            .observe_band(crate::strategy::station_band(&state.recording));
        // #42 Alert: every new live decode once, whether or not a browser is connected.
        s.strategy.alert_step(state);
        s.tick(state);
        s.automation.tick(s, state, publication);
    }
}
