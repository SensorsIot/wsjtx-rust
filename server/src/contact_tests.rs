#![forbid(unsafe_code)]
// Proves: CL-010-01, CL-010-02, CL-010-03, CL-010-04, CL-010-10, CL-010-12; TC-007-001, TC-008-001, TC-011-001.
// (#24 S4b: CL-024-04; TC-024-011, TC-024-014, the classic Hound.)
// (#41 DirectLog: the contacts the engine hands to the log.)
// The contact engine against the actual #9 transmit owner core (`Core`) on a virtual
// UTC clock with a recording hardware double (no audio, PTT or radio). Decoded rows are
// hand-authored; expected states, next slots and texts are the independent table of
// TC-007-001 written below, not engine output.
use crate::contact::*;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicI64, Ordering},
};
use wstx_rust::decoder::Mode;
use wstx_rust::transmit::service::{
    ArmState, AudioError, AudioPoll, Capability, Context, Core, DisarmCause, Hardware, Program,
    PttError, PttState,
};
use wstx_rust::transmit::{ClockState, Parity};

const P0: i64 = 1_800_000_000_000; // an even FT8 period (multiple of 30 s)
const SECOND: i64 = 1000;

/// Waveform plays: (UTC start, 48 kHz samples, first sample played).
type Plays = Vec<(i64, Arc<[f32]>, usize)>;
#[derive(Default)]
struct Bench {
    now: AtomicI64,
    capability: Mutex<Option<Capability>>,
    keys: Mutex<Vec<(i64, bool)>>,
    playing: Mutex<Option<(i64, usize)>>,
    /// Every waveform play: (UTC start, samples played).
    plays: Mutex<Vec<(i64, usize)>>,
    /// The device reports the end this long after the last sample was due (#49).
    late_ms: AtomicI64,
    /// Every waveform play's audio: (UTC start, 48 kHz samples, first sample played).
    audio: Mutex<Plays>,
}
#[derive(Clone)]
struct Fake(Arc<Bench>);
impl Hardware for Fake {
    fn now_utc_ms(&self) -> i64 {
        self.0.now.load(Ordering::SeqCst)
    }
    fn clock(&self) -> ClockState {
        ClockState::Synchronized
    }
    fn context(&self) -> Context {
        let capability = self
            .0
            .capability
            .lock()
            .unwrap()
            .unwrap_or(Capability::Available);
        Context {
            capability,
            safety_revision: (capability == Capability::Available).then_some(7),
            radio_transmitting: Some(false),
        }
    }
    fn ptt(&mut self, on: bool) -> Result<(), PttError> {
        let t = self.now_utc_ms();
        self.0.keys.lock().unwrap().push((t, on));
        Ok(())
    }
    fn open_audio(&mut self) -> Result<(), AudioError> {
        Ok(())
    }
    fn play(&mut self, program: Program) -> Result<(), AudioError> {
        let waveform = matches!(program, Program::Waveform { .. });
        if let Program::Waveform { samples, skip } = &program {
            let at = self.now_utc_ms();
            self.0
                .audio
                .lock()
                .unwrap()
                .push((at, samples.clone(), *skip));
        }
        let remaining = match program {
            Program::Waveform { samples, skip } => samples.len() - skip,
            Program::Tone { .. } => usize::MAX / 2,
        };
        *self.0.playing.lock().unwrap() = Some((self.now_utc_ms(), remaining));
        if waveform {
            self.0
                .plays
                .lock()
                .unwrap()
                .push((self.now_utc_ms(), remaining));
        }
        Ok(())
    }
    fn poll_audio(&mut self) -> AudioPoll {
        match *self.0.playing.lock().unwrap() {
            Some((at, n))
                if (self.now_utc_ms() - at - self.0.late_ms.load(Ordering::SeqCst)) * 48
                    >= n as i64 =>
            {
                AudioPoll::Finished
            }
            Some(_) => AudioPoll::Playing,
            None => AudioPoll::Idle,
        }
    }
    fn stop_audio(&mut self) {
        *self.0.playing.lock().unwrap() = None;
    }
    fn audio_stopper(&self) -> Arc<dyn Fn() + Send + Sync> {
        Arc::new(|| {})
    }
}

struct Station {
    fake: Fake,
    core: Core<Fake>,
    engine: Engine,
    sequence: u64,
    /// The station's operating mode (Ctx.mode) and the mode of the rows it decodes.
    mode: Mode,
    /// Texts whose audio started, with their period start.
    sent: Vec<(i64, String)>,
    /// The Tx offset of each started transmission (the engine's setting at its start).
    sent_hz: Vec<(i64, u32)>,
    /// The profile callsign (Ctx.call).
    call: String,
}
/// The one contact handed to the log since the last check (WstxContact::DirectLog).
fn one_entry(s: &mut Station) -> (LogKind, Contact) {
    let mut logs = s.engine.take_logs();
    assert_eq!(logs.len(), 1, "exactly one contact for the log: {logs:?}");
    logs.pop().unwrap()
}
fn one_log(s: &mut Station) -> Contact {
    one_entry(s).1
}
fn station() -> Station {
    let fake = Fake(Arc::new(Bench::default()));
    fake.0.now.store(P0 + 2 * SECOND, Ordering::SeqCst);
    let mut ids = 0u32;
    Station {
        core: Core::new(fake.clone()),
        fake,
        engine: Engine::new(Box::new(move || {
            ids += 1;
            Some(format!("00000000-0000-4000-8000-{ids:012}"))
        })),
        sequence: 0,
        mode: Mode::Ft8,
        sent: Vec::new(),
        sent_hz: Vec::new(),
        call: "HB9BLA".into(),
    }
}
/// Hand-authored standard row "TO FROM EXCHANGE" decoded at `hz` in `period`.
fn parse(text: &str) -> Standard {
    let words: Vec<_> = text.split(' ').collect();
    let call = |w: &str| {
        if w == "CQ" {
            Call::Token(w.into())
        } else if w == "<...>" {
            Call::Hash
        } else {
            Call::Sign(w.into())
        }
    };
    let (ack, exchange) = match words.get(2).copied() {
        None => (false, Exchange::Blank),
        Some("RRR") => (false, Exchange::Rrr),
        Some("RR73") => (false, Exchange::Rr73),
        Some("73") => (false, Exchange::SeventyThree),
        Some(w) if w.starts_with('R') && w.len() > 1 && !w.as_bytes()[1].is_ascii_alphabetic() => {
            (true, Exchange::Report(w[1..].parse().unwrap()))
        }
        Some(w) if w.starts_with(['+', '-']) => (false, Exchange::Report(w.parse().unwrap())),
        Some(w) => (false, Exchange::Grid(w.into())),
    };
    Standard {
        to: call(words[0]),
        from: call(words[1]),
        ack,
        exchange,
    }
}
impl Station {
    fn now(&self) -> i64 {
        self.fake.0.now.load(Ordering::SeqCst)
    }
    fn ctx(&self) -> Ctx {
        Ctx {
            call: Some(self.call.clone()),
            locator: Some("JN47AA".into()),
            now_utc_ms: self.now(),
            granted: true,
            mode: Some(self.mode),
            automatic: false,
        }
    }
    fn row(&mut self, period: i64, text: &str, hz: f64, snr: Option<f64>) -> Row {
        self.sequence += 1;
        Row {
            key: RowKey {
                source_id: "s".into(),
                job_id: "j".into(),
                generation: 1,
                sequence: self.sequence,
            },
            mode: self.mode,
            period_start_ms: Some(period),
            frequency_hz: hz,
            snr_db: snr,
            text: text.into(),
            standard: Some(parse(text)),
            dxpedition: None,
        }
    }
    fn command(&mut self, command: Command) -> Result<(), &'static str> {
        let ctx = self.ctx();
        let result = self.engine.command(command, Some(&mut self.core), &ctx);
        self.step(&[]);
        result
    }
    fn step(&mut self, rows: &[Row]) {
        let ctx = self.ctx();
        self.engine.step(Some(&mut self.core), &ctx, rows);
    }
    /// Advances the virtual clock: the transmit owner ticks every 10 ms, the engine
    /// every 50 ms (as the station timer does).
    fn run(&mut self, until: i64) {
        let mut t = self.now();
        while t < until {
            t = (t + 10).min(until);
            self.fake.0.now.store(t, Ordering::SeqCst);
            let before = self.core.view().last_text.clone();
            let last = self.core.view().last_period_utc_ms;
            self.core.tick();
            let view = self.core.view();
            if view.last_period_utc_ms != last
                || (view.last_text != before && view.last_text.is_some())
            {
                self.sent.push((
                    view.last_period_utc_ms.unwrap(),
                    view.last_text.clone().unwrap(),
                ));
                self.sent_hz
                    .push((view.last_period_utc_ms.unwrap(), self.engine.settings.tx_hz));
            }
            if t % 50 == 0 {
                self.step(&[]);
            }
        }
    }
    fn deliver(&mut self, rows: &[Row]) {
        self.step(rows);
    }
    fn state(&self) -> (State, Slot) {
        let c = self.engine.contact.as_ref().unwrap();
        (c.state, c.next)
    }
    fn next_text(&self) -> String {
        let c = self.engine.contact.as_ref().unwrap();
        c.messages[c.next.index()].clone().unwrap()
    }
    fn armed(&self) -> bool {
        self.core.view().arm_state == ArmState::Armed
    }
    fn sent_in(&self, period: i64) -> Option<String> {
        self.sent
            .iter()
            .find(|(p, _)| *p == period)
            .map(|(_, t)| t.clone())
    }
}
fn period(n: i64) -> i64 {
    P0 + n * 15 * SECOND
}

#[test]
fn selecting_a_cq_row_prepares_the_independent_message_set_without_any_request() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(c.dx_call.as_deref(), Some("K1ABC"));
    assert_eq!(c.dx_grid.as_deref(), Some("FN42"));
    assert_eq!(render_report(c.report), "-12");
    assert_eq!(
        (s.engine.settings.rx_hz, s.engine.settings.tx_hz),
        (1235, 1235)
    );
    assert_eq!(s.engine.settings.parity, Parity::Odd);
    assert_eq!((c.state, c.next), (State::Replying, Slot::Tx1));
    let expected = [
        "K1ABC HB9BLA JN47",
        "K1ABC HB9BLA -12",
        "K1ABC HB9BLA R-12",
        "K1ABC HB9BLA RRR",
        "K1ABC HB9BLA 73",
        "CQ HB9BLA JN47",
    ];
    assert_eq!(c.messages.map(|m| m.unwrap()), expected.map(String::from));
    s.run(period(3));
    let v = s.core.view();
    assert_eq!(v.arm_state, ArmState::Disarmed, "selection never arms");
    assert!(
        v.outcomes.is_empty(),
        "no TransmitRequest before Enable Tx: {:?}",
        v.outcomes
    );
    assert!(s.fake.0.keys.lock().unwrap().is_empty());
    // Report rendering of ReportRange.
    for (db, text) in [
        (-5, "-05"),
        (3, "+03"),
        (0, "+00"),
        (-15, "-15"),
        (49, "+49"),
    ] {
        assert_eq!(render_report(db), text);
    }
    assert_eq!(report_from_snr(-12.5), -13);
    assert_eq!(report_from_snr(12.5), 13);
    assert_eq!(report_from_snr(-70.0), -50);
}

#[test]
fn responder_progresses_tx1_tx3_tx5_and_completes_once_after_the_transmitted_73() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(s.armed());
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("K1ABC HB9BLA JN47"));
    let report = s.row(period(2), "HB9BLA K1ABC -05", 1240.0, Some(-7.0));
    s.deliver(std::slice::from_ref(&report));
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    // Delivered twice: counted once (no change, no second effect).
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(period(4) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("K1ABC HB9BLA R-12"));
    let rr73 = s.row(period(4), "HB9BLA K1ABC RR73", 1240.0, Some(-7.0));
    s.deliver(&[rr73]);
    assert_eq!(s.state(), (State::Signoff, Slot::Tx5));
    s.run(period(5) + 14 * SECOND);
    assert_eq!(s.sent_in(period(5)).as_deref(), Some("K1ABC HB9BLA 73"));
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(!s.armed(), "Enable Tx off on completion");
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCompleted
    );
    let (kind, logged) = one_entry(&mut s);
    assert_eq!(kind, LogKind::Completion, "logged at completion, no review");
    let fields = logged.log_fields(s.now()).unwrap();
    assert_eq!(fields.call, "K1ABC");
    assert_eq!(fields.rst_sent.as_deref(), Some("-12"));
    assert_eq!(fields.rst_rcvd.as_deref(), Some("-05"));
    // TIME_ON: one period before the first transmitted Tx3 (no Tx2 was sent).
    assert_eq!(fields.start_utc_ms, period(2));
    // TIME_OFF: end of the last period with a counted message (my Tx5).
    assert_eq!(fields.end_utc_ms, period(6));
    // A reply after completion changes nothing and never logs again.
    let late = s.row(period(6), "HB9BLA K1ABC 73", 1240.0, None);
    s.deliver(&[late]);
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(s.engine.take_logs().is_empty(), "completion logs once");
    s.run(period(9));
    assert_eq!(
        s.sent.len(),
        3,
        "Auto Seq never starts another transmission: {:?}",
        s.sent
    );
}

#[test]
fn caller_cq_then_selected_reply_reaches_rogers_and_completes_on_73_or_sent_rr73() {
    for rr73 in [false, true] {
        let mut s = station();
        // Call 1st off: the reply to my CQ waits for the operator's selection (#12).
        s.command(Command::SetCallFirst(false)).unwrap();
        s.command(Command::SetParity(Parity::Even)).unwrap();
        s.command(Command::EnableTx(true, Some(7))).unwrap();
        assert_eq!(s.state(), (State::Calling, Slot::Tx6));
        s.run(period(1) + 14 * SECOND);
        assert_eq!(s.sent_in(period(2)), None);
        assert_eq!(s.sent.first().map(|x| x.1.as_str()), Some("CQ HB9BLA JN47"));
        let answer = s.row(period(1), "HB9BLA K1ABC FN42", 900.0, Some(3.0));
        // Not selected yet: the reply to my CQ does not choose the partner (#12).
        s.deliver(std::slice::from_ref(&answer));
        assert_eq!(s.state(), (State::Calling, Slot::Tx6));
        s.command(Command::SelectRow {
            row: answer,
            replace: false,
        })
        .unwrap();
        assert_eq!(s.state(), (State::Report, Slot::Tx2));
        assert_eq!(s.next_text(), "K1ABC HB9BLA +03");
        assert_eq!(
            s.engine.settings.tx_hz, 1500,
            "a reply to me keeps my Tx frequency"
        );
        assert!(s.armed(), "selection from calling keeps Enable Tx");
        if rr73 {
            s.command(Command::SetTx4(Tx4::Rr73)).unwrap();
        }
        s.run(period(3) + 14 * SECOND);
        assert_eq!(s.sent_in(period(2)).as_deref(), Some("K1ABC HB9BLA +03"));
        let roger = s.row(period(3), "HB9BLA K1ABC R-07", 900.0, None);
        s.deliver(&[roger]);
        assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
        let tx4 = if rr73 {
            "K1ABC HB9BLA RR73"
        } else {
            "K1ABC HB9BLA RRR"
        };
        assert_eq!(s.next_text(), tx4);
        s.run(period(5) + 14 * SECOND);
        assert_eq!(s.sent_in(period(4)).as_deref(), Some(tx4));
        if rr73 {
            assert_eq!(s.state(), (State::Completed, Slot::Tx6));
        } else {
            assert_eq!(
                s.state(),
                (State::Rogers, Slot::Tx4),
                "RRR is not completion"
            );
            let seventy_three = s.row(period(5), "HB9BLA K1ABC 73", 900.0, None);
            s.deliver(&[seventy_three]);
            assert_eq!(s.state(), (State::Completed, Slot::Tx6));
        }
        assert!(!s.armed());
        let sent = s.sent.len();
        s.run(period(9));
        assert_eq!(s.sent.len(), sent, "no further CQ after completion");
        let fields = one_log(&mut s).log_fields(s.now()).unwrap();
        assert_eq!(
            fields.start_utc_ms,
            period(2),
            "TIME_ON: the first transmitted Tx2 period"
        );
        assert_eq!(fields.rst_rcvd.as_deref(), Some("-07"));
    }
}

