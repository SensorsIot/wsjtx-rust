#![forbid(unsafe_code)]
// #111 slice S1: the transmit state, its start actions and its stops, at the contact engine
// against the actual transmit owner core on a virtual UTC clock (the bench of contact_tests).
// The oracles are the tables of CL-111-02 and CL-111-03 and the clauses CL-111-05 to -08
// and -10 as the issue words them, written below as expected values; none is engine output.
use super::*;
use wstx_rust::transmit::service::{ArmCause, TransmitRefusal};

const REV: Option<u64> = Some(7);
/// Three own periods of FT8 (an own period every 30 s).
const THREE_OWN: i64 = 90 * SECOND;
/// Builds a station in one state of the tables.
type Build = fn() -> Station;

fn reply(s: &mut Station, row: Row) -> Result<(), &'static str> {
    s.command(Command::Reply {
        row,
        safety_revision: REV,
    })
}
fn call_dx(s: &mut Station, call: &str, replace: bool) -> Result<(), &'static str> {
    s.command(Command::CallDx {
        call: call.into(),
        grid: None,
        replace,
        safety_revision: REV,
    })
}
fn cq_row(s: &mut Station, call: &str) -> Row {
    // Always a new row of an even (the partner's) period that has passed.
    let period = s.now().div_euclid(30 * SECOND) * 30 * SECOND;
    s.row(period, &format!("CQ {call} FN42"), 1234.0, Some(-12.0))
}
fn partner(s: &mut Station, text: &str) -> Row {
    let period = s.now().div_euclid(30 * SECOND) * 30 * SECOND;
    s.row(period, text, 1234.0, Some(-5.0))
}
fn cause(s: &Station) -> DisarmCause {
    s.core.view().last_disarm_cause
}
fn id(s: &Station) -> String {
    s.engine.contact.as_ref().unwrap().id.clone()
}
fn dx(s: &Station) -> Option<String> {
    s.engine.contact.as_ref().and_then(|c| c.dx_call.clone())
}
fn key_ons(s: &Station) -> usize {
    s.fake.0.keys.lock().unwrap().iter().filter(|k| k.1).count()
}
/// What a refusal must leave as it was.
fn facts(s: &Station) -> (Option<Contact>, ArmState, DisarmCause, Option<ArmCause>) {
    let v = s.core.view();
    (
        s.engine.contact.clone(),
        v.arm_state,
        v.last_disarm_cause,
        v.last_arm_cause,
    )
}
/// No request is planned or keyed over three own periods.
fn silent(s: &mut Station, label: &str) {
    // A transmission on the air at the stop finishes first.
    s.run(s.now() + 16 * SECOND);
    let (sent, keys) = (s.sent.len(), key_ons(s));
    let end = s.now() + THREE_OWN;
    while s.now() < end {
        s.run(s.now() + SECOND);
        assert_eq!(s.core.view().pending_sequence, None, "{label}: a request");
    }
    assert_eq!((s.sent.len(), key_ons(s)), (sent, keys), "{label}: keyed");
    assert!(!s.armed(), "{label}: on");
}
/// The state is on and the next own period carries a transmission; returns its text.
fn transmits(s: &mut Station, label: &str) -> String {
    assert!(s.armed(), "{label}: the state is on");
    let sent = s.sent.len();
    s.run(s.now() + 31 * SECOND);
    assert!(s.sent.len() > sent, "{label}: sent in the next own period");
    s.sent[sent].1.clone()
}
/// The transmit owner's next step sees `capability`.
fn capability(s: &mut Station, capability: Capability) {
    *s.fake.0.capability.lock().unwrap() = Some(capability);
    s.core.tick();
}
/// The radio goes away; the profile's safety revision stays.
fn radio_lost(s: &mut Station) {
    *s.fake.0.revision.lock().unwrap() = Some(7);
    capability(s, Capability::Unavailable);
}
/// A station on 20 m with the repetition limit `limit`.
fn limited(limit: u32) -> Station {
    let mut s = station();
    s.band = Some("20m");
    s.command(Command::SetWatchdogs {
        tx_calls: limit,
        tune_seconds: 90,
    })
    .unwrap();
    s
}

// ---------------------------------------------------------------- the states of CL-111-02
fn idle() -> Station {
    limited(6)
}
fn own_cq() -> Station {
    let mut s = idle();
    s.command(Command::CallCq(REV)).unwrap();
    assert_eq!(s.state().0, State::Calling);
    s
}
/// A QSO with K1ABC in replying, the state on, Tx1 sent once.
fn qso_on() -> Station {
    qso_on_with(6)
}
fn qso_on_with(limit: u32) -> Station {
    let mut s = limited(limit);
    let cq = cq_row(&mut s, "K1ABC");
    reply(&mut s, cq).unwrap();
    s.run(period(1) + 14 * SECOND);
    assert_eq!(s.sent.len(), 1);
    assert!(s.armed());
    s
}
/// The QSO kept, the state off by the repetition limit (limit 1: the second Tx1 is not keyed).
fn qso_limit() -> Station {
    let mut s = qso_on_with(1);
    s.run(period(3) + 2 * SECOND);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::TxWatchdog));
    assert_eq!(s.state(), (State::Replying, Slot::Tx1), "state kept");
    s
}
/// The QSO kept, the state off after Halt.
fn qso_halted() -> Station {
    let mut s = qso_on();
    s.core.halt();
    s.step(&[]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::Halt));
    assert_eq!(s.state(), (State::Replying, Slot::Tx1), "state kept");
    s
}
/// The QSO kept, the state off after the radio was lost; the radio is back.
fn qso_radio_lost() -> Station {
    let mut s = qso_on();
    radio_lost(&mut s);
    s.step(&[]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::DeviceLost));
    capability(&mut s, Capability::Available);
    s
}
/// The QSO kept, the state off after a refused transmission (the clock lost its
/// synchronization before the next own period); the clock is back.
fn qso_refused() -> Station {
    let mut s = qso_on();
    *s.fake.0.clock.lock().unwrap() = Some(ClockState::Unsynchronized);
    s.run(period(3) + 2 * SECOND);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::Refused));
    *s.fake.0.clock.lock().unwrap() = None;
    s
}
/// The QSO kept, the state off because the partner works another station on my Tx frequency.
fn qso_partner_works_other() -> Station {
    let mut s = qso_on();
    let hz = f64::from(s.engine.settings.tx_hz);
    let mut other = partner(&mut s, "W1AW K1ABC -05");
    other.frequency_hz = hz + 50.0;
    s.deliver(&[other]);
    s
}
fn completed() -> Station {
    let mut s = qso_on();
    s.command(Command::OpenLog).unwrap();
    assert_eq!(
        (s.state().0, s.armed(), cause(&s)),
        (State::Completed, false, DisarmCause::ContactCompleted)
    );
    s.run(s.now() + 16 * SECOND);
    s
}
fn cancelled() -> Station {
    let mut s = qso_on();
    s.command(Command::Cancel).unwrap();
    assert_eq!(
        (s.state().0, s.armed(), cause(&s)),
        (State::Cancelled, false, DisarmCause::ContactCancelled)
    );
    s.run(s.now() + 16 * SECOND);
    s
}

