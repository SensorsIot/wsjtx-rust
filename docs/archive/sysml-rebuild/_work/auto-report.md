# Report: the auto part

2026-11-16. Main session. In progress: the decisions are collected here first; the part is
written after them.

## Decided by the operator

1. **Auto is #119's Auto** (operator 2026-11-16, question 1, option 1): CL-119-01 to -08
   are auto's promises, `target` or `partial` where the code differs, revised by the later
   decisions: #122 (no MCP policy run), #123 (no pounce), #226 (no grant, so no
   `authority_lost`), transmit line 9 (no `runEnded`: the contact is cancelled), transmit
   line 10 (the repetition limit is qso's, and so is the exemption of Auto's own contact).
   The old texts are taken over where they still hold (leave modes, retry pause, busy
   pause, CQ wait, slot choice). Every difference from the code goes to the report as work
   for the code. The operator added: there is no formal Tx watchdog any more; only qso's
   repetition limit remains (a WSJT-X watchdog of minutes is no counterpart).
2. **Auto's CQ at the repetition limit** (operator 2026-11-16, question 2, option 2): the CQ
   ends at the limit, Auto stays on and calls CQ again after a full CQ wait. Auto never
   goes off for this reason; `tx_watchdog` is no Auto-off reason. The no-client rule still
   bounds unattended operation. Changes CL-119-03's last bullet and CL-119-05 item 5.
   Code: `automation.rs` `tick` stops the run with `tx_watchdog` (the `disarmed` reason).
   The operator added a quiet counter for the CQ (question 3a, answered "ok" to the
   proposal, 2026-11-16): `AutoKeys::cqQuietPeriods`, a setting of every strategy, 0 to 40,
   default 8, counted like `cqWaitPeriods` (every period, both parities). It starts when
   Auto's CQ ends at the repetition limit with no caller answered; other ends of the CQ
   (Halt QSO, a refusal, a station called from it) keep the ordinary CQ wait. During it
   Auto calls no CQ and still calls every callable station; a QSO in between ends it, and
   the ordinary CQ wait follows. After it Auto calls CQ at the first period with nothing
   callable (it replaces the CQ wait, they do not add). 0: no pause. Shown in Auto's state
   as the periods left. New: no code, no WSJT-X counterpart. Changes the strategy data
   (`WstxStrategies::AutoKeys`, the built-ins, the profile's `StrategyCheck`).
3. **Auto is a toggle that only the operator or an unavailable radio stops** (operator
   2026-11-16, in place of the answer to question 3a). Replaces CL-119-05's list. Stops:
   the operator's (or an agent's) Auto off, None selected, Halt; the radio unavailable
   (not ready, the SWR fault halt, a refusal radioUnavailable or transmitUnsupported, a
   failure after admission, deviceLost). Every other event that switched Auto off in #119
   or the code keeps it on: `transmit_refused` (packRefused, frequencyOutOfRange: the
   contact is cancelled or the CQ ends, and Auto picks again), `tx_watchdog` (decision 2),
   `authority_lost` (#226); `no_client`: question 4.
4. **The lost link stops Auto** (operator 2026-11-16, question 4, option 2): with no
   operator or agent connected (the station link's measure: 60 s now, #118's presence
   later; Auto only reacts) an unanswered call and the CQ end at once, a started QSO is
   finished, then Auto goes off with `no_client`. It is "the operator unavailable", beside
   the radio unavailable. The operator added: **Halt QSO is no reason for Auto off**; it
   ends that QSO only, and Auto picks a new station later (as CL-119-06: the dropped
   station is skipped for one pick).

5. **Auto's files** (operator 2026-11-16, question 3): `Watchdog` becomes `AutoMode` (the
   toggle, its three kinds of stop, the started QSO finished); M2.1 changed. The operator
   added: do not overcomplicate, do not duplicate variables, and store only what must
   survive a shutdown of the program. Auto stores nothing: its state, the stations
   completed since Auto on, the retry pauses and the counts are memory; the strategy's
   Auto settings stay in the strategies file as they are.