#[test]
fn repeats_resend_and_a_report_from_rogers_returns_to_tx3() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-1.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -05", 1500.0, None);
    s.deliver(&[report]);
    // The partner misses my Tx3 and repeats its report: Tx3 is sent again.
    s.run(period(4) + 14 * SECOND);
    let again = s.row(period(4), "HB9BLA K1ABC -05", 1500.0, None);
    s.deliver(std::slice::from_ref(&again));
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(period(5) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)), s.sent_in(period(5)));
    // R+report: rogers; a re-decode of the same period counts once.
    let roger = s.row(period(6), "HB9BLA K1ABC R-05", 1500.0, None);
    let redecode = s.row(period(6), "HB9BLA K1ABC R-05", 1500.4, None);
    s.run(period(6) + 14 * SECOND);
    s.deliver(&[roger, redecode]);
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
    // The earlier report row delivered again (same identity) counts once: it does not
    // send the contact back to Tx3.
    s.deliver(std::slice::from_ref(&again));
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4), "one row counts once");
    // The partner did not copy my R-report and sends its report again: back to Tx3.
    s.run(period(8) + 14 * SECOND);
    let report_again = s.row(period(8), "HB9BLA K1ABC -06", 1500.0, None);
    s.deliver(&[report_again]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    // Messages not in the table change nothing (grid in rogerReport).
    let grid = s.row(period(8), "HB9BLA K1ABC FN42", 1500.0, None);
    s.deliver(&[grid]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
}

#[test]
fn other_stations_wrong_period_and_previous_partner_rows_change_nothing() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    let other = s.row(period(2), "HB9BLA W1XYZ -10", 1500.0, None);
    let my_period = s.row(period(1), "HB9BLA K1ABC -05", 1500.0, None);
    s.deliver(&[other, my_period]);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    // A different partner while active needs the explicit ChangeContact.
    let cq2 = s.row(period(2), "CQ DL1ABC JO62", 800.0, None);
    assert_eq!(
        s.command(Command::SelectRow {
            row: cq2.clone(),
            replace: false
        }),
        Err("contact_active")
    );
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("K1ABC")
    );
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.command(Command::SelectRow {
        row: cq2,
        replace: true,
    })
    .unwrap();
    assert!(s.armed(), "ChangeContact keeps Enable Tx (#50)");
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("DL1ABC")
    );
    let late = s.row(period(2), "HB9BLA K1ABC -05", 1500.0, None);
    s.deliver(&[late]);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
}

#[test]
fn tx1_skip_report_override_and_manual_entry_follow_the_domains() {
    let mut s = station();
    s.command(Command::SetTx1Skip(true)).unwrap();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-20.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert_eq!(s.state(), (State::Report, Slot::Tx2));
    assert_eq!(
        s.engine.contact.as_ref().unwrap().messages[0].as_deref(),
        Some("K1ABC HB9BLA JN47"),
        "Tx1 text kept"
    );
    assert_eq!(s.command(Command::ChooseNext(Slot::Tx1)), Ok(()));
    assert_eq!(
        s.state().1,
        Slot::Tx2,
        "choosing Tx1 selects Tx2 with Tx1 skipped"
    );
    for (db, text) in [(-50, "K1ABC HB9BLA -50"), (49, "K1ABC HB9BLA +49")] {
        s.command(Command::SetReport(db)).unwrap();
        assert_eq!(s.next_text(), text);
    }
    for db in [-51, 50] {
        assert_eq!(s.command(Command::SetReport(db)), Err("invalid_report"));
    }
    assert_eq!(s.next_text(), "K1ABC HB9BLA +49");
    s.command(Command::Cancel).unwrap();
    s.command(Command::SetTx1Skip(false)).unwrap();
    s.command(Command::EnterDx {
        call: "dl1abc".into(),
        grid: Some("JO62".into()),
        replace: false,
    })
    .unwrap();
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        (c.origin, c.dx_call.as_deref(), c.dx_grid.as_deref()),
        (Origin::ManualEntry, Some("DL1ABC"), Some("JO62"))
    );
    assert_eq!((c.state, c.next), (State::Replying, Slot::Tx1));
    assert_eq!(
        render_report(c.report),
        "+49",
        "manual entry uses the current report value"
    );
    for (call, grid, code) in [
        ("AB1", None, "invalid_call"),
        ("<...>", None, "invalid_call"),
        ("DL2ABC", Some("SS00"), "invalid_grid"),
    ] {
        assert_eq!(
            s.command(Command::EnterDx {
                call: call.into(),
                grid: grid.map(String::from),
                replace: true
            }),
            Err(code)
        );
    }
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("DL1ABC"),
        "refusals change nothing"
    );
    // An edited message must pack as a standard message.
    assert_eq!(
        s.command(Command::EditMessage(
            Slot::Tx5,
            "DL1ABC HB9BLA 73 GL".into()
        )),
        Err("invalid_message")
    );
    s.command(Command::EditMessage(Slot::Tx5, "dl1abc hb9bla rr73".into()))
        .unwrap();
    assert_eq!(
        s.engine.contact.as_ref().unwrap().messages[4].as_deref(),
        Some("DL1ABC HB9BLA RR73")
    );
    // Tx offset domain 200..2950, Rx 0..3000.
    for (tx, ok) in [(199, false), (200, true), (2950, true), (2951, false)] {
        assert_eq!(
            s.command(Command::SetFrequency {
                rx: None,
                tx: Some(tx)
            })
            .is_ok(),
            ok,
            "{tx}"
        );
    }
    assert_eq!(
        s.command(Command::SetFrequency {
            rx: Some(3001),
            tx: None
        }),
        Err("out_of_range")
    );
    s.command(Command::SetFrequency {
        rx: Some(0),
        tx: None,
    })
    .unwrap();
}

#[test]
fn partner_working_another_call_within_50_hz_halts_in_replying_and_skipped_report() {
    for skipped in [false, true] {
        for (offset, stops) in [(50.0, true), (51.0, false)] {
            let mut s = station();
            s.command(Command::SetTx1Skip(skipped)).unwrap();
            let cq = s.row(P0, "CQ K1ABC FN42", 1000.0, None);
            s.command(Command::SelectRow {
                row: cq,
                replace: false,
            })
            .unwrap();
            let expected = if skipped {
                (State::Report, Slot::Tx2)
            } else {
                (State::Replying, Slot::Tx1)
            };
            assert_eq!(s.state(), expected);
            s.command(Command::EnableTx(true, Some(7))).unwrap();
            s.run(period(1) + 3 * SECOND);
            assert!(s.core.view().transmitting);
            let elsewhere = s.row(period(0), "W9XYZ K1ABC -10", 1000.0 + offset, None);
            s.deliver(&[elsewhere]);
            assert_eq!(!s.armed(), stops, "offset {offset} skipped {skipped}");
            assert_eq!(!s.core.view().transmitting, stops);
            assert_eq!(s.state(), expected, "the state is kept");
        }
    }
}

#[test]
fn auto_seq_off_cancel_halt_and_watchdog_while_calling() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetAutoSeq(false)).unwrap();
    let report = s.row(period(2), "HB9BLA K1ABC -05", 1500.0, None);
    s.deliver(&[report]);
    assert_eq!(
        s.state(),
        (State::Replying, Slot::Tx1),
        "Auto Seq off never changes the next slot"
    );
    s.command(Command::SetAutoSeq(true)).unwrap();
    // Halt keeps the state; the contact can resume after Enable Tx.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(1) + 2 * SECOND);
    assert!(s.core.view().transmitting);
    s.core.halt();
    s.step(&[]);
    assert!(!s.armed());
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    // Cancel: disarm, clear DX and Tx1-Tx5, Tx6 next.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.command(Command::Cancel).unwrap();
    assert!(!s.armed());
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        (c.state, c.next, c.dx_call),
        (State::Cancelled, Slot::Tx6, None)
    );
    assert!(c.messages[..5].iter().all(Option::is_none));
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCancelled
    );
    // The Tx watchdog expiring while calling CQ ends the CQ (idle).
    s.command(Command::SetWatchdogs {
        tx_calls: 1,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    // The operator's Enable Tx starts the count; the second CQ is never keyed.
    let start = s.now();
    s.run(start + 100 * SECOND);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert!(s.core.view().tx_expired);
    assert_eq!(s.state().0, State::Idle);
}

// Proves: CL-010-10; TC-008-001 (#39, 2026-11-06). The live reports: SV1DZB repeated -09
// while we repeated R+06 (partner messages), and J88IH sent one report while the operator
// clicked in the page: 13 R-07 at limit 6 (browser requests).
#[test]
fn tc_008_001_the_watchdog_stops_at_n_repetitions_whatever_the_partner_or_browser_does() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 3,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
    s.deliver(&[report]);
    assert_eq!(s.core.view().tx_remaining_calls, 3, "a different message");
    let halts = s.core.view().halt_state;
    // R+report in periods 3, 5 and 7; the partner repeats and the browser clicks around it.
    for (own, left) in [(3, 2), (5, 1), (7, 0)] {
        s.run(period(own) + 2 * SECOND);
        let sent = s.sent_in(period(own)).expect("the repetition is sent");
        assert!(sent.starts_with("K1ABC HB9BLA R"), "{sent}");
        assert_eq!(s.core.view().tx_remaining_calls, left, "period {own}");
        s.command(Command::SetHoldTx(false)).unwrap();
        s.command(Command::SetFrequency {
            rx: Some(1400 + own as u32),
            tx: None,
        })
        .unwrap();
        s.command(Command::SetWatchdogs {
            tx_calls: 3,
            tune_seconds: 90,
        })
        .unwrap();
        assert_eq!(s.core.view().tx_remaining_calls, left, "browser requests");
        s.run(period(own + 1) + 13 * SECOND);
        let repeat = s.row(period(own + 1), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
        s.deliver(&[repeat]);
        assert_eq!(s.core.view().tx_remaining_calls, left, "partner repeat");
    }
    s.run(period(9) + 2 * SECOND);
    let v = s.core.view();
    assert_eq!(
        (
            v.arm_state,
            v.last_disarm_cause,
            v.tx_expired,
            v.halt_state,
            v.ptt
        ),
        (
            ArmState::Disarmed,
            DisarmCause::TxWatchdog,
            true,
            halts,
            PttState::Released
        ),
        "stopped without a halt"
    );
    assert_eq!(s.sent_in(period(9)), None, "the fourth is never sent");
    let reps = |s: &Station| {
        s.engine
            .contact
            .as_ref()
            .unwrap()
            .dialogue
            .iter()
            .map(|e| (e.tx, e.count))
            .collect::<Vec<_>>()
    };
    assert_eq!(
        reps(&s),
        vec![(true, 1), (false, 4), (true, 3)],
        "the dialogue's Rep is the count"
    );
    // A browser request does not end the stop; an operator Enable Tx sends it again.
    s.command(Command::SetHoldTx(false)).unwrap();
    assert!(s.core.view().tx_expired);
    s.run(period(10) + 2 * SECOND);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(
        (s.core.view().tx_expired, s.core.view().tx_remaining_calls),
        (false, 3)
    );
    s.run(period(11) + 2 * SECOND);
    assert!(
        s.sent_in(period(11))
            .is_some_and(|t| t.starts_with("K1ABC HB9BLA R"))
    );
    assert_eq!(s.core.view().tx_remaining_calls, 2);
    assert_eq!(reps(&s), vec![(true, 1), (false, 4), (true, 3), (true, 1)]);
}

// Proves: CL-010-10; TC-008-001: a different message starts at 1 again, also when the
// partner advances just before the send beyond the limit is due.
#[test]
fn tc_008_001_the_partner_advancing_at_the_limit_sends_the_next_message() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
    s.deliver(&[report]);
    // The live first decode comes at about +14.2 s, after the start window's lead.
    s.run(period(6) + 14_200);
    assert_eq!(s.core.view().tx_remaining_calls, 0, "R+report sent twice");
    assert!(s.armed(), "the send beyond the limit is not due yet");
    let rr73 = s.row(period(6), "HB9BLA K1ABC RR73", 1500.0, Some(-9.0));
    s.deliver(&[rr73]);
    assert_eq!(s.core.view().tx_remaining_calls, 2, "a different message");
    s.run(period(7) + 14 * SECOND);
    assert!(s.sent_in(period(7)).is_some_and(|t| t.ends_with(" 73")));
    assert_eq!(s.state().0, State::Completed);
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCompleted
    );
}

// Proves: CL-010-10; TC-008-001: selecting a row of the current partner and Enable Tx
// while armed are clicks: neither restarts the count.
#[test]
fn tc_008_001_clicks_on_the_partner_and_enable_tx_while_armed_restart_nothing() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-9.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
    s.deliver(std::slice::from_ref(&report));
    s.run(period(3) + 2 * SECOND);
    assert_eq!(s.core.view().tx_remaining_calls, 1);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 1, "Enable Tx while armed");
    s.run(period(5) + 2 * SECOND);
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    s.command(Command::SelectRow {
        row: report,
        replace: false,
    })
    .unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 0, "the partner's row");
    assert_eq!(s.engine.contact.as_ref().unwrap().dialogue.len(), 3);
    s.run(period(7) + 2 * SECOND);
    assert_eq!(s.sent_in(period(7)), None, "the third is never sent");
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
}

// Proves: CL-010-10; TC-008-001: selecting the partner's row at another SNR keeps the report
// sent, so the message and its count stay.
#[test]
fn tc_008_001_a_partner_row_with_another_snr_restarts_nothing() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-9.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
    s.deliver(std::slice::from_ref(&report));
    s.run(period(5) + 2 * SECOND);
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    let weaker = s.row(period(4), "HB9BLA K1ABC -09", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: weaker,
        replace: false,
    })
    .unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 0, "the partner's row");
    s.run(period(7) + 2 * SECOND);
    assert_eq!(s.sent_in(period(7)), None, "never a third send");
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
}

// Proves: CL-010-10; TC-008-001: a limit lowered under a pending send stops before it keys.
#[test]
fn tc_008_001_a_pending_send_beyond_a_lowered_limit_is_never_keyed() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, None);
    s.deliver(std::slice::from_ref(&report));
    s.run(period(5) + 2 * SECOND);
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    s.run(period(7) + 2 * SECOND);
    assert_eq!(s.sent_in(period(7)), None, "never a third send");
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
}

// Proves: CL-010-10; TC-008-001: when the message at its limit becomes due again, the other
// message still pending is not keyed.
#[test]
fn tc_008_001_going_back_to_a_message_at_its_limit_cancels_the_pending_send() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-9.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13 * SECOND);
    let report = s.row(period(2), "HB9BLA K1ABC -09", 1500.0, Some(-9.0));
    s.deliver(std::slice::from_ref(&report));
    s.run(period(6) + 13 * SECOND);
    let rr73 = s.row(period(6), "HB9BLA K1ABC RR73", 1500.0, Some(-9.0));
    s.deliver(std::slice::from_ref(&rr73));
    s.command(Command::ChooseNext(Slot::Tx3)).unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    s.run(period(7) + 2 * SECOND);
    assert_eq!(s.sent_in(period(7)), None, "neither message is sent");
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
}

// Proves: CL-010-10; TC-008-001: N identical CQs stop; a caller answered by Call 1st is a
// new contact, which starts at the limit again.
#[test]
fn tc_008_001_identical_cqs_stop_and_an_answered_cq_starts_again() {
    let mut s = station();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::SetCallFirst(false)).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    let start = s.now();
    while s.core.view().tx_remaining_calls == 2 && s.now() < start + 40 * SECOND {
        s.run(s.now() + SECOND);
    }
    assert_eq!(s.core.view().tx_remaining_calls, 1, "one CQ sent");
    let last = s.core.view().last_period_utc_ms.unwrap();
    let caller = s.row(last + 15 * SECOND, "HB9BLA DL1XYZ JO62", 900.0, Some(-7.0));
    s.deliver(&[caller]);
    assert_eq!(
        s.core.view().tx_remaining_calls,
        1,
        "with Call 1st off the CQ goes on: an answer restarts nothing"
    );
    s.run(s.now() + 90 * SECOND);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert_eq!(s.state().0, State::Idle, "the stop ends the CQ");
    // Call 1st on: one CQ, then the caller.
    s.command(Command::SetCallFirst(true)).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 2);
    let start = s.now();
    while s.core.view().tx_remaining_calls == 2 && s.now() < start + 40 * SECOND {
        s.run(s.now() + SECOND);
    }
    assert_eq!(s.core.view().tx_remaining_calls, 1, "one CQ sent");
    let last = s.core.view().last_period_utc_ms.unwrap();
    let caller = s.row(last + 15 * SECOND, "HB9BLA DL1XYZ JO62", 900.0, Some(-7.0));
    s.deliver(&[caller]);
    assert_eq!(s.state().0, State::Report, "Call 1st answered");
    assert_eq!(s.core.view().tx_remaining_calls, 2, "a new contact");
}