// ---------------------------------------------------------------- TC-111-001
// Proves: CL-111-03; TC-111-001 (a). The partner works another station on my Tx frequency:
// off, cause partnerWorksOther, the QSO state kept.
#[test]
fn tc_111_001_a_partner_works_another_station_stops_and_keeps_the_qso() {
    let s = qso_partner_works_other();
    assert_eq!(
        (s.armed(), cause(&s)),
        (false, DisarmCause::PartnerWorksOther)
    );
    assert_eq!(s.state(), (State::Replying, Slot::Tx1), "state kept");
    assert_eq!(dx(&s).as_deref(), Some("K1ABC"));
}

// Proves: CL-111-03; TC-111-001 (d). After each stop that keeps the QSO state nothing is sent in
// three own periods; Reply on the partner's row then transmits again, the same contact.
#[test]
fn tc_111_001_d_a_kept_qso_is_silent_until_reply_on_the_partners_row_continues_it() {
    let stops: [(&str, Build, DisarmCause); 5] = [
        ("halt", qso_halted, DisarmCause::Halt),
        ("limit", qso_limit, DisarmCause::TxWatchdog),
        (
            "partner works another",
            qso_partner_works_other,
            DisarmCause::PartnerWorksOther,
        ),
        ("radio lost", qso_radio_lost, DisarmCause::DeviceLost),
        ("refused", qso_refused, DisarmCause::Refused),
    ];
    for (label, build, shown) in stops {
        let mut s = build();
        let contact = id(&s);
        silent(&mut s, label);
        assert_eq!(cause(&s), shown, "{label}");
        assert_eq!(id(&s), contact, "{label}: the QSO is kept");
        let row = cq_row(&mut s, "K1ABC");
        reply(&mut s, row).unwrap();
        assert_eq!(id(&s), contact, "{label}: the same contact identity");
        assert_eq!(
            s.core.view().last_arm_cause,
            Some(ArmCause::Operator),
            "{label}"
        );
        assert_eq!(transmits(&mut s, label), "K1ABC HB9BLA JN47", "{label}");
    }
}

// ---------------------------------------------------------------- TC-111-002
// Proves: CL-111-01; TC-111-002 (the commands and the partner message; the reload, the
// reconnect and the repeated command_id are station cases). What is not a start never switches
// the state on: zero requests over three own periods, state and cause unchanged.
#[test]
fn tc_111_002_what_is_not_a_start_never_transmits() {
    let mut s = idle();
    assert_eq!(
        (s.armed(), cause(&s), s.core.view().last_arm_cause),
        (false, DisarmCause::Startup, None),
        "off at a station start, cause startup"
    );
    let row = cq_row(&mut s, "K1ABC");
    let commands = vec![
        Command::SelectRow {
            row: row.clone(),
            replace: false,
        },
        Command::EnterDx {
            call: "DL1XYZ".into(),
            grid: Some("JO62".into()),
            replace: true,
        },
        Command::SelectRow { row, replace: true },
        Command::ChooseNext(Slot::Tx2),
        Command::SetFrequency {
            rx: Some(1000),
            tx: Some(1100),
        },
        Command::EditMessage(Slot::Tx5, "K1ABC HB9BLA 73".into()),
        Command::SetReport(-7),
        Command::SetTx1Skip(true),
        Command::SetTx1Skip(false),
        Command::SetTx4(Tx4::Rr73),
        Command::SetHoldTx(false),
        Command::SetParity(Parity::Odd),
        Command::SetAutoSeq(false),
        Command::SetAutoSeq(true),
        Command::SetCallFirst(false),
        Command::SetContest {
            activity: Activity::NaVhf,
            exchange: None,
        },
        Command::SetContest {
            activity: Activity::None,
            exchange: None,
        },
        Command::SetWatchdogs {
            tx_calls: 3,
            tune_seconds: 60,
        },
    ];
    for command in commands {
        let label = format!("{command:?}");
        s.command(command).unwrap();
        assert_eq!(
            (s.armed(), cause(&s), s.core.view().last_arm_cause),
            (false, DisarmCause::Startup, None),
            "{label}"
        );
        assert_eq!(s.core.view().pending_sequence, None, "{label}");
    }
    assert_eq!(dx(&s).as_deref(), Some("K1ABC"), "the QSO is prepared");
    silent(&mut s, "after every command that is no start");
    // A partner message while the state is off.
    let report = partner(&mut s, "HB9BLA K1ABC -05");
    s.deliver(&[report]);
    silent(&mut s, "a partner message while off");
    assert_eq!(cause(&s), DisarmCause::Startup);
    assert!(s.sent.is_empty() && s.fake.0.keys.lock().unwrap().is_empty());
}

// ---------------------------------------------------------------- TC-111-003
/// One state of the outcome table, built anew for each cell.
struct Before {
    name: &'static str,
    build: Build,
    /// A QSO with a partner exists (replying to signoff).
    qso: bool,
    /// The cell of reset_repetitions.
    reset: Result<(), &'static str>,
}
const STATES: [Before; 7] = [
    Before {
        name: "no contact, idle",
        build: idle,
        qso: false,
        reset: Err("no_contact"),
    },
    Before {
        name: "own CQ calling",
        build: own_cq,
        qso: false,
        reset: Err("no_contact"),
    },
    Before {
        name: "QSO, state on",
        build: qso_on,
        qso: true,
        reset: Ok(()),
    },
    Before {
        name: "QSO kept, off, cause txWatchdog",
        build: qso_limit,
        qso: true,
        reset: Ok(()),
    },
    Before {
        name: "QSO kept, off, any other cause",
        build: qso_halted,
        qso: true,
        reset: Err("state_conflict"),
    },
    Before {
        name: "completed",
        build: completed,
        qso: false,
        reset: Err("no_contact"),
    },
    Before {
        name: "cancelled",
        build: cancelled,
        qso: false,
        reset: Err("no_contact"),
    },
];
/// A refusal sends nothing and changes nothing.
fn refused(s: &mut Station, command: Command, code: &'static str, label: &str) {
    let before = facts(s);
    let (sent, on) = (s.sent.len(), s.armed());
    assert_eq!(s.command(command), Err(code), "{label}");
    assert_eq!(facts(s), before, "{label}: nothing changes");
    if !on {
        s.run(s.now() + 31 * SECOND);
        assert_eq!(s.sent.len(), sent, "{label}: nothing is sent");
    }
}