6. **Tx moves differ between a contact made by hand and Auto's** (operator 2026-11-16,
   question 5, in place of its options). Hand: qso moves Tx only to protect the partner's
   frequency, when the operator starts Tx on or close to the partner's Tx frequency; there
   is no busy-partner split and no other move. Auto: `TxSlot`'s strategy, keep the
   frequency when nothing needs optimizing and optimize otherwise (#106's slot choice and
   moves, the busy-partner split of `BusyPause`). So only auto uses the partner's PSK
   Reporter frequencies, qso needs no hearing connection, and auto needs no progress from
   contacts made by hand. Code: `contact.rs` splits for every contact
   (`freeslot::split_target`); the hand split goes, as work for the code. The protection
   move and what "close" means are written with qso. **Changed by qso decisions 1 and 2**
   (2026-11-16): every contact, hand-made or Auto's, moves Tx when its partner works another
   station close to my Tx, by one rule of qso, to the nearest open slot clear of him
   (`OpenSlots`, which auto gives qso), instead of stopping; no PSK Reporter for it. Auto's
   `BusyRule` loses its split. See `_work/qso-report.md`.

7. **The PSK Reporter information is always on screen while a station is selected**
   (operator 2026-11-16, with "go on and build the part"). Spots follows the station of the
   contact in progress, made by hand or by Auto, and gives its `TargetReport` to the station
   service as well as to auto; the station shows it. So Auto's state carries no `hearing`
   (it would copy spots' report). Changes spots: `FeedContext::target`, `HearingFeed`'s
   target, `SpotsControlPort` (the report to the station service), CL-039-20 now `partial`.
   Code: `pskr.rs` follows only a strategy run's own target
   (`tc_039_022_only_a_strategy_run_subscribes_to_its_target`), work for the code.

8. **Auto under a contest that forbids automatic operation is acknowledged once, in a
   central setting** (operator 2026-11-16, "For the operator" line 2, in place of its
   options): "The operator acknowledges in a central setting the usage of auto mode also in
   situations where it is forbidden. With this signature, nobody has to ask again."
   Written: `WstxAutoControl::AutoConfig::forbiddenContests` (Boolean, default false), an
   operator-level setting (`OperatorSettings::auto`, key `auto` of `operator.json`), given
   to Auto in `AutoContext::config`. With it: no prompt at Auto on, and a change of the
   strategy to a forbidding contest leaves Auto on. Without it: a switchOn under a
   forbidding contest is refused `notConfirmed`, and a change of the strategy or of the
   setting that puts Auto under a forbidding contest without it switches Auto off
   (`stopped`). `SwitchAuto::confirmed` left the model: one confirmation, not two (decided
   by the operator's rule "no duplicated variables"; the per-switch prompt would be a
   second way to confirm). Code: `automation_confirmed` of `POST /strategy/auto`
   (`strategy.rs` `auto_request`) and the forbidding-contest stop in `strategy.rs` `put`;
   work for the code. WSJT-X has no Auto and no automation clause.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| #106's slot choice (quietest by level, not clamped; the 2400 Hz range as a fallback step) and the moves (per PSK case between unanswered repetitions; off a station that appeared on my Tx) | decision 1: the operator's decisions recorded on issues are modelled; #106's promises are the operator's answers of 2026-11-11, written on #119 | modelled in `TxSlot`, `target` where the code differs; #106 is held only for its order after #119 |

## Decided by rule (more)

| Point | Rule | Result |
|---|---|---|
| Auto reads the decoded records (calls, frequencies, the partner's messages) | M5.4: a stream goes from its producer to its consumer directly | port `decodes : ~DecodesPort`, connection `decodesAuto` in `Station.sysml` |
| The bands of the strategy for the waiting reason `band` | M1.4: one fact in one place; the bands are ranking's share | `RankedList::offBand`, set by ranking |
| The automation clause of a contest for the switchOn | M5.7 and the shares: operating gives Auto what it needs of the strategy | `AutoStrategy::automation` |
| Halt reaches Auto | M5.3: commands only from the station service | `SwitchAuto` with `halt` |
| A refused start and failures after admission | #119 CL-119-08 with decision 3 (only an unavailable radio stops Auto) | `StartRule`: packRefused and frequencyOutOfRange leave Auto on |
| The partnerWorksOther stop of qso for Auto's contact | decision 6: Tx moves of Auto's contact are Auto's | qso does not stop Auto's contact; `BusyRule` moves or leaves (handover to qso) |
| `slot_check`, `hearing`, `his_end`, leave `mode` and `busy` in Auto's state | operator 2026-11-16: no duplicated variables | dropped: the PSK case comes from spots' report, the moves show as Tx, the mode is the strategy's, busy is qso's `busyWith` |
| Repetition limit for the paused calls | the limit is qso's (transmit line 10) | `AutoContext::repetitionLimit` |

## Identities

Placed (44): CL-039-05, -09, -22, CL-065-01, CL-081-01, CL-097-04, -05, -06, -08, and the
new CL-119-04, -05, -06, -08, CL-097-11; 31 test cases (`ledger.md`).

Retired: CL-039-07 (no promise), CL-039-23 (into CL-097-04 and CL-119-04), CL-042-03,
TC-042-004, TC-042-005 (pounce, #123), CL-063-05 (into CL-039-05), CL-063-06 (into
CL-119-05), TC-039-049 (Hold Tx has no effect under Auto), TC-065-001 and TC-065-002
(replaced by TC-082-001 and TC-082-003, as their tests say). Not carried (planned, no
test): TC-039-051, TC-065-004, TC-081-007, TC-082-005, TC-082-006, TC-089-005. Handed over:
TC-082-003 (station link).

Tests not bound because they assert what the decisions remove (work for the code): the
caller exception (`tc_039_043_a_caller_is_answered_at_once_unless_off_quiet_or_answered`,
`tc_039_044_a_contest_caller_is_answered_at_once`,
`tc_097_009_g_a_caller_is_answered_at_once_in_each_mode`), the Tx watchdog stop of Auto's CQ
(`tc_063_011_the_tx_watchdog_stops_a_run_on_a_silent_band`,
`tc_039_045_the_watchdog_and_no_client_end_the_cq_and_its_slot_is_quiet`), the unattended
stop at N (`tc_039_033_unattended_x_is_never_doubled`,
`tc_097_009_f_unattended_until_logged_and_contest_end_at_the_stop_at_n`,
`tc_097_011_g_unattended_the_busy_calls_count_and_tx_still_moves`), the 8 hours
(`tc_039_033_a_strategy_run_lasts_at_most_8_hours_from_its_selection`,
`tc_039_004_a_run_goes_on...` keeps its other steps), the manual intervention and MCP
refusals (`tc_039_004_a_double_click_*`, `tc_039_004_a_manual_qso_*`,
`tc_039_004_stop_and_halt_while_manual`, `tc_039_004_an_mcp_client_cannot_restart_*`,
`tc_039_004_a_strategy_run_follows_the_grant_not_the_transport`, `tc_089_004_after_*`,
`tc_063_009_a_manual_qso_of_the_period_*`), Hold Tx (`tc_039_049_*`,
`tc_089_002_a_held_slot_check_*`), his end (`tc_039_010_his_end_excludes_*`,
`tc_066_002_his_end_applies_*`, `tc_039_048_the_run_shows_the_hearing_and_his_end`), the
pounce (`tc_042_004_*`, `tc_039_042_a_selection_with_auto_off_leaves_a_pounce_running`,
`tc_039_010_a_pounce_*`, `tc_081_003_auto_on_ending_a_pounce_*`), the MCP policy run
(`tc_081_003_an_mcp_stop_*`, `automation_tests.rs::tc_039_010_a_plain_policy_run_*`), the
grant (`tc_081_005_g_a_safety_edit_*`). Bound tests that assert a removed behaviour in
one step carry a line "Planned, no test yet" with the model's behaviour.

## Work for the code

1. Auto stays on for the repetition limit of its CQ, for packRefused and
   frequencyOutOfRange, for Halt QSO and for a strategy change; it goes off only by
   `AutoStops`; no `tx_watchdog`, `authority_lost`, `run_limit`, `strategy_missing` or
   `manual` (decisions 2 to 4, #119).
2. Nobody connected: cancel an unanswered contact and the CQ at once (decision 4).
3. No caller exception; the publication of a completion or a leaving counts for the CQ wait
   (#119); no busy leave and no busyPause setting (qso decision 5).
4. The CQ pause (`cqQuietPeriods`), in the strategy data, the built-ins, the check and the
   editor (CL-097-11).
5. The waiting reasons `contact`, `clock`, `tune`; Halt QSO skips the station once; the
   operator's starts refused `auto_on` while Auto is on (#119).
6. The move off a new station, no Hold Tx effect, Rx stays at a move (#106, #119); Auto
   names the station and when to move, qso places Tx (qso decisions 3, 4).
7. No split for Auto's contact; the rule "too close to the partner's Tx" is qso's for every
   contact (qso decisions 1, 2).
8. Spots follows every contact in progress and the screen shows its report (decision 7).
9. The acknowledgement setting `forbiddenContests` in `operator.json`, the Settings page and
   the agent's view; `automation_confirmed` leaves `POST /strategy/auto` and the browser's
   prompt goes; a change to a forbidding contest leaves Auto on with the acknowledgement
   (decision 8).

## Size

Measured with a script: the old text of the 57 identities in `QsoData.sysml` was 122,005
characters, the taken-over `AutoControl.sysml` 21,653, and the old `auto/Strategy.sysml`
and `auto/Automation.sysml` 66,897 (shared with ranking and the MCP run). The new part is
112,370 characters in eight files: 14 clauses, 31 test cases.

## For the operator

1. Decision 7 changes spots: CL-039-20 is `partial`, the station service gets the
   `TargetReport`. **Done:** spots' description rewritten from the model (2026-11-16),
   also for FR-027, `SpotsControl`, the broker and collector settings and `decodes`.
2. **Answered** (decision 8): the acknowledgement is one central setting; with it a change
   to a forbidding contest leaves Auto on, without it Auto goes off.
3. `AutoContext` (presence, receive, Auto Seq, call, activity, band, mode, repetition
   limit, contact parity, operator's contact) is new; the station service fills it. The Tx
   offset comes from qso (`QsoProgress::txHz`).
4. **Answered** by qso decisions 1, 2 and 6: the too-close rule and its measure.


## Work for the code: promises no test shows yet

Taken from the test cases when they became skeleton and a title (operator 2026-11-16, SensorsIot/harness#129). Each is a behaviour the model promises and no bound test shows; the case's clause carries the status.

- TC-039-042 (`AutoMode.sysml`): a change of the active strategy while Auto is on leaves Auto on, and its contact goes on under the leave rules of the new strategy; the agent's switchOn and switchOff do what the operator's do.
- TC-063-011 (`AutoMode.sysml`): Halt QSO on Auto's CQ ends the CQ and Auto stays on; a failure of a transmission of Auto's CQ switches Auto off with transmit_stopped.
- TC-039-033 (`AutoMode.sysml`): at the moment nobody is connected, Auto's contact that K1ABC has not answered and Auto's CQ are cancelled at once, and Auto goes off with no_client; a started QSO with K1ABC runs on to its completion first.
- TC-039-004 (`TargetChoice.sysml`): Halt QSO on Auto's contact with G4ABC cancels it, Auto stays on, the next pick skips G4ABC and the pick after it calls him again; Auto on while the operator's contact is in progress waits with contact until it ends, then calls the next station.
- TC-063-009 (`TargetChoice.sysml`): under a contest in force Auto does not wait for a special activity: the contest brings its own.
- TC-039-043 (`Leave.sysml`): JA1XYZ calling the profile's call during Auto's call of K1ABC does not end it, whether or not callers come first.
- TC-039-044 (`Leave.sysml`): K2NEW calling the profile's call during Auto's call of K1ABC does not end it.
- TC-097-009 (`Leave.sysml`): in each mode N1NEW calling the profile's call at the second call does not end the contact with K1ABC.
- TC-039-045 (`CqWhenIdle.sysml`): Rx stays where it is when the CQ takes its offset; the CQ that the repetition limit 2 ends leaves Auto on and starts the CQ pause.
- TC-097-018 (`CqWhenIdle.sysml`): after a QSO with N1NEW, and after K1ABC is left under leaving after 1 call, the publication in which the contact ended counts as the first: with a CQ wait of 3 the CQ comes at the second empty publication after it.
- TC-089-004 (`CqWhenIdle.sysml`): Hold Tx on changes nothing: the CQ from 1450 Hz.
- TC-097-015 (`CqWhenIdle.sysml`): JA2ABC calling the profile's call during Auto's contact with JA1XYZ does not end it.
- TC-039-022 (`TxSlot.sysml`): Rx stays on K1ABC when Tx moves.
- TC-097-010 (`TxSlot.sysml`): Rx stays on K1ABC when Tx moves; a station decoded on Tx in a counted period makes Auto ask for a move before the next transmission, except while K1ABC's report is -4 dB or better or the message due has not been repeated, and one move when both reasons come together.