#[test]
fn receive_only_station_prepares_and_logs_but_refuses_transmit() {
    let mut s = station();
    *s.fake.0.capability.lock().unwrap() = Some(Capability::Unsupported);
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        s.command(Command::EnableTx(true, Some(7))),
        Err("transmit_unavailable")
    );
    assert_eq!(s.command(Command::Tune(true)), Err("transmit_unavailable"));
    s.command(Command::OpenLog).unwrap();
    assert_eq!(one_entry(&mut s).0, LogKind::LogQso, "Log QSO logs now");
    // Without a CL-022 grant (plaintext profile) nothing arms.
    *s.fake.0.capability.lock().unwrap() = Some(Capability::Available);
    let ctx = Ctx {
        granted: false,
        ..s.ctx()
    };
    assert_eq!(
        s.engine
            .command(Command::EnableTx(true, Some(7)), Some(&mut s.core), &ctx),
        Err("transmit_unavailable")
    );
    assert!(!s.armed());
    // Profile without a locator: no message set, transmit stays unavailable.
    let ctx = Ctx {
        locator: None,
        ..s.ctx()
    };
    let row = s.row(P0, "CQ W1AW FN31", 1500.0, None);
    assert_eq!(
        s.engine.command(
            Command::SelectRow { row, replace: true },
            Some(&mut s.core),
            &ctx
        ),
        Err("profile_incomplete")
    );
    // Rows that are not standard or have an unresolved partner are refused.
    let mut hashed = s.row(P0, "CQ <...> FN42", 1500.0, None);
    assert_eq!(
        s.command(Command::SelectRow {
            row: hashed.clone(),
            replace: true
        }),
        Err("row_not_standard")
    );
    hashed.standard = None;
    assert_eq!(
        s.command(Command::SelectRow {
            row: hashed,
            replace: true
        }),
        Err("row_not_standard")
    );
}

#[test]
fn tc_008_001_tx_watchdog_counts_unanswered_calls_and_tune_ends_at_its_limit() {
    let mut s = station();
    let v = s.core.view();
    assert_eq!((v.tx_calls, v.tune_seconds), (6, 90), "startup defaults");
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_calls: 0,
            tune_seconds: 90
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_calls: 100,
            tune_seconds: 90
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_calls: 6,
            tune_seconds: 0
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_calls: 6,
            tune_seconds: 301
        }),
        Err("out_of_range")
    );
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetWatchdogs {
        tx_calls: 2,
        tune_seconds: 300,
    })
    .unwrap();
    assert_eq!(
        s.core.view().tx_remaining_calls,
        0,
        "counter 0 while disarmed"
    );
    // TC-008-001 (#39 2026-11-04): two unanswered Tx1, the third is never keyed.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 2);
    s.run(period(1) + 2 * SECOND);
    assert_eq!(s.core.view().tx_remaining_calls, 1);
    s.run(period(3) + 2 * SECOND);
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    let halts = s.core.view().halt_state;
    s.run(period(5) + 2 * SECOND);
    let v = s.core.view();
    assert_eq!(
        (
            v.arm_state,
            v.last_disarm_cause,
            v.tx_expired,
            v.halt_state,
            v.ptt
        ),
        (
            ArmState::Disarmed,
            DisarmCause::TxWatchdog,
            true,
            halts,
            PttState::Released
        ),
        "stopped before keying, without a halt"
    );
    assert_eq!(s.sent_in(period(5)), None, "the third call is never sent");
    assert_eq!(
        s.state(),
        (State::Replying, Slot::Tx1),
        "contact state kept"
    );
    // Re-enable clears the expiry (a late start in period 5, then period 7); the
    // partner's report makes the next message a different one.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(!s.core.view().tx_expired);
    s.run(period(7) + 2 * SECOND);
    assert!(s.armed());
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    let other = s.row(period(6), "DL1XYZ W1AW -03", 1500.0, Some(-3.0));
    s.deliver(&[other]);
    assert_eq!(
        s.core.view().tx_remaining_calls,
        0,
        "a message to someone else is no answer"
    );
    s.run(period(8) + 13 * SECOND);
    let report = s.row(period(8), "HB9BLA K1ABC -05", 1500.0, Some(-5.0));
    s.deliver(&[report]);
    assert_eq!(s.core.view().tx_remaining_calls, 2, "a different message");
    s.run(period(11) + 2 * SECOND);
    assert!(
        s.sent_in(period(9))
            .is_some_and(|t| t.starts_with("K1ABC HB9BLA R"))
    );
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    // A call to me from another station than the partner is no answer.
    let stranger = s.row(period(10), "HB9BLA W1AW FN31", 1800.0, Some(-9.0));
    s.deliver(&[stranger]);
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    // An accepted browser request changes nothing: the third reply is never sent.
    s.command(Command::SetHoldTx(false)).unwrap();
    assert_eq!(s.core.view().tx_remaining_calls, 0);
    s.run(period(13) + 2 * SECOND);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert!(s.sent_in(period(11)).is_some() && s.sent_in(period(13)).is_none());
    s.command(Command::Cancel).unwrap();
    s.command(Command::SetCallFirst(false)).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.state().0, State::Calling);
    let cq_from = s.now();
    while s.core.view().tx_remaining_calls == 2 && s.now() < cq_from + 40 * SECOND {
        s.run(s.now() + SECOND);
    }
    assert_eq!(s.core.view().tx_remaining_calls, 1, "one CQ sent");
    s.command(Command::EnableTx(false, None)).unwrap();
    s.run(s.now() + 15 * SECOND);
    assert!(!s.core.view().transmitting);
    // Tune: limit 1 s, ends through #9 with release.
    s.command(Command::SetWatchdogs {
        tx_calls: 6,
        tune_seconds: 1,
    })
    .unwrap();
    assert_eq!(
        s.command(Command::Tune(true)),
        Err("state_conflict"),
        "Tune needs Enable Tx"
    );
    // Armed with no contact transmitting (nothing pending): Tune through #9.
    s.command(Command::Cancel).unwrap();
    s.engine.contact = None;
    s.core.arm(7).unwrap();
    s.step(&[]);
    s.command(Command::Tune(true)).unwrap();
    assert!(s.core.view().tune);
    assert_eq!(
        s.fake.0.keys.lock().unwrap().last().map(|k| k.1),
        Some(true)
    );
    let t = s.now();
    s.run(t + 1100);
    assert!(!s.core.view().tune, "Tune ends at its 1 s limit");
    assert_eq!(
        s.fake.0.keys.lock().unwrap().last().map(|k| k.1),
        Some(false)
    );
    // Tune false is always admitted.
    s.command(Command::Tune(false)).unwrap();
}

// #41: no review queue. Every Log QSO and every completion is handed to the log at
// once; nothing is held, so nothing blocks the next contact or CQ.
#[test]
fn log_qso_and_completion_log_at_once_and_never_block_a_new_contact() {
    let mut s = station();
    for i in 0..9 {
        s.command(Command::EnterDx {
            call: format!("DL{i}ABC"),
            grid: None,
            replace: true,
        })
        .unwrap();
        s.command(Command::OpenLog).unwrap();
        let logged = one_log(&mut s);
        assert_eq!(logged.dx_call, Some(format!("DL{i}ABC")));
        // #37: Log QSO before completion closes the contact; nothing stays queued.
        assert_eq!(logged.state, State::Completed, "Log QSO before completion");
        assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    }
    // A contact completes on a received 73 in rogers (no transmission needed).
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: Some("FN42".into()),
        replace: true,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(std::slice::from_ref(&seventy_three));
    assert_eq!(s.state().0, State::Completed);
    let done = one_log(&mut s);
    assert_eq!(
        (done.dx_call.as_deref(), done.dx_grid.as_deref()),
        (Some("K1ABC"), Some("FN42"))
    );
    s.deliver(&[seventy_three]);
    assert!(
        s.engine.take_logs().is_empty(),
        "a repeated 73 logs nothing"
    );
    // Cancel (Esc) on the completed contact only selects Tx6; Log QSO re-logs it.
    s.command(Command::Cancel).unwrap();
    let c = s.engine.contact.clone().unwrap();
    assert_eq!((c.state, c.next), (State::Completed, Slot::Tx6));
    assert_eq!(c.messages[4].as_deref(), Some("K1ABC HB9BLA 73"));
    s.command(Command::OpenLog).unwrap();
    assert_eq!(one_log(&mut s).id, done.id, "the same contact identity");
    // The next contact and a CQ are prepared at once.
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    s.command(Command::Cancel).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.engine.contact.as_ref().unwrap().origin, Origin::OwnCq);
    assert!(s.engine.take_logs().is_empty());
    // An own CQ has no DX call: Log QSO refuses it.
    assert_eq!(s.command(Command::OpenLog), Err("no_contact"));
}

#[test]
fn an_operator_disarm_is_not_reported_as_a_refused_transmission() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(
        s.core.view().pending_sequence.is_some(),
        "a request is pending"
    );
    s.command(Command::EnableTx(false, None)).unwrap();
    s.run(s.now() + 200);
    assert_eq!(s.engine.transmit_problem, None, "disarm cancels quietly");
}

// Proves: CL-010-02, CL-010-03; TC-007-001. #49: CQ keeps calling, armed, when every
// transmission's end is reported 900 ms late (inside the release bound).
#[test]
fn cq_keeps_calling_armed_when_the_device_reports_each_end_900_ms_late() {
    let mut s = station();
    s.fake.0.late_ms.store(900, Ordering::SeqCst);
    s.command(Command::SetParity(Parity::Even)).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    s.run(period(6) + 14 * SECOND + 500);
    let cqs: Vec<_> = s.sent.iter().map(|(p, t)| (*p, t.as_str())).collect();
    assert_eq!(
        cqs,
        vec![
            (period(0), "CQ HB9BLA JN47"),
            (period(2), "CQ HB9BLA JN47"),
            (period(4), "CQ HB9BLA JN47"),
            (period(6), "CQ HB9BLA JN47")
        ]
    );
    let releases: Vec<_> = s
        .fake
        .0
        .keys
        .lock()
        .unwrap()
        .iter()
        .filter(|k| !k.1)
        .map(|k| k.0)
        .collect();
    assert_eq!(
        releases,
        [0, 2, 4, 6]
            .map(|n| period(n) + 500 + 12_640 + 900)
            .to_vec(),
        "released when the device reports the end"
    );
    assert!(s.armed(), "a late end report never disarms");
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    assert_eq!(s.engine.transmit_problem, None);
}

#[test]
fn a_non_disarming_refusal_is_not_resubmitted_every_step() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    // Another client exhausted the boot's request sequences.
    s.core.arm(7).unwrap();
    let _ = s.core.submit(wstx_rust::transmit::service::Request {
        contact_id: None,
        request_sequence: 9_007_199_254_740_991,
        mode: Mode::Ft8,
        period_start_utc_ms: period(1),
        message_text: "CQ HB9BLA JN47".into(),
        tx_offset_hz: 1500,
    });
    s.core.disarm(DisarmCause::Operator);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(s.now() + 2000);
    let duplicates = s
        .core
        .view()
        .outcomes
        .iter()
        .filter(|o| {
            o.refusal == Some(wstx_rust::transmit::service::TransmitRefusal::DuplicateSequence)
        })
        .count();
    assert!(duplicates <= 1, "{duplicates} duplicate submissions");
    assert!(!s.armed(), "the refusal disarms visibly");
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::Refused);
    assert_eq!(
        s.engine.transmit_problem.as_deref(),
        Some("duplicate_sequence")
    );
}

#[test]
fn enable_tx_arms_with_the_revision_the_operator_saw_and_9_refuses_a_changed_one() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, None);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    // The station's CL-022 safety revision is 7; the operator saw 6.
    assert_eq!(
        s.command(Command::EnableTx(true, Some(6))),
        Err("stale_revision")
    );
    assert!(!s.armed());
    assert_eq!(
        s.command(Command::EnableTx(true, None)),
        Err("stale_revision"),
        "no revision shown"
    );
    assert!(!s.armed());
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(s.armed());
}

// Re-check of fd6c776d2, item 1: slot choices never reopen a finished contact.
#[test]
fn choosing_a_slot_on_a_finished_contact_never_changes_its_state() {
    let mut s = station();
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: Some("FN42".into()),
        replace: false,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(&[seventy_three]);
    assert_eq!(s.state().0, State::Completed);
    let done = s.engine.contact.as_ref().unwrap().id.clone();
    let logged = one_log(&mut s);
    assert_eq!(logged.id, done);
    let end = logged.log_fields(s.now()).unwrap().end_utc_ms;
    s.command(Command::ChooseNext(Slot::Tx5)).unwrap();
    s.command(Command::ChooseNext(Slot::Tx6)).unwrap();
    assert_eq!(
        s.state(),
        (State::Completed, Slot::Tx6),
        "the state never changes"
    );
    // Enable Tx starts a fresh own-CQ contact; the completed one was logged already.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    let cq = s.engine.contact.clone().unwrap();
    assert_ne!(cq.id, done);
    assert_eq!((cq.origin, cq.state), (Origin::OwnCq, State::Calling));
    assert!(s.engine.take_logs().is_empty(), "slot choices log nothing");
    assert_eq!(
        logged.log_fields(s.now()).unwrap().end_utc_ms,
        end,
        "TIME_OFF fixed at completion"
    );
}

// ---------------------------------------------------------------- FT4 (#11 slice B)
// Proves: CL-011-03, CL-011-04; TC-007-008. The same engine and #9 owner core in FT4;
// expected periods, texts, samples and times are hand-written from WstxContact
// ContactMode/ModeChange, the FT4-NOTE rules and WSJT-X (Modulator.cpp FT4 delay
// 300 ms; 105 symbols x 576 x 4 = 241920 samples at 48 kHz; m_TRperiod 7.5 s).
const FT4: i64 = 7_500;
const FT4_SAMPLES_48K: usize = 241_920;
fn ft4_station() -> Station {
    let mut s = station();
    s.mode = Mode::Ft4;
    s
}

#[test]
fn ft4_responder_transmits_in_odd_7_5_s_periods_and_completes_with_an_ft4_log_offer() {
    let mut s = ft4_station();
    // P0 is a multiple of 15 s: an even FT4 period, so I transmit in the odd ones.
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(c.mode, Mode::Ft4);
    assert_eq!(s.engine.settings.parity, Parity::Odd);
    assert_eq!(c.tx4, Tx4::Rr73, "FT4-NOTE: Tx4 is RR73");
    assert_eq!(c.messages[3].as_deref(), Some("K1ABC HB9BLA RR73"));
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(P0 + 22 * SECOND);
    assert_eq!(
        s.sent_in(P0 + FT4).as_deref(),
        Some("K1ABC HB9BLA JN47"),
        "{:?}",
        s.sent
    );
    let report = s.row(P0 + 2 * FT4, "HB9BLA K1ABC -05", 1240.0, None);
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(P0 + 37 * SECOND);
    assert_eq!(
        s.sent_in(P0 + 3 * FT4).as_deref(),
        Some("K1ABC HB9BLA R-12")
    );
    let rr73 = s.row(P0 + 4 * FT4, "HB9BLA K1ABC RR73", 1240.0, None);
    s.deliver(&[rr73]);
    assert_eq!(s.state(), (State::Signoff, Slot::Tx5));
    s.run(P0 + 60 * SECOND);
    assert_eq!(s.sent_in(P0 + 5 * FT4).as_deref(), Some("K1ABC HB9BLA 73"));
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(!s.armed());
    assert_eq!(s.sent.len(), 3, "{:?}", s.sent);
    // #9 played the FT4 waveform 300 ms after each odd FT4 period start.
    let plays = s.fake.0.plays.lock().unwrap().clone();
    assert_eq!(
        plays,
        vec![
            (P0 + FT4 + 300, FT4_SAMPLES_48K),
            (P0 + 3 * FT4 + 300, FT4_SAMPLES_48K),
            (P0 + 5 * FT4 + 300, FT4_SAMPLES_48K),
        ]
    );
    let fields = one_log(&mut s).log_fields(s.now()).unwrap();
    assert_eq!(fields.mode, Mode::Ft4);
    assert_eq!(
        fields.start_utc_ms,
        P0 + 2 * FT4,
        "TIME_ON one FT4 period before the first Tx3"
    );
    assert_eq!(
        fields.end_utc_ms,
        P0 + 6 * FT4,
        "TIME_OFF end of my Tx5 period"
    );
}

#[test]
fn ft4_caller_keeps_rr73_completes_on_the_sent_rr73_and_bounds_tx_at_2916_hz() {
    let mut s = ft4_station();
    s.fake.0.now.store(P0 + 8 * SECOND, Ordering::SeqCst);
    s.command(Command::SetParity(Parity::Even)).unwrap();
    assert_eq!(
        s.command(Command::SetFrequency {
            rx: None,
            tx: Some(2917)
        }),
        Err("out_of_range")
    );
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(2916),
    })
    .unwrap();
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(1500),
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.engine.contact.as_ref().unwrap().mode, Mode::Ft4);
    s.run(P0 + 29 * SECOND);
    assert_eq!(s.sent_in(P0 + 2 * FT4).as_deref(), Some("CQ HB9BLA JN47"));
    let answer = s.row(P0 + 3 * FT4, "HB9BLA K1ABC FN42", 900.0, Some(3.0));
    s.command(Command::SelectRow {
        row: answer,
        replace: false,
    })
    .unwrap();
    assert_eq!(s.state(), (State::Report, Slot::Tx2));
    assert_eq!(s.command(Command::SetTx4(Tx4::Rrr)), Err("out_of_range"));
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!(
        (c.tx4, c.messages[3].as_deref()),
        (Tx4::Rr73, Some("K1ABC HB9BLA RR73")),
        "a refused set_tx4 changes nothing"
    );
    s.run(P0 + 44 * SECOND);
    assert_eq!(s.sent_in(P0 + 4 * FT4).as_deref(), Some("K1ABC HB9BLA +03"));
    let roger = s.row(P0 + 5 * FT4, "HB9BLA K1ABC R-07", 900.0, None);
    s.deliver(&[roger]);
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
    s.run(P0 + 60 * SECOND);
    assert_eq!(
        s.sent_in(P0 + 6 * FT4).as_deref(),
        Some("K1ABC HB9BLA RR73")
    );
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    let fields = one_log(&mut s).log_fields(s.now()).unwrap();
    assert_eq!(fields.start_utc_ms, P0 + 4 * FT4, "first transmitted Tx2");
    assert_eq!(fields.mode, Mode::Ft4);
}