// Proves: CL-111-02; TC-111-003 (the column reply).
#[test]
fn tc_111_003_reply_in_each_state() {
    for state in &STATES {
        let name = state.name;
        // Another partner: prepared (an own CQ replaced, an old QSO cancelled), on.
        let mut s = (state.build)();
        let old = s.engine.contact.as_ref().map(|c| c.id.clone());
        let row = cq_row(&mut s, "DL1XYZ");
        reply(&mut s, row).unwrap();
        assert_eq!(dx(&s).as_deref(), Some("DL1XYZ"), "{name}");
        assert_ne!(Some(id(&s)), old, "{name}: a new contact");
        assert_eq!(s.state(), (State::Replying, Slot::Tx1), "{name}");
        assert_eq!(transmits(&mut s, name), "DL1XYZ HB9BLA JN47", "{name}");
        if !state.qso {
            continue;
        }
        // The same partner: the QSO continues at the row's message, on.
        let mut s = (state.build)();
        let contact = id(&s);
        let row = partner(&mut s, "HB9BLA K1ABC -05");
        reply(&mut s, row).unwrap();
        assert_eq!(id(&s), contact, "{name}: the QSO continues");
        assert_eq!(s.state(), (State::RogerReport, Slot::Tx3), "{name}");
        assert_eq!(transmits(&mut s, name), "K1ABC HB9BLA R-05", "{name}");
    }
}

// Proves: CL-111-02, CL-111-05; TC-111-003 (the column call_cq).
#[test]
fn tc_111_003_call_cq_in_each_state() {
    for state in &STATES {
        let name = state.name;
        let mut s = (state.build)();
        if state.qso {
            refused(&mut s, Command::CallCq(REV), "contact_active", name);
            continue;
        }
        let before = facts(&s);
        let calling = s.engine.contact.as_ref().map(|c| c.state) == Some(State::Calling);
        s.command(Command::CallCq(REV)).unwrap();
        if calling {
            assert_eq!(facts(&s), before, "{name}: accepted, nothing changes");
        } else {
            assert_ne!(
                s.engine.contact.as_ref().map(|c| c.id.clone()),
                before.0.map(|c| c.id),
                "{name}: a new own CQ"
            );
        }
        assert_eq!(s.state(), (State::Calling, Slot::Tx6), "{name}");
        assert_eq!(transmits(&mut s, name), "CQ HB9BLA JN47", "{name}");
    }
}

// Proves: CL-111-02; TC-111-003 (the column call_dx).
#[test]
fn tc_111_003_call_dx_in_each_state() {
    for state in &STATES {
        let name = state.name;
        if state.qso {
            // replace false: refused, also for the QSO's own partner (Enter never continues).
            for call in ["DL1XYZ", "K1ABC"] {
                let mut s = (state.build)();
                refused(
                    &mut s,
                    Command::CallDx {
                        call: call.into(),
                        grid: None,
                        replace: false,
                        safety_revision: REV,
                    },
                    "contact_active",
                    name,
                );
            }
        }
        // Prepared and on: with replace true the old QSO is cancelled, the same partner too.
        for call in ["DL1XYZ", "K1ABC"] {
            let mut s = (state.build)();
            let old = s.engine.contact.as_ref().map(|c| c.id.clone());
            call_dx(&mut s, call, state.qso).unwrap();
            assert_eq!(dx(&s).as_deref(), Some(call), "{name}");
            assert_ne!(Some(id(&s)), old, "{name}: a new contact");
            assert_eq!(s.state(), (State::Replying, Slot::Tx1), "{name}");
            assert_eq!(
                transmits(&mut s, name),
                format!("{call} HB9BLA JN47"),
                "{name}"
            );
        }
    }
}

// Proves: CL-111-02, CL-111-05; TC-111-003 (the column send_next).
#[test]
fn tc_111_003_send_next_in_each_state() {
    for state in &STATES {
        let name = state.name;
        let mut s = (state.build)();
        if !state.qso {
            refused(
                &mut s,
                Command::SendNext(Slot::Tx2, REV),
                "no_contact",
                name,
            );
            continue;
        }
        let contact = id(&s);
        s.command(Command::SendNext(Slot::Tx2, REV)).unwrap();
        assert_eq!(id(&s), contact, "{name}");
        assert_eq!(s.state(), (State::Report, Slot::Tx2), "{name}: the slot");
        assert_eq!(transmits(&mut s, name), "K1ABC HB9BLA -12", "{name}");
        // A slot without text: invalid_message, as choose_next.
        let mut s = (state.build)();
        s.engine.contact.as_mut().unwrap().messages[4] = None;
        refused(
            &mut s,
            Command::SendNext(Slot::Tx5, REV),
            "invalid_message",
            name,
        );
    }
}

// Proves: CL-111-02, CL-111-08; TC-111-003 (the column reset_repetitions).
#[test]
fn tc_111_003_reset_repetitions_in_each_state() {
    for state in &STATES {
        let name = state.name;
        let mut s = (state.build)();
        match state.reset {
            Err(code) => refused(&mut s, Command::ResetRepetitions(REV), code, name),
            Ok(()) => {
                let contact = id(&s);
                s.command(Command::ResetRepetitions(REV)).unwrap();
                assert_eq!(id(&s), contact, "{name}");
                assert_eq!(s.state(), (State::Replying, Slot::Tx1), "{name}");
                // The message due next is sent.
                assert_eq!(transmits(&mut s, name), "K1ABC HB9BLA JN47", "{name}");
            }
        }
    }
}

/// An own CQ kept off after the radio was lost (the radio still away).
fn own_cq_radio_lost() -> Station {
    let mut s = own_cq();
    radio_lost(&mut s);
    s.step(&[]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::DeviceLost));
    assert_eq!(s.state(), (State::Calling, Slot::Tx6), "the own CQ is kept");
    s
}

