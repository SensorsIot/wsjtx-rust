#![forbid(unsafe_code)]
// Proves: CL-010-01, CL-010-02, CL-010-03, CL-010-10, CL-010-12; TC-007-001, TC-008-001.
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
    PttError,
};
use wstx_rust::transmit::{ClockState, Parity};

const P0: i64 = 1_800_000_000_000; // an even FT8 period (multiple of 30 s)
const SECOND: i64 = 1000;

#[derive(Default)]
struct Bench {
    now: AtomicI64,
    capability: Mutex<Option<Capability>>,
    keys: Mutex<Vec<(i64, bool)>>,
    playing: Mutex<Option<(i64, usize)>>,
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
        let remaining = match program {
            Program::Waveform { samples, skip } => samples.len() - skip,
            Program::Tone { .. } => usize::MAX / 2,
        };
        *self.0.playing.lock().unwrap() = Some((self.now_utc_ms(), remaining));
        Ok(())
    }
    fn poll_audio(&mut self) -> AudioPoll {
        match *self.0.playing.lock().unwrap() {
            Some((at, n)) if (self.now_utc_ms() - at) * 48 >= n as i64 => AudioPoll::Finished,
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
    /// Texts whose audio started, with their period start.
    sent: Vec<(i64, String)>,
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
        sent: Vec::new(),
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
            Call::Call(w.into())
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
            call: Some("HB9BLA".into()),
            locator: Some("JN47AA".into()),
            now_utc_ms: self.now(),
            granted: true,
            mode: Some(Mode::Ft8),
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
            mode: Mode::Ft8,
            period_start_ms: Some(period),
            frequency_hz: hz,
            snr_db: snr,
            text: text.into(),
            standard: Some(parse(text)),
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
    s.deliver(&[report.clone()]);
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
    let review = s.engine.review().cloned().expect("one log offer");
    assert!(review.automatic);
    let fields = review.fields(s.now()).unwrap();
    assert_eq!(fields.call, "K1ABC");
    assert_eq!(fields.rst_sent.as_deref(), Some("-12"));
    assert_eq!(fields.rst_rcvd.as_deref(), Some("-05"));
    // TIME_ON: one period before the first transmitted Tx3 (no Tx2 was sent).
    assert_eq!(fields.start_utc_ms, period(2));
    // TIME_OFF: end of the last period with a counted message (my Tx5).
    assert_eq!(fields.end_utc_ms, period(6));
    // A reply after completion changes nothing and never offers again.
    s.engine.prune_saved(|_| true);
    let late = s.row(period(6), "HB9BLA K1ABC 73", 1240.0, None);
    s.deliver(&[late]);
    assert_eq!(s.state(), (State::Completed, Slot::Tx6));
    assert!(s.engine.review().is_none());
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
        s.command(Command::SetParity(Parity::Even)).unwrap();
        s.command(Command::EnableTx(true, Some(7))).unwrap();
        assert_eq!(s.state(), (State::Calling, Slot::Tx6));
        s.run(period(1) + 14 * SECOND);
        assert_eq!(s.sent_in(period(2)), None);
        assert_eq!(s.sent.first().map(|x| x.1.as_str()), Some("CQ HB9BLA JN47"));
        let answer = s.row(period(1), "HB9BLA K1ABC FN42", 900.0, Some(3.0));
        // Not selected yet: the reply to my CQ does not choose the partner (#12).
        s.deliver(&[answer.clone()]);
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
        let fields = s.engine.review().unwrap().fields(s.now()).unwrap();
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
    s.deliver(&[again.clone()]);
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
    s.deliver(&[again.clone()]);
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
    assert!(!s.armed(), "ChangeContact turns Enable Tx off");
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
        tx_minutes: 1,
        tune_seconds: 90,
    })
    .unwrap();
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    // The first CQ differs from the earlier Tx1 text: its start resets the count.
    let start = s.now();
    s.run(start + 100 * SECOND);
    assert!(!s.armed());
    assert_eq!(s.core.view().last_disarm_cause, DisarmCause::TxWatchdog);
    assert!(s.core.view().tx_expired);
    assert_eq!(s.state().0, State::Idle);
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
    assert!(!s.engine.review().unwrap().automatic);
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
fn tx_watchdog_counts_whole_minutes_from_the_last_reset_and_tune_ends_at_its_limit() {
    let mut s = station();
    let v = s.core.view();
    assert_eq!((v.tx_minutes, v.tune_seconds), (6, 90), "startup defaults");
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_minutes: 0,
            tune_seconds: 90
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_minutes: 100,
            tune_seconds: 90
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_minutes: 6,
            tune_seconds: 0
        }),
        Err("out_of_range")
    );
    assert_eq!(
        s.command(Command::SetWatchdogs {
            tx_minutes: 6,
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
        tx_minutes: 1,
        tune_seconds: 300,
    })
    .unwrap();
    assert_eq!(
        s.core.view().tx_remaining_minutes,
        0,
        "counter 0 while disarmed"
    );
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    let armed_at = s.now();
    assert_eq!(s.core.view().tx_remaining_minutes, 1);
    // Identical Tx1 text every period does not reset; a refused request does not reset.
    s.run(armed_at + 50 * SECOND);
    assert_eq!(s.command(Command::SetReport(99)), Err("invalid_report"));
    s.run(armed_at + 59 * SECOND);
    assert!(s.armed());
    // An accepted operating request at 0:59 resets the count.
    s.command(Command::SetHoldTx(false)).unwrap();
    let reset = s.now();
    s.run(armed_at + 61 * SECOND);
    assert!(s.armed(), "reset by the accepted request");
    s.run(reset + 60 * SECOND - 20);
    let before = s.core.view().arm_state;
    s.run(reset + 60 * SECOND + 20);
    assert_eq!(before, ArmState::Armed);
    assert!(
        !s.armed(),
        "expired exactly one whole minute after the last reset"
    );
    assert!(s.core.view().tx_expired);
    assert_eq!(
        s.state(),
        (State::Replying, Slot::Tx1),
        "contact state kept"
    );
    // Re-enable clears the expiry.
    s.command(Command::EnableTx(true, Some(7))).unwrap();
    assert!(!s.core.view().tx_expired);
    s.command(Command::EnableTx(false, None)).unwrap();
    // Tune: limit 1 s, ends through #9 with release.
    s.command(Command::SetWatchdogs {
        tx_minutes: 6,
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

// Review findings P2-1, P3-3, P3-4 (independent review of 761b00fbf).
#[test]
fn an_unsaved_review_is_kept_when_another_contact_is_offered() {
    let mut s = station();
    s.command(Command::EnterDx {
        call: "DL1ABC".into(),
        grid: Some("JO62".into()),
        replace: false,
    })
    .unwrap();
    s.command(Command::OpenLog).unwrap();
    let a = s.engine.contact.as_ref().unwrap().id.clone();
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    s.command(Command::OpenLog).unwrap();
    let b = s.engine.contact.as_ref().unwrap().id.clone();
    assert_ne!(a, b);
    let offered: Vec<String> = s.engine.reviews().map(|r| r.contact.id.clone()).collect();
    assert_eq!(
        offered,
        vec![a.clone(), b.clone()],
        "A stays offered first until saved or discarded"
    );
    assert_eq!(s.engine.review().unwrap().contact.id, a);
    // Repeated Log QSO for B does not add a second B; discarding A shows B.
    s.command(Command::OpenLog).unwrap();
    assert_eq!(s.engine.reviews().count(), 2);
    s.command(Command::DiscardReview(a.clone())).unwrap();
    assert_eq!(s.engine.review().unwrap().contact.id, b);
    // A saved review leaves the queue.
    s.engine.prune_saved(|id| id == b);
    assert!(s.engine.review().is_none());
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

// Re-review follow-ups (a) and (b).
#[test]
fn a_completed_contact_that_found_the_review_queue_full_is_never_dropped() {
    let mut s = station();
    for i in 0..8 {
        s.command(Command::EnterDx {
            call: format!("DL{i}ABC"),
            grid: None,
            replace: true,
        })
        .unwrap();
        s.command(Command::OpenLog).unwrap();
    }
    assert_eq!(s.engine.reviews().count(), 8);
    // A ninth contact completes on a received 73 in rogers (no transmission needed).
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: Some("FN42".into()),
        replace: true,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(&[seventy_three]);
    assert_eq!(s.state().0, State::Completed);
    assert_eq!(s.engine.reviews().count(), 8, "the queue holds 8");
    assert_eq!(
        s.engine.transmit_problem.as_deref(),
        Some("review_queue_full")
    );
    // While it waits for a queue place, no new contact or CQ may replace it.
    assert_eq!(
        s.command(Command::EnterDx {
            call: "W1AW".into(),
            grid: None,
            replace: true
        }),
        Err("state_conflict")
    );
    let cq = s.row(P0, "CQ W2AW FN31", 900.0, None);
    assert_eq!(
        s.command(Command::SelectRow {
            row: cq,
            replace: true
        }),
        Err("state_conflict")
    );
    assert_eq!(
        s.command(Command::EnableTx(true, Some(7))),
        Err("state_conflict")
    );
    assert_eq!(
        s.engine.contact.as_ref().unwrap().dx_call.as_deref(),
        Some("K1ABC")
    );
    // Freeing a place lets Log QSO queue it; then new contacts are prepared again.
    let first = s.engine.review().unwrap().contact.id.clone();
    s.command(Command::DiscardReview(first)).unwrap();
    s.command(Command::OpenLog).unwrap();
    assert!(
        s.engine
            .reviews()
            .any(|r| r.contact.dx_call.as_deref() == Some("K1ABC"))
    );
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
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

// Re-check of b3fd3f312, item 1: Cancel never strands the held contact.
#[test]
fn cancel_keeps_a_held_completed_contact_loggable_and_discard_clears_the_hold() {
    let mut s = station();
    for i in 0..8 {
        s.command(Command::EnterDx {
            call: format!("DL{i}ABC"),
            grid: None,
            replace: true,
        })
        .unwrap();
        s.command(Command::OpenLog).unwrap();
    }
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: Some("FN42".into()),
        replace: true,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(&[seventy_three]);
    let held = s.engine.contact.as_ref().unwrap().id.clone();
    assert_eq!(s.state().0, State::Completed);
    // Cancel (Esc) on the completed contact only disarms and selects Tx6.
    s.command(Command::Cancel).unwrap();
    let c = s.engine.contact.clone().unwrap();
    assert_eq!((c.state, c.next), (State::Completed, Slot::Tx6));
    assert_eq!(
        (c.dx_call.as_deref(), c.dx_grid.as_deref()),
        (Some("K1ABC"), Some("FN42"))
    );
    assert_eq!(c.messages[4].as_deref(), Some("K1ABC HB9BLA 73"));
    // A freed place lets Log QSO queue it.
    let first = s.engine.review().unwrap().contact.id.clone();
    s.command(Command::DiscardReview(first)).unwrap();
    s.command(Command::OpenLog).unwrap();
    assert!(s.engine.reviews().any(|r| r.contact.id == held));
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();

    // Second path: discarding the held contact id itself clears the hold.
    let mut s = station();
    for i in 0..8 {
        s.command(Command::EnterDx {
            call: format!("DL{i}ABC"),
            grid: None,
            replace: true,
        })
        .unwrap();
        s.command(Command::OpenLog).unwrap();
    }
    s.command(Command::EnterDx {
        call: "K1ABC".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    s.command(Command::ChooseNext(Slot::Tx4)).unwrap();
    let seventy_three = s.row(P0, "HB9BLA K1ABC 73", 1500.0, None);
    s.deliver(&[seventy_three]);
    let held = s.engine.contact.as_ref().unwrap().id.clone();
    s.command(Command::Cancel).unwrap();
    assert_eq!(
        s.command(Command::EnterDx {
            call: "W1AW".into(),
            grid: None,
            replace: true
        }),
        Err("state_conflict")
    );
    s.command(Command::DiscardReview(held)).unwrap();
    s.command(Command::EnterDx {
        call: "W1AW".into(),
        grid: None,
        replace: true,
    })
    .unwrap();
    assert_eq!(
        s.engine.reviews().count(),
        8,
        "the queued reviews are untouched"
    );
}