#[test]
fn rows_of_the_other_mode_never_count_and_a_mode_change_disarms_and_cancels() {
    // An armed FT8 responder with a pending request and a 2940 Hz Tx offset.
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(2940),
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("K1ABC HB9BLA JN47"));
    // An FT4 row of the partner (even FT4 and FT8 period start) never counts.
    s.mode = Mode::Ft4;
    let ft4_report = s.row(period(2), "HB9BLA K1ABC -05", 1240.0, None);
    s.mode = Mode::Ft8;
    s.deliver(&[ft4_report]);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    assert!(s.armed());
    assert!(
        s.core.view().pending_sequence.is_some(),
        "a request is pending"
    );
    let keys = s.fake.0.keys.lock().unwrap().len();
    // The station switches to FT4 (the live job now decodes FT4).
    s.mode = Mode::Ft4;
    s.step(&[]);
    let c = s.engine.contact.clone().unwrap();
    assert_eq!((c.state, c.next), (State::Cancelled, Slot::Tx6));
    assert_eq!(c.dx_call, None);
    assert!(!s.armed());
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCancelled
    );
    assert_eq!(s.core.view().pending_sequence, None);
    assert_eq!(s.engine.settings.tx_hz, 2916, "clamped into the FT4 domain");
    s.run(period(6));
    assert_eq!(
        s.fake.0.keys.lock().unwrap().len(),
        keys,
        "no key after the switch"
    );
    // Enable Tx afterwards is a fresh own CQ in FT4, in odd FT4 periods.
    let sent = s.sent.len();
    let played = s.fake.0.plays.lock().unwrap().len();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    let cq = s.engine.contact.clone().unwrap();
    assert_eq!((cq.origin, cq.mode), (Origin::OwnCq, Mode::Ft4));
    s.run(period(8));
    let later = &s.sent[sent..];
    assert!(!later.is_empty());
    for (p, text) in later {
        assert_eq!(text, "CQ HB9BLA JN47");
        assert_eq!(p.rem_euclid(15_000), FT4, "odd FT4 period: {p}");
    }
    for (_, n) in s.fake.0.plays.lock().unwrap().iter().skip(played) {
        assert_eq!(*n, FT4_SAMPLES_48K);
    }

    // A calling FT4 CQ returns to idle on a switch back to FT8.
    s.mode = Mode::Ft8;
    s.step(&[]);
    assert_eq!(s.state().0, State::Idle);
    assert!(!s.armed());

    // A completed FT8 contact keeps its fields and was logged in FT8.
    let mut s = station();
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: None,
        replace: false,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(&[seventy_three]);
    assert_eq!(s.state().0, State::Completed);
    s.mode = Mode::Ft4;
    s.step(&[]);
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        (c.state, c.dx_call.as_deref()),
        (State::Completed, Some("K1ABC"))
    );
    assert_eq!(one_log(&mut s).mode, Mode::Ft8);
    // A manual entry now is an FT4 contact.
    s.command(Command::EnterDx {
        call: "DL1ABC".into(),
        grid: None,
        replace: false,
    })
    .unwrap();
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!((c.mode, c.tx4), (Mode::Ft4, Tx4::Rr73));
}

// Proves: CL-011-04; TC-007-008. WstxTransmit::StationModeGate: the #9 owner alone (no
// contact step after the switch) never keys a request of another station mode.
#[test]
fn the_owner_never_keys_a_request_of_another_station_mode_without_a_contact_step() {
    use wstx_rust::transmit::service::{OutcomeKind, Request, TransmitRefusal};
    let mut s = station();
    s.core.set_station_mode(Some(Mode::Ft8));
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(
        s.core.view().pending_sequence.is_some(),
        "Tx1 pending for period(1)"
    );
    // The station switches to FT4; only the owner runs across the period start.
    s.core.set_station_mode(Some(Mode::Ft4));
    let mut t = s.now();
    while t < period(1) + 3 * SECOND {
        t += 10;
        s.fake.0.now.store(t, Ordering::SeqCst);
        s.core.tick();
    }
    assert!(s.fake.0.keys.lock().unwrap().is_empty(), "never keyed");
    assert!(s.fake.0.plays.lock().unwrap().is_empty(), "no audio");
    let v = s.core.view();
    assert_eq!(v.arm_state, ArmState::Disarmed);
    assert_eq!(v.refusal, Some(TransmitRefusal::StaleRequest));
    assert!(
        v.outcomes
            .iter()
            .any(|o| o.kind == OutcomeKind::Refused
                && o.refusal == Some(TransmitRefusal::StaleRequest)),
        "{:?}",
        v.outcomes
    );
    // A new request of the old mode is refused at admission.
    s.core.arm(7).unwrap();
    let outcome = s.core.submit(Request {
        contact_id: None,
        request_sequence: u64::MAX >> 12,
        mode: Mode::Ft8,
        period_start_utc_ms: period(3),
        message_text: "CQ HB9BLA JN47".into(),
        tx_offset_hz: 1500,
    });
    assert_eq!(
        (outcome.kind, outcome.refusal),
        (OutcomeKind::Refused, Some(TransmitRefusal::StaleRequest))
    );
    assert_eq!(s.core.view().arm_state, ArmState::Disarmed);
}

// ---------------------------------------------------------------- #11 live RR73 stall
// Proves: CL-011-03; TC-007-008. Replay of the 2026-11-02 13:44-13:46 UTC FT4 contact
// with IW9FRA (partner in the even 7.5 s periods at 1838 Hz, Hold Tx on with my Tx at
// 2439 Hz): after my R+10 the partner's RR73 must move me to Tx5, send 73 once,
// complete and log once (WSJT-X auto-sequence). Rows reach the engine `decode_ms`
// after the partner's period start, as the live receive path publishes them.
struct Replay {
    decode_ms: i64,
    /// The operator also double-clicks the partner's first report row (Reply).
    reselect: bool,
    /// The partner's final message (RR73, RRR or 73).
    last: &'static str,
}
fn replay(mode: Mode, r: &Replay) -> Station {
    let mut s = station();
    s.mode = mode;
    let len = period_ms(mode);
    let dx = |s: &mut Station, n: i64, text: &str, snr: f64| {
        s.row(P0 + n * len, text, 1838.0, Some(snr))
    };
    s.command(Command::SetHoldTx(true)).unwrap();
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(2439),
    })
    .unwrap();
    s.fake.0.now.store(P0 + r.decode_ms, Ordering::SeqCst);
    let cq = dx(&mut s, 0, "CQ IW9FRA JM68", 10.0);
    s.deliver(std::slice::from_ref(&cq));
    // The operator double-clicks IW9FRA's row: select, then Enable Tx (Reply).
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    let last = format!("HB9BLA IW9FRA {}", r.last);
    let partner = [
        (2, "HB9BLA IW9FRA +10".to_string(), 10.0),
        (4, "HB9BLA IW9FRA +10".to_string(), 15.0),
        (6, last.clone(), 17.0),
        (8, last.clone(), 9.0),
        (10, last, 16.0),
    ];
    for (n, text, snr) in partner {
        s.run(P0 + n * len + r.decode_ms);
        let row = dx(&mut s, n, &text, snr);
        s.deliver(std::slice::from_ref(&row));
        if r.reselect && n == 2 {
            s.run(P0 + n * len + r.decode_ms + 400);
            s.command(Command::SelectRow {
                row,
                replace: false,
            })
            .unwrap();
            s.command(Command::EnableTx(true, Some(7))).unwrap();
        }
    }
    s.run(P0 + 13 * len);
    s
}
fn assert_replay(mode: Mode, r: &Replay, expected: &[(i64, &str)]) {
    let mut s = replay(mode, r);
    let len = period_ms(mode);
    let sent: Vec<_> = s
        .sent
        .iter()
        .map(|(p, t)| ((p - P0) / len, t.clone()))
        .collect();
    let expected: Vec<_> = expected.iter().map(|(n, t)| (*n, t.to_string())).collect();
    let label = format!(
        "{mode:?} decode +{} ms reselect {} {}",
        r.decode_ms, r.reselect, r.last
    );
    assert_eq!(sent, expected, "{label}");
    assert_eq!(s.state(), (State::Completed, Slot::Tx6), "{label}");
    assert!(!s.armed(), "{label}");
    let (kind, c) = one_entry(&mut s);
    assert_eq!(kind, LogKind::Completion, "{label}");
    assert!(s.engine.take_logs().is_empty(), "logged once: {label}");
    let f = c.log_fields(s.now()).unwrap();
    assert_eq!(
        (f.call.as_str(), f.grid.as_deref(), f.mode),
        ("IW9FRA", Some("JM68"), mode),
        "{label}"
    );
    assert_eq!(
        (f.rst_sent.as_deref(), f.rst_rcvd.as_deref()),
        (Some("+10"), Some("+10")),
        "{label}"
    );
}
#[test]
fn ft4_rr73_after_my_roger_report_sends_73_once_completes_and_logs_once() {
    // RR73 counted just before my next period (+6.7..7.3 s): 73 replaces the pending
    // Tx3 of that period.
    let at_once = [
        (1, "IW9FRA HB9BLA JN47"),
        (3, "IW9FRA HB9BLA R+10"),
        (5, "IW9FRA HB9BLA R+10"),
        (7, "IW9FRA HB9BLA 73"),
    ];
    for decode_ms in [6_700, 7_000, 7_300] {
        for reselect in [false, true] {
            for last in ["RR73", "73"] {
                let r = Replay {
                    decode_ms,
                    reselect,
                    last,
                };
                assert_replay(Mode::Ft4, &r, &at_once);
            }
        }
    }
    // Every partner message counted after the audio of my next transmission started:
    // that period still sends the previous message, the new one follows a period later.
    let late = [
        (1, "IW9FRA HB9BLA JN47"),
        (3, "IW9FRA HB9BLA JN47"),
        (5, "IW9FRA HB9BLA R+10"),
        (7, "IW9FRA HB9BLA R+10"),
        (9, "IW9FRA HB9BLA 73"),
    ];
    let r = Replay {
        decode_ms: 8_200,
        reselect: false,
        last: "RR73",
    };
    assert_replay(Mode::Ft4, &r, &late);
}
// #11 review: only a decoded row of the same partner keeps the known grid; a manual
// entry sets exactly the grid entered (none clears it).
#[test]
fn a_manual_entry_of_the_same_partner_sets_exactly_the_grid_entered() {
    let mut s = station();
    for (grid, expected) in [(Some("JM68"), Some("JM68")), (None, None)] {
        s.command(Command::EnterDx {
            call: "IW9FRA".into(),
            grid: grid.map(String::from),
            replace: false,
        })
        .unwrap();
        let c = s.engine.contact.as_ref().unwrap();
        assert_eq!(c.dx_grid.as_deref(), expected, "entered {grid:?}");
    }
}
// The live 13:44-13:46 record with Auto Seq off: the partner's +10 and RR73s are
// counted (report and TIME_OFF) but change nothing, so Tx3 repeats as observed; the
// engine offers Tx5 instead of dropping the RR73, and choosing it sends 73 once.
#[test]
fn auto_seq_off_offers_tx5_after_the_partners_rr73_and_choosing_it_completes() {
    let mut s = station();
    s.mode = Mode::Ft4;
    let len = period_ms(Mode::Ft4);
    s.command(Command::SetAutoSeq(false)).unwrap();
    s.fake.0.now.store(P0 + 7_000, Ordering::SeqCst);
    let cq = s.row(P0, "CQ IW9FRA JM68", 1838.0, Some(10.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(P0 + 2 * len + 7_000);
    let report = s.row(P0 + 2 * len, "HB9BLA IW9FRA +10", 1838.0, Some(10.0));
    s.deliver(&[report]);
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        (c.state, c.next),
        (State::Replying, Slot::Tx1),
        "Auto Seq off"
    );
    assert_eq!(
        c.suggested,
        Some(Slot::Tx3),
        "Tx3 offered after their report"
    );
    // The operator chooses Tx3 (late start in the open window).
    s.run(P0 + 2 * len + 7_400);
    s.command(Command::ChooseNext(Slot::Tx3)).unwrap();
    assert_eq!(s.engine.contact.as_ref().unwrap().suggested, None);
    for n in [6, 8] {
        s.run(P0 + n * len + 7_000);
        let rr73 = s.row(P0 + n * len, "HB9BLA IW9FRA RR73", 1838.0, Some(17.0));
        s.deliver(&[rr73]);
        let c = s.engine.contact.clone().unwrap();
        assert_eq!((c.state, c.next), (State::RogerReport, Slot::Tx3));
        assert_eq!(c.suggested, Some(Slot::Tx5), "Tx5 offered, never dropped");
        assert_eq!(
            c.last_counted_end,
            Some(P0 + (n + 1) * len),
            "counted: TIME_OFF"
        );
    }
    s.command(Command::ChooseNext(Slot::Tx5)).unwrap();
    s.run(P0 + 12 * len);
    let sent: Vec<_> = s
        .sent
        .iter()
        .map(|(p, t)| ((p - P0) / len, t.clone()))
        .collect();
    assert_eq!(
        sent,
        [
            (1, "IW9FRA HB9BLA JN47"),
            (3, "IW9FRA HB9BLA R+10"),
            (5, "IW9FRA HB9BLA R+10"),
            (7, "IW9FRA HB9BLA R+10"),
            (9, "IW9FRA HB9BLA 73"),
        ]
        .map(|(n, t)| (n, t.to_string()))
    );
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert_eq!(one_entry(&mut s).0, LogKind::Completion);
}
#[test]
fn ft8_rrr_or_rr73_after_my_roger_report_sends_73_once_completes_and_logs_once() {
    let at_once = [
        (1, "IW9FRA HB9BLA JN47"),
        (3, "IW9FRA HB9BLA R+10"),
        (5, "IW9FRA HB9BLA R+10"),
        (7, "IW9FRA HB9BLA 73"),
    ];
    for decode_ms in [13_500, 14_700] {
        for last in ["RR73", "RRR", "73"] {
            let r = Replay {
                decode_ms,
                reselect: decode_ms == 14_700,
                last,
            };
            assert_replay(Mode::Ft8, &r, &at_once);
        }
    }
}

// ---------------------------------------------------------------- #37 compact QSO pane
// Proves: CL-010-16, CL-011-01; TC-007-009, TC-011-001. Log QSO on a running, armed
// contact closes it: completed with Tx6, Enable Tx off (contactCompleted), nothing
// transmitted in the next period, one record (the Log QSO), and the partner's later
// RR73/73 neither advances nor logs it again.
#[test]
fn log_qso_closes_a_running_contact_so_nothing_stays_queued_or_logs_twice() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1234.6, Some(-12.4));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("K1ABC HB9BLA JN47"));
    let report = s.row(period(2), "HB9BLA K1ABC -05", 1240.0, Some(-7.0));
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    assert!(s.armed());
    s.command(Command::OpenLog).unwrap();
    let (kind, logged) = one_entry(&mut s);
    assert_eq!(kind, LogKind::LogQso);
    assert_eq!(logged.state, State::Completed);
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(!s.armed(), "Enable Tx off");
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCompleted
    );
    s.run(period(4) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(3)),
        None,
        "nothing queued for the next period"
    );
    let rr73 = s.row(period(4), "HB9BLA K1ABC RR73", 1240.0, Some(-7.0));
    let seventy_three = s.row(period(6), "HB9BLA K1ABC 73", 1240.0, Some(-7.0));
    s.deliver(&[rr73, seventy_three]);
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(s.engine.take_logs().is_empty(), "logged once, by Log QSO");
    s.command(Command::OpenLog).unwrap();
    assert_eq!(
        one_log(&mut s).id,
        logged.id,
        "a repeated Log QSO is the same contact"
    );
}