// Proves: CL-111-02; TC-111-003 (call_cq on an own CQ kept off). With the radio back the same CQ
// goes on (cause operator) and is sent in the next own period; with the radio still away it is
// refused with the reason and nothing changes.
#[test]
fn tc_111_003_call_cq_on_an_own_cq_kept_off() {
    let mut s = own_cq_radio_lost();
    capability(&mut s, Capability::Available);
    let contact = id(&s);
    s.command(Command::CallCq(REV)).unwrap();
    assert_eq!(id(&s), contact, "the same CQ");
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
    assert_eq!(s.core.view().last_arm_cause, Some(ArmCause::Operator));
    assert_eq!(transmits(&mut s, "the radio back"), "CQ HB9BLA JN47");
    let mut s = own_cq_radio_lost();
    refused(
        &mut s,
        Command::CallCq(REV),
        "transmit_unavailable",
        "the radio away",
    );
    assert_eq!(s.state(), (State::Calling, Slot::Tx6));
}

// Proves: CL-111-02; TC-111-003 (further negatives). A stale safety revision is stale_revision
// and nothing is prepared; a Hound's call_cq is no_contact.
#[test]
fn tc_111_003_a_stale_safety_revision_prepares_nothing_and_a_hound_calls_no_cq() {
    for stale in [Some(6), None] {
        let mut s = idle();
        let row = cq_row(&mut s, "K1ABC");
        let starts = vec![
            Command::Reply {
                row,
                safety_revision: stale,
            },
            Command::CallCq(stale),
            Command::CallDx {
                call: "K1ABC".into(),
                grid: None,
                replace: false,
                safety_revision: stale,
            },
        ];
        for start in starts {
            let label = format!("{start:?}");
            refused(&mut s, start, "stale_revision", &label);
            assert_eq!(s.engine.refusal_field, Some("safety_revision"), "{label}");
            assert_eq!(s.engine.contact, None, "{label}: nothing is prepared");
        }
        let mut s = qso_halted();
        refused(
            &mut s,
            Command::SendNext(Slot::Tx2, stale),
            "stale_revision",
            "send_next",
        );
        let mut s = qso_limit();
        refused(
            &mut s,
            Command::ResetRepetitions(stale),
            "stale_revision",
            "reset after the limit",
        );
    }
    let mut s = hound_station();
    refused(&mut s, Command::CallCq(REV), "no_contact", "a Hound");
    assert_eq!(s.engine.contact, None);
}

// ---------------------------------------------------------------- TC-111-006
// Proves: CL-111-05; TC-111-006. A start never becomes a CQ: send_next and reset_repetitions on
// a completed and a cancelled QSO and with no contact are no_contact and nothing is sent in
// three own periods; reply and call_dx after a completed QSO call their own partner; only
// call_cq calls CQ.
#[test]
fn tc_111_006_a_start_never_becomes_a_cq() {
    let ended: [(&str, Build); 3] = [
        ("completed", completed),
        ("cancelled", cancelled),
        ("no contact", idle),
    ];
    for (label, build) in ended {
        let mut s = build();
        let before = facts(&s);
        assert_eq!(
            s.command(Command::SendNext(Slot::Tx1, REV)),
            Err("no_contact"),
            "{label}"
        );
        assert_eq!(
            s.command(Command::ResetRepetitions(REV)),
            Err("no_contact"),
            "{label}"
        );
        silent(&mut s, label);
        assert_eq!(facts(&s), before, "{label}: nothing changes");
    }
    let mut s = completed();
    let row = cq_row(&mut s, "DL1XYZ");
    reply(&mut s, row).unwrap();
    assert_eq!(transmits(&mut s, "reply"), "DL1XYZ HB9BLA JN47");
    let mut s = completed();
    call_dx(&mut s, "EA4HTI", false).unwrap();
    assert_eq!(transmits(&mut s, "call_dx"), "EA4HTI HB9BLA JN47");
    for s in [&mut completed(), &mut cancelled(), &mut idle()] {
        s.command(Command::CallCq(REV)).unwrap();
        assert_eq!(transmits(s, "call_cq"), "CQ HB9BLA JN47");
    }
}

// ---------------------------------------------------------------- TC-111-009
/// The QSO with K1ABC in rogerReport on 20 m, the state on.
fn roger_report() -> Station {
    let mut s = qso_on();
    let report = partner(&mut s, "HB9BLA K1ABC -05");
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    assert!(s.armed());
    s
}

// Proves: CL-111-03; TC-111-009 (a), (b) at the engine (the station band, whether the selection
// or the radio's dial moved it), (c), (d), (e). A band change stops and cancels.
#[test]
fn tc_111_009_a_band_change_stops_and_cancels() {
    // (a), (b): a QSO in rogerReport, the state on, 20 m to 40 m.
    let mut s = roger_report();
    s.band = Some("40m");
    s.step(&[]);
    let c = s.engine.contact.clone().unwrap();
    assert_eq!(
        (s.armed(), cause(&s)),
        (false, DisarmCause::BandChanged),
        "off, cause bandChanged"
    );
    assert_eq!((c.state, c.next), (State::Cancelled, Slot::Tx6));
    assert_eq!((c.dx_call, c.dx_grid), (None, None), "DX call cleared");
    assert!(c.messages[..5].iter().all(Option::is_none), "Tx1 to Tx5");
    assert!(c.messages[5].is_some(), "Tx6 stays");
    silent(&mut s, "after the band change");
    // (c): an own CQ becomes idle.
    let mut s = own_cq();
    s.band = Some("40m");
    s.step(&[]);
    assert_eq!(
        (s.state().0, s.armed(), cause(&s)),
        (State::Idle, false, DisarmCause::BandChanged)
    );
    silent(&mut s, "an own CQ after the band change");
    // (d): a completed QSO keeps its fields.
    let mut s = completed();
    let before = s.engine.contact.clone().unwrap();
    s.band = Some("40m");
    s.step(&[]);
    let mut after = s.engine.contact.clone().unwrap();
    after.band = before.band;
    assert_eq!(after, before, "fields kept");
    assert_eq!(cause(&s), DisarmCause::ContactCompleted);
    // (e): the same band again, and an unknown station band: nothing changes.
    for band in [Some("20m"), None] {
        let mut s = roger_report();
        let before = facts(&s);
        s.band = band;
        s.step(&[]);
        s.command(Command::SetHoldTx(true)).unwrap();
        assert_eq!(facts(&s), before, "{band:?}");
        // Tx3 with my report of K1ABC (-12, the SNR of the row replied to).
        assert_eq!(transmits(&mut s, "no band change"), "K1ABC HB9BLA R-12");
    }
    // A band that becomes known is the contact's band: the next one is the change.
    let mut s = station();
    let cq = cq_row(&mut s, "K1ABC");
    reply(&mut s, cq).unwrap();
    s.band = Some("20m");
    s.step(&[]);
    assert!(s.armed(), "unknown to 20 m is no band change");
    s.band = Some("40m");
    s.step(&[]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::BandChanged));
}

