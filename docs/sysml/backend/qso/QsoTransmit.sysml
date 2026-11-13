package WstxQsoTransmit {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-007';
    private import WstxArchitecture::'FR-008';
    private import WstxRequirements::AutomationState;
    private import WstxTransmit::'TC-111-015';
    private import WstxTransmit::'CL-039-06';
    private import WstxContact::TxSlot;
    requirement 'CL-111-02' {
        doc /* Start actions. The start actions are exactly these. Each is one ContactCommand and carries the safety revision shown to its sender; grant, clock, period and safety-revision checks are unchanged. Reply: double-click or row menu Reply on a Band Activity row, double-click or Enter on a Calling me row: reply {row, directive_confirmed?, safety_revision}. CQ: the CQ button: call_cq {safety_revision}. Call: Enter in the DX call or grid field, and the button beside them: call_dx {dx_call, dx_grid, replace, safety_revision}. Send next: "Send <exchange> next": send_next {slot, safety_revision}. Reset: the Reset button: reset_repetitions {safety_revision}. Auto: a strategy, contest or policy run: reply or call_cq sent by the run, cause auto. The outcome of each start in each state is the table of WstxQsoTransmit::StartActions. A Hound's call_cq is no_contact. A slot without text is invalid_message, as choose_next. enable_tx is retired: refused invalid_request with field action, for the browser and for MCP clients. select_row, enter_dx and choose_next stay and never start. An MCP client may send reply, call_cq, call_dx and send_next; its start is automatic: after a repetition-limit stop, or when no browser action was seen this boot, it is refused tx_watchdog. A start refused for a stale contact or safety revision, for tx_watchdog, or by a row or call refusal changes nothing: no QSO is prepared. The browser retries a start refused stale_revision at most twice with the reloaded snapshot, as CL-061-02. Not delivered yet: the browser controls and the runs still send select_row or enter_dx and enable_tx, enable_tx is still accepted, and the MCP tool description does not name the starts. Details: WstxQsoTransmit::StartActions, ContactCommand. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs";
    }
    dependency CL_111_02_to_FR_007 from 'CL-111-02' to 'FR-007';
    dependency CL_111_02_to_FR_008 from 'CL-111-02' to 'FR-008';
    requirement 'CL-111-05' {
        doc /* A start never becomes a CQ. Only call_cq calls CQ. reply and call_dx name their own partner and start that QSO in every state. send_next and reset_repetitions act on the current QSO: when it has ended, was cancelled or never existed they are refused no_contact and nothing is sent (the table of WstxQsoTransmit::StartActions). Not delivered yet: enable_tx with no partner still calls CQ. Details: WstxQsoTransmit::StartActions. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs";
    }
    dependency CL_111_05_to_FR_007 from 'CL-111-05' to 'FR-007';
    requirement 'CL-111-08' {
        doc /* Reset. The QSO pane has a Reset button. It is offered only for a QSO with a partner: while it transmits (state on, replying to signoff), and while it is stopped by the repetition limit (state off, cause txWatchdog). It is not offered during an own CQ, in any other state, or after Halt, a lost radio or a refused transmission. While on: the repetition count of the message due next starts anew; the state stays on. While stopped by the limit: the count starts anew, the state goes on, and the message due next, the one that got no answer, is sent from the next own period. Only the operator in the browser may use it: from a run or an MCP client it is refused operator_required. Its other outcomes are the table of WstxQsoTransmit::StartActions. The limit itself is unchanged: 1..99, default 6; a send that would exceed it is never keyed. Labels: "Reset count" while the state is on; "Reset · send again" while stopped by the limit. Not delivered yet: the button; the command reset_repetitions is. Details: WstxQsoTransmit::StartActions, TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs";
    }
    dependency CL_111_08_to_FR_007 from 'CL-111-08' to 'FR-007';
    dependency CL_111_08_to_FR_008 from 'CL-111-08' to 'FR-008';
    verification 'TC-111-003' {
        doc /* TC-111-003 — Each start in each state
             CL-111-02
             Setup: as TC-111-001, one station built anew for each cell; for the wire the actual station router (contact_http_tests fixture).
             Steps: every cell of the outcome table of WstxQsoTransmit::StartActions, one command each; call_cq on an own CQ kept off after a lost radio, with the radio back and with the radio still away. Further negatives: a stale safety revision; enable_tx; a Hound's call_cq.
             Expected (the outcome table): a cell that says "on" transmits in the next own period, a refusal sends nothing and changes nothing. The own CQ kept off: with the radio back the same CQ, on, cause operator, sent in the next own period; with the radio away transmit_unavailable, nothing changed. A stale safety revision is stale_revision and nothing is prepared; enable_tx is invalid_request field action; a Hound's call_cq is no_contact.
             Not automated yet: enable_tx refused.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-02';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_111_02_verified_by_TC_111_003 from 'CL-111-02' to 'TC-111-003';
    verification 'TC-111-004' {
        doc /* TC-111-004 — Only start controls lead to a transmission
             CL-111-02
             Setup: Chromium against the candidate server with a recording hardware double; "QSO prepared, state off".
             Steps: every button and input of the operating view is used once; a double-click on a row.
             Expected (the start table of CL-111-02): the set that caused a TransmitRequest equals the start table; the test fails when its list of controls is not the page's. A double-click sends exactly one reply.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-02';
        }
    }
    dependency CL_111_02_verified_by_TC_111_004 from 'CL-111-02' to 'TC-111-004';
    verification 'TC-111-006' {
        doc /* TC-111-006 — A start never becomes a CQ
             CL-111-05
             Setup: as TC-111-001.
             Steps: send_next and reset_repetitions on a completed and on a cancelled QSO and with no contact; reply and call_dx after a completed QSO; call_cq.
             Expected (CL-111-05): no_contact, no CQ and no other request in 3 periods. reply and call_dx call their own partner, never CQ. call_cq calls CQ.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-05';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_05_verified_by_TC_111_006 from 'CL-111-05' to 'TC-111-006';
    dependency CL_111_02_verified_by_TC_111_008 from 'CL-111-02' to 'TC-111-008';
    verification 'TC-111-012' {
        doc /* TC-111-012 — Reset
             CL-111-08
             Setup: as TC-111-001, limit 2; for (g) Chromium against the candidate server.
             Steps: (a) QSO, state on, the message sent once: Reset. (b) after the limit's stop: Reset. (c) a kept QSO after Halt, after deviceLost and after a refused transmission. (d) no contact, idle, own CQ calling, own CQ ended by the limit, completed, cancelled; then the CQ button. (e) from an MCP principal and from a run. (f) a stale safety revision. (g) the button in each state.
             Expected (CL-111-08, the outcome table): (a) two more sends are keyed and the next is not (three in all). (b) the same message is sent again from the next own period, cause operator, count 1. (c) state_conflict. (d) no_contact; the CQ button then calls CQ again. (e) operator_required, count unchanged. (f) stale_revision. (g) the button is present in exactly the two offered states, with the labels of CL-111-08, and absent in the states of (c) and (d).
             Not automated yet: (g).
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-08';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_08_verified_by_TC_111_012 from 'CL-111-08' to 'TC-111-012';
    dependency CL_111_02_verified_by_TC_111_015 from 'CL-111-02' to 'TC-111-015';
    dependency CL_111_08_verified_by_TC_111_015 from 'CL-111-08' to 'TC-111-015';
    verification 'TC-111-008' {
        doc /* TC-111-008 — Runs and MCP
             CL-111-02, CL-039-06
             Setup: the station with a strategy run and a contest run (strategy_tests) and with an MCP client (mcp_tests).
             Steps: each run starts; an MCP reply before any browser action, after a repetition-limit stop, and after an operator start.
             Expected (CL-039-06): a run starts by one reply or call_cq, cause auto; the MCP reply is tx_watchdog with nothing prepared in the first two, accepted in the third.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-111-02';
            verify 'CL-039-06';
        }
    }
    calc def StationOperatingMode {
        in liveDecodingMode : WstxOfflineDecode::Mode[0..1];
        in selectionMode : WstxOfflineDecode::Mode;
        return mode : WstxOfflineDecode::Mode;
        doc /* #11 CL-011-02. The station's operating mode is the mode of whichever came
             last: the last started ft4|ft8 live decoding job (WstxOperatingReceive
             receive start, including the former Next receive mode control) or the last
             admitted operating selection (its requested mode, from admission on, even
             if the restart later fails); FT8 at a fresh boot. It persists across a
             receive stop and a spectrum-only job (review repair 2026-11-01: an FT4
             contact is not cancelled by stopping receive). An operating selection with
             action band keeps it: the band's entry is resolved in the station's
             operating mode, not in WireSelection's last mode (WSJT-X keeps the mode on
             a band change). FT4 is selected per station through the existing
             operating selection (action mode ft4, which retunes the dial to the FT4
             entry and restarts the live job in FT4) or the existing receive start;
             there is no second mode control, browser, rig-control, log or transmit
             authority for FT4: the #9 transmit panel's mode is a read-only display of
             this mode, its Tx offset input and the contact Tx input are bounded by the
             mode's domain (2916 Hz FT4, 2950 Hz FT8), both following station.tick. It
             sets the mode of a manually entered contact and of an own CQ, the Tx offset
             domain (FrequencyControls), station.tick period_ms (7500 FT4, 15000 FT8)
             and WstxTransmit::StationModeGate. */
    }
    action def ModeChange {
        doc /* #11 CL-011-04. When StationOperatingMode differs from the mode of a contact
             in calling, replying, report, rogerReport, rogers or signoff, the engine
             (at its next step or command: POST /receive/start, /receive/stop and an
             admitted /receive/select run one synchronous contact step before their
             202 reply, otherwise at most one 50 ms step later) turns Enable
             Tx off through #9 (TransmitArming disarm, DisarmCause modeChanged: no
             unkeyed request of the old mode remains) and cancels the contact as
             CancelContact (calling -> idle; replying..signoff -> cancelled, DX call and
             Tx1-Tx5 cleared, Tx6 next). A completed contact keeps its fields and its
             log record keeps its own mode (DirectLog); idle and cancelled contacts are
             unchanged. The Tx offset is clamped into the new mode's domain (an FT8
             2917..2950 Hz offset becomes 2916 Hz in FT4). Enable Tx afterwards starts a
             fresh own CQ in the new mode. DIFFERENT from WSJT-X, which keeps the DX
             call and Enable Tx across a mode change: a contact's messages, periods and
             log mode belong to one mode, so no contact or arm continues across modes.
             As WSJT-X (MW updateModeControlLock disables the mode controls while
             transmitting), an operating selection with action mode is refused busy,
             after the profile/revision checks and before any effect, while #9 reports
             PTT keyed, a transmission or Tune. Independently of the contact step, the
             #9 owner never keys or plays a request of another mode
             (WstxTransmit::StationModeGate), so no transmission of the old mode starts
             on the new mode's dial in the interval before the step; the contact's
             disarm cause is then refused (staleRequest) instead of contactCancelled. */
    }
    attribute def TransmitSubmission {
        attribute contactId : String;
        attribute slot : TxSlot;
        doc /* How QsoAndLogging uses WstxTransmit::TransmitRequest. While armed it keeps
             one pending request for the next period of the contact's txParity with the
             current nextSlot text, txOffsetHz and mode, and a new requestSequence for
             every change. A sequence, text, report or offset change replaces the pending
             request through #9 until its audio starts; #9 then refuses audioStarted and
             the change applies to the following period (D7; the #37 fold-out Now of a Tx
             line chooses it next and turns Enable Tx on, so it too goes from the next own
             period, never into a waveform already on the air). lastTransmittedText changes only on a started outcome; the contact
             reaches completed only on a completed Tx4 RR73/Tx5 73 outcome; refused or
             failed outcomes disarm with the visible refusal. A client timeout, colour
             change or disconnected press never means RF stopped. Tx offset domain FT8
             200..2950 Hz (Ft8WaveformContract tone 0; FT4-NOTE 200..2916). */
    }
    action def SetEnableTx {
        in enable : Boolean;
        doc /* #37 (operator design interview 2026-11-01): there is no Enable Tx control.
             Starting a QSO means transmitting: the QSO pane CQ button (no transmitting
             contact: a new own CQ; an active contact is cancelled first after a
             confirmation), a double-click on a decoded row
             (SelectDecodedRow, then on) and RR73/73 (choose Tx4 RR73/Tx5, then on; offered
             only while the contact is in progress, never on a completed or cancelled one,
             where Enable Tx would start a fresh own CQ) send
             enable_tx {enabled:true} with the shown safety revision, so grant, clock,
             period and safety-revision checks are unchanged; the CQ button, an explicit
             operator choice like the double-click, retries their enable_tx at most twice after a
             stale_revision refusal with the reloaded snapshot (CL-061-02). Transmission ends by itself
             on completion (Enable Tx off after a completed Tx4 RR73/Tx5 73, see the
             transition table), by the Tx watchdog, by Cancel contact or F4 (the contact
             is cancelled, a transmission already on the air finishes), by Abort QSO (Esc,
             AbortQso: the transmission stops now) or by HALT, the emergency stop. Alt+N has no
             function. Earlier text: Separate explicit operator action (Alt+N where the browser delivers it,
             HT Alt+N). Maps to WstxTransmit::TransmitArming (armed/disarmed is #9
             state). On: transmissions of the next slot start in the contact's parity
             periods through TransmitSubmission; with no partner, next Tx6 means
             calling CQ (state calling). Off (disarm): no new request; a transmission
             already started finishes (WSJT-X Enable Tx off lets the current Tx finish). */
    }
    attribute def StartActions {
        doc /* CL-111-02, CL-111-05, CL-111-07, CL-111-08. The start actions switch the
             transmit state (WstxTransmit::TransmitArming) on. Each is one ContactCommand
             that carries the CL-022 safety revision shown to its sender: reply (the row's
             SelectDecodedRow with replace true, then on), call_cq (the only start that
             calls CQ), call_dx (EnterDxStation, then on), send_next (chooses the slot of
             the current QSO, then on) and reset_repetitions (a new repetition count of
             the message due next, TxWatchdog). A start by the operator in the browser
             switches on with cause operator; a start by a run or an MCP client is
             automatic, switches on with cause auto and is refused tx_watchdog after a
             repetition-limit stop or when no browser action was seen this boot;
             reset_repetitions from a run or an MCP client is refused operator_required.
             An operator start that finds the state off opens a new repetition count.
             "QSO" is a contact with a partner in replying to signoff. Outcome per state
             before (reply | call_cq | call_dx | send_next | reset_repetitions):
             no contact, idle: prepares the row's QSO, on | a new own CQ, on | prepares,
             on | no_contact | no_contact.
             own CQ calling: the CQ is replaced by the row's QSO, on | state on: accepted,
             nothing changes; state off (kept after a lost radio or a refusal): the same
             CQ, on | the CQ is replaced, on | no_contact | no_contact.
             QSO, state on: another partner: the old QSO is cancelled, the new one
             prepared; the same partner: the QSO continues at the row's message with the
             same contact identity; on | contact_active | replace false: contact_active,
             also for the QSO's own partner; replace true: the old QSO is cancelled and a
             new one prepared (a new contact identity for the same partner too), on |
             chooses the slot, stays on | a new count, stays on.
             QSO kept, off, cause txWatchdog: as the row above, on | contact_active | as
             the row above | chooses the slot, on | a new count, on, the message due next
             is sent.
             QSO kept, off, any other cause: as the row above, on | contact_active | as
             the row above | chooses the slot, on | state_conflict.
             completed, cancelled: prepares the row's QSO, on | a new own CQ, on |
             prepares, on | no_contact | no_contact.
             A Hound's call_cq is no_contact. A slot without text is invalid_message, as
             choose_next. A safety revision other than the station's is stale_revision
             with field safety_revision. A start that arrives after a stop of the same
             station step is refused state_conflict (WstxTransmit::StopOrder). A refused
             start changes nothing: no QSO is prepared.
             When reply or call_dx is admitted but transmission is not possible (no
             transmit capability: transmit_unsupported; radio, its PTT switch or
             authorization not ready by the transmit owner's arm conditions
             (WstxTransmit::TransmitArming): radio_unavailable or not_authorized; clock
             not synchronized: clock_not_synchronized; Tune on: busy), the command is accepted, the QSO is
             prepared, the transmit state stays off with its causes unchanged and the
             transmit view's refusal is that reason; nothing starts by itself when the
             reason goes away. call_cq, send_next and reset_repetitions in the same
             situation are refused with that reason as their ContactRefusal
             (transmit_unavailable, clock_not_synchronized or busy) and change nothing.
             select_row, enter_dx and choose_next never start. */
    }
    dependency startActionsClause from StartActions to WstxQsoTransmit::'CL-111-02';
    dependency startNeverCqClause from StartActions to WstxQsoTransmit::'CL-111-05';
    dependency startCannotTransmitClause from StartActions to WstxContact::'CL-111-07';
    dependency resetClause from StartActions to WstxQsoTransmit::'CL-111-08';
    action def BandChange {
        doc /* CL-111-03. A contact holds the station band it was prepared on. The station
             band is the radio's dial band, else the band of the operating selection
             (WstxStrategy station band). When it differs from the contact's band, the
             engine at its next step or command switches the transmit state off
             (DisarmCause bandChanged; a transmission on the air finishes) and cancels a
             contact in calling, replying, report, rogerReport, rogers or signoff as
             ModeChange does (calling -> idle; a QSO -> cancelled, DX call and Tx1-Tx5
             cleared, Tx6 next). A completed, cancelled or idle contact keeps its fields
             and takes the band. An unknown station band is no band change, and a
             contact prepared while the band was unknown takes the first band seen. */
    }
    dependency bandChangeClause from BandChange to WstxTransmit::'CL-111-03';
    action def HaltTx {
        doc /* The operator's emergency stop (operator decision #39, 2026-11-04: HALT is
             emergency only and only manual): the Halt Tx buttons and Alt+H (HT). Sends
             WstxTransmit::HaltTransmit (POST /transmit/halt), stopping a transmission
             or Tune now and disarming (MW on_stopTxButton_clicked). Esc is no longer a
             halt (AbortQso). Shown as halted only after #9 confirms; until then
             pending/unknown. The keyboard halt is sent by the always-loaded page script
             (never waiting for the contact client), skipped only when the station is
             known receive-only. The remote emergency stop is MCP wstx_transmit_halt only;
             UDP has no Halt Tx. The station and its automation never send it in normal flow
             (WstxTransmit::TransmitHaltUse). */
    }
    action def AbortQso {
        doc /* Abort QSO (operator decision #39, 2026-11-04, "stop the transmission and
             the QSO immediately, but not HALT the system"): Esc and the "Abort QSO"
             button beside HALT send ContactCommand abort {}. The station stops the
             current transmission or Tune now (WstxTransmit::AbortTransmission: audio
             stopped, PTT released with readback, requests dropped, Enable Tx off with
             cause contactCancelled) and cancels the contact as CancelContact (nothing
             logged; a completed contact only selects Tx6 and keeps its fields). It is no
             halt: halt_state and the halt count are unchanged and the station stays
             ready for the next QSO. Like cancel it is accepted on any older contact
             revision. Esc (MW keyPressEvent ~3683 abortQSO) acts on every page state and
             in every focused field and closes no panel; an open dialog or menu takes Esc
             first. With nothing active (no contact in progress, disarmed, not
             transmitting) the button is disabled and Esc sends nothing. A running station
             automation run reacts to the cancelled contact as to any operator contact
             change. */
    }

    // ---------------------------------------------------------------- watchdogs
    attribute def TxWatchdog {
        attribute limitCalls : Integer = 6;
        attribute minimumCalls : Integer = 1;
        attribute maximumCalls : Integer = 99;
        attribute remainingCalls : Integer;
        assert constraint limitDomain { limitCalls >= minimumCalls and limitCalls <= maximumCalls }
        doc /* Operator rule #39, 2026-11-06 (replaces the WSJT-X time watchdog, CFG
             TxWatchdog ~3749, MW tx_watchdog ~14646, and the unanswered count of
             2026-11-04): the Tx watchdog limits how often one message is repeated, in
             manual operation and under automation alike, whatever the message (CQ,
             Tx1..Tx5, free text), except a strategy run's own contact while the run is attended,
             which has no stop (WstxStrategy::StrategyWatchdog; WD:n shows only this watchdog,
             never the run's leave count). Server-owned station-session setting: limit 1..99
             repetitions, default 6 at each station start. DIFFERENT: WSJT-X 0 = disabled
             is not offered; a safety bound always applies.
             It keeps no count of its own: the repetition count is the Rep of the
             ContactSnapshot dialogue, the count of the newest tx entry when that entry
             holds the message due next, otherwise 0. Whatever restarts that Rep is the
             only restart: a different message (the exchange advanced), a new contact, and
             one addition for the operator: an operator Enable Tx while Enable Tx
             is off makes the next transmission open a new tx entry, so a stopped station
             may send the same message again; while it is on it restarts nothing. Partner messages, browser clicks, settings, Auto Seq, MCP
             and automation requests restart nothing by themselves.
             Stop: when the send due next would exceed the limit it is never planned or
             keyed: 1.2 s into its period (past the latest live decode measured, #47) Enable
             Tx goes off (cause txWatchdog), PTT stays released, nothing is halted (no HaltTransmit,
             halt_state unchanged), a transmission already keyed finishes, the contact
             state is kept and the station shows "Tx watchdog: same message sent N times" until
             the next Enable Tx. A partner message decoded before that moment still changes
             the message due next, sent by a late start as below the limit. A request still pending when
             the send due next is at the limit (the limit lowered, or a Tx button going back to
             a message at its limit) would key, so Enable Tx goes off at once. The repetitions left are shown while Enable Tx is on
             (WD:n, watchdog tx_remaining_calls = limit - Rep, less the paused calls below).
             Automation (WstxStrategy::WatchdogFromOperator): an automatic Enable Tx is
             refused tx_watchdog after a stop or while no browser action was seen this
             boot; only the browser may set the watchdogs (set_watchdogs from another
             source is refused operator_required). A new message or target chosen by a run
             restarts the Rep like any other, so a run is bounded per message, not in
             total. Mouse movement the server cannot observe is not activity.
             Busy pause (#97 decision 7, BusyPartner; operator #93 2026-11-09 "Keep calling, don't
             count"): a send of the message due next while the partner is busy at its stop point
             (1.2 s into its period, BusyPartner) is a paused call and does not count toward the
             limit: the counted repetitions are Rep minus the
             paused calls of that tx entry, and tx_remaining_calls = limit - counted. The paused
             calls of one message are at most limitCalls (operator 2026-11-09, #97 Q5: at most N
             paused calls per message, N the limit); a further send while he is busy counts. So
             one message is sent at most twice the limit; nothing the partner does can extend it.
             A new message or contact restarts the paused count with the Rep; the operator's Enable
             Tx while off restarts it as it restarts the Rep. Which contacts pause: a manual contact
             (operator 2026-11-09, #97 Q7 "yes, both") and a strategy or contest run's own contact
             whose strategy has busy_pause on (WstxStrategy::BusyPause; the run's own contact has no
             stop while attended, StrategyWatchdog, so there the pause counts for the leave rule).
             A pounce and an MCP policy run never pause. */
    }
    attribute def TuneWatchdog {
        attribute limitSeconds : Integer = 90;
        attribute minimumSeconds : Integer = 1;
        attribute maximumSeconds : Integer = 300;
        assert constraint limitDomain { limitSeconds >= minimumSeconds and limitSeconds <= maximumSeconds }
        doc /* D4 adopted (CFG TuneWatchdog default true, TuneWatchdogTime default 90 s
             ~3750-3751; mainwindow_slots.cpp ~590; MW stopTuneATU ~12728). Always
             enabled (DIFFERENT: not switchable off), 1..300 s, default 90 s per
             station session. Starts when #9 confirms Tune on; at expiry the server
             ends Tune through #9; the remaining seconds are shown on the Tune control. */
    }
    dependency transmitBoundary from TransmitSubmission to WstxTransmit::TransmitRequest;
    dependency transmitOwner from TransmitSubmission to WstxArchitecture::TransmitService;
    dependency transmitPromise from TxWatchdog to WstxArchitecture::'FR-008';
    dependency busyWatchdogClause from TxWatchdog to WstxContact::'CL-097-06';
}