// Proves: CL-010-16; TC-007-009. The QSO pane's last partner message (ContactSnapshot
// last_rcvd): the latest counted partner message to my call with its rounded SNR; an
// identical repeat counts up (xN), a new text starts again at 1; a selected row to my call
// is the first one; a new contact starts empty.
#[test]
fn the_last_partner_message_counts_identical_repeats() {
    let mut s = station();
    let heard = |s: &Station| {
        s.engine
            .contact
            .as_ref()
            .unwrap()
            .last_rcvd
            .as_ref()
            .map(|h| (h.text.clone(), h.snr, h.period_ms, h.count))
    };
    let call = s.row(P0, "HB9BLA IW9FRA JM68", 1838.0, Some(9.6));
    s.command(Command::SelectRow {
        row: call,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        heard(&s),
        Some(("HB9BLA IW9FRA JM68".into(), Some(10), P0, 1))
    );
    for (n, text, snr, count) in [
        (2, "HB9BLA IW9FRA R+10", -3.4, 1),
        (4, "HB9BLA IW9FRA RR73", 17.0, 1),
        (6, "HB9BLA IW9FRA RR73", 9.0, 2),
        (8, "HB9BLA IW9FRA RR73", 16.0, 3),
    ] {
        let row = s.row(period(n), text, 1838.0, Some(snr));
        s.deliver(&[row]);
        let snr = Some(snr.round() as i32);
        assert_eq!(
            heard(&s),
            Some((text.into(), snr, period(n), count)),
            "{text} ({n})"
        );
    }
    // Another station to my call and a message to someone else are not the partner's.
    let other = s.row(period(10), "HB9BLA DL1ABC JO31", 1850.0, Some(-8.0));
    let elsewhere = s.row(period(10), "K1ABC IW9FRA 73", 1838.0, Some(5.0));
    s.deliver(&[other, elsewhere]);
    assert_eq!(heard(&s).map(|h| h.3), Some(3));
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    assert_eq!(heard(&s), None, "a new contact starts without one");
}

// Proves: CL-050-04; TC-050-004 (a). #50 (operator 2026-11-02, US5WFL then YO3GNF): calling
// another station while Enable Tx is on keeps it on, and the next own period calls the new
// station; nothing more goes to the old partner.
#[test]
fn changing_the_contact_while_armed_keeps_enable_tx_and_the_next_period_calls_the_new_station() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("K1ABC HB9BLA JN47"));
    let cause = s.core.view().last_disarm_cause;
    // K1ABC does not answer; the operator calls DL1ABC instead (an even-period CQ).
    let other = s.row(period(2), "CQ DL1ABC JO62", 800.0, Some(-3.0));
    s.command(Command::SelectRow {
        row: other,
        replace: true,
    })
    .unwrap();
    assert!(s.armed(), "Enable Tx stays on");
    assert_eq!(s.core.view().last_disarm_cause, cause, "no new disarm");
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("DL1ABC")
    );
    s.run(period(5) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("DL1ABC HB9BLA JN47"));
    assert!(
        s.sent
            .iter()
            .filter(|(p, _)| *p > period(1))
            .all(|(_, t)| t.starts_with("DL1ABC ")),
        "nothing more to K1ABC: {:?}",
        s.sent
    );
    // The same through a manual entry (enter_dx replace).
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    assert!(s.armed(), "a manual replacement keeps Enable Tx as well");
}

/// The 2026-11-02 22:48 CQ run (#10): four stations call my CQ in two periods, listed in
/// decode order.
fn callers(s: &mut Station, first: i64, second: i64) -> (Vec<Row>, Vec<Row>) {
    let a = vec![
        s.row(first, "HB9BLA EA4HTI IM69", 1678.0, Some(-8.0)),
        s.row(first, "HB9BLA F1PBZ -13", 2144.0, Some(-10.0)),
    ];
    let b = vec![
        s.row(second, "HB9BLA EA8BIA -11", 1595.0, Some(0.0)),
        s.row(second, "HB9BLA SV1DZB KM18", 1678.0, Some(-8.0)),
    ];
    (a, b)
}

// Proves: CL-010-17; TC-010-010. WSJT-X Call 1st (cbFirst, on by default): my own CQ
// answers the first caller of the period in decode order at once, with Enable Tx kept;
// the later callers change nothing.
#[test]
fn call_first_answers_the_first_caller_of_my_cq_in_the_next_own_period() {
    let mut s = station();
    s.command(Command::SetHoldTx(true)).unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    // Default parity odd: my CQ goes in period 1, the callers answer in period 2.
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("CQ HB9BLA JN47"));
    let (first, second) = callers(&mut s, period(2), period(4));
    // Delivered in reverse slice order: decode order (row sequence) decides.
    let reversed: Vec<Row> = first.iter().rev().cloned().collect();
    s.deliver(&reversed);
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        c.dx_call.as_deref(),
        Some("EA4HTI"),
        "the first caller in decode order"
    );
    assert_eq!(c.dx_grid.as_deref(), Some("IM69"));
    assert_eq!(
        s.state(),
        (State::Report, Slot::Tx2),
        "their grid: my report next"
    );
    assert_eq!(s.next_text(), "EA4HTI HB9BLA -08");
    assert!(s.armed(), "Enable Tx stays on");
    assert_eq!(s.engine.settings.tx_hz, 1500, "Hold Tx keeps my Tx offset");
    s.run(period(4) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("EA4HTI HB9BLA -08"));
    // Callers during a running QSO do not switch it.
    s.deliver(&second);
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("EA4HTI")
    );
}

// Proves: CL-010-17; TC-010-010. With Call 1st off, Auto Seq off, or only continuing
// exchanges to my call (R+report, RRR, RR73, 73: WSJT-X AutoRespondPeriod.cpp
// continuingExchange), the CQ keeps running; set_call_first changes the setting.
#[test]
fn call_first_off_auto_seq_off_or_a_sign_off_keep_the_cq_running() {
    assert!(
        Settings::default().call_first,
        "Call 1st is on by default (#10)"
    );
    for case in 0..4 {
        let mut s = station();
        match case {
            0 => s.command(Command::SetCallFirst(false)).unwrap(),
            1 => s.command(Command::SetAutoSeq(false)).unwrap(),
            _ => {}
        }
        s.command(Command::EnableTx(true, Some(7))).unwrap();
        s.run(period(2) + 14 * SECOND);
        if case == 3 {
            // Enable Tx off: the CQ contact stays calling, but nobody is answered.
            s.command(Command::EnableTx(false, None)).unwrap();
            let rows = callers(&mut s, period(2), period(4)).0;
            s.deliver(&rows);
            assert_eq!(s.state(), (State::Calling, Slot::Tx6), "Enable Tx off");
            s.run(period(3) + 14 * SECOND);
            assert_eq!(
                s.sent_in(period(3)),
                None,
                "nothing sent with Enable Tx off"
            );
            continue;
        }
        let rows = if case == 2 {
            vec![
                s.row(period(2), "HB9BLA DL1ABC RR73", 900.0, None),
                s.row(period(2), "HB9BLA DL2ABC 73", 950.0, None),
                s.row(period(2), "HB9BLA DL3ABC RRR", 990.0, None),
                s.row(period(2), "HB9BLA DL4ABC R-10", 1010.0, None),
            ]
        } else {
            callers(&mut s, period(2), period(4)).0
        };
        s.deliver(&rows);
        assert_eq!(s.state(), (State::Calling, Slot::Tx6), "case {case}");
        s.run(period(3) + 14 * SECOND);
        assert_eq!(
            s.sent_in(period(3)).as_deref(),
            Some("CQ HB9BLA JN47"),
            "case {case}"
        );
    }
    let mut s = station();
    s.command(Command::SetCallFirst(false)).unwrap();
    assert!(!s.engine.settings.call_first);
}

// Proves: CL-050-04; TC-050-004 (a). A switch in my own period after PTT is keyed and before
// its audio starts (FT8 audio delay 500 ms) replaces that period's request: the new
// contact's Tx1 goes out in the same period and Enable Tx stays on (review #50 finding 1).
#[test]
fn a_switch_in_the_keyed_window_before_audio_sends_the_new_contact_in_that_period() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(3) + 100);
    let keys = s.fake.0.keys.lock().unwrap().clone();
    assert_eq!(
        keys.last(),
        Some(&(period(3), true)),
        "PTT keyed at the period start"
    );
    assert!(!s.core.view().transmitting, "audio not started yet");
    let other = s.row(period(2), "CQ DL1ABC JO62", 800.0, Some(-3.0));
    s.command(Command::SelectRow {
        row: other,
        replace: true,
    })
    .unwrap();
    assert!(s.armed(), "Enable Tx stays on");
    s.run(period(3) + 14 * SECOND);
    assert!(s.armed());
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("DL1ABC HB9BLA JN47"));
}

// Proves: CL-009-03, CL-050-04; TC-050-004 (a). #10: a switch to a station of my own parity
// in the keyed window (PTT keyed, audio not started) moves the contact to the other parity.
// The keyed period's message still goes out, the new contact's Tx1 is queued for its next
// period and Enable Tx stays on: the core never refuses busy for that timing (review #50
// observation).
#[test]
fn a_parity_switch_in_the_keyed_window_keeps_enable_tx_and_queues_the_new_period() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(3) + 100);
    assert!(!s.core.view().transmitting, "audio not started yet");
    let other = s.row(period(1), "CQ DL1ABC JO62", 800.0, Some(-3.0));
    s.command(Command::SelectRow {
        row: other,
        replace: true,
    })
    .unwrap();
    assert!(s.armed(), "Enable Tx stays on: {:?}", s.core.view());
    s.run(period(4) + 14 * SECOND);
    assert!(s.armed(), "{:?}", s.core.view());
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("K1ABC HB9BLA JN47"));
    assert_eq!(s.sent_in(period(4)).as_deref(), Some("DL1ABC HB9BLA JN47"));
}

// Proves: CL-009-03; TC-050-004 (a). #10: Enable Tx late in my own period starts that
// period late. When the engine steps after PTT is keyed but before the owner's next tick
// starts the audio, and its lead already lies past the period's start window, the next
// own period's request is queued behind the keyed one; Enable Tx stays on (the debug-load
// failure of selected_row_prepares_without_transmit_and_only_an_explicit_enable_arms).
#[test]
fn a_late_start_keyed_before_audio_queues_the_next_own_period_without_disarming() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    s.run(period(3) + 10_100);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.core.tick(); // keys at once for the late admitted start
    assert_eq!(
        s.fake.0.keys.lock().unwrap().last(),
        Some(&(period(3) + 10_100, true))
    );
    assert!(!s.core.view().transmitting, "audio not started yet");
    // The engine steps before the owner's next tick: its target moves to period(5).
    s.fake.0.now.store(period(3) + 10_300, Ordering::SeqCst);
    s.step(&[]);
    assert!(s.armed(), "Enable Tx stays on: {:?}", s.core.view());
    s.run(period(5) + 14 * SECOND);
    assert!(s.armed(), "{:?}", s.core.view());
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("K1ABC HB9BLA JN47"));
    assert_eq!(s.sent_in(period(5)).as_deref(), Some("K1ABC HB9BLA JN47"));
}

// Proves: CL-050-06; TC-050-006 (a). #37 QSO dialogue: counted partner messages and this
// contact's transmissions as sent, oldest first, repeats counted, bounded; a new contact
// starts empty and a cancel empties it.
#[test]
fn the_contact_dialogue_holds_the_exchanged_messages_in_order() {
    let mut s = station();
    let cq = s.row(P0, "CQ K1ABC FN42", 1500.0, Some(-12.0));
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert!(
        s.engine.contact.as_ref().unwrap().dialogue.is_empty(),
        "a CQ row is not addressed to me"
    );
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(4) + 14 * SECOND);
    let report = s.row(period(4), "HB9BLA K1ABC -05", 1500.0, Some(-5.0));
    s.deliver(&[report]);
    s.run(period(6) + 14 * SECOND);
    let rr73 = s.row(period(6), "HB9BLA K1ABC RR73", 1500.0, Some(-6.0));
    s.deliver(&[rr73]);
    s.run(period(7) + 14 * SECOND);
    assert_eq!(s.state().0, State::Completed);
    let d: Vec<_> = s
        .engine
        .contact
        .as_ref()
        .unwrap()
        .dialogue
        .iter()
        .map(|e| (e.tx, e.text.clone(), e.snr, e.period_ms, e.count))
        .collect();
    let e = |tx: bool, t: &str, snr: Option<i32>, p: i64, n: u32| (tx, t.to_owned(), snr, p, n);
    assert_eq!(
        d,
        vec![
            e(true, "K1ABC HB9BLA JN47", None, period(1), 2),
            e(false, "HB9BLA K1ABC -05", Some(-5), period(4), 1),
            e(true, "K1ABC HB9BLA R-12", None, period(5), 1),
            e(false, "HB9BLA K1ABC RR73", Some(-6), period(6), 1),
            e(true, "K1ABC HB9BLA 73", None, period(7), 1),
        ]
    );
    // A new contact starts empty; its selected row to me is its first entry.
    let call = s.row(period(8), "HB9BLA W1AW FN31", 700.0, Some(1.0));
    s.command(Command::SelectRow {
        row: call,
        replace: false,
    })
    .unwrap();
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!(c.dialogue.len(), 1);
    assert_eq!(c.dialogue[0].text, "HB9BLA W1AW FN31");
    // Bounded: the oldest entries are dropped beyond DIALOGUE_MAX (Auto Seq off, so the
    // reports are counted without changing the state).
    s.command(Command::SetAutoSeq(false)).unwrap();
    for i in 0..20 {
        let r = s.row(
            period(8 + 2 * i),
            &format!("HB9BLA W1AW -{:02}", i + 1),
            700.0,
            None,
        );
        s.deliver(&[r]);
    }
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!(c.dialogue.len(), DIALOGUE_MAX);
    assert_eq!(c.dialogue.back().unwrap().text, "HB9BLA W1AW -20");
    // #60: a repeated message keeps its first period and takes the latest non-null SNR.
    for (p, snr) in [
        (period(48), Some(-12.0)),
        (period(50), Some(-3.0)),
        (period(52), None),
    ] {
        let r = s.row(p, "HB9BLA W1AW -07", 700.0, snr);
        s.deliver(&[r]);
    }
    let last = s.engine.contact.as_ref().unwrap().dialogue.back().unwrap();
    assert_eq!(
        (last.text.as_str(), last.snr, last.period_ms, last.count),
        ("HB9BLA W1AW -07", Some(-3), period(48), 3)
    );
    s.command(Command::Cancel).unwrap();
    assert!(
        s.engine.contact.as_ref().unwrap().dialogue.is_empty(),
        "cancel empties it"
    );
}

// ---------------------------------------------------------------- #24 S1b
/// A decoded row as the station builds it (WstxOfflineDecode::HashResolution, then the
/// station's row reader): packed, unpacked, filled in from `table`, which then learns it.
fn decoded(
    s: &mut Station,
    table: &mut wstx_rust::decoder::HashTable,
    period: i64,
    text: &str,
    hz: f64,
    snr: f64,
) -> Row {
    use wstx_rust::decoder::{Decode, unpack};
    let payload = table.resolve(&unpack(&wstx_rust::transmit::pack(text).unwrap().bits));
    table.learn(&payload);
    s.sequence += 1;
    let mut record = serde_json::to_value(Decode {
        payload,
        start_frame: 0,
        frequency_hz: hz,
        snr_db: Some(snr),
        a_priori: None,
    })
    .unwrap();
    record["sequence"] = serde_json::json!(s.sequence);
    record["period_start_utc"] = serde_json::json!(utc_text(period));
    let identity = ("s".to_string(), "j".to_string(), 1);
    crate::contact_http::row_of(&record, &identity, "ft8").unwrap()
}
fn set(s: &Station) -> Vec<String> {
    s.engine
        .contact
        .as_ref()
        .unwrap()
        .messages
        .iter()
        .map(|m| m.clone().unwrap_or_default())
        .collect()
}

// Proves: CL-024-01; TC-024-003 (a). A standard station works a nonstandard CQ caller
// with WSJT-X's compound message set and sequences it to the log.
#[test]
fn a_standard_call_works_a_nonstandard_partner_to_the_log() {
    let mut s = station();
    let mut table = wstx_rust::decoder::HashTable::new();
    table.set_my_call(Some("HB9BLA"));
    let cq = decoded(&mut s, &mut table, P0, "CQ PJ4/K1ABC", 1234.6, -12.4);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        set(&s),
        [
            "<PJ4/K1ABC> HB9BLA JN47",
            "<PJ4/K1ABC> HB9BLA -12",
            "<PJ4/K1ABC> HB9BLA R-12",
            "PJ4/K1ABC <HB9BLA> RRR",
            "PJ4/K1ABC <HB9BLA> 73",
            "CQ HB9BLA JN47"
        ]
    );
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(1)).as_deref(),
        Some("<PJ4/K1ABC> HB9BLA JN47")
    );
    let report = decoded(
        &mut s,
        &mut table,
        period(2),
        "HB9BLA <PJ4/K1ABC> -12",
        1240.0,
        -7.0,
    );
    assert_eq!(report.text, "HB9BLA <PJ4/K1ABC> -12");
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(period(4) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(3)).as_deref(),
        Some("<PJ4/K1ABC> HB9BLA R-12")
    );
    let rr73 = decoded(
        &mut s,
        &mut table,
        period(4),
        "<HB9BLA> PJ4/K1ABC RR73",
        1240.0,
        -7.0,
    );
    assert_eq!(rr73.text, "<HB9BLA> PJ4/K1ABC RR73");
    s.deliver(&[rr73]);
    assert_eq!(s.state(), (State::Signoff, Slot::Tx5));
    s.run(period(6));
    assert_eq!(
        s.sent_in(period(5)).as_deref(),
        Some("PJ4/K1ABC <HB9BLA> 73")
    );
    assert_eq!(s.state().0, State::Completed);
    let logged = one_log(&mut s);
    assert_eq!(logged.dx_call.as_deref(), Some("PJ4/K1ABC"));
    assert_eq!(logged.report_rcvd, Some(-12));
}