// ---------------------------------------------------------------- TC-111-010
fn last_key(s: &Station) -> Option<bool> {
    s.fake.0.keys.lock().unwrap().last().map(|k| k.1)
}

// Proves: CL-111-06; TC-111-010 (a) to (e). Tune is accepted whatever the transmit state and
// never changes it.
#[test]
fn tc_111_010_tune_is_independent_of_the_transmit_state() {
    // (a) off, no contact, ready: keyed; state and cause unchanged; Tune off releases.
    let mut s = idle();
    let before = facts(&s);
    s.command(Command::Tune(true, REV)).unwrap();
    assert!(s.core.view().tune);
    assert_eq!(last_key(&s), Some(true), "keyed");
    assert_eq!(facts(&s), before, "state and cause unchanged");
    s.command(Command::Tune(false, None)).unwrap();
    assert!(!s.core.view().tune);
    assert_eq!(last_key(&s), Some(false), "released");
    assert_eq!(facts(&s), before);
    // (b) a stale safety revision: stale_revision with its field, not keyed.
    for stale in [Some(6), None] {
        let mut s = idle();
        assert_eq!(s.command(Command::Tune(true, stale)), Err("stale_revision"));
        assert_eq!(s.engine.refusal_field, Some("safety_revision"));
        assert_eq!(key_ons(&s), 0);
        assert!(!s.core.view().tune);
    }
    // (c) a request pending, and a transmission on the air: busy.
    let mut s = idle();
    let cq = cq_row(&mut s, "K1ABC");
    reply(&mut s, cq).unwrap();
    assert!(s.core.view().pending_sequence.is_some(), "pending");
    assert_eq!(s.command(Command::Tune(true, REV)), Err("busy"));
    s.run(period(1) + 5 * SECOND);
    assert!(s.core.view().transmitting, "on the air");
    assert_eq!(s.command(Command::Tune(true, REV)), Err("busy"));
    assert!(!s.core.view().tune);
    assert!(s.armed(), "the refusal leaves the state on");
    // (d) no capability, and no grant: transmit_unavailable.
    let mut s = idle();
    capability(&mut s, Capability::Unsupported);
    assert_eq!(
        s.command(Command::Tune(true, REV)),
        Err("transmit_unavailable")
    );
    capability(&mut s, Capability::Unavailable);
    assert_eq!(
        s.command(Command::Tune(true, REV)),
        Err("transmit_unavailable")
    );
    capability(&mut s, Capability::Available);
    let ungranted = Ctx {
        granted: false,
        ..s.ctx()
    };
    assert_eq!(
        s.engine
            .command(Command::Tune(true, REV), Some(&mut s.core), &ungranted),
        Err("transmit_unavailable")
    );
    assert_eq!(key_ons(&s), 0);
    // (e) reply while Tune is on: accepted, the QSO prepared, refusal busy, the state off;
    // nothing is sent after Tune ends.
    let mut s = idle();
    s.command(Command::Tune(true, REV)).unwrap();
    let cq = cq_row(&mut s, "K1ABC");
    reply(&mut s, cq).unwrap();
    assert_eq!(dx(&s).as_deref(), Some("K1ABC"), "prepared");
    let v = s.core.view();
    assert_eq!(
        (v.arm_state, v.last_disarm_cause, v.refusal),
        (
            ArmState::Disarmed,
            DisarmCause::Startup,
            Some(TransmitRefusal::Busy)
        )
    );
    assert!(v.tune, "Tune goes on");
    s.command(Command::Tune(false, None)).unwrap();
    silent(&mut s, "after Tune ended");
    assert!(s.sent.is_empty());
    assert_eq!(cause(&s), DisarmCause::Startup);
}

/// Tune on from an automatic principal (an MCP client), then the station's next step.
fn automatic_tune(s: &mut Station) -> Result<(), &'static str> {
    let automatic = Ctx {
        automatic: true,
        ..s.ctx()
    };
    let result = s
        .engine
        .command(Command::Tune(true, REV), Some(&mut s.core), &automatic);
    s.step(&[]);
    result
}
fn automatic_tune_refused(s: &mut Station, label: &str) {
    let (before, keys) = (facts(s), key_ons(s));
    assert_eq!(automatic_tune(s), Err("tx_watchdog"), "{label}");
    assert_eq!(key_ons(s), keys, "{label}: not keyed");
    assert!(!s.core.view().tune, "{label}");
    assert_eq!(facts(s), before, "{label}: nothing changes");
}

// Proves: CL-111-06, CL-044-14; TC-111-010 (g). Tune on from an MCP principal is refused
// tx_watchdog at boot before any browser action, after a clear fault and after a repetition-limit
// stop; after a browser action it keys.
#[test]
fn tc_111_010_g_tune_from_an_automatic_principal_needs_an_operator() {
    let mut s = station();
    automatic_tune_refused(&mut s, "at boot");
    // A browser action: a human was seen this boot.
    s.command(Command::SetHoldTx(false)).unwrap();
    automatic_tune(&mut s).unwrap();
    assert!(s.core.view().tune);
    assert_eq!(last_key(&s), Some(true), "keyed");
    s.command(Command::Tune(false, None)).unwrap();
    // A clear fault (CL-044-14): automation waits for an operator action again.
    s.core.require_operator();
    automatic_tune_refused(&mut s, "after a clear fault");
    let mut s = qso_limit();
    automatic_tune_refused(&mut s, "after the repetition limit");
}

// ---------------------------------------------------------------- TC-111-011
/// The transmit owner refuses to arm: a PTT release failed and left the switch indeterminate.
fn release_failed(s: &mut Station) {
    s.fake.0.release_fails.store(true, Ordering::SeqCst);
    s.command(Command::Tune(true, REV)).unwrap();
    s.command(Command::Tune(false, None)).unwrap();
    assert_eq!(s.core.view().ptt, PttState::Indeterminate);
}
/// The transmit owner refuses to arm after an owner fault.
fn owner_fault(s: &mut Station) {
    s.core.fail_closed();
    s.step(&[]);
}

