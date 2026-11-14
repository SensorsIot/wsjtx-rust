package WstxAutoControl {
    private import ScalarValues::*;
    port def AutoControlPort {
        out item command : AutoCommand;
        in item activity : AutoActivity;
    }
    item def AutoCommand { doc /* Auto on or off, the active strategy's Auto rules. */ }
    item def AutoActivity { doc /* What Auto is doing. */ }
    interface def AutoControl {
        doc /* The station service commands the auto function; auto reports what it is doing. */
        end station : AutoControlPort;
        end auto : ~AutoControlPort;
    }
    attribute def StrategyRun {
        doc /* A WstxMcp::OperatingAutomation run with strategy true; one run at a time.
             Start and end (AutoToggle): a run starts only when Auto is switched on with a
             strategy or a contest selected, or when the selection changes while Auto is on.
             Switching Auto on ends any running pounce or MCP run (the operator wins). It starts
             through the same internal path as AutomationCommand configure and start, with the
             request's grant, the current safety revision and the operator's watchdog activity
             (WatchdogFromOperator), as the station's decision: the client sends only the
             selection and the toggle. Without a grant transport or transmit owner no run
             starts: Auto goes off and the snapshot's strategy_refusal names the reason
             (transmit_unavailable) until the next Auto on or selection. A selection change ends
             the run (a contact the run armed is disarmed, and cancelled so that the next can
             start, unless it is a started QSO, which is finished, StartedQso; a manual contact
             is left alone).
             max_contacts and max_run_minutes do not apply and read null. Run limit (operator
             decision 2026-11-06; the constant automation::STRATEGY_RUN_MAX, no setting): a run lasts
             at most 8 hours from its start, also with a browser open; a new start
             gives a new 8 hours. Unattended (operator decision 2026-11-06, #39 comment
             6685226511; the constant automation::CLIENT_GONE, no setting): no authenticated
             client for 60 s. A client is there while a status WebSocket session is open
             (authenticated at its upgrade), and at each authenticated POST /mcp, which has only
             per-request authentication: its last request within the 60 s; an Auto on or a
             selection itself counts. A client back before the stop continues the run.
             At the run limit or unattended ("Finish the QSO first", operator 2026-11-07): the
             run selects and calls no new station and answers no caller; its own CQ is
             disarmed and cancelled at once; a contact in progress ends its normal way: a QSO
             the partner is answering is completed, otherwise LeaveRule ends it (its unattended
             rule: no m, no contest stay, no busy pause) or the stop at N that is back
             (StrategyWatchdog); a manual one is left alone; when the run next waits it stops
             run_limit or no_client. So with every browser closed it does not go on calling.
             The run checks the grant, not the transport of the starting request: a page load, a
             second tab or a 401 recovery (a new proof) and the transport's own 8 h deadline do
             not end it; a revoked grant or a safety edit does (authority_lost).
             The run ends only by HALT, Auto off, a selection change, the grant
             (authority_lost), no client (no_client), the run limit (run_limit), a Tx watchdog
             stop (tx_watchdog: of its CQ, or left by a manual contact, which refuses the run's
             next enable_tx), or a refused command (transmit_refused, provider_error). Every end
             turns Auto off with the stop reason shown; the strategy stays selected and only an
             Auto on (or a new selection while Auto is on) starts it again: an AutomationCommand
             start of a configuration a strategy run left is refused 409 operator_required
             strategy, from an MCP client and from the browser. HALT from any source (button,
             Alt+H, MCP) ends the run and turns Auto off at the next station step, also with no
             run; the selection stays, so the marks stay (operator Q5, which replaces "HALT sets
             active None"); pushed by strategy.state. Esc (Abort QSO) changes neither.
             Ends at once (Q6; the contact is disarmed and cancelled at the next station step,
             no QuietTime): a band change (the station band differs from the band at the
             target's selection; the station never changes band or mode itself), a mode change
             (a new live identity), HALT; and, for a contact that is no started QSO, the end of
             a contest period, a contest deselected, Auto off (#81: a started QSO is finished,
             StartedQso). The run goes on after a band or mode change (it waits and selects from the
             next publication on the new band or mode) and after a period end (it waits
             outside_period; manual while a started QSO finishes); it stops after the others.
             Receive: a strategy run has no receive identity of its own. Without FT8 or FT4
             receive it waits with reason no_receive; when receive starts or the live identity
             changes it re-identifies and waits instead of stopping; last_decode restarts at
             the latest publication.
             Waiting reasons (run.reason while state waiting): no_receive, auto_seq (Auto Seq
             off), call (a nonstandard own call, #24 S1b), activity (a contest activity or Hound,
             #24 S2a; a contest strategy: any other than its own, WstxAutoControl::ContestRun), band
             (the station band is not one of the strategy's, StrategyBands; a contact the run
             armed on a band it then left ends at once as a band change does); it
             selects nothing until the reason is gone.
             Waiting: on each fresh complete publication the list is the verdicts with a rank,
             not completed in this run on this band and mode, not given up by the operator
             (ManualIntervention) and not in QuietTime, one per call, in ValueOrder (callers
             first with callers_first). The first is selected (select_row {replace false}), Tx
             and Rx take their place by FreeTxSlot (with Hold Tx on Tx stays and Rx is on the
             station, D16) and it is armed (enable_tx). Nothing listed: it
             keeps waiting, or calls CQ (CqWhenNoTarget). A contact the run did not select:
             ManualIntervention.
             Decision timing (#89, operator 2026-11-09: "decision always fastest when needed
             info is available. this is a general rule for the auto mode"): every decision of an
             Auto run (a selection, a slot, a slot check, a CQ, a leaving) is taken at the
             earliest moment the information it needs is available, never later: on the
             publication that brings it at once, and, where that information can be missing,
             at the latest at the moment its own rule names, then with what is there. A
             decision whose information is all there is taken at once, without waiting. The
             waiting cases are named where the decision is defined (FreeTxSlot "Waiting for
             the newest period").
             In a contact: completion counts and returns to waiting; LeaveRule decides when the
             run leaves the target; no stop. The browser itself never sends enable_tx for a
             strategy. The run snapshot (WstxMcp) carries left (null or {call, reason
             repetitions|gone|tx_changes|caller}, #97 LeaveRule), quiet ([{call,
             band, mode, remaining_s}], the retry pause), hearing (PskrUse), tx_slot (FreeTxSlot),
             slot_check (StrategyWatchdog) and leave (LeaveCountLabel). */
    }
    attribute def AutoToggle {
        doc /* Mode (Q5, Q11, Q12, Q17, Q29). Auto is a toggle above the QSO pane next to CQ
             (WstxQsoPane::QsoPane): green on, grey off. It is not part of a strategy
             and one toggle serves strategies and contests. It is station state in memory only:
             off after a station restart, after HALT from any source and after every run end
             (StrategyRun). With Auto off a selected strategy or contest only marks its
             candidates in Band Activity and nothing transmits for it.
             POST /strategy/auto {v 1, profile_id, boot_id, auto, automation_confirmed?}
             (operating access, the browser only; an MCP principal is refused at the boundary,
             #58, and no MCP tool dispatches to it; exact keys, the refusals of POST
             /strategy/ignore). auto true needs a selection: an active strategy or a contest
             (else 409 not_configured strategy, Auto stays off); a contest whose
             AutomationClause is forbidden needs automation_confirmed true (else 400
             invalid_request field automation_confirmed, Auto stays off), the browser asking the
             WstxStrategies::ContestPrompt warning first. A selection change while Auto is on to a
             contest whose clause is forbidden turns Auto off instead of starting it: the
             confirmation goes only with Auto on. auto false ends the run; a QSO the run has
             started is finished as an ordinary contact (StartedQso, #81: Auto only decides
             whether new QSOs start). Selecting None turns Auto off. The GET /strategy snapshot carries auto (boolean) and
             strategy_refusal; a change increments the strategy revision and is pushed by
             strategy.state. The reply is the GET /strategy snapshot.
             Browser: the Auto button reads the snapshot's auto (never a local guess); it is
             disabled without a selection or without transmit capability, with the reason as its
             title; enabled, its title is "Auto on: the selection transmits. Click to switch
             Auto off; a QSO already started is finished" while on (#81) and "Auto off: the
             selection only marks. Click to let it transmit" while off; a click sends POST
             /strategy/auto with the other value (for a forbidden contest after the
             confirmation). */
    }
    attribute def FreeTxSlots {
        attribute eventBytesMax : Integer = 1024;
        attribute rangesMaxFt8 : Integer = 48;
        attribute rangesMaxFt4 : Integer = 26;
        doc /* Open Tx slots (#65, replaced by #82, D18): every free frequency on my side at
             the time the other station will be transmitting, for the operator to see on the
             waterfall and to place Tx by hand (WstxSignalArea::FreeTxSlotMarks). The
             station's own value, built with or without an automation run, a QSO or Auto (no
             run_id, no ranking, no limit; #65's five best of each run decision go).
             Judged parity (round 2 Q1, "when he will be transmitting"): my Rx parity, the
             periods the other station transmits in (#66). In a QSO (Enable Tx on, my own CQ
             included, or a contact in progress, replying..signoff; by a run or by hand) the
             contact's Rx parity, the other of its Tx parity, so the value stays on that one
             parity. Otherwise (only listening: no run, a run waiting, Tune alone) the next
             period I could transmit in is the one after the period P in progress, and its Rx
             parity is P's own (round 1 Q3): the parity alternates every period.
             Counted periods, floor and value: FreeTxSlot's, unchanged (the last
             periodsPerParity periods of that parity that are due, ended on the clock or in
             progress with their complete publication published, #89; a period I transmitted in or did not
             receive leaving a gap; the WSJT-X
             passband floor; a slot's largest rise above it in those periods, clamped at 0 in
             whole dB). They are taken from the station's live job in the station's operating
             mode (WstxQsoTransmit::StationOperatingMode), from the last station band change on
             and from a new live identity's first period (FreeTxSlot Band, kept by the station,
             not by a run).
             Open (round 2 Q2): a Tx frequency f of FreeTxSlot's candidate grid (stepHz 10 Hz
             steps with my whole signal inside the Tx range, FT8 300..2650, FT4 300..2610) is
             open when its compared value is 0 (at or under the floor) and its signal
             [f, f + width) (FT8 50 Hz, FT4 90 Hz) overlaps no station decoded in a counted
             period (|f - d| below the width, d the decoded audio frequency). Nothing else
             applies: no clearance of a called station or of my Rx, no his end, no fallback
             when none is open, no ranking. The partner and every other decoded station of the
             counted periods close their own slots.
             Open ranges: the union of the signals [f, f + width) of the open f, as half-open
             intervals; overlapping intervals join, touching ones stay separate. Each range is
             [lo_hz, hi_hz) with lo an open f and hi an open f + width, at least one width
             long, ascending and disjoint. So at most rangesMaxFt8 (48, 2400 / 50) in FT8 and
             rangesMaxFt4 (26, floor of 2400 / 90) in FT4.
             Built: at each period start on the station clock; when the decodes of a counted
             period are published (operator 2026-11-09, Rebuild on decodes), also the complete
             publication of the period in progress of the judged parity, which makes it due and
             counted from that build on (#89; while only listening the judged parity is that
             period's own, so the last build before the next period start counts it); at once when a QSO starts or ends (the judged parity may change); at once when the live job, its mode or the
             station band changes. Without a live receive (no live job) the value is null; with
             no counted period open is [].
             Value: null or {at_utc_ms (station time of the build), mode ft8|ft4, rx_parity
             even|odd (the judged parity), qso (true in a QSO), periods (the number of counted
             periods, 0..periodsPerParity), open [[lo_hz, hi_hz], ...]}, integers in Hz, no
             per-slot numbers. It is GET /automation free_tx_slots (WstxMcp::AutomationWire)
             and the free_tx_slots.state event (WstxStationLink::PushedStationState), at
             most eventBytesMax (1024) bytes with the most ranges at their longest numbers.
             Auto's choice is FreeTxSlot's, unchanged: its own candidates (clear of the called
             station and with Hold Tx on of my Rx, his end where known), its own ranking (the
             lowest value, then the current Tx, nearer it, lower) and tx_slot in the run status.
             That ranking is not on screen. */
    }
    attribute def ContestRun {
        doc /* A contest with Auto on is a WstxAutoControl::StrategyRun: one run at a time, through
             the same internal path and the same contact engine, started only by a browser's
             selection with Auto on or Auto on (WstxAutoControl::AutoToggle). It applies the contest
             strategy's settings: the list is ContestVerdict with a rank (the contest's rules, with
             the strategy's lists on top, in ContestValueOrder); leaving and the retry pause are
             WstxStrategy::LeaveRule and QuietTime with the strategy's leave and retry_minutes
             (contest built-in: contest style after 2 Tx changes, 10 minutes); Tx moves are
             WstxStrategy::TxMoveRule; the busy pause is WstxStrategy::BusyPause (off in the contest
             built-ins); with cq_when_idle on (the contest built-ins' default) it calls CQ after
             cq_wait_periods publications with nothing callable listed
             (WstxStrategy::CqWhenNoTarget). Unchanged: HALT stops
             every run from any source and turns Auto off (revision + 1, pushed by
             strategy.state; the contest, its strategy and period stay); Esc
             changes neither; ManualIntervention (a double-click always, the run resumes after the
             QSO); WatchdogFromOperator; the 8 hour run limit (run_limit) and 60 s without a client
             (no_client), finishing the QSO first, with the contest staying selected, Auto off
             and the reason shown; the grant (authority_lost); WstxStrategy::FreeTxSlot; an
             AutomationCommand start of what it left is refused operator_required. A contact that
             is no started QSO ends at once at the end of the period (the run waits
             outside_period) and when the contest is deselected (WstxAutoControl::StrategyRun
             "Ends at once"); a started QSO is finished (#81, WstxStrategy::StartedQso).
             Waiting reasons in a contest (run.reason while state waiting), besides no_receive,
             auto_seq and call: activity (the station's activity is not the profile's), band (the
             station band is not in the profile), outside_period (the station clock is outside
             [start, end)). It selects nothing and calls nothing until the reason is gone.
             Selecting: on each fresh complete publication the list is ContestVerdict with a rank,
             one per call, not completed in this run on this band and mode nor given up; the first is
             selected as a strategy run selects, not in its QuietTime. The run never gives a station
             up: it is left by LeaveRule and may be called again after its QuietTime.
             Calling CQ (cq_when_idle on, after the CQ wait): while waiting and no reason it decides
             the slot (FreeTxSlot, no called station;
             decided in waiting without a fresh publication, at Auto on, when a reason ends, when a
             manual contact ends or Esc gives a caller up, after a completion or a leaving, it
             waits for the newest Rx period's complete publication and decides at once when it
             arrives, at the latest when the period in progress ends, WstxStrategy::FreeTxSlot
             Waiting for the newest period, #89, StrategyRun Decision timing;
             with Hold Tx on the held Tx, no decision, WstxStrategy D16) and
             sends enable_tx with no partner, which calls CQ with the activity's Tx6; state
             calling_cq. WstxStandardQso::CallFirst does not answer a CQ started by automation. On each
             fresh complete publication of the partner's parity the callers of my call
             (ContestVerdict kind caller with a rank, so only with Calling stations are answered on
             and never a dupe; in ContestValueOrder; not worked in this run on this band and mode,
             not given up, not in QuietTime) are read; the first is selected with select_row
             {replace false}, which keeps Enable Tx, and Tx stays on its slot
             (WstxStrategy::FreeTxSlot with that station). No caller: the CQ goes on. In the contact
             as when selecting; after completion or a leaving it waits, and calls CQ again after the
             CQ wait.
             In calling_cq: a reason appearing disarms and cancels the CQ and it waits; run_limit
             or no_client disarm and cancel the CQ at once and stop (there is no exchange to
             end); an operator's selection or cancel makes it manual; a disarm stops it with
             the cause (tx_watchdog, transmit_stopped): the Tx watchdog counts a repeated CQ like
             any message, so a CQ on a silent band stops at its limit until a new selection (the
             step that sees the disarm stops it tx_watchdog, and an automatic enable_tx after a
             watchdog stop is refused besides, WatchdogFromOperator). Every stop
             and a selection cancel a CQ of the run: none is left to read as the operator's contact.
             Esc on the run's own CQ ends that CQ; the run calls again. A dupe caller has no
             rank: it is never answered and never ends a stay (the #63 fix: the stay check read
             the award evaluator, which counts any caller); every check of a contest run reads
             ContestVerdict.
             The log: ContestLog of the last build on the station step, built at the selection
             first; each step of the run asks for it, so a build behind the log runs on its own
             thread as soon as a QSO is logged, also a manual one, well before the next
             publication; until it is done a QSO is held off by this run's own completed list. Band Activity follows ContestView; the status
             names "calling CQ", "<call>", "your QSO", "waiting · <reason>", "stopped · <reason>"
             or "not started · <reason>" from GET /automation on automation.state only, never a
             timer. The prompt offers the contest strategies (D11; no operation choice); AutomationClause forbidden asks
             WstxOperatingLayout's confirmation with the clause's text when Auto is switched on
             and sends automation_confirmed true with POST /strategy/auto, nothing when
             declined; silent asks nothing, the clause is on the prompt. After a stop only Auto
             on starts it again. No band hopping. */
    }
}