// Proves: CL-024-01; TC-024-003 (b). A nonstandard own call calls CQ without a grid and
// answers a standard caller with its hashed own call.
#[test]
fn a_nonstandard_own_call_answers_a_standard_caller_to_the_log() {
    let mut s = station();
    s.call = "DL/HB9BLA".into();
    s.engine.settings.call_first = false;
    let mut table = wstx_rust::decoder::HashTable::new();
    table.set_my_call(Some("DL/HB9BLA"));
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(set(&s)[5], "CQ DL/HB9BLA");
    s.run(period(1) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("CQ DL/HB9BLA"));
    let call = decoded(
        &mut s,
        &mut table,
        period(2),
        "<DL/HB9BLA> K1ABC FN42",
        1240.0,
        -9.0,
    );
    assert_eq!(call.text, "<DL/HB9BLA> K1ABC FN42");
    s.command(Command::SelectRow {
        row: call,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        set(&s),
        [
            "<K1ABC> DL/HB9BLA",
            "K1ABC <DL/HB9BLA> -09",
            "K1ABC <DL/HB9BLA> R-09",
            "<K1ABC> DL/HB9BLA RRR",
            "<K1ABC> DL/HB9BLA 73",
            "CQ DL/HB9BLA"
        ]
    );
    assert_eq!(s.state(), (State::Report, Slot::Tx2));
    s.run(period(4) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(3)).as_deref(),
        Some("K1ABC <DL/HB9BLA> -09")
    );
    let rr = decoded(
        &mut s,
        &mut table,
        period(4),
        "<DL/HB9BLA> K1ABC R-07",
        1240.0,
        -9.0,
    );
    s.deliver(&[rr]);
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
    s.run(period(6) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(5)).as_deref(),
        Some("<K1ABC> DL/HB9BLA RRR")
    );
    let bye = decoded(
        &mut s,
        &mut table,
        period(6),
        "DL/HB9BLA <K1ABC> 73",
        1240.0,
        -9.0,
    );
    assert_eq!(bye.text, "DL/HB9BLA <K1ABC> 73");
    s.deliver(&[bye]);
    assert_eq!(s.state().0, State::Completed);
    let logged = one_log(&mut s);
    assert_eq!(
        (
            logged.dx_call.as_deref(),
            logged.dx_grid.as_deref(),
            logged.report_rcvd
        ),
        (Some("K1ABC"), Some("FN42"), Some(-7))
    );
}

// Proves: CL-024-01; TC-024-003 (c, d). Nonstandard entries, two nonstandard calls,
// unresolved hashes and Tx5 free text.
#[test]
fn nonstandard_entries_and_free_text_are_validated() {
    let mut s = station();
    let enter = |s: &mut Station, call: &str| {
        s.command(Command::EnterDx {
            call: call.into(),
            grid: None,
            replace: true,
        })
    };
    enter(&mut s, "YW18FIFA").unwrap();
    assert_eq!(set(&s)[0], "<YW18FIFA> HB9BLA JN47");
    enter(&mut s, "PJ4/K1ABC/P").unwrap();
    assert_eq!(set(&s)[3], "PJ4/K1ABC/P <HB9BLA> RRR");
    assert_eq!(enter(&mut s, "PJ4/K1ABCDEF"), Err("invalid_call"));
    let mut table = wstx_rust::decoder::HashTable::new();
    let row = decoded(
        &mut s,
        &mut table,
        P0,
        "W9XYZ <PJ4/K9XX> -10",
        1500.0,
        -10.0,
    );
    assert_eq!(
        s.command(Command::SelectRow { row, replace: true }),
        Err("row_not_standard")
    );
    // An i3=4 row whose hashed 'from' is unresolved names no partner either.
    let row = decoded(
        &mut s,
        &mut table,
        P0,
        "PJ4/K9YY <W8ZZZ> RR73",
        1500.0,
        -10.0,
    );
    assert_eq!(row.text, "PJ4/K9YY <...> RR73");
    assert_eq!(
        s.command(Command::SelectRow { row, replace: true }),
        Err("row_not_standard")
    );
    let row = decoded(
        &mut s,
        &mut table,
        P0,
        "<PJ4/K9XX> W9XYZ RR73",
        1500.0,
        -10.0,
    );
    s.command(Command::SelectRow { row, replace: true })
        .unwrap();
    for (text, expected) in [
        ("tnx 73 gl", Ok("TNX 73 GL")),
        ("TNX FER QSO 73 GL", Err("invalid_message")),
        ("HI, 73", Err("invalid_message")),
        ("<W9XYZ> PA/K1XX 73", Ok("<W9XYZ> PA/K1XX 73")),
    ] {
        let r = s.command(Command::EditMessage(Slot::Tx5, text.into()));
        assert_eq!(
            r.map(|_| set(&s)[4].clone()),
            expected.map(String::from),
            "{text}"
        );
    }
    s.call = "DL/HB9BLA".into();
    assert_eq!(
        enter(&mut s, "PA/K1XX"),
        Err("invalid_call"),
        "two nonstandard calls"
    );
    enter(&mut s, "K1ABC").unwrap();
    assert_eq!(set(&s)[1], "K1ABC <DL/HB9BLA> -10");
}

// Proves: CL-024-01; TC-024-003 (e). Call 1st answers only plain standard callers.
#[test]
fn call_first_skips_hashed_and_nonstandard_callers() {
    let mut s = station();
    let mut table = wstx_rust::decoder::HashTable::new();
    table.set_my_call(Some("HB9BLA"));
    decoded(&mut s, &mut table, P0, "CQ PJ4/K1ABC", 1000.0, -10.0);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(1) + 14 * SECOND);
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    let rows = [
        decoded(
            &mut s,
            &mut table,
            period(2),
            "<HB9BLA> PA/K1XX",
            1100.0,
            -10.0,
        ),
        decoded(
            &mut s,
            &mut table,
            period(2),
            "HB9BLA <PJ4/K1ABC> -12",
            1200.0,
            -10.0,
        ),
        decoded(
            &mut s,
            &mut table,
            period(2),
            "HB9BLA W9XYZ -10",
            1300.0,
            -10.0,
        ),
    ];
    assert_eq!(rows[1].text, "HB9BLA <PJ4/K1ABC> -12");
    s.deliver(&rows);
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!(c.dx_call.as_deref(), Some("W9XYZ"));
}

// Proves: CL-024-01; TC-024-003 (d). A free-text Tx5 on an own CQ is sent once like a 73:
// the contact completes and, without a partner, nothing goes to the log.
#[test]
fn a_free_text_tx5_on_an_own_cq_is_sent_once_and_never_logged() {
    let mut s = station();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.command(Command::EditMessage(Slot::Tx5, "tnx 73 gl".into()))
        .unwrap();
    s.command(Command::ChooseNext(Slot::Tx5)).unwrap();
    assert_eq!(s.state(), (State::Signoff, Slot::Tx5));
    s.run(period(4));
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("TNX 73 GL"));
    assert_eq!(s.sent.len(), 1, "sent once: {:?}", s.sent);
    assert_eq!(s.state().0, State::Completed);
    assert!(!s.armed());
    assert!(s.engine.take_logs().is_empty());
}

// ---------------------------------------------------------------- #24 S2a
// Proves: CL-024-02; TC-024-005 (a). WW Digi: CQ WW, a caller's grid answered with R+grid,
// RR73 answered with 73 and the contact logged with the grid and no reports.
#[test]
fn ww_digi_answers_a_caller_grid_with_r_grid_and_logs_on_rr73() {
    let mut s = station();
    let mut table = wstx_rust::decoder::HashTable::new();
    s.command(Command::SetContest {
        activity: Activity::WwDigi,
        exchange: None,
    })
    .unwrap();
    s.engine.settings.call_first = false;
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(set(&s)[5], "CQ WW HB9BLA JN47");
    s.run(period(1) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("CQ WW HB9BLA JN47"));
    let caller = decoded(
        &mut s,
        &mut table,
        period(2),
        "HB9BLA S52XYZ JN76",
        1300.0,
        -8.0,
    );
    s.command(Command::SelectRow {
        row: caller,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        set(&s),
        [
            "S52XYZ HB9BLA JN47",
            "S52XYZ HB9BLA JN47",
            "S52XYZ HB9BLA R JN47",
            "S52XYZ HB9BLA RRR",
            "S52XYZ HB9BLA 73",
            "CQ WW HB9BLA JN47"
        ]
    );
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(period(3) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(3)).as_deref(),
        Some("S52XYZ HB9BLA R JN47")
    );
    let rr73 = decoded(
        &mut s,
        &mut table,
        period(4),
        "HB9BLA S52XYZ RR73",
        1300.0,
        -8.0,
    );
    s.deliver(&[rr73]);
    assert_eq!(s.state(), (State::Signoff, Slot::Tx5));
    s.run(period(6));
    assert_eq!(s.sent_in(period(5)).as_deref(), Some("S52XYZ HB9BLA 73"));
    let logged = one_log(&mut s);
    assert_eq!(
        (
            logged.dx_call.as_deref(),
            logged.dx_grid.as_deref(),
            logged.report_sent,
            logged.report_rcvd
        ),
        (Some("S52XYZ"), Some("JN76"), None, None)
    );
}

// Proves: CL-024-02; TC-024-005 (b). NA VHF: answering a CQ TEST, the CQer's R+grid
// moves to Tx4 and the partner's 73 completes the contact.
#[test]
fn na_vhf_moves_to_rogers_on_r_grid() {
    let mut s = station();
    let mut table = wstx_rust::decoder::HashTable::new();
    s.command(Command::SetContest {
        activity: Activity::NaVhf,
        exchange: None,
    })
    .unwrap();
    let cq = decoded(&mut s, &mut table, P0, "CQ TEST K1ABC FN42", 1200.0, -10.0);
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert_eq!(set(&s)[5], "CQ TEST HB9BLA JN47");
    assert_eq!(set(&s)[2], "K1ABC HB9BLA R JN47");
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("K1ABC HB9BLA JN47"));
    let r = decoded(
        &mut s,
        &mut table,
        period(2),
        "HB9BLA K1ABC R FN42",
        1200.0,
        -10.0,
    );
    s.deliver(&[r]);
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
    s.run(period(4) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("K1ABC HB9BLA RRR"));
    let bye = decoded(
        &mut s,
        &mut table,
        period(4),
        "HB9BLA K1ABC 73",
        1200.0,
        -10.0,
    );
    s.deliver(&[bye]);
    assert_eq!(s.state().0, State::Completed);
    assert_eq!(one_log(&mut s).dx_grid.as_deref(), Some("FN42"));
}

// Proves: CL-024-02; TC-024-005 (c, d). ARRL Digi with a nonstandard own call, and none.
#[test]
fn arrl_digi_with_a_nonstandard_own_call_and_back_to_none() {
    let mut s = station();
    s.call = "DL/HB9BLA".into();
    s.command(Command::SetContest {
        activity: Activity::ArrlDigi,
        exchange: None,
    })
    .unwrap();
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: None,
        replace: false,
    })
    .unwrap();
    assert_eq!(set(&s)[5], "CQ DL/HB9BLA");
    assert_eq!(set(&s)[1], "K1ABC <DL/HB9BLA> JN47");
    assert_eq!(set(&s)[2], "K1ABC <DL/HB9BLA> R JN47");
    s.call = "HB9BLA".into();
    s.command(Command::SetContest {
        activity: Activity::None,
        exchange: None,
    })
    .unwrap();
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    assert_eq!(set(&s)[1], "K1ABC HB9BLA -15");
    assert_eq!(set(&s)[5], "CQ HB9BLA JN47");
    for (a, name, udp) in [
        (Activity::None, "none", 0),
        (Activity::NaVhf, "na_vhf", 1),
        (Activity::WwDigi, "ww_digi", 5),
        (Activity::ArrlDigi, "arrl_digi", 8),
    ] {
        assert_eq!((a.name(), a.special_operation()), (name, udp));
        assert_eq!(Activity::parse(name), Some(a));
    }
    assert_eq!(Activity::parse("eu_vhf"), None);
}

// Proves: CL-024-02; TC-024-005 (e). The activity regenerates a running CQ's Tx6 and an
// active contact's exchange at once; a report change keeps Tx6.
#[test]
fn set_activity_regenerates_the_running_contact() {
    let mut s = station();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.command(Command::EditMessage(Slot::Tx6, "CQ DX HB9BLA JN47".into()))
        .unwrap();
    s.command(Command::SetContest {
        activity: Activity::WwDigi,
        exchange: None,
    })
    .unwrap();
    assert_eq!(set(&s)[5], "CQ WW HB9BLA JN47");
    s.command(Command::EditMessage(Slot::Tx6, "CQ DX HB9BLA JN47".into()))
        .unwrap();
    s.command(Command::SetReport(-10)).unwrap();
    assert_eq!(set(&s)[5], "CQ DX HB9BLA JN47", "a report change keeps Tx6");
    s.command(Command::SetContest {
        activity: Activity::None,
        exchange: None,
    })
    .unwrap();
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    assert_eq!(set(&s)[1..3], ["K1ABC HB9BLA -10", "K1ABC HB9BLA R-10"]);
    s.command(Command::SetContest {
        activity: Activity::WwDigi,
        exchange: None,
    })
    .unwrap();
    assert_eq!(set(&s)[1..3], ["K1ABC HB9BLA JN47", "K1ABC HB9BLA R JN47"]);
    s.command(Command::SetContest {
        activity: Activity::None,
        exchange: None,
    })
    .unwrap();
    assert_eq!(set(&s)[1..3], ["K1ABC HB9BLA -10", "K1ABC HB9BLA R-10"]);
    assert_eq!(set(&s)[5], "CQ HB9BLA JN47");
}

// ---------------------------------------------------------------- #24 S2b
fn decoded_in(s: &mut Station, period: i64, text: &str, snr: f64, mode: &str) -> Row {
    use wstx_rust::decoder::{Decode, unpack};
    let payload = unpack(&wstx_rust::transmit::pack(text).unwrap().bits);
    s.sequence += 1;
    let mut record = serde_json::to_value(Decode {
        payload,
        start_frame: 0,
        frequency_hz: 1300.0,
        snr_db: Some(snr),
        a_priori: None,
    })
    .unwrap();
    record["sequence"] = serde_json::json!(s.sequence);
    record["period_start_utc"] = serde_json::json!(utc_text(period));
    let identity = ("s".to_string(), "j".to_string(), 1);
    crate::contact_http::row_of(&record, &identity, mode).unwrap()
}
fn contest(s: &mut Station, activity: Activity, exchange: &str) {
    s.command(Command::SetContest {
        activity,
        exchange: Some(exchange.into()),
    })
    .unwrap();
}
fn adif_of(c: &Contact) -> String {
    let record = crate::contact_http::Station::record_of(
        c,
        P0 + 300 * SECOND,
        Some(7_074_000),
        1500,
        "HB9BLA",
        Some("JN47AA"),
    )
    .unwrap();
    assert_eq!(
        crate::logbook::validate_record(&record, "HB9BLA", "JN47AA"),
        Ok(())
    );
    record.adi_fields()
}

// Proves: CL-024-03; TC-024-008 (a). Field Day as the CQer: CQ FD, the caller's exchange
// answered with R + my exchange, RR73 answered with 73, logged with the ADIF contest fields.
#[test]
fn field_day_cq_answers_the_exchange_and_logs_the_contest_fields() {
    let mut s = station();
    contest(&mut s, Activity::FieldDay, "1a  ema");
    assert_eq!(s.engine.settings.exchange.as_deref(), Some("1A EMA"));
    s.engine.settings.call_first = false;
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(set(&s)[5], "CQ FD HB9BLA JN47");
    s.run(period(1) + 14 * SECOND);
    let caller = decoded_in(&mut s, period(2), "HB9BLA K1ABC 2A WI", -8.0, "ft8");
    s.command(Command::SelectRow {
        row: caller,
        replace: false,
    })
    .unwrap();
    assert_eq!(
        set(&s),
        [
            "K1ABC HB9BLA JN47",
            "K1ABC HB9BLA 1A EMA",
            "K1ABC HB9BLA R 1A EMA",
            "K1ABC HB9BLA RRR",
            "K1ABC HB9BLA 73",
            "CQ FD HB9BLA JN47"
        ]
    );
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(period(3) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(3)).as_deref(),
        Some("K1ABC HB9BLA R 1A EMA")
    );
    let rr73 = decoded_in(&mut s, period(4), "HB9BLA K1ABC RR73", -8.0, "ft8");
    s.deliver(&[rr73]);
    s.run(period(6));
    assert_eq!(s.sent_in(period(5)).as_deref(), Some("K1ABC HB9BLA 73"));
    let c = one_log(&mut s);
    assert_eq!(
        (c.exchange_sent.as_deref(), c.exchange_rcvd.as_deref()),
        (Some("1A EMA"), Some("2A WI"))
    );
    assert_eq!(s.engine.settings.serial, 2);
    let adif = adif_of(&c);
    for field in [
        "<stx_string:6>1A EMA",
        "<contest_id:14>ARRL-FIELD-DAY",
        "<srx_string:5>2A WI",
        "<class:2>2A",
        "<arrl_sect:2>WI",
    ] {
        assert!(adif.contains(field), "{field} in {adif}");
    }
    assert!(!adif.contains("rst_"), "{adif}");
}