// Proves: CL-111-07; TC-111-011 (the transmit owner refuses to arm). call_cq, send_next and
// reset_repetitions are refused with the reason and change nothing.
#[test]
fn tc_111_011_a_start_the_transmit_owner_cannot_arm_is_refused() {
    type Refuse = fn(&mut Station);
    let owners: [(&str, Refuse); 2] = [
        ("a failed PTT release", release_failed),
        ("an owner fault", owner_fault),
    ];
    for (label, refuse) in owners {
        let mut s = idle();
        refuse(&mut s);
        refused(&mut s, Command::CallCq(REV), "transmit_unavailable", label);
        assert_eq!(s.engine.contact, None, "{label}: no CQ is prepared");
        let mut s = own_cq_radio_lost();
        capability(&mut s, Capability::Available);
        refuse(&mut s);
        refused(&mut s, Command::CallCq(REV), "transmit_unavailable", label);
        let mut s = qso_halted();
        refuse(&mut s);
        refused(
            &mut s,
            Command::SendNext(Slot::Tx2, REV),
            "transmit_unavailable",
            label,
        );
        assert_eq!(s.state(), (State::Replying, Slot::Tx1), "{label}: no slot");
    }
    // reset_repetitions after the limit's stop (an owner fault itself stops with cause failed,
    // after which Reset is state_conflict by the table).
    let mut s = qso_limit();
    release_failed(&mut s);
    assert_eq!(cause(&s), DisarmCause::TxWatchdog);
    refused(
        &mut s,
        Command::ResetRepetitions(REV),
        "transmit_unavailable",
        "a failed PTT release",
    );
    assert!(s.core.view().tx_expired, "the limit's stop stays");
}

/// A kept QSO with the state on and Tune on (the transmit owner switched on under Tune, as the
/// Set level assistant does).
fn on_under_tune() -> Station {
    let mut s = qso_halted();
    s.command(Command::Tune(true, REV)).unwrap();
    s.core.arm(7).unwrap();
    assert!(s.armed() && s.core.view().tune);
    s
}

// Proves: CL-111-07, CL-111-08; TC-111-011 (Reset while the state is on). While transmission is
// not possible reset_repetitions is refused with the reason and the count stays: Tune on is
// busy, a PTT switch left indeterminate is transmit_unavailable.
#[test]
fn tc_111_011_reset_while_on_but_unable_to_transmit_is_refused() {
    let mut tune = on_under_tune();
    let mut stuck = on_under_tune();
    stuck.fake.0.release_fails.store(true, Ordering::SeqCst);
    let hz = stuck.engine.settings.tx_hz;
    stuck.core.set_tune(false, hz).unwrap();
    assert_eq!(stuck.core.view().ptt, PttState::Indeterminate);
    for (label, s, code) in [
        ("Tune on", &mut tune, "busy"),
        ("PTT indeterminate", &mut stuck, "transmit_unavailable"),
    ] {
        assert!(s.armed(), "{label}: the state is on");
        let before = (facts(s), s.engine.repetitions_due());
        let ctx = s.ctx();
        assert_eq!(
            s.engine
                .command(Command::ResetRepetitions(REV), Some(&mut s.core), &ctx),
            Err(code),
            "{label}"
        );
        assert_eq!(
            (facts(s), s.engine.repetitions_due()),
            before,
            "{label}: the count stays"
        );
    }
}
// Proves: CL-111-07; TC-111-011 (the engine and the transmit view; the operating view shows the
// reason in the browser slice). A start that cannot transmit.
#[test]
fn tc_111_011_a_start_that_cannot_transmit_prepares_and_stays_off() {
    type Set = fn(&mut Station, bool);
    let situations: [(&str, Set, TransmitRefusal, &str); 3] = [
        (
            "no capability",
            |s, on| {
                capability(
                    s,
                    if on {
                        Capability::Unsupported
                    } else {
                        Capability::Available
                    },
                )
            },
            TransmitRefusal::TransmitUnsupported,
            "transmit_unavailable",
        ),
        (
            "radio unavailable",
            |s, on| {
                capability(
                    s,
                    if on {
                        Capability::Unavailable
                    } else {
                        Capability::Available
                    },
                )
            },
            TransmitRefusal::RadioUnavailable,
            "transmit_unavailable",
        ),
        (
            "clock not synchronized",
            |s, on| *s.fake.0.clock.lock().unwrap() = on.then_some(ClockState::Unsynchronized),
            TransmitRefusal::ClockNotSynchronized,
            "clock_not_synchronized",
        ),
    ];
    for (label, set, reason, code) in situations {
        for by_call in [false, true] {
            let mut s = idle();
            set(&mut s, true);
            if by_call {
                call_dx(&mut s, "K1ABC", false).unwrap();
            } else {
                let cq = cq_row(&mut s, "K1ABC");
                reply(&mut s, cq).unwrap();
            }
            assert_eq!(dx(&s).as_deref(), Some("K1ABC"), "{label}: prepared");
            assert_eq!(s.state(), (State::Replying, Slot::Tx1), "{label}");
            let v = s.core.view();
            assert_eq!(
                (v.arm_state, v.last_disarm_cause, v.last_arm_cause),
                (ArmState::Disarmed, DisarmCause::Startup, None),
                "{label}: off, cause unchanged"
            );
            assert_eq!(v.refusal, Some(reason), "{label}: the reason");
            // call_cq and send_next in the same situation: refused, nothing changed.
            refused(&mut s, Command::CallCq(REV), "contact_active", label);
            refused(&mut s, Command::SendNext(Slot::Tx2, REV), code, label);
            // The reason removed: nothing starts by itself; a new reply transmits.
            set(&mut s, false);
            silent(&mut s, label);
            assert!(s.sent.is_empty(), "{label}");
            let cq = cq_row(&mut s, "K1ABC");
            reply(&mut s, cq).unwrap();
            assert_eq!(transmits(&mut s, label), "K1ABC HB9BLA JN47", "{label}");
            assert_eq!(s.core.view().refusal, None, "{label}");
        }
        let mut s = idle();
        set(&mut s, true);
        refused(&mut s, Command::CallCq(REV), code, label);
        assert_eq!(s.engine.contact, None, "{label}: no CQ is prepared");
    }
}

// ---------------------------------------------------------------- TC-111-012
/// The transmissions of `text` so far.
fn count_of(s: &Station, text: &str) -> usize {
    s.sent.iter().filter(|(_, t)| t == text).count()
}

