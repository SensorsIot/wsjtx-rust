# Report: the qso part

2026-11-16. Main session. Built: the six qso files and the interface `QsoControl` pass the five
tests of `part_done.py`.

## Decided by the operator

1. **The protection move of a hand-made contact** (operator 2026-11-16, question 1, option 1;
   auto decision 6 left "close" to qso): close means the two signals are less than 50 Hz apart,
   Auto's clearance (`WstxTxSlot::SlotLimits::clearanceHz`: Tx within 99 Hz of the partner's
   decoded frequency in FT8, 139 Hz in FT4). Tx then moves to the nearest offset clear of him,
   the lower on a tie, inside the Tx range; Rx stays on him. Checked when a start is accepted
   (Reply, Call, Send next); an explicit Tx setting of the operator afterwards wins. With Hold
   Tx off Tx lands beside him instead of on him. Code: no such move (`follow_selection`); work
   for the code. WSJT-X has none. Where Tx goes: decision 2.
2. **The partner of a hand-made contact works another station close to my Tx: Tx moves, it does
   not stop** (operator 2026-11-16, question 2, in place of its options: "Always when this
   happens, we shift TX frequency to a free slot instead of stopping transmission"; question 2a:
   "We have a function to display and also to find empty slots"). While I call him (replying, or
   report after a skipped Tx1) and his message to another call has his signal less than 50 Hz
   from mine (decision 1's measure), Tx moves before my next own period; transmission stays on.
   Where Tx goes, for this move and for decision 1's: the nearest offset inside the open slots
   that auto builds with Auto on or off (`WstxTxSlot::OpenSlotRule`, `OpenSlots`, CL-065-01),
   clear of him; the lower on a tie; Rx stays on him. With no open offset clear of him, the
   nearest offset clear of him (Tx never stays on him). No PSK Reporter (qso has no hearing
   link). **The same with Auto on and off** (operator 2026-11-16, while question 2 was being
   recorded: "I think this case is exactly the same in auto on and auto off"): one move rule,
   qso's, for every contact, hand-made or Auto's; Auto's `BusyRule` loses its split. This
   changes auto decision 6 ("no busy-partner split" for a hand-made contact). WSJT-X stops instead
   (auto_sequence, stopTolerance 50). Code: the busy split `freeslot::split_target` (from 500 Hz,
   decoded stations, his PSK frequencies); work for the code. By rule (M5.7, downward): auto gives
   qso `OpenSlots` over `TargetChoice`.

3. **The clear-spot rules are qso's, not Auto's** (operator 2026-11-16, question 3, in place of
   its options: "Why do we have so many functions? I think all are called only in one area. They
   do not belong to Auto. They belong to the general QSO"). The rule "too close to the partner's
   Tx" and the function "find a clear spot" stand in qso; auto's `TxSlot` loses `SlotLimits`,
   `SlotLevel`, `SlotChoice`, `OpenSlotRule` and the "where" of `MoveRule` (CL-039-09, CL-065-01
   and their cases move to qso; CL-097-05's "when" stays Auto's strategy). How many functions
   remain: question 4.
4. **One function, "best quiet space"** (operator 2026-11-16, question 4: "One function, best
   quiet space, which includes not only the level, the signal level, it also includes information
   from the PSK reporter from the other station"; question 4a, option 1). qso's one function
   replaces `SlotLimits`, `SlotLevel`, `SlotChoice`, `OpenSlotRule`, `MoveRule`'s "where", the
   busy split and decisions 1-2's "where". The candidates: offsets on the 10 Hz grid from 500 Hz
   in the Tx range with the whole signal inside it, clear of the partner (50 Hz between the
   signals). Then, each while one remains: free of the stations decoded in the counted periods;
   free at his end (50 Hz from each frequency PSK Reporter shows the partner decoding in my
   transmit parity); below 2400 Hz. Then the quietest by level (the passband floor rule of
   `SlotLevel`). Among equal levels the one nearest a frequency he decodes (#39 (c), 2026-11-04),
   then the current Tx, the nearer, the lower. With no free offset, the quietest offset clear of
   him. Without PSK information, my side alone. The screen shows the free offsets of the same
   function (my recommendation in question 4, not contradicted: from 500 Hz, at the floor, no
   decoded station). Consequence: spots' `TargetReport` also goes to qso. Users: the rule "too
   close to the partner's Tx" (decisions 1, 2), Auto's pick, CQ and moves (Auto says when, qso
   where; `CallTarget` loses `txHz`). Code: `freeslot.rs` `choose`, `split_target`, the open
   ranges; (ii) not built; work for the code. **Question 4b** (operator 2026-11-16, option 1):
   one bound, 500 Hz, for the choice and the screen's free offsets. The tests that assert the
   screen from 300 Hz (`freeslot_tests.rs` `tc_082_001_a_station_closes_*`,
   `tc_082_001_other_parity_*`, `tc_082_001_the_value_of_a_build`) are not bound; work for the
   code. Code: (i) "free at his end" is built in `candidates` (`quietest_clear` with `his`) and
   shown by `tc_039_010_his_end_excludes_and_is_ignored_when_it_leaves_nothing` and
   `tc_066_002_his_end_applies_among_the_candidates_left_by_decodes`; Auto passes no `his` (#119).
5. **Busy pause for every contact** (operator 2026-11-16, question 5: "Busy pause for all. If
   the partner doesn't have a contact, we do not add repetitions. This is a busy pause"). While
   the partner is in another QSO (`WstxOperatingChain::BusyPartner`), a send to him counts no
   repetition, for every contact, hand-made or Auto's; qso's rule, with its bound (at most the
   repetition limit of paused calls per message). The strategy setting `AutoKeys::busyPause` and
   the leave with reason busy (`LeaveReason::busy`) go; Auto's `BusyRule` keeps nothing of its
   own (the paused calls still count for nothing toward leaving, a change point or a move). Code:
   `Automated::pause`, `busy_pause` in strategy.rs; work for the code. Changes auto (BusyPause,
   Leave, AutoKeys, the built-ins, the profile's strategy check).

6. **Hold Tx** (operator 2026-11-16, question 6: "If hold TX is off, TX is moved to RX. This is
   the normal behavior of TX hold off"; question 6a: "The too-close rule is only for Tx hold
   on"). Hold Tx on (the default, session only): a selection keeps Tx, and the rule "too close to
   the partner's Tx" applies (decisions 1, 2). Hold Tx off: Tx follows Rx (WSJT-X), also onto the
   partner, and the too-close rule does not apply. A selection of a station calling me keeps Tx
   in both (code and WSJT-X). Decided by rule from this and "the same with Auto on and off":
   Auto's contact has no Hold Tx (#119) and its Tx is the best quiet space, clear of the partner;
   the too-close rule applies to it as with Hold Tx on.
7. **#109 against decisions 2 and 5** (operator 2026-11-16, question 7, option 1): today's decisions
   stand; see "Decisions found on issues", line 5.
8. **Hound** (operator 2026-11-16, question 8: "hound mode is special and implemented exactly the
   same as wsjt-x without automation"): the Hound places its Tx by its own rules as WSJT-X (Tx1 at
   random 1000-2998 Hz below 999 Hz, Tx3 on the decoded Fox frequency, Fox +-300 Hz on a repeat;
   `HoundTransmissionPolicy::planFoxReportReply`); the too-close rule, the quiet space and the busy
   pause do not apply; Auto does not run (auto's `WaitRule` waits on a special activity without a
   contest in force).
9. **Rule of thumb** (operator 2026-11-16, unasked: "whenever wsjt-x would stop because the tx
   frequency is too close, we select an open one and continue"). So the move when the partner works
   another station holds with Hold Tx off too (WSJT-X stops there regardless of Hold Tx); decision
   6a ("only for Tx hold on") keeps only the judgement at a start, where Hold Tx off puts Tx on Rx.
   Written into `TooCloseRule`.

## The Tx placement and Auto clauses, cleaned (2026-11-16)

Done in the model files on the operator's instruction ("we want clean SysML files"), with
decisions 1 to 6 and 4b:

- New qso files: `Qso.sysml` (`QsoService` with its ports, `display` and `hearing` moved from
  auto), `HoldTx.sysml` (`SlotLimits`, `SlotLevel`, the one function `QuietSpace`,
  CL-039-09, CL-065-01 with `OpenSlotRule`, CL-039-08 with `HoldTxRule`, the new CL-039-29
  with `TooCloseRule`; cases TC-039-010, -050, TC-066-002, TC-089-001, -002, TC-082-001,
  TC-039-009), `StandardQso.sysml` (CL-097-06 with `BusyPause`, TC-097-011).
- Auto: `BusyPause.sysml` deleted (M2.1 changed); `TxSlot.sysml` keeps only when Auto asks for
  a move (CL-097-05, `MoveRule`); `Leave`, `CqWhenIdle`, `TargetChoice` name no slot rule and no
  busy rule; `Auto.sysml` lost `display` and `freeslot.rs`.
- Interfaces: `AutoControl` lost `TxChoice`, `OpenRange`, `OpenSlots`, `LeaveCount::paused`,
  `LeaveReason::busy`, `AutoContext::txHz`; `QsoControl` gained them (`QsoState::txSlot`,
  `QsoProgress::txHz`, the port item `openSlots`) and lost its old busy-pause paragraph;
  `OperatingChain`: `BusyPartner` is the detection only, `CallTarget` lost `txHz`;
  `Strategies` lost `busyPause`; `Hearing` and spots name qso as a receiver of `TargetReport`;
  `TransmitControl` and `TransmitState` lost `partnerWorksOther`; `StationLink` names
  `WstxQsoControl::OpenSlots`; `Station.sysml` connects `display` and `hearing` to qso.
- Not carried: TC-082-002, TC-089-003, TC-066-001 (every test asserts the free offsets from
  300 Hz). Unbound: `tc_082_001_a_station_closes_*`, `tc_082_001_other_parity_*`,
  `tc_082_001_the_value_of_a_build` (300 Hz), `tc_039_010_a_band_change_a_caller_on_my_slot_and_a_pounce`
  (a pounce), `tc_097_011_d_*` (the nearest split), `tc_097_011_f_*` (busy pause off).
- Gate: no `busyPause`, `BusyRule`, `SlotChoice`, `FreeTxSlot`, `split` (but the rig's) or
  `partnerWorksOther` in the model; the reading of old strategy files names `busy_pause`.
- Still old text, rebuilt with qso's interface: the rest of `QsoControl.sysml` and CL-085-02.

## Decided by rule

| Point | Rule | Result |
|---|---|---|
| CL-099-01 (the EU VHF packer) and the packer half of CL-024-03 (S2b1) | M1.1 and the source rule: `WstxMessageEncode::PackMessage` packs every family "in the order in which WSJT-X chooses it" (modes, CL-009-01) | not qso's: CL-099-01 retires into CL-009-01; TC-099-001, TC-024-007 go to modes (handover) |
| The contest serial | an operator decision recorded on an issue is modelled (#98, CL-098-04): while a contest is selected the serial is 1 + the highest STX of the period's contacts in the log, also those handed over and not yet visible; 1 when none; a restart continues; without a contest a boot counter | qso's `ContestSerial`; with six stations one logbook gives one sequence; code: boot counter only, work for the code |
| CL-085-03 (the serial counts only when the log accepts) | follows from the serial from the log for a contest; stays for the boot counter | kept |
| The station's operating mode (CL-011-02) | handover row 62: the station service's | qso gets the mode in its context; the contact's mode is fixed at preparation (qso) |
| Enable Tx (`enable_tx`, CL-010-03, `SetEnableTx`) | #111, #121 | retired; the starts switch transmission on; Cancel and Abort stay qso's; Halt is the station service's |
| The radio authorization (`granted`, `not_authorized`, `NotAuthorized`) | #226 | gone from qso |
| An agent's starts, Reset, set of the limit, the directed-CQ confirmation | #122: an agent equals the operator | no `automatic` principal for agents; only Auto's own commands are Auto's |
| Log QSO (`open_log`) | log report, 2026-11-16: Log QSO resends, hands nothing over and closes nothing | qso hands a contact over only at completion |
| The Tx watchdog (repetition limit, count, calls left, expired) | handover row 119 | qso's; CL-039-06 and TC-039-005 come to qso; the Tune limit stays transmit's |
| qso's configuration | handover row 192, `_work/settings.csv` | Auto Seq, Call 1st, the repetition limit, the special activity with its exchange, the Rx and Tx offsets in `QsoConfig` (station config); Hold Tx, Skip Tx1, Tx4 form, report, parity are session state; no `qso-settings.json` |
| The activity in a contest | #228, handover row 206 | the contest's activity while it is in force, else the operator's |
| "Station automation does not start in a contest activity / as a Hound" (CL-024-02, -04) | #119, #228 and auto's `WaitRule` (`activity`) | the old sentence goes; auto waits by its own rule |
| CL-010-14 (clock, period bar, level meter), CL-010-15 (the contact wire) | M4.7, M2.1 | frontend and station link (handover) |
| CL-039-25, CL-042-05, -06, -07, CL-063-08 | the screens | frontend (handover) |

## Decisions found on issues (modelled)

Issue #109 (cr:deciding; operator 2026-11-11 and 2026-11-13; reference WSJT-X v3.3.0-beta6, commit
7255454) decides the sequence. Modelled in `StandardQso`:

1. **Step back** as WSJT-X: a counted grid gives report/Tx2, a report rogerReport/Tx3, an R-report
   rogers/Tx4, in every active state. A 73 sent while a step back is counted completes nothing; the
   stepped-back message follows.
2. **Nothing advances while the transmit state is off**: a partner message changes no state and
   completes nothing; the report, the dialogue and the offered step are still recorded (default D1).
   The QSO goes on by Reply, Send next or Reset.
3. **A message chosen after the end** reopens the QSO at that message (CL-109-01); a second
   completion hands nothing to the log and does not count the serial again (CL-109-02's qso half,
   CL-109-03).
4. **A 73 in rogerReport** is answered with one 73, then completed: a deliberate difference from
   WSJT-X (operator 2026-11-11).
5. **The stop when the partner works another station** (operator 2026-11-13: a manual QSO stops,
   no move, no paused calls): **replaced** by today's decisions 2 and 5 (Tx moves, the busy pause
   for every contact; operator 2026-11-16, question 7: "Today stands"). The bound of the busy pause
   (at most twice the limit of sends of one message) answers #109's reason. #109's promise 5 and
   its list of changed text are to be revised on the issue when the operator allows the post.

Issue #111/#121 (Enable Tx retired; the starts switch transmission on), #122 (an agent equals the
operator), #123 (pounce removed), #226 (no radio authorization), #228 (the activity of the contest
in force), #98 (the contest serial from the log) are taken as decided. #86 (a one-click button for
the quiet space by hand) and #189 (the contact after a device fault) are recorded, not decided:
not modelled.

## Where the identities stand

The old texts were read in full (QsoData, QsoTransmit, QsoWire, StandardQso, SpecialActivities,
and the rows handed over by log, modes and transmit); the ledger has each row.

| File | Clauses | Cases |
|---|---|---|
| `Qso.sysml` | (the part `QsoService`) | |
| `StandardQso.sysml` | CL-010-01 `PrepareRule`, CL-010-02 `SequenceRule` (with #109), CL-109-01 `ReopenRule` (new), CL-010-17 `CallFirstRule`, CL-050-04 `ReplaceRule`, CL-050-06 `DialogueRule`, CL-011-03 `FtModeRule`, CL-011-04 `ModeChangeRule`, CL-039-24 `DirectedCqRule` (takes CL-063-07 and the warning of CL-097-09), CL-097-06 `BusyPause`, CL-085-02 `HandOverRule`, `LogTimes` | TC-007-001, TC-007-008, TC-007-010, TC-010-010, TC-050-004, TC-050-006, TC-039-053 (new), TC-097-011, TC-097-012, TC-097-017 |
| `MessageChoice.sysml` | CL-010-12 `MessageSet`, `ReportRange`; CL-024-05 `NonstandardRule` (new, handover row 37) | TC-024-003 |
| `QsoTransmit.sysml` | CL-111-02 `StartRule`, CL-111-05, CL-111-07 `BlockedStartRule`, CL-111-08 `ResetRule`, CL-010-03 `EndRule`, CL-039-06 `RepetitionLimit`, CL-039-21 | TC-008-001, TC-039-054 (new), TC-007-004, TC-111-002, TC-111-003, TC-111-011, TC-111-012, TC-111-018 |
| `SpecialActivities.sysml` | `ActivityRule`; CL-024-02 `GridExchangeRule`, CL-024-03 `ContestExchange`, `ContestLogFields`, CL-099-02 `EuVhfRule`, CL-024-04 `HoundRule`, CL-111-10 `HoundLimits`, CL-085-03 `ContestSerialRule` | TC-024-005, TC-024-008, TC-099-002, TC-024-011, TC-024-012, TC-024-014, TC-111-016 |
| `HoldTx.sysml` | (as before) and CL-010-11 `OffsetRule` | |
| `interfaces/internal/QsoControl.sysml` | `QsoContext` with `QsoConfig`, `QsoCommand`, `QsoAnswer`, `QsoState`, the enumerations | |

Elsewhere, in the same change: `OperatingChain` (`FinishedContact` has its features; CL-085-02 and
`TxSlot` moved out), `Logbook` (`DirectLog` names the features; its marker is gone),
`ProfileAccess` (`StationConfig::qso`), `Strategies` (the activity is typed; the rule moved to
`ActivityRule`), `StationLink` (the contact wire moved in, as taken over), `Mcp` (its reference).

Not qso's, by rule (the ledger has each): the screens and browser tests to the frontend; the
contact wire to the station link; CL-011-02 and the a-priori context to the station service;
CL-010-10 into CL-039-06 and transmit's Tune limit; CL-099-01 into CL-009-01, TC-099-001 and
TC-024-007 into modes' TC-005-001 and TC-005-002 (their bound files hold the tests); CL-110-01
and TC-110-001 to -004 retired (no `qso-settings.json`); planned cases without a test not
carried.

## The tests read

Every test of `contact_tests.rs` and `transmit_state_tests.rs` was read in full, and the
station tests of `contact_http_tests.rs` that a qso case names (FT4, activities, the hash table,
the a-priori context, the serial). A test is bound when it shows its clause; the tests that use
the retired `EnableTx` only as the start are bound. Not bound, because they assert behaviour the
decisions remove:

| Test | What it asserts |
|---|---|
| `repeats_resend_and_a_report_from_rogers_returns_to_tx3`, `the_whole_auto_sequence_table_of_a_partner_message` | a grid in roger_report changes nothing (#109: steps back) |
| `tc_007_010_c_a_halted_tx4_rr73_then_the_partners_rr73_sends_73_once` | a partner message advances while transmission is off (#109) |
| `choosing_a_slot_on_a_finished_contact_never_changes_its_state` | a chosen message never reopens (#109, CL-109-01) |
| `partner_working_another_call_moves_a_manual_contact_clear_of_him`, `tc_097_012_b_*`, `tc_097_017_c_the_split_frequency_table`, `tc_097_017_c_a_move_before_or_after_the_audio_start` | the nearest offset (decision 4) |
| `partner_working_another_call_within_50_hz_stops_*`, `tc_097_017_a_contact_that_does_not_pause_counts_every_send`, `transmit_state_tests.rs` `tc_111_001_a_*`, `tc_111_001_d_*` | the stop or a contact without the busy pause (decisions 2, 5, 9) |
| `receive_only_station_prepares_and_logs_but_refuses_transmit`, `log_qso_and_completion_log_at_once_*`, `log_qso_closes_a_running_contact_*`, `tc_099_002_eu_vhf_udp_directive_and_rs_bounds`, `contact_http_tests.rs` `simultaneous_ft4_and_ft8_stations_*`, `tc_085_004_*`, and the `transmit_state_tests.rs` tests built on `completed()` (`tc_111_003_*_in_each_state`, `tc_111_006_*`, `tc_111_009_*`, `tc_111_012_where_reset_is_refused`) | Log QSO hands the contact over and closes it (log, 2026-11-16) |
| `enable_tx_arms_with_the_revision_*`, `an_operator_disarm_is_not_reported_*`, `tc_111_003_a_stale_safety_revision_*`, `tc_111_010_tune_is_independent_*`, `tc_111_010_g_*` | the safety revision and the grant (#226), the agent barrier (#122), Enable Tx |
| `tc_111_016_the_hound_stops_300_s_after_its_last_start` | an automatic start in Hound (decision 8) |
| `tc_110_004_*`, `contact_http_tests.rs` `tc_110_00*` | `qso-settings.json` |
| `strategy_tests.rs` `tc_039_002_a_selection_of_a_cq_not_for_me_*`, `tc_039_005_core_*` | an agent cannot confirm, the operator barrier (#122) |

## The slice

- Old files: `backend/operating/qso/` QsoData (package `WstxContact`, 2038 lines), StandardQso
  (412), SpecialActivities (554), QsoTransmit (303), QsoWire (94), Qso (22).
- Ledger: 57 rows TO PLACE (QsoData 47, QsoTransmit 8, QsoWire 2) and 30 rows waiting for
  `StandardQso`/`SpecialActivities` (same name; rebuilt): 87 identities.
- Handover rows to qso: `_work/handover.md` lines 28, 29, 36-39, 75, 78-82, 103, 109, 118-121,
  123, 124, 130, 175, 192, 199, 206, 212, 225.
- Interfaces: `QsoControl.sysml` (taken over: `QsoProgress` is auto's work and stays; the rest
  is old text), `OperatingChain.sysml` (`TargetChoice`, `MessageToSend`, `CompletedContact`,
  `CL-085-02`, `TxSlot`, `BusyPartner`, `TransmitRequest`).
- Code: `server/src/contact.rs` (3391), `contact_http.rs` (1511), tests `contact_tests.rs`
  (5797), `contact_http_tests.rs` (3385), `transmit_state_tests.rs`, `autofinish_tests.rs`
  (auto's), `newest_rx_tests.rs` (482).

## What `contact.rs` shows (read in full)

- Constants: `REPORT_MIN` -50, `REPORT_MAX` 49, `REPORT_DEFAULT` -15; `RX_MAX_HZ` 3000,
  `TX_MIN_HZ` 200, `tx_max_hz` FT8 2950 / FT4 2916; `STOP_TOLERANCE_HZ` 50 (partnerWorksOther);
  `LEAD_MS` 1000 (code: the planning lead); `WATCHDOG_STOP_AFTER_DUE_MS` 1200 (private);
  `COUNTED_KEYS` 4096 (private, inside); `period_ms` 15000/7500 (modes' `Period`, a copy);
  `BUSY_FREE_TEXT_HZ` 10; `DIALOGUE_MAX` 16; `HOUND_WATCHDOG_MS` 300000; reply timeout 11 periods
  (literal in `fox_report`); Hound random 1000..2998, Fox +-300, limit 600 and 999 (literals).
- Enumerations: `Slot` tx1..tx6; `Tx4` rrr, rr73 (FT8 default rrr, FT4 always rr73, set rrr on FT4
  refused out_of_range); `State` idle, calling, replying, report, roger_report, rogers, signoff,
  completed, cancelled; `Origin` decoded_row, manual_entry, own_cq; `Call` Sign, Token, Hashed,
  Hash; `Exchange` Grid, Report, Contest, Rrr, Rr73, SeventyThree, Blank; `Received` Grid,
  SignalReport, RogerReport, Rogers, SeventyThree, Other; `ContestKind` FieldDay, Rtty; `Activity`
  none, na_vhf, eu_vhf, ww_digi, arrl_digi, field_day, rtty, hound (special operation 0,1,2,5,8,3,
  4,7; CQ word TEST/WW/FD/RU); `LogKind` Completion, LogQso; `LogAnswer` Accepted, Refused;
  `HoundReply` None, Pending, Sent; `FoxMessage` Report, Rr73.
- `transition` = the AutoSequence table (incl. #69 rogers in replying/report/rogers/signoff, 73 in
  roger_report to signoff, 73 in rogers completes, report in rogers back to roger_report).
  `first_slot`: not to me tx1 (tx2 when Tx1 disabled); to me Grid/Other tx2, report tx3, R-report
  tx4, rogers/73 tx5.
- `generate_contest`: Tx1..Tx6 with nonstandard brackets, activity CQ word, exchanges (grid; FD
  exchange; RTTY "5n9 X|serial"; EU VHF "<DX> <MY> [R] 5nSSSS GRID6"); every text must pack.
- `Settings` (defaults): auto_seq true, call_first true, tx1_skip false, rx 1500, tx 1500,
  hold_tx true, parity odd, report -15, activity none, exchange none, serial 1. Not saved in this
  module (the saving is in contact_http.rs; check).
- `Command`: SelectRow, EnterDx, Cancel, Abort, ChooseNext, EditMessage, SetReport, SetTx1Skip,
  SetTx4, SetFrequency, SetHoldTx, SetParity, SetAutoSeq, SetCallFirst, SetContest, SetWatchdogs,
  EnableTx (still there), Reply, CallCq, CallDx, SendNext, ResetRepetitions, Tune, Redecode
  (always refused redecode_unavailable), OpenLog (closes an unfinished contact and hands it over:
  contradicts the decision "Log QSO resends").
- Engine fields set by the station before each step: `repeat_exempt` (Auto's contact: no stop),
  `automated` {split, pause} (the busy split and pause for the run's contact; a manual contact gets
  both: contradicts auto decision 6), `his_psk` (spots' decoded offsets for the split).
- Starts: `admit_start` (stopped_in_step: state_conflict; safety revision: stale_revision;
  automatic and watchdog_spent: tx_watchdog); `obstacle` (capability, not authorized, clock, Tune);
  `switch_on` (arm or arm_automatic; an operator start from off opens a new count).
- Step: outcomes (started: dialogue tx, first periods, report_sent, exchange_sent; completed of a
  Tx5 or Tx4 RR73 completes), judge_stop_point (paused calls), Hound rows, rx decodes, counted
  partner messages (busy start/end, partnerWorksOther stop or split), band follow, Call 1st, Hound
  timeouts, arm transitions (halt or watchdog end a CQ: idle; Hound back to tx1 on tx_expired),
  submit (watchdog stop 1.2 s into the due period; one pending request; refused target not
  resubmitted; duplicateSequence disarms refused).
- Log: `log_fields` (start: first Tx2 period, else one period before the first Tx3, else first tx,
  else preparation; end: last counted end), `contest_fields` (STX/STX_STRING, SRX/SRX_STRING,
  CONTEST_ID ARRL-FIELD-DAY, CLASS, ARRL_SECT, STATE; EU VHF STX/SRX four digits).

## What `contact_http.rs` shows (read in full)

- Constants: `SNAPSHOT_BYTES_MAX` 4096, `RECEIPTS` 16 (station link's), `LOG_PENDING_MAX` 64 and
  `LOG_RETRY` 5 s (the log's: DirectLog lives here), `CQ_ONLY_AFTER_MS` 300000 (the a-priori
  context, handover row 36), `STATE_CHANGED_BYTES_MAX` 1780 (station link's), `MAX_SAFE`.
- `qso-settings.json` with Auto Seq and Call 1st (CL-110-01): decided away (handover 192).
- `operate_as`: every principal but the browser is automatic (contradicts #122); `granted` is the
  CL-022 grant (gone, #226).
- Directed CQ: `strategy::selection_warning`; an automatic select is refused
  directive_not_answerable; the browser gets 409 with the reason and may resend with
  directive_confirmed; a run's own select passes for its CQ target words (`run_admits`).
- Command revision: stale unless cancel, abort, enable_tx false, tune false.
- `tick`: sets `repeat_exempt`, `automated` (busy policy) and `his_psk` (spots' offsets, only
  while the feed follows this partner) before `step`; rows from the live job; a-priori context;
  DirectLog (`collect_logs`: same_station_again refused; `store_logs` under the authorization
  lock; first store to the UDP outbox).
- `station_tick` order: halt_step, observe_band, alert_step, contact tick, automation tick, free
  Tx slots, auto_step, the feed's target (only a run's own contact: auto decision 7 changes it).
- `record_of`: MODE FT8 or MFSK/FT4, FREQ dial + Tx offset, BAND from the dial, the activity
  (CL-112-05).

Decisions that bear on the slice: Enable Tx retired (#111, #121); no radio authorization
(#226); an agent equals the operator (#122); Log QSO resends, the logbook immutable
(2026-11-16); settings in three stores, qso's configuration in `QsoControl` (handover 192);
the activity follows the contest in force (#228, handover 206); the Tx watchdog is qso's
(handover 119); no hand split, only the protection move (auto decision 6); `QsoProgress`,
`CallTarget`, `StartAnswer` (auto).

## Work for the code: promises no test shows yet

- TC-039-010 (`HoldTx.sysml`): a level below the floor counts as it is: an offset 2 dB below the floor wins over one at the floor, and the level shown is negative; FT8 2350 Hz at -1 dB wins over 2360 Hz at -6 dB, and an offset whose signal goes above 2400 Hz is chosen only when every one below is on a decoded station; among equal levels the offset nearest a frequency the partner decodes wins; Rx stays on the partner.
- TC-082-001 (`HoldTx.sysml`): the free offsets start at 500 Hz (decision 4b).
- TC-097-011 (`StandardQso.sysml`): the busy pause holds for every contact, made by hand or by Auto; no strategy setting switches it off, and Auto never leaves a busy partner for being busy.
- CL-039-29 (`HoldTx.sysml`, no case): the rule "too close to the partner's Tx": when the partner sends to another call close to my Tx (Hold Tx on and off) and at a start (Auto, or Hold Tx on), Tx moves to the quiet space and stays on; not for a Hound.
- CL-010-02, CL-109-01 (`StandardQso.sysml`, #109): the step back, nothing advancing while transmission is off, a chosen message reopening a completed contact, a second completion handing nothing over; and the tests above that assert the old table.
- CL-111-02, CL-039-06 (`QsoTransmit.sysml`): `enable_tx` is still accepted and starts a CQ with no partner; an agent's start, Reset and setting of the limit are still refused (`operator_required`, `tx_watchdog`; #122); the count and the limit live in transmit (`tx_calls`, `tx_expired`, `watchdog_spent`; handover row 119); the safety revision of the starts (#226).
- CL-085-02 (`StandardQso.sysml`): Log QSO hands the contact over and closes it (`OpenLog`, `LogKind::LogQso`); the log's Log QSO resends instead.
- CL-085-03 (`SpecialActivities.sysml`): the serial counts from a boot counter; under a contest it comes from the log (#98).
- `QsoConfig`: Auto Seq and Call 1st are kept in `qso-settings.json`, the limit in transmit, the activity, the exchange and the offsets are not kept; the model keeps all in the station config.
- CL-024-04: a Hound still lets automation start (`tc_111_016`, a run's start).
- The tests that build `completed()` through Log QSO: build it through a completed exchange.
- TC-097-019 reads the old model's wording; it goes with the old model.

## For the operator

1. **The packer for qso** (handover row 38): answered (operator 2026-11-16, "add the
   connection from qso to modes"): `PackProcessingLink` in `ModeProcessing.sysml`, qso's
   port `pack`, modes' port `pack`, `Station.sysml` `packQso`.
2. **Issue #109** (decision 7): its promise 5 and its list of changed text are to be revised to
   today's decisions; posting needs your OK.
3. **The contact wire** now stands in `StationLink.sysml` as taken-over text; the station link
   rebuilds it.