// Proves: CL-024-03; TC-024-008 (b). RTTY Roundup with a DX serial: answering CQ RU
// starts with Tx2 (Tx1 disabled), "5n9 serial", the TU; R exchange moves to Tx4, the log
// has the 5n9 RSTs, STX and STATE, and the next contact sends the next serial.
#[test]
fn rtty_roundup_answers_cq_ru_with_tx2_and_logs_rst_stx_and_state() {
    let mut s = station();
    contest(&mut s, Activity::Rtty, "DX");
    let cq = decoded_in(&mut s, P0, "CQ RU W9XYZ EN37", -3.0, "ft8");
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    assert_eq!(set(&s)[1], "W9XYZ HB9BLA 559 0001");
    assert_eq!(set(&s)[5], "CQ RU HB9BLA JN47");
    assert_eq!(s.state(), (State::Report, Slot::Tx2));
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 14 * SECOND);
    assert_eq!(
        s.sent_in(period(1)).as_deref(),
        Some("W9XYZ HB9BLA 559 0001")
    );
    let r = decoded_in(&mut s, period(2), "TU; HB9BLA W9XYZ R 579 MA", -3.0, "ft8");
    s.deliver(&[r]);
    assert_eq!(s.state(), (State::Rogers, Slot::Tx4));
    s.run(period(4) + 14 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("W9XYZ HB9BLA RRR"));
    let bye = decoded_in(&mut s, period(4), "HB9BLA W9XYZ 73", -3.0, "ft8");
    s.deliver(&[bye]);
    let c = one_log(&mut s);
    assert_eq!(
        (c.exchange_sent.as_deref(), c.exchange_rcvd.as_deref()),
        (Some("559 0001"), Some("579 MA"))
    );
    let adif = adif_of(&c);
    for field in [
        "<rst_sent:3>559",
        "<rst_rcvd:3>579",
        "<stx:4>0001",
        "<state:2>MA",
    ] {
        assert!(adif.contains(field), "{field} in {adif}");
    }
    assert!(!adif.contains("contest_id"), "{adif}");
    let next = decoded_in(&mut s, period(6), "CQ RU K9AN EN50", -3.0, "ft8");
    s.command(Command::SelectRow {
        row: next,
        replace: false,
    })
    .unwrap();
    assert_eq!(set(&s)[1], "K9AN HB9BLA 559 0002");
}

fn ft4_period(n: i64) -> i64 {
    P0 + n * 7_500
}
/// FT4 RTTY: Tx3 to K1ABC in period 1, their RR73 counted 3 s into period 2 (my Tx3
/// started 10.5 s before), then a new caller selected `after` ms later; returns its Tx3.
fn ft4_next_caller_tx3(after: i64) -> String {
    let mut s = ft4_station();
    contest(&mut s, Activity::Rtty, "MA");
    let caller = decoded_in(&mut s, ft4_period(0), "HB9BLA K1ABC 579 NY", -3.0, "ft4");
    s.command(Command::SelectRow {
        row: caller,
        replace: false,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(ft4_period(2) + 3_000);
    assert_eq!(
        s.sent_in(ft4_period(1)).as_deref(),
        Some("K1ABC HB9BLA R 559 MA")
    );
    let rr73 = decoded_in(&mut s, ft4_period(2), "HB9BLA K1ABC RR73", -3.0, "ft4");
    s.deliver(&[rr73]);
    s.fake
        .0
        .now
        .store(ft4_period(2) + 3_000 + after, Ordering::SeqCst);
    let next = decoded_in(&mut s, ft4_period(2), "HB9BLA W9XYZ 579 OH", -3.0, "ft4");
    s.command(Command::SelectRow {
        row: next,
        replace: true,
    })
    .unwrap();
    set(&s)[2].clone()
}
// Proves: CL-024-03; TC-024-008 (c). FT4 TU;: the operator's selection right after an
// RR73 thanks the previous partner in Tx3; three whole seconds later it does not.
#[test]
fn ft4_rtty_selection_right_after_rr73_prefixes_tu() {
    assert_eq!(ft4_next_caller_tx3(500), "TU; W9XYZ HB9BLA R 559 MA");
    assert_eq!(ft4_next_caller_tx3(3_000), "W9XYZ HB9BLA R 559 MA");
}

// Proves: CL-024-03; TC-024-008 (d), (e). Exchange validation, a nonstandard DX call, a
// Field Day row in RTTY, the UDP values, and the slots accept a contest text.
#[test]
fn contest_exchanges_are_validated_and_rows_of_another_family_are_other() {
    let fd = |x: Option<&str>| contest_exchange(Activity::FieldDay, x);
    assert_eq!(fd(Some(" 32f  wwa ")), Some(Some("32F WWA".into())));
    for bad in [
        None,
        Some("0A EMA"),
        Some("33A EMA"),
        Some("1G EMA"),
        Some("1A XX"),
        Some("1AEMA"),
    ] {
        assert_eq!(fd(bad), None, "{bad:?}");
    }
    let rtty = |x: Option<&str>| contest_exchange(Activity::Rtty, x);
    for good in ["MA", "#", "dx", "PEI", "X99", "DR"] {
        assert!(rtty(Some(good)).is_some(), "{good}");
    }
    assert_eq!(rtty(Some("DXX")), None);
    assert_eq!(rtty(Some("0013")), Some(Some("0013".into())));
    assert_eq!(rtty(Some("8000")), None);
    // Non-ASCII is refused, never a panic (review S2b2 finding 1).
    assert_eq!(fd(Some("1\u{e9} EMA")), None);
    assert_eq!(rtty(Some("\u{e9}")), None);
    assert_eq!(contest_exchange(Activity::WwDigi, Some("MA")), None);
    assert_eq!(contest_exchange(Activity::None, None), Some(None));
    let mut s = station();
    assert_eq!(
        s.command(Command::SetContest {
            activity: Activity::FieldDay,
            exchange: None
        }),
        Err("invalid_exchange")
    );
    contest(&mut s, Activity::FieldDay, "1A EMA");
    assert_eq!(
        s.command(Command::EnterDx {
            call: "PJ4/K1ABC".into(),
            grid: None,
            replace: false
        }),
        Err("invalid_call")
    );
    let fd_row = decoded_in(&mut s, P0, "HB9BLA K1ABC 2A WI", -3.0, "ft8");
    let fd_msg = fd_row.standard.clone().unwrap();
    assert_eq!(
        classify_in(&fd_msg, Activity::FieldDay),
        Received::SignalReport
    );
    assert_eq!(classify_in(&fd_msg, Activity::Rtty), Received::Other);
    assert_eq!(classify_in(&fd_msg, Activity::None), Received::Other);
    assert_eq!(
        (
            Activity::FieldDay.special_operation(),
            Activity::Rtty.special_operation()
        ),
        (3, 4)
    );
    assert_eq!(
        slot_text("k1abc hb9bla 3a wi").as_deref(),
        Some("K1ABC HB9BLA 3A WI")
    );
    assert_eq!(
        slot_text("TU; K1ABC HB9BLA R 579 MA").as_deref(),
        Some("TU; K1ABC HB9BLA R 579 MA")
    );
    // A contact prepared before the activity changes follows it (review S2b2 finding 2).
    let mut s = station();
    let cq = decoded_in(&mut s, P0, "CQ K1ABC FN42", -3.0, "ft8");
    s.command(Command::SelectRow {
        row: cq,
        replace: false,
    })
    .unwrap();
    contest(&mut s, Activity::FieldDay, "1A EMA");
    assert_eq!(
        s.engine.contact.as_ref().unwrap().activity,
        Activity::FieldDay
    );
    assert_eq!(set(&s)[1], "K1ABC HB9BLA 1A EMA");
}

// ---------------------------------------------------------------- #24 S4b Hound
const FOX: &str = "KH7Z";
/// The c28 of a standard call, as packed in the first call slot of i3=1.
fn c28(call: &str) -> u128 {
    let bits = wstx_rust::transmit::pack(&format!("{call} K1ABC RR73"))
        .unwrap()
        .bits;
    bits[..28]
        .iter()
        .fold(0u128, |v, b| (v << 1) | u128::from(*b))
}
/// A 0.1 DXpedition payload "FIRST RR73; SECOND <FOX> RPT" built from its fields (the
/// packer refuses 0.1): c28 c28 h10 r5 n3=1 i3=0.
pub(crate) fn dxpedition_bits(first: &str, second: &str, fox: &str, report: i32) -> [u8; 77] {
    let fields = [
        (c28(first), 28),
        (c28(second), 28),
        (
            u128::from(wstx_rust::decoder::ihashcall(fox, 10).unwrap()),
            10,
        ),
        (u128::try_from((report + 30) / 2).unwrap(), 5),
        (1, 3),
        (0, 3),
    ];
    let mut out = [0u8; 77];
    let mut at = 0;
    for (v, w) in fields {
        for i in (0..w).rev() {
            out[at] = ((v >> i) & 1) as u8;
            at += 1;
        }
    }
    assert_eq!(at, 77);
    out
}
/// A published record of `bits` as the station builds it: the DX call of the current
/// contact is set on the table first (the contact step), then fill-in and learning.
fn record_of_bits(
    s: &mut Station,
    table: &mut wstx_rust::decoder::HashTable,
    period: i64,
    bits: &[u8; 77],
    hz: f64,
    snr: f64,
) -> Row {
    use wstx_rust::decoder::{Decode, unpack};
    table.set_dx_call(s.engine.contact.as_ref().and_then(|c| c.dx_call.as_deref()));
    let payload = table.resolve(&unpack(bits));
    table.learn(&payload);
    s.sequence += 1;
    let mut record = serde_json::to_value(Decode {
        payload,
        start_frame: 0,
        frequency_hz: hz,
        snr_db: Some(snr),
        a_priori: None,
    })
    .unwrap();
    record["sequence"] = serde_json::json!(s.sequence);
    record["period_start_utc"] = serde_json::json!(utc_text(period));
    let identity = ("s".to_string(), "j".to_string(), 1);
    crate::contact_http::row_of(&record, &identity, "ft8").unwrap()
}
fn fox_says(
    s: &mut Station,
    table: &mut wstx_rust::decoder::HashTable,
    period: i64,
    text: &str,
    hz: f64,
    snr: f64,
) -> Row {
    let bits = wstx_rust::transmit::pack(text).unwrap().bits;
    record_of_bits(s, table, period, &bits, hz, snr)
}
fn hound_table() -> wstx_rust::decoder::HashTable {
    let mut t = wstx_rust::decoder::HashTable::new();
    t.set_my_call(Some("HB9BLA"));
    t
}
/// A Hound station whose random calling offset is 1717 Hz (asserting WSJT-X's range).
fn hound_station() -> Station {
    let mut s = station();
    s.engine.random_hz = Box::new(|lo, hi| {
        assert_eq!(
            (lo, hi),
            (1000, 2999),
            "QRandomGenerator bounded(1000, 2999)"
        );
        1717
    });
    s.command(Command::SetContest {
        activity: Activity::Hound,
        exchange: None,
    })
    .unwrap();
    s
}
fn select(s: &mut Station, row: Row) {
    s.command(Command::SelectRow {
        row,
        replace: false,
    })
    .unwrap();
}
impl Station {
    /// The Tx offset of the transmission that started in `period`.
    fn hz_in(&self, period: i64) -> Option<u32> {
        self.sent_hz
            .iter()
            .find(|(p, _)| *p == period)
            .map(|(_, hz)| *hz)
    }
}

// Proves: CL-024-04; TC-024-011 (a), (f). The Hound transmits in the second period, calls
// at a random 1000..2998 Hz offset when its offset is below 999 Hz, answers the Fox's
// report with Tx3 on the Fox's frequency, repeats it on Fox-300 Hz and logs on RR73.
#[test]
fn a_hound_calls_at_a_random_offset_and_answers_the_fox_report_on_its_frequency() {
    let mut s = station();
    s.engine.random_hz = Box::new(|lo, hi| {
        assert_eq!((lo, hi), (1000, 2999));
        1717
    });
    let mut t = hound_table();
    s.command(Command::SetParity(Parity::Even)).unwrap();
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(800),
    })
    .unwrap();
    s.command(Command::SetContest {
        activity: Activity::Hound,
        exchange: None,
    })
    .unwrap();
    assert_eq!(
        (
            s.engine.settings.parity,
            s.engine.settings.hold_tx,
            s.engine.settings.activity.special_operation()
        ),
        (Parity::Odd, true, 7),
        "Tx even/1st off, Hold Tx on, UDP special operation 7"
    );
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.4, -9.0);
    select(&mut s, cq);
    assert_eq!(
        s.engine.settings.tx_hz, 800,
        "a Hound selection keeps the Tx offset"
    );
    assert_eq!(s.engine.settings.rx_hz, 812);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    assert_eq!(s.next_text(), "KH7Z HB9BLA JN47");
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(1) + 2 * SECOND);
    assert_eq!(s.sent_in(period(1)).as_deref(), Some("KH7Z HB9BLA JN47"));
    assert_eq!(s.hz_in(period(1)), Some(1717), "random calling offset");
    s.run(period(2) + 13_500);
    let report = fox_says(&mut s, &mut t, period(2), "HB9BLA KH7Z -12", 812.4, -7.2);
    s.deliver(&[report]);
    let c = s.engine.contact.as_ref().unwrap();
    assert_eq!(c.report_rcvd, Some(-12));
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    assert_eq!(
        s.next_text(),
        "KH7Z HB9BLA R-07",
        "Tx3 carries the Fox's SNR"
    );
    assert_eq!(s.engine.settings.tx_hz, 812, "Tx3 on the Fox's frequency");
    assert_eq!(s.engine.hound.fox_hz, Some(812));
    s.run(period(5) + 2 * SECOND);
    assert_eq!(s.sent_in(period(3)).as_deref(), Some("KH7Z HB9BLA R-07"));
    assert_eq!(s.hz_in(period(3)), Some(812));
    assert_eq!(s.sent_in(period(4)), None, "never in the Fox's period");
    assert_eq!(s.sent_in(period(5)).as_deref(), Some("KH7Z HB9BLA R-07"));
    assert_eq!(s.hz_in(period(5)), Some(512), "a repeat goes to Fox-300 Hz");
    s.run(period(6) + 13_500);
    let rr73 = fox_says(&mut s, &mut t, period(6), "HB9BLA KH7Z RR73", 812.4, -6.0);
    s.deliver(&[rr73]);
    assert!(!s.armed());
    assert_eq!(
        s.core.view().last_disarm_cause,
        DisarmCause::ContactCompleted
    );
    assert_eq!(s.state().0, State::Completed);
    let fields = one_log(&mut s).log_fields(s.now()).unwrap();
    assert_eq!(
        (
            fields.call.as_str(),
            fields.rst_sent.as_deref(),
            fields.rst_rcvd.as_deref()
        ),
        ("KH7Z", Some("-07"), Some("-12"))
    );
    // (f) Calling the next Fox with a Tx offset of 1500 Hz keeps it.
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(1500),
    })
    .unwrap();
    let cq = fox_says(&mut s, &mut t, period(8), "CQ KH7Z BL01", 812.4, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(9) + 2 * SECOND);
    assert_eq!(s.sent_in(period(9)).as_deref(), Some("KH7Z HB9BLA JN47"));
    assert_eq!(s.hz_in(period(9)), Some(1500));
    assert!(
        s.sent
            .iter()
            .all(|(p, _)| wstx_rust::transmit::parity(Mode::Ft8, *p) == Parity::Odd),
        "every transmission in the second period: {:?}",
        s.sent
    );
}