// Proves: CL-111-08; TC-111-012 (a), (b). Limit 2. Reset while the state is on starts the count
// anew; after the limit's stop it starts the count anew and sends the message due next.
#[test]
fn tc_111_012_reset_starts_the_count_anew_and_continues_after_the_limit() {
    const TX1: &str = "K1ABC HB9BLA JN47";
    // (a) the message sent once, Reset, then two more are keyed and the next is not.
    let mut s = qso_on_with(2);
    assert_eq!(count_of(&s, TX1), 1);
    s.command(Command::ResetRepetitions(REV)).unwrap();
    assert!(s.armed(), "the state stays on");
    assert_eq!(s.core.view().tx_remaining_calls, 2, "the full limit again");
    s.run(period(9));
    assert_eq!(count_of(&s, TX1), 3, "three in all: {:?}", s.sent);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::TxWatchdog));
    assert_eq!(key_ons(&s), 3, "the next is never keyed");
    // (b) after the limit's stop: the same message again from the next own period.
    let mut s = qso_on_with(2);
    s.run(period(5) + 2 * SECOND);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::TxWatchdog));
    assert_eq!(count_of(&s, TX1), 2);
    assert!(s.core.view().tx_expired);
    s.command(Command::ResetRepetitions(REV)).unwrap();
    let v = s.core.view();
    assert_eq!(
        (v.arm_state, v.last_arm_cause, v.tx_expired),
        (ArmState::Armed, Some(ArmCause::Operator), false)
    );
    assert_eq!(s.state(), (State::Replying, Slot::Tx1), "the message due");
    assert_eq!(s.engine.repetitions_due(), 0, "a new count");
    // Its first transmission starts no later than the next own period (period 7).
    while count_of(&s, TX1) == 2 {
        assert!(s.now() < period(7) + SECOND, "sent by the next own period");
        s.run(s.now() + 100);
    }
    assert_eq!(s.sent.last().map(|(_, t)| t.as_str()), Some(TX1));
    assert_eq!(s.engine.repetitions_due(), 1, "count 1");
    assert_eq!(s.core.view().tx_remaining_calls, 1);
}

// Proves: CL-111-08; TC-111-012 (c) to (f). Where Reset is refused.
#[test]
fn tc_111_012_where_reset_is_refused() {
    // (c) a kept QSO after Halt, after the radio was lost and after a refused transmission.
    let kept: [(&str, Build); 3] = [
        ("halt", qso_halted),
        ("radio lost", qso_radio_lost),
        ("refused", qso_refused),
    ];
    for (label, build) in kept {
        let mut s = build();
        refused(
            &mut s,
            Command::ResetRepetitions(REV),
            "state_conflict",
            label,
        );
    }
    // (d) no contact, an own CQ calling, an own CQ ended by the limit, completed, cancelled.
    let cq_ended: Build = || {
        let mut s = limited(1);
        s.command(Command::CallCq(REV)).unwrap();
        s.run(period(3) + 2 * SECOND);
        assert_eq!(
            (s.state().0, s.armed(), cause(&s)),
            (State::Idle, false, DisarmCause::TxWatchdog),
            "the limit ends an own CQ"
        );
        s
    };
    let none: [(&str, Build); 5] = [
        ("no contact", idle),
        ("own CQ calling", own_cq),
        ("own CQ ended by the limit", cq_ended),
        ("completed", completed),
        ("cancelled", cancelled),
    ];
    for (label, build) in none {
        let mut s = build();
        refused(&mut s, Command::ResetRepetitions(REV), "no_contact", label);
    }
    // The CQ button then calls CQ again.
    let mut s = cq_ended();
    let sent = count_of(&s, "CQ HB9BLA JN47");
    s.command(Command::CallCq(REV)).unwrap();
    assert_eq!(transmits(&mut s, "CQ again"), "CQ HB9BLA JN47");
    assert!(count_of(&s, "CQ HB9BLA JN47") > sent);
    // (e) from an MCP principal and from a run (both automatic): operator_required, the count
    // unchanged, while on and after the limit's stop.
    for build in [qso_on as Build, qso_limit] {
        let mut s = build();
        let before = (facts(&s), s.engine.repetitions_due());
        let automatic = Ctx {
            automatic: true,
            ..s.ctx()
        };
        assert_eq!(
            s.engine.command(
                Command::ResetRepetitions(REV),
                Some(&mut s.core),
                &automatic
            ),
            Err("operator_required")
        );
        assert_eq!((facts(&s), s.engine.repetitions_due()), before);
    }
    // (f) a stale safety revision.
    for build in [qso_on as Build, qso_limit] {
        let mut s = build();
        let count = s.engine.repetitions_due();
        refused(
            &mut s,
            Command::ResetRepetitions(Some(6)),
            "stale_revision",
            "stale",
        );
        assert_eq!(s.engine.repetitions_due(), count);
    }
}

// ---------------------------------------------------------------- TC-111-013
/// A start arriving in the step of a stop: refused state_conflict, the state off.
fn loses(s: &mut Station, start: Command, label: &str) {
    let keys = key_ons(s);
    let ctx = s.ctx();
    assert_eq!(
        s.engine.command(start, Some(&mut s.core), &ctx),
        Err("state_conflict"),
        "{label}"
    );
    assert!(!s.armed(), "{label}: the state is off");
    s.step(&[]);
    silent(s, label);
    assert_eq!(key_ons(s), keys, "{label}: nothing keyed");
}
/// Runs to the step in which the repetition limit stops the station (limit 1).
fn to_the_limit(s: &mut Station) {
    while s.armed() {
        assert!(s.now() < period(4), "the limit stops in period 3");
        s.run(s.now() + 50);
    }
    assert_eq!(cause(s), DisarmCause::TxWatchdog);
}

// Proves: CL-111-03; TC-111-013 (stop against start). In one station step any stop wins over
// any start.
#[test]
fn tc_111_013_a_stop_wins_over_a_start_in_one_step() {
    // Halt and reply.
    let mut s = qso_on();
    s.run(s.now() + 16 * SECOND);
    s.core.halt();
    let row = cq_row(&mut s, "K1ABC");
    loses(
        &mut s,
        Command::Reply {
            row,
            safety_revision: REV,
        },
        "Halt and reply",
    );
    assert_eq!(cause(&s), DisarmCause::Halt);
    // The limit and send_next.
    let mut s = qso_on_with(1);
    to_the_limit(&mut s);
    loses(
        &mut s,
        Command::SendNext(Slot::Tx2, REV),
        "the limit and send_next",
    );
    assert_eq!(cause(&s), DisarmCause::TxWatchdog);
    assert_eq!(s.state(), (State::Replying, Slot::Tx1), "no slot is chosen");
    // A band change and call_cq.
    let mut s = own_cq();
    s.run(s.now() + 31 * SECOND);
    s.band = Some("40m");
    loses(&mut s, Command::CallCq(REV), "a band change and call_cq");
    assert_eq!(cause(&s), DisarmCause::BandChanged);
    assert_eq!(s.state().0, State::Idle);
    // After the step the same start is a start again.
    let mut s = qso_on();
    s.core.halt();
    s.step(&[]);
    let row = cq_row(&mut s, "K1ABC");
    reply(&mut s, row).unwrap();
    assert!(s.armed());
}

// Proves: CL-111-03; TC-111-013 (two stops in one step). The shown cause is the first of the
// order of CL-111-03, whichever stop arrived first.
#[test]
fn tc_111_013_of_two_stops_in_one_step_the_first_of_the_order_is_shown() {
    // Halt and radio lost: halt (in both orders of arrival).
    let mut s = qso_on();
    radio_lost(&mut s);
    assert_eq!(cause(&s), DisarmCause::DeviceLost);
    s.core.halt();
    assert_eq!(cause(&s), DisarmCause::Halt);
    let mut s = qso_on();
    s.core.halt();
    radio_lost(&mut s);
    assert_eq!(cause(&s), DisarmCause::Halt);
    // Radio lost and Abort QSO: deviceLost.
    let mut s = qso_on();
    radio_lost(&mut s);
    s.command(Command::Abort).unwrap();
    assert_eq!(cause(&s), DisarmCause::DeviceLost);
    assert_eq!(s.state().0, State::Cancelled, "the abort still cancels");
    // Abort QSO and the limit: contactCancelled.
    let mut s = qso_on_with(1);
    to_the_limit(&mut s);
    s.command(Command::Abort).unwrap();
    assert_eq!(cause(&s), DisarmCause::ContactCancelled);
    // Cancel contact and the limit: txWatchdog.
    let mut s = qso_on_with(1);
    to_the_limit(&mut s);
    s.command(Command::Cancel).unwrap();
    assert_eq!(cause(&s), DisarmCause::TxWatchdog);
    assert_eq!(s.state().0, State::Cancelled, "the cancel still cancels");
    // The limit and partner works another, both in the step the limit is due: txWatchdog.
    let mut s = qso_on_with(1);
    let due = period(3) + 1200;
    s.run(due - 50);
    assert!(s.armed(), "the limit's stop is not due yet");
    s.fake.0.now.store(due, Ordering::SeqCst);
    let hz = f64::from(s.engine.settings.tx_hz);
    let mut other = partner(&mut s, "W1AW K1ABC -05");
    other.frequency_hz = hz;
    s.deliver(&[other]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::TxWatchdog));
    assert!(s.core.view().tx_expired);
    // Partner works another and a band change: partnerWorksOther.
    let mut s = qso_on();
    let mut other = partner(&mut s, "W1AW K1ABC -05");
    other.frequency_hz = hz;
    s.band = Some("40m");
    s.deliver(&[other]);
    assert_eq!(
        (s.armed(), cause(&s)),
        (false, DisarmCause::PartnerWorksOther)
    );
    assert_eq!(s.state().0, State::Cancelled, "the band change cancels");
    // A band change and completion: bandChanged; the completed QSO keeps its fields.
    let mut s = qso_on();
    let roger = partner(&mut s, "HB9BLA K1ABC R-05");
    s.deliver(&[roger]);
    assert_eq!(s.state().0, State::Rogers);
    s.run(s.now() + 30 * SECOND);
    let bye = partner(&mut s, "HB9BLA K1ABC 73");
    s.band = Some("40m");
    s.deliver(&[bye]);
    assert_eq!((s.armed(), cause(&s)), (false, DisarmCause::BandChanged));
    assert_eq!(s.state().0, State::Completed);
    assert_eq!(dx(&s).as_deref(), Some("K1ABC"), "fields kept");
    assert_eq!(one_entry(&mut s).0, LogKind::Completion, "logged once");
}

// ---------------------------------------------------------------- TC-111-016
/// A Hound calling the Fox KH7Z with Tx1 since `on`, the repetition limit out of the way.
fn hound_calling() -> (Station, i64) {
    let mut s = hound_station();
    s.command(Command::SetWatchdogs {
        tx_calls: 99,
        tune_seconds: 90,
    })
    .unwrap();
    let cq = s.row(P0, "CQ KH7Z BL01", 812.0, Some(-9.0));
    let on = s.now();
    reply(&mut s, cq).unwrap();
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    (s, on)
}
/// Off with cause txWatchdog at `at`, not 1 s before.
fn stops_at(s: &mut Station, at: i64, label: &str) {
    s.run(at - SECOND);
    assert!(s.armed(), "{label}: not 1 s before");
    s.run(at);
    assert_eq!(
        (s.armed(), cause(s)),
        (false, DisarmCause::TxWatchdog),
        "{label}"
    );
}

// Proves: CL-111-10; TC-111-016. While the Hound still calls with Tx1 the state goes off 300 s
// after the last accepted start; every accepted start restarts the 300 s, Reset does not.
#[test]
fn tc_111_016_the_hound_stops_300_s_after_its_last_start() {
    // 300 s after the start, not at 299 s.
    let (mut s, on) = hound_calling();
    stops_at(&mut s, on + 300 * SECOND, "the start");
    assert_eq!(s.state(), (State::Replying, Slot::Tx1));
    // A second reply at 150 s moves it to 450 s.
    let (mut s, on) = hound_calling();
    s.run(on + 150 * SECOND);
    let again = s.row(period(8), "CQ KH7Z BL01", 812.0, Some(-9.0));
    reply(&mut s, again).unwrap();
    stops_at(&mut s, on + 450 * SECOND, "a second reply");
    // A run's start restarts it the same way.
    let (mut s, on) = hound_calling();
    s.run(on + 150 * SECOND);
    let row = s.row(period(8), "CQ KH7Z BL01", 812.0, Some(-9.0));
    let run = Ctx {
        automatic: true,
        ..s.ctx()
    };
    s.engine
        .command(
            Command::Reply {
                row,
                safety_revision: REV,
            },
            Some(&mut s.core),
            &run,
        )
        .unwrap();
    assert_eq!(s.core.view().last_arm_cause, Some(ArmCause::Auto));
    stops_at(&mut s, on + 450 * SECOND, "a run's start");
    // reset_repetitions at 150 s does not move it.
    let (mut s, on) = hound_calling();
    s.run(on + 150 * SECOND);
    s.command(Command::ResetRepetitions(REV)).unwrap();
    stops_at(&mut s, on + 300 * SECOND, "Reset");
    // With Tx3 next nothing stops at 300 s.
    let (mut s, on) = hound_calling();
    s.run(on + 280 * SECOND);
    let report = s.row(period(18), "HB9BLA KH7Z -12", 812.0, Some(-7.0));
    s.deliver(&[report]);
    assert_eq!(s.state(), (State::RogerReport, Slot::Tx3));
    s.run(on + 301 * SECOND);
    assert!(s.armed(), "Tx3 next: the 300 s do not stop");
}