// Proves: CL-024-04; TC-024-011 (b). The Fox's report inside a 0.1 multi-message is answered
// on its frequency, the repeat goes to Fox+300 Hz (Fox at or below 600 Hz), a repeated Fox
// report returns to the Fox's frequency, and the 0.1 RR73 to my call completes and logs.
#[test]
fn a_hound_answers_a_0_1_report_moves_300_hz_on_a_repeat_and_logs_the_0_1_rr73() {
    let mut s = hound_station();
    let mut t = hound_table();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 450.3, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13_500);
    assert_eq!(s.hz_in(period(1)), Some(1500), "1500 Hz is kept");
    let multi = record_of_bits(
        &mut s,
        &mut t,
        period(2),
        &dxpedition_bits("W9XYZ", "HB9BLA", FOX, -12),
        450.3,
        -5.0,
    );
    assert_eq!(multi.text, "W9XYZ RR73; HB9BLA <KH7Z> -12");
    assert!(multi.standard.is_none());
    s.deliver(&[multi]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    assert_eq!(s.next_text(), "KH7Z HB9BLA R-05");
    assert_eq!(s.engine.contact.as_ref().unwrap().report_rcvd, Some(-12));
    s.run(period(6) + 13_500);
    assert_eq!(s.hz_in(period(3)), Some(450));
    assert_eq!(s.hz_in(period(5)), Some(750), "Fox+300 Hz");
    let again = fox_says(&mut s, &mut t, period(6), "HB9BLA KH7Z -10", 450.3, -4.0);
    s.deliver(&[again]);
    assert_eq!(s.next_text(), "KH7Z HB9BLA R-04");
    s.run(period(10) + 13_500);
    assert_eq!(
        s.hz_in(period(7)),
        Some(450),
        "a repeated report: the Fox's frequency"
    );
    assert_eq!(s.hz_in(period(9)), Some(750));
    assert_eq!(s.sent_in(period(9)).as_deref(), Some("KH7Z HB9BLA R-04"));
    let done = record_of_bits(
        &mut s,
        &mut t,
        period(10),
        &dxpedition_bits("HB9BLA", "K1ABC", FOX, -8),
        450.3,
        -5.0,
    );
    assert_eq!(done.text, "HB9BLA RR73; K1ABC <KH7Z> -08");
    s.deliver(&[done]);
    assert!(!s.armed());
    assert_eq!(s.state().0, State::Completed);
    let fields = one_log(&mut s).log_fields(s.now()).unwrap();
    assert_eq!(
        (fields.call.as_str(), fields.rst_rcvd.as_deref()),
        ("KH7Z", Some("-10"))
    );
}

// Proves: CL-024-04; TC-024-011 (c). A Hound selects only Fox rows of :00/:30 that are not
// another Hound's R+report, transmits only Tx1/Tx3 in the second period, never calls CQ and
// exists only in FT8.
#[test]
fn a_hound_refuses_wrong_period_rows_other_hounds_other_slots_and_ft4() {
    let mut s = hound_station();
    let mut t = hound_table();
    assert_eq!(
        s.command(Command::EnableTx(true, Some(7))),
        Err("no_contact"),
        "a Hound never calls CQ"
    );
    let late = fox_says(&mut s, &mut t, period(1), "CQ KH7Z BL01", 812.0, -9.0);
    assert_eq!(
        s.command(Command::SelectRow {
            row: late,
            replace: false
        }),
        Err("state_conflict"),
        "a row decoded at :15"
    );
    let hound = fox_says(&mut s, &mut t, P0, "KH7Z W9XYZ R-05", 1900.0, -9.0);
    assert_eq!(
        s.command(Command::SelectRow {
            row: hound,
            replace: false
        }),
        Err("state_conflict"),
        "another Hound's Tx3"
    );
    let multi = record_of_bits(
        &mut s,
        &mut t,
        P0,
        &dxpedition_bits("W9XYZ", "K1ABC", FOX, -12),
        812.0,
        -9.0,
    );
    assert_eq!(
        s.command(Command::SelectRow {
            row: multi,
            replace: false
        }),
        Err("row_not_standard")
    );
    assert!(s.engine.contact.is_none(), "nothing prepared");
    let cq = fox_says(&mut s, &mut t, period(2), "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    assert_eq!(
        s.command(Command::SetParity(Parity::Even)),
        Err("state_conflict")
    );
    for slot in [Slot::Tx2, Slot::Tx4, Slot::Tx5, Slot::Tx6] {
        assert_eq!(
            s.command(Command::ChooseNext(slot)),
            Err("state_conflict"),
            "{slot:?}"
        );
    }
    s.command(Command::SetTx1Skip(true)).unwrap();
    s.command(Command::ChooseNext(Slot::Tx3)).unwrap();
    s.command(Command::ChooseNext(Slot::Tx1)).unwrap();
    assert_eq!(
        s.state(),
        (State::Replying, Slot::Tx1),
        "Tx1 is never skipped"
    );
    // FT4: the station mode change ends the Hound activity; hound is FT8 only.
    s.mode = Mode::Ft4;
    s.step(&[]);
    assert_eq!(s.engine.settings.activity, Activity::None);
    assert_eq!(
        s.command(Command::SetContest {
            activity: Activity::Hound,
            exchange: None
        }),
        Err("state_conflict")
    );
}

// Proves: CL-024-04; TC-024-011 (d). Not the Fox's report or RR73: an RR73 from another
// station, a 0.1 RR73 with another hashed call; during Tune only the Fox frequency is noted.
#[test]
fn a_hound_ignores_rr73_of_other_stations_and_replies_nothing_while_tuning() {
    let mut s = hound_station();
    let mut t = hound_table();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 5 * SECOND);
    let other = fox_says(&mut s, &mut t, period(2), "HB9BLA K1ABC RR73", 812.0, -9.0);
    let foreign = record_of_bits(
        &mut s,
        &mut t,
        period(2),
        &dxpedition_bits("HB9BLA", "W9XYZ", "VP8PJ", -8),
        900.0,
        -9.0,
    );
    let foreign_report = record_of_bits(
        &mut s,
        &mut t,
        period(2),
        &dxpedition_bits("W9XYZ", "HB9BLA", "VP8PJ", -8),
        900.0,
        -9.0,
    );
    s.deliver(&[other, foreign, foreign_report]);
    assert!(s.armed());
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    assert_eq!(s.engine.hound.fox_hz, None);
    // Tune needs the transmit owner armed without a request: arm it directly and tune.
    s.command(Command::EnableTx(false, None)).unwrap();
    s.core.arm(7).unwrap();
    s.core.set_tune(true, 1500).unwrap();
    let report = fox_says(&mut s, &mut t, period(2), "HB9BLA KH7Z -12", 812.0, -7.0);
    s.deliver(&[report]);
    assert_eq!(
        s.engine.hound.fox_hz,
        Some(812),
        "the Fox frequency is noted"
    );
    assert_eq!(
        s.state(),
        (State::Replying, Slot::Tx1),
        "no reply while Tune"
    );
    assert_eq!(s.engine.settings.tx_hz, 1500);
    s.core.set_tune(false, 1500).unwrap();
}

// Proves: CL-024-04; TC-024-011 (e). The reply timeout (11 T/R) and the Hound watchdog (300 s
// of Tx1) turn Enable Tx off; the station's Tx watchdog returns a Hound to Tx1.
#[test]
fn hound_reply_timeout_hound_watchdog_and_tx_watchdog() {
    // Reply timeout: 165 s after the Fox's report.
    let mut s = hound_station();
    let mut t = hound_table();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13_500);
    let report = fox_says(&mut s, &mut t, period(2), "HB9BLA KH7Z -12", 812.0, -7.0);
    let t0 = s.now();
    s.deliver(&[report]);
    s.run(t0 + 165 * SECOND - 100);
    assert!(s.armed(), "not before 11 T/R");
    s.run(t0 + 165 * SECOND + 100);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert_eq!(
        s.state(),
        (State::RogerReport, Slot::Tx3),
        "the slot stays Tx3"
    );

    // The operator turning Enable Tx off and on again ends the reply timeout (MW
    // on_autoButton_clicked stopWRTimer.stop(); review S4b finding 1).
    let mut s = hound_station();
    let mut t = hound_table();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13_500);
    let report = fox_says(&mut s, &mut t, period(2), "HB9BLA KH7Z -12", 812.0, -7.0);
    let t0 = s.now();
    s.deliver(&[report]);
    s.run(t0 + 20 * SECOND);
    s.command(Command::EnableTx(false, None)).unwrap();
    s.run(t0 + 150 * SECOND);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(t0 + 165 * SECOND + 100);
    assert!(s.armed(), "a re-arm ends the reply timeout");
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));

    // Hound watchdog: 300 s of Tx1 since the operator turned Enable Tx on (the Tx
    // watchdog's count is raised so it does not end first).
    let mut s = hound_station();
    let mut t = hound_table();
    s.command(Command::SetWatchdogs {
        tx_calls: 99,
        tune_seconds: 90,
    })
    .unwrap();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    let on = s.now();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(on + 300 * SECOND - 100);
    assert!(s.armed());
    s.run(on + 300 * SECOND + 100);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert!(
        !s.core.view().tx_expired,
        "the Hound watchdog, not the Tx watchdog"
    );
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));

    // The station's Tx watchdog (1 unanswered call) while Tx3 repeats: back to Tx1.
    let mut s = hound_station();
    let mut t = hound_table();
    s.command(Command::SetWatchdogs {
        tx_calls: 1,
        tune_seconds: 90,
    })
    .unwrap();
    let cq = fox_says(&mut s, &mut t, P0, "CQ KH7Z BL01", 812.0, -9.0);
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    s.run(period(2) + 13_500);
    let report = fox_says(&mut s, &mut t, period(2), "HB9BLA KH7Z -12", 812.0, -7.0);
    s.deliver(&[report]);
    s.run(period(3) + 100 * SECOND);
    assert!(!s.armed());
    assert!(s.core.view().tx_expired);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
}

// ---------------------------------------------------------------- TC-024-014
/// The 12 kHz samples of the Hound's own waveforms that started in `period` (decimated
/// from the 48 kHz the transmit owner played), at their offset from the period start.
fn hound_audio(s: &Station, period: i64, into: &mut [f32]) {
    for (at, samples, skip) in s.fake.0.audio.lock().unwrap().iter() {
        if *at < period || *at >= period + 15 * SECOND {
            continue;
        }
        let peak = samples.iter().fold(0f32, |m, x| m.max(x.abs())).max(1e-9);
        let offset = usize::try_from((at - period) * 12).unwrap();
        for (k, x) in samples[*skip..].iter().step_by(4).enumerate() {
            if let Some(slot) = into.get_mut(offset + k) {
                *slot += 0.1 * x / peak;
            }
        }
    }
}
/// One 15 s FT8 period at 12 kHz: uniform noise plus Fox frames (77 bits, tone-0 Hz)
/// starting 0.5 s after the period start, with the station's waveform generator.
fn fox_audio(frames: &[([u8; 77], f64)], seed: u64) -> Vec<f32> {
    use wstx_rust::decoder::{Channel, quadratures};
    let channel = Channel::new();
    let mut state = seed;
    let mut audio: Vec<f32> = (0..180_000)
        .map(|_| {
            state = state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (((state >> 33) as f64 / (1u64 << 31) as f64 - 0.5) * 0.6) as f32
        })
        .collect();
    for (bits, hz) in frames {
        let tones = channel.tones(&channel.encode(bits, Mode::Ft8), Mode::Ft8);
        let wave = quadratures(Mode::Ft8, &tones, *hz).unwrap();
        for (k, w) in wave.iter().enumerate() {
            if let Some(slot) = audio.get_mut(6000 + k) {
                *slot += 0.1 * w[0];
            }
        }
    }
    audio
}
fn decode_period(audio: &[f32]) -> Vec<wstx_rust::decoder::Decode> {
    wstx_rust::decoder::Decoder::new()
        .decode(audio, Mode::Ft8, &|| false)
        .unwrap()
}
/// The Hound's rows of one decoded period, through its hash table and row reader.
fn hound_rows(
    s: &mut Station,
    table: &mut wstx_rust::decoder::HashTable,
    period: i64,
    audio: &[f32],
) -> Vec<Row> {
    decode_period(audio)
        .into_iter()
        .map(|d| {
            let bits: [u8; 77] = std::array::from_fn(|i| d.payload.payload77.as_bytes()[i] - b'0');
            record_of_bits(
                s,
                table,
                period,
                &bits,
                d.frequency_hz,
                d.snr_db.unwrap_or(-10.0),
            )
        })
        .collect()
}
fn noise(seed: u64) -> Vec<f32> {
    fox_audio(&[], seed)
}

// Proves: CL-024-04; TC-024-014. A Hound QSO with a scripted Fox over an audio loopback with
// no RF: the Fox decodes the waveforms the transmit owner played and the Hound decodes the
// Fox's synthesized frames with the station's decoder, hash table and row reader.
#[test]
fn a_hound_works_a_scripted_fox_over_an_audio_loopback() {
    let mut s = hound_station();
    let mut t = hound_table();
    s.command(Command::SetFrequency {
        rx: None,
        tx: Some(700),
    })
    .unwrap();
    let packed = |text: &str| wstx_rust::transmit::pack(text).unwrap().bits;
    let fox_heard = |audio: &[f32]| {
        decode_period(audio)
            .into_iter()
            // The station renders R+report as "R -04" (decoder_signal canonical()).
            .map(|d| {
                let text = d.payload.text.unwrap_or_default();
                (
                    text.replace(" R -", " R-").replace(" R +", " R+"),
                    d.frequency_hz,
                )
            })
            .collect::<Vec<_>>()
    };
    // Period 0: the Fox calls CQ at 800 Hz; the operator selects it and enables Tx.
    s.run(P0 + 13_500);
    let rows = hound_rows(
        &mut s,
        &mut t,
        P0,
        &fox_audio(&[(packed("CQ KH7Z BL01"), 800.0)], 1),
    );
    let cq = rows
        .iter()
        .find(|r| r.text == "CQ KH7Z BL01")
        .cloned()
        .unwrap_or_else(|| panic!("the Fox's CQ decodes: {rows:?}"));
    select(&mut s, cq);
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    // Period 1: the Fox decodes my Tx1 at the random calling offset.
    s.run(period(2));
    let mut audio = noise(2);
    hound_audio(&s, period(1), &mut audio);
    let heard = fox_heard(&audio);
    assert!(
        heard
            .iter()
            .any(|(text, hz)| text == "KH7Z HB9BLA JN47" && (hz - 1717.0).abs() <= 3.0),
        "the Fox hears Tx1 at 1717 Hz: {heard:?}"
    );
    // Period 2: the Fox's 0.1 multi-message carries my report.
    s.run(period(2) + 13_500);
    let rows = hound_rows(
        &mut s,
        &mut t,
        period(2),
        &fox_audio(&[(dxpedition_bits("W9XYZ", "HB9BLA", FOX, -12), 800.0)], 3),
    );
    assert!(
        rows.iter()
            .any(|r| r.text == "W9XYZ RR73; HB9BLA <KH7Z> -12"),
        "the 0.1 report with the Fox filled in: {rows:?}"
    );
    s.deliver(&rows);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    let tx3 = s.next_text();
    assert!(tx3.starts_with("KH7Z HB9BLA R-"), "{tx3}");
    // Period 3: my Tx3 on the Fox's frequency; the Fox misses it (works K1ABC in period 4).
    s.run(period(4));
    let mut audio = noise(4);
    hound_audio(&s, period(3), &mut audio);
    let heard = fox_heard(&audio);
    assert!(
        heard
            .iter()
            .any(|(text, hz)| *text == tx3 && (hz - 800.0).abs() <= 3.0),
        "Tx3 at 800 Hz: {heard:?}"
    );
    s.run(period(4) + 13_500);
    let rows = hound_rows(
        &mut s,
        &mut t,
        period(4),
        &fox_audio(&[(packed("K1ABC KH7Z -15"), 800.0)], 5),
    );
    s.deliver(&rows);
    // Period 5: the repeat on Fox-300 Hz; the Fox answers with RR73 in a 0.1 message.
    s.run(period(6));
    let mut audio = noise(6);
    hound_audio(&s, period(5), &mut audio);
    let heard = fox_heard(&audio);
    assert!(
        heard
            .iter()
            .any(|(text, hz)| *text == tx3 && (hz - 500.0).abs() <= 3.0),
        "the repeat at 500 Hz: {heard:?}"
    );
    s.run(period(6) + 13_500);
    let rows = hound_rows(
        &mut s,
        &mut t,
        period(6),
        &fox_audio(&[(dxpedition_bits("HB9BLA", "K1ABC", FOX, -8), 800.0)], 7),
    );
    s.deliver(&rows);
    assert!(!s.armed());
    assert_eq!(s.state().0, State::Completed);
    let fields = one_log(&mut s).log_fields(s.now()).unwrap();
    assert_eq!(
        (fields.call.as_str(), fields.rst_rcvd.as_deref()),
        ("KH7Z", Some("-12"))
    );
    assert!(
        s.fake
            .0
            .audio
            .lock()
            .unwrap()
            .iter()
            .all(
                |(at, ..)| wstx_rust::transmit::parity(Mode::Ft8, (at / 15_000) * 15_000)
                    == Parity::Odd
            ),
        "the Hound never transmitted in the Fox's period"
    );
}
