package WstxStandardQso {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-005';
    private import WstxContact::'CL-010-03';
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-019';
    private import WstxRequirementsFrontend::'CL-010-06';
    private import WstxRequirements::'CL-010-07';
    private import WstxRequirements::'CL-010-08';
    private import WstxQsoWire::'CL-010-15';
    private import WstxLogbook::'CL-010-04';
    private import WstxContact::'CL-010-10';
    private import WstxLogbook::'TC-110-004';
    private import WstxContact::Tx4Form;
    private import WstxContact::Contact;
    private import WstxContact::ReceivedKind;
    private import WstxContact::SequenceEvent;
    private import WstxContact::TxSlot;
    // #10 standard FT8 contact (decisions: issue #10 comment 6539901776, 2026-10-31);
    // detailed contract in WstxContact. FT4 rules marked FT4-NOTE there belong to #11.
    requirement 'CL-010-01' {
        doc /* Prepare a contact only from an acknowledged decoded row identity or an operator-entered DX Call/Grid that packs as a standard message; preparation sets partner, grid, report, Rx/Tx offsets, period parity and the six standard messages, and never arms or starts transmission; a receive-only station can prepare contacts and log. Details: WstxStandardQso::SelectDecodedRow, EnterDxStation, FirstSlotOnSelection, ChangeContact. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_01_to_FR_007 from 'CL-010-01' to 'FR-007';
    requirement 'CL-010-12' {
        doc /* Generate the WSJT-X standard messages Tx1 grid, Tx2 report, Tx3 R+report, Tx4 RRR or RR73, Tx5 73 and Tx6 CQ on the server with the -50..+49 report rendering, operator report override, Tx1 skip and the RRR/RR73 toggle (FT8 default RRR); Now buttons and F11/F12 steps are not offered. Details: WstxStandardQso::StandardMessageSet, ReportRange, OverrideReport, ToggleTx1Skip, ToggleTx4Form. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; client/contact.js";
    }
    dependency CL_010_12_to_FR_005 from 'CL-010-12' to 'FR-005';
    dependency CL_010_12_to_FR_007 from 'CL-010-12' to 'FR-007';

    verification 'TC-007-001' {
        doc /* TC-007-001 — Standard FT8 contact
             CL-010-01, CL-010-02, CL-010-03, CL-010-12
             Setup: actual candidate server and Chromium; profile HB9BLA/JN47; virtual UTC clock; independently scripted decoded-result source and a #9 transmit-service double that records TransmitRequests and returns started/completed/halted/refused outcomes (no audio, PTT or radio).
             Steps: (a) responder: select a hand-authored "CQ K1ABC FN42" row (SNR -12.4, 1234.6 Hz, even period); Enable Tx; feed "HB9BLA K1ABC -05", then "HB9BLA K1ABC RR73"; (b) responder with RRR: feed "HB9BLA K1ABC RRR", then nothing; (c) caller: Enable Tx with no partner (Tx6, state calling), feed "HB9BLA K1ABC FN42" and select that row (prepareReply with firstSlot tx2), feed "HB9BLA K1ABC R-07", once with Tx4 RRR then "HB9BLA K1ABC 73", once toggled to RR73; (d) repeats: partner repeats each message one to three times; partner misses my Tx3 and resends its report from rogers; (e) other stations and late rows: "HB9BLA W1XYZ -10" during the contact, a row of the previous partner after ChangeContact, a reply after completion; (f) Tx1 skip, report override -50/+49/-51/+50, manual entry "DL1ABC" grid JO62 and invalid "AB1", "<...>" and grid "SS00"; (g) partner answers another call at 50 Hz and at 51 Hz from my Tx offset, in replying and again in report after a Tx1-skipped start; the watchdog expires while calling CQ; (h) Auto Seq off; Esc, Halt, disarm and cancel in every state.
             Expected (independent hand-written table, not candidate output): selection gives dxCall K1ABC, grid FN42, report -12 rendered "-12", Rx and Tx 1235 Hz, odd parity, next Tx1 "K1ABC HB9BLA JN47", Tx2 "K1ABC HB9BLA -12", Tx3 "K1ABC HB9BLA R-12", Tx4 "K1ABC HB9BLA RRR", Tx5 "K1ABC HB9BLA 73", Tx6 "CQ HB9BLA JN47" and no TransmitRequest before Enable Tx. States/next slots follow WstxStandardQso::AutoSequence exactly: (a) replying/Tx1 -> rogerReport/Tx3 -> signoff/Tx5 -> completed after the completed Tx5 outcome, Enable Tx off, one log offer; (b) RRR from the partner gives signoff/Tx5; the contact completes after the first completed Tx5 transmission (AutoSequence sent73), Enable Tx off, one log offer; (c) calling/Tx6 -> report/Tx2 only after selection -> rogers/Tx4 -> completed on 73 (RRR) or on the completed RR73 transmission, Enable Tx off and no further CQ; (d) repeats resend the same text, report-from-rogers returns to Tx3, no second completion or log offer; (e) other/late rows change nothing; (f) with Tx1 skip, selecting the CQ row enters report directly with next Tx2, overrides -50/+49 accepted and rendered "-50"/"+49", -51/+50 and invalid entries refused with no contact; (g) this manual contact pauses for a busy partner (CL-097-06): his report to another call at 50 Hz and at 51 Hz from my Tx offset (FT8) both move Tx to the nearest candidate at least 100 Hz from his frequency (from 500 Hz), Enable Tx stays on and the call goes on, in replying and in the Tx1-skipped report (99 Hz moves, 100 Hz does not, TC-097-017 (c)), and only a refused move disarms; in a contact that does not pause (a pounce, an MCP policy run, a run with busy_pause off) 50 Hz disarms and 51 Hz does not; watchdog expiry while calling returns to idle; (h) Auto Seq off never changes the next slot; Halt and Alt+H send the halt request first; Esc sends one abort and no halt; last transmitted text changes only on started outcomes and differs visibly from the next message. Each request carries a fresh requestSequence; a duplicated browser action (same command_id) yields one request; one decoded row delivered twice counts once.             2 — Isolated automated functional tests; Windows development PC, actual candidate server and browser, independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    dependency CL_010_01_verified_by_TC_007_001 from 'CL-010-01' to 'TC-007-001';
    dependency CL_010_01_verified_by_TC_007_003 from 'CL-010-01' to 'TC-007-003';
    dependency CL_010_01_verified_by_TC_007_007 from 'CL-010-01' to 'TC-007-007';
    dependency CL_010_12_verified_by_TC_007_001 from 'CL-010-12' to 'TC-007-001';
    requirement 'CL-010-02' {
        doc /* Progress the contact on the server by the WstxStandardQso::AutoSequence table (messages from the partner addressed to my call; repeats resend, other stations ignored, a partner RRR/RR73 before my 73 answered with one 73 in every active state, completion after a transmitted RR73/73 or a received 73 after RRR) and show confirmed sequence, next message, last transmitted message, pending requests, stale observations and failures separately. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_02_to_FR_007 from 'CL-010-02' to 'FR-007';
    dependency CL_010_02_to_FR_008 from 'CL-010-02' to 'FR-008';
    dependency CL_010_02_to_FR_019 from 'CL-010-02' to 'FR-019';
    verification 'TC-007-010' {
        doc /* TC-007-010 — A partner's RRR or RR73 before my 73 (#69)
             CL-010-02
             Setup: the actual contact engine (server, not the browser) with a virtual UTC clock, profile HB9BLA/JN37, Auto Seq on, Call 1st off, Tx watchdog 6, hand-authored standard decoded rows in the partner's parity and the #9 transmit-service double that records TransmitRequests and returns started/completed/halted outcomes (no audio, PTT or radio).
             Steps: (a) reproduction of the SV2CLJ contact of 2026-11-08: Tx4 rrr; Enable Tx calling CQ; select "HB9BLA SV2CLJ KN10" (report/Tx2); after the sent Tx2 feed "HB9BLA SV2CLJ R+02"; after the sent Tx4 feed "HB9BLA SV2CLJ RR73"; run four more own periods; then feed "HB9BLA SV2CLJ 73"; (b) as (a), the partner answers my RRR with "HB9BLA SV2CLJ RRR"; (c) as (a) in FT4 (Tx4 rr73) and in FT8 with Tx4 rr73: my RR73 transmission is halted (state rogers kept), the partner's RR73 arrives, Enable Tx again; (d) replying: select "CQ K1ABC FN42", after the sent Tx1 feed "HB9BLA K1ABC RR73"; report: select a caller's "HB9BLA K1ABC FN42" after my CQ, after the sent Tx2 feed "HB9BLA K1ABC RRR"; (e) in rogers the partner's RR73 is counted once while my next Tx4 is pending before its audio starts, and once after that Tx4's audio has started; (f) Auto Seq off, the partner's RR73 in rogers, replying and report; (g) in rogers: "HB9BLA W1XYZ RR73" from another station, "W1XYZ SV2CLJ RR73" from the partner to another call, the partner's RR73 decoded in a period of my own parity, the same RR73 row delivered twice; "HB9BLA K1ABC 73" in replying and in report; "HB9BLA SV2CLJ 73" in rogers; (h) ww_digi: after my Tx4 RRR following the partner's R grid, the partner's RR73; (i) as (a), but my 73 transmission is halted, then Enable Tx again.
             Expected (independent hand-written table from WSJT-X 3.3.0-beta5 DecodedMessageReaction.cpp ~585-616 and mainwindow.cpp ~8237-8255, not candidate output): (a) report/Tx2 -> rogers/Tx4 "SV2CLJ HB9BLA RRR" -> after the RR73 signoff/Tx5; the next own period carries "SV2CLJ HB9BLA 73", exactly one 73 and no RRR after the RR73 period; after the completed 73 outcome state completed/Tx6, Enable Tx off (disarm cause contactCompleted), exactly one log entry of kind completion with call SV2CLJ, RST_SENT the sent report, RST_RCVD +02; nothing transmitted in the following periods; the late 73 changes nothing and logs nothing; (b) the same as (a); (c) the same: one 73, one log, completed; (d) replying -> signoff/Tx5 "K1ABC HB9BLA 73", one 73, completed, one log with RST_SENT and RST_RCVD absent; report -> signoff/Tx5, one 73, completed, one log with RST_SENT the sent report and RST_RCVD absent; (e) before the audio start that period carries Tx5 instead of Tx4; after it the Tx4 of that period is sent and Tx5 follows in my next own period, one 73 and one log either way; (f) state and next slot unchanged, suggested_slot tx5 in each, nothing completed or logged; (g) the other station's and the other-call rows and the own-parity row change nothing; the twice-delivered row gives one 73 and one log; 73 in replying or report changes nothing; 73 in rogers completes at once with no 73 sent and one log; (h) signoff/Tx5, one 73, completed, one log; (i) state signoff kept with nothing logged; Enable Tx again sends one 73, then completed and one log.
             2 — Isolated automated functional tests; Windows development PC, actual contact engine with independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-02';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    verification 'TC-007-003' {
        doc /* TC-007-003 — Received views, Rx Frequency pane and partner selection
             CL-010-01, CL-010-06
             Setup: actual server/browser with an independently scripted result source and request recorder; rows with distinct UTC/DT/SNR/frequency/text including literal markup, unresolved hashes, duplicate/old tuples, 2047/2048/2049 retained records and expired cursors; Rx offset 1500 Hz; profile call HB9BLA, DX call K1ABC.
             Steps: filter/sort Band Activity; with no contact, read the QSO pane Calling me lines for one period with rows at 1449.9, 1450.0, 1489.9, 1510.1, 1550.0 Hz, "HB9BLA W1XYZ -10" at 400 Hz and "HB9BL K1ABC -01" at 2600 Hz (#37); select rows by click/Enter and by manual DX entry; switch profile.
             Expected (fixed input catalogue): the Calling me lines are exactly the HB9BLA row, plain (no warning sign), with call W1XYZ, SNR −10, no grid and country U.S.A. (#37 2026-11-04), and not the CQs near Rx or HB9BL; sorting Band Activity sends no request and changes no contact/log; selection sends the exact identity and changes the partner only after acceptance; unresolved/old/wrong-profile rows cannot prepare a contact; no invented UTC/callsign, executable markup or cross-profile state.
             2 — Isolated automated functional tests; Windows development PC, real browser/server and independent result source. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-06';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-004' {
        doc /* TC-007-004 — Authority, control and connection barriers
             CL-010-02, CL-010-03, CL-010-07, CL-010-08, CL-010-15
             Setup: actual server/browser; transmit-service and radio-control doubles with supported/unsupported transmit, CAT-only/audio-only, delayed/rejected/lost responses; two profiles; all secondary panels open.
             Steps: Enable Tx, Tune, Halt (button and Alt+H, also before the contact client loads and without a contact snapshot), Esc (focus in a text field, in the DX Call input and in an open panel; Abort QSO), Cancel while transmitting, the partner working another call within 50 Hz while transmitting, save and contact change while the link drops; reconnect; replay old requests; unauthenticated, wrong-Origin and wrong-profile requests; Tx offset 199/200/2950/2951 Hz; every ContactCommand action with missing/extra keys, 1024/1025-byte bodies, stale contact_revision (also for cancel and enable_tx false), a retained command_id with identical and different bodies; GET /contact at its 4096-byte maximum shape; Esc on a receive-only station.
             Expected (independent operation/state catalogue): Alt+H and Halt reach the #9 halt operation first even with panels open (exactly one halt per Alt+H); Esc sends exactly one ContactCommand abort and no halt, stops the transmission now (PTT released, outcome aborted, halt_state unchanged), cancels the contact with nothing logged and leaves the station ready for the next QSO; Cancel lets a transmission on the air finish; the partner working another call within 50 Hz while transmitting: in a manual contact (it pauses, CL-097-06) the transmission on the air finishes, Tx moves clear of his signal (FT8 100 Hz) for the next send and Enable Tx stays on, with no PTT release by a stop; in a pounce or an MCP policy run the partner-works-other stop releases PTT without a halt; Esc closes no panel; state shows pending/unknown until #9 confirms; reconnect loads the snapshot and replays no arm, tune, next-message or transmit request; no request reaches PTT except through the transmit-service double; unsupported transmit leaves Enable Tx/Tune disabled with a reason; 200 and 2950 accepted, 199/2951 refused; Tune is accepted with the transmit state off and leaves it off (CL-111-06); barrier refusals unchanged; no cross-profile contact. Each malformed command returns the independently expected ContactRefusal code and field with no state change; stale revisions refused except cancel/abort/disarm; an identical retained command_id returns the same receipt with no second effect, a different body state_conflict; the maximum snapshot (watchdog busy_with with a 13-character call, paused_calls 99) is exactly admitted within 4096 bytes and GET /contact is never gzip-coded; StatusReply keeps exactly {version,radio}; on the receive-only station Alt+H sends no halt, while row selection and Log QSO still work.
             2 — Isolated automated functional tests; Windows development PC, actual candidate server/browser and independent control, audio and transmit emulators. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-07';
            verify 'CL-010-08';
            verify 'CL-010-15';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs; server/src/contact_tests.rs; server/src/logbook_http_tests.rs";
    }
    verification 'TC-007-007' {
        doc /* TC-007-007 — Live FT8 contact on the IC-7300
             CL-010-01, CL-010-02, CL-010-03, CL-010-04, CL-010-10
             Setup: deployed candidate on HB9BLA with the IC-7300 (USB audio and CAT, USB-D, 20 m 14.074 MHz or another FT8 dial frequency), operator present at the radio, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), Halt Tx and the radio's own power control within reach; transmit authorized by the operator on 2026-10-31 for this test only; the 30 W instructed by the operator on 2026-11-07. An independent receiver (separate WSJT-X station or PSK Reporter reception reports) observes our transmissions.
             Steps: run a UDP listener on 127.0.0.1:2237 enabled as a WSJT-X UDP target with QSO Logged and Logged ADIF; complete at least one contact answering a real CQ and, if band conditions allow, one by calling CQ, with Auto Seq, without pressing Log QSO; then Enable Tx without operator activity until the Tx watchdog (set to 2 repetitions for the test) stops it; Halt once during a transmission; restart the server.
             Expected: the partner's messages addressed to HB9BLA appear in the Rx Frequency pane with the report we sent echoed back; the independent receiver decodes exactly the transmitted texts in the expected periods and audio offset within 10 Hz; the contact completes per the AutoSequence table with Enable Tx off and logs itself (no review form; the Logbook page lists it); the listener receives one QSO Logged and one Logged ADIF with the same call, reports, times and frequency; contacts.adi contains exactly one record with the independent observations (call, grid, reports, date/time, band, FREQ = dial + Tx offset) after restart; Halt stops RF promptly as observed on the radio; watchdog expiry stops transmission and disarms. Failures are recorded, not reworded as passes.
             5 — Live RF transmission with operator authorization; HB9BLA station PC with the actual IC-7300 and antenna. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-04';
            verify 'CL-010-10';
        }
    }
    dependency CL_010_02_verified_by_TC_007_001 from 'CL-010-02' to 'TC-007-001';
    dependency CL_010_02_verified_by_TC_007_004 from 'CL-010-02' to 'TC-007-004';
    dependency CL_010_02_verified_by_TC_007_007 from 'CL-010-02' to 'TC-007-007';
    dependency CL_010_02_verified_by_TC_007_010 from 'CL-010-02' to 'TC-007-010';
    dependency CL_010_02_verified_by_TC_110_004 from 'CL-010-02' to 'TC-110-004';
    attribute def StandardMessageSet {
        attribute dxCall : String;
        attribute myCall : String;
        attribute myGrid4 : String;
        attribute reportDb : Integer;
        attribute tx4 : Tx4Form;
        attribute tx1Text : String;
        attribute tx2Text : String;
        attribute tx3Text : String;
        attribute tx4Text : String;
        attribute tx5Text : String;
        attribute tx6Text : String;
        assert constraint reportInRange { reportDb >= -50 and reportDb <= 49 }
        doc /* Generated by the server only (MW genStdMsgs ~9690, genCQMsg ~9594), with
             R = the rendered report and single blanks:
             Tx1 "DX MYCALL GRID4"; Tx2 "DX MYCALL R" e.g. "K1ABC HB9BLA -12";
             Tx3 "DX MYCALL R" with R prefixed by "R" and no blank, "K1ABC HB9BLA R-12";
             Tx4 "DX MYCALL RRR" or "DX MYCALL RR73" per tx4; Tx5 "DX MYCALL 73";
             Tx6 "CQ MYCALL GRID4". MYCALL and GRID4 come from the selected profile's
             callsign and the first four characters of its locator
             (WstxProfiles::Settings); without a profile callsign, or a locator for
             Tx1/Tx6, no message set is generated and transmit stays unavailable with
             that reason. Without a DX call only Tx6 exists. Directed CQ (CQ DX/nnn)
             is not offered.
             Nonstandard and compound calls (#24 S1b, CL-024-01; MW genStdMsgs ~9690-9850,
             77-bit branch): a call is standard when it matches Radio::is_standard_callsign
             (prefix [A-Z]{0,2}|[A-Z][0-9]|[0-9][A-Z], then a digit and at most 3
             letters, optionally /R or /P), else nonstandard (e.g. PJ4/K1ABC, DL/HB9BLA,
             YW18FIFA). With a nonstandard DX call and a standard MYCALL: Tx1
             "<DX> MYCALL GRID4", Tx2 "<DX> MYCALL R", Tx3 "<DX> MYCALL RR" (R prefixed by R),
             Tx4 "DX <MYCALL> RRR|RR73", Tx5 "DX <MYCALL> 73". With a nonstandard MYCALL
             and a standard DX call: Tx1 "<DX> MYCALL", Tx2 "DX <MYCALL> R", Tx3
             "DX <MYCALL> RR", Tx4 "<DX> MYCALL RRR|RR73", Tx5 "<DX> MYCALL 73", and Tx6
             "CQ MYCALL" (no grid; genCQMsg). Two nonstandard calls have no message set: such
             a DX call is refused invalid_call (make-qso.adoc: no QSO between two nonstandard
             calls). Every generated text must pack unaltered with
             WstxMessageEncode::PackMessage as the standard i3=1/2 or the nonstandard i3=4
             family; a DX call that does not is refused at entry. Contest forms belong to
             #24 S2. Regenerating after a report, DX call or tx4 change
             replaces Tx2-Tx4 (and Tx1/Tx5 on a DX-call change); operator-edited text
             of a slot is kept until the next regeneration and requires server
             validation through PackMessage before it can be chosen as next: it must
             pack unaltered as a standard i3=1/2, a nonstandard i3=4 or a free-text 0.0
             message (at most 13 characters of the free-text alphabet, WSJT-X Tx5 free
             text such as "TNX 73 GL", #24 S1b), else invalid_message. A free-text Tx5
             is sent like a 73: once sent in signoff the contact completes (logged only
             when it has a DX call).
             Tx4 default is rrr in FT8: m_send_RR73 starts false and is not saved
             (MW ~580, ~9661; Rr73Policy.cpp tx4AllowsRr73). FT4-NOTE: rr73, and
             always rr73 (MW send_rr73_for_tx4 ~9661 is true for FT4 whatever
             m_send_RR73; set_rr73_tx4 ~9676 forces it), see ToggleTx4Form. */
    }
    action def ToggleTx4Form {
        doc /* D7 adopted (MW on_txrb4_doubleClicked ~9047): switches tx4 between rrr
             and rr73 for the current contact and regenerates Tx4. Applies to the next
             transmission, never to one whose audio has started. FT4-NOTE: an FT4
             contact keeps rr73; set_tx4 rrr on it is refused out_of_range with field
             form and changes nothing (DIFFERENT from WSJT-X, which silently keeps RR73:
             a refusal never looks like an accepted change). */
    }
    action def ToggleTx1Skip {
        doc /* D7 adopted (MW on_txrb1_doubleClicked ~9010 toggle_tx1_enabled_preference):
             with Tx1 skipped, a reply to a CQ or to a station not addressed to me starts
             with Tx2 and state report instead of Tx1/replying (DMR ~696-704), and
             choosing Tx1 as next selects Tx2 (MW ~8989). The Tx1 text is kept.
             Station-session preference, initially not skipped (mainwindow_settings
             tx1State default true); not part of the saved profile schema. */
    }
    action def SelectDecodedRow {
        in rowIdentity : String;
        out prepared : Contact[0..1];
        doc /* CL-010-01. rowIdentity is the full validated profile/boot/source/job/
             generation/sequence tuple of a live result row with a concrete 'from' call:
             a standard i3=1/2 message (WstxOfflineDecode::StandardFields) whose 'from'
             is a concrete call or a hash the station filled in (HashResolution), or a
             nonstandard i3=4 message (#24 S1b), whose 'from' and 'to' are the full call
             and the filled-in hash in their hash_second order, a CQ having 'to' CQ and
             an RRR/RR73/73 its roger exchange (none: blank). A 'to' hash filled in with
             my call is my call. Effects, after server
             acknowledgement only (DMR handleDecodeSelection ~320-360, D-adopted):
             dxCall = the row's 'from' call; dxGrid = the row's grid exchange if any
             (a row without a grid of the same partner and mode keeps the known dxGrid,
             as WSJT-X's DX Grid, #11; EnterDxStation sets exactly the grid entered);
             report from the row SNR, with the exception stated there (ReportRange); rxOffsetHz = row frequency rounded
             to integer Hz; txOffsetHz = the same, unless Hold Tx is on (the default, CL-039-08) or the row's
             'to' call is my call (replying to me keeps my Tx frequency, DMR ~320-333);
             txParity = opposite of the row's period parity; message set generated, except the texts kept for the same active partner (ContactSnapshot dialogue);
             nextSlot and state per FirstSlotOnSelection. Unresolved hashes (<...>), rows
             without a concrete call, a DX call that would pair two nonstandard calls,
             old/wrong-profile tuples and other families are refused with a reason (an
             EU VHF row is selectable while eu_vhf is set, EuVhfExchange, #99).
             Received partner messages count by the same row reading, so a compound QSO
             sequences as a standard one (AutoSequence). Never sets enableTx (DIFFERENT from
             CFG quick_call "double-click sets Tx enable": #10 safety rule; the browser's
             double-click sends SetEnableTx on after it, OperatingLayout BandActivity) and
             never clears it: a replacement while Enable Tx is on keeps it on
             (ChangeContact). */
    }
    action def EnterDxStation {
        in dxCallText : String;
        in dxGridText : String[0..1];
        out prepared : Contact[0..1];
        doc /* D1 adopted (MW dxCallEntry/dxGridEntry, on_dxCallEntry_returnPressed): call a
             station that was not decoded. The call is upper-cased; it must give a
             StandardMessageSet (a standard call, optionally /R or /P, or a nonstandard
             call with my standard call, #24 S1b), else refused invalid_call (no message
             set, no contact). Grid is
             optional, 4 or 6 Maidenhead characters (AA00..RR99[AA..XX]) else refused.
             Enter or Generate creates the contact with origin manualEntry, state
             replying, nextSlot tx1 (tx2/report when Tx1 skipped), the current report
             value, unchanged Rx/Tx offsets and the current Tx-period choice. Never
             sets enableTx. Same ChangeContact rule as selection while a contact is
             active. */
    }
    action def ChangeContact {
        doc /* Explicit server-accepted replacement of an active partner: the old
             contact is cancelled before the new one is prepared; Enable Tx keeps its
             state (#50, operator 2026-11-02, as WSJT-X 3.3.0-beta5: handleDecodeSelection,
             widgets/mainwindow.cpp ~9122-9229, replaces the DX call and regenerates the
             messages through processMessage and never turns Enable Tx off, except an
             Alt double-click; DecodedMessageReaction.cpp appendReactedTail ~365-413 sets
             DX call/grid, report and messages and, with quick_call "Double-click on call
             sets Tx enable", Enable Tx on), so while it is on the next period of the new
             contact's parity carries the new contact's next message (the pending request
             of the old contact is replaced; a transmission already on the air continues,
             as with CancelContact; a replacement in my own period after PTT is keyed and
             before its audio starts replaces that period's request, so the new message is
             sent in it; when the new contact has the other parity, the keyed message is
             sent and the new one is queued for the next period of its parity, never
             refused busy, #10). The replacement itself never turns Enable Tx on. During a station
             automation run without a strategy (WstxMcp OperatingAutomation; a strategy run:
             WstxStrategy::ManualIntervention, #39) an operator replacement of the
             run's contact ends the run, which disarms (contact_changed, TC-020-003); this
             exception stands until the operator decides otherwise. A
             completed contact is not active and is already logged (DirectLog), so a new
             partner simply replaces it (#41: no held unsaved contact). */
    }
    action def CallFirst {
        doc /* #10 (operator 2026-11-02). WSJT-X 3.3.0-beta5 calls Call 1st the respond
             policy "CQ: First" (widgets/mainwindow.cpp ~1489-1493 respondComboBox;
             updateRespondTarget ~17697-17731: the first current-period caller,
             claimFirst per decode period, processed as a double-click with
             auto_tx_mode(true); AutoRespondPeriod.cpp ~11-32
             isDirectAutoRespondCandidate: addressed to my call, a callsign sender other
             than me, an exchange that is not R+report, RRR, RR73 or 73): while the
             contact is calling (an own CQ started by the operator; an MCP run keeps its own rules, WstxMcp; a CQ called by automation: the automation answers its callers only with Calling stations are answered on, WstxStrategy::CallerOfMyCall, WstxContest::ContestRun) with Enable Tx,
             Auto Seq and Call 1st on (WSJT-X AutoRespondPeriod.cpp observePeriod opens
             the respond period only while Enable Tx is on), the first decoded row of the step, in decode order (row
             sequence), that is a standard message to my call from a concrete call in the
             station's mode (neither call a filled-in hash nor an i3=4 message: WSJT-X's
             recipient and sender words must be plain calls), decoded in a period of the parity opposite to my Tx parity,
             whose exchange is a grid or a report, is answered at once as SelectDecodedRow
             of that row (prepareReply: report Tx2 after their grid, roger report Tx3
             after their report, as FirstSlotOnSelection; Hold Tx and the to-my-call rule
             keep my Tx offset). Enable Tx keeps its state, so the next own period answers
             that caller; the answer is automatic, not operator activity. At most one caller is answered: the contact is then no longer
             calling. With Call 1st off a calling contact moves only on an operator
             selection (#12). */
    }
    action def CancelContact {
        doc /* Abort the current contact: disarm (Enable Tx off), clear DX call/grid and
             Tx1-Tx5, select Tx6 (MW abortQSO ~9637). A transmission in progress
             continues unless Halt is also requested. A completed contact keeps its
             fields (only Tx6 is selected), so Log QSO can still re-log it (DirectLog). */
    }
    state def AutoSequence {
        attribute acceptedEvent : SequenceEvent;
        attribute received : ReceivedKind;
        attribute addressedToMe : Boolean;
        attribute fromPartner : Boolean;
        attribute autoSequenceOn : Boolean;
        attribute tx4IsRr73 : Boolean;
        attribute sentTx4 : Boolean;
        attribute firstSlot : TxSlot;
        attribute startedWithTx1Skipped : Boolean;
        entry; then idle;
        state idle; state calling; state replying; state report; state rogerReport;
        state rogers; state signoff; state completed; state cancelled;
        transition cq first idle if acceptedEvent == SequenceEvent::startCq then calling;
        transition prepareIdleTx1 first idle if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx1 then replying;
        transition prepareIdleTx2 first idle if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx2 then report;
        transition prepareIdleTx3 first idle if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx3 then rogerReport;
        transition prepareIdleTx4 first idle if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx4 then rogers;
        transition prepareIdleTx5 first idle if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx5 then signoff;
        transition prepareCqTx1 first calling if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx1 then replying;
        transition prepareCqTx2 first calling if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx2 then report;
        transition prepareCqTx3 first calling if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx3 then rogerReport;
        transition prepareCqTx4 first calling if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx4 then rogers;
        transition prepareCqTx5 first calling if acceptedEvent == SequenceEvent::prepareReply and firstSlot == TxSlot::tx5 then signoff;
        transition gridToReport first replying if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::grid then report;
        transition reportFromReplying first replying if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::signalReport then rogerReport;
        transition reportFromReport first report if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::signalReport then rogerReport;
        transition rogerReportFromReplying first replying if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogerReport then rogers;
        transition rogerReportFromReport first report if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogerReport then rogers;
        transition rogerReportRepeat first rogerReport if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogerReport then rogers;
        transition rogersToSignoff first rogerReport if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogers then signoff;
        transition seventyThreeInRogerReport first rogerReport if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::seventyThree then signoff;
        transition rogersRepeat first signoff if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogers then signoff;
        transition rogersInRogers first rogers if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogers then signoff;
        transition rogersFromReplying first replying if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogers then signoff;
        transition rogersFromReport first report if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::rogers then signoff;
        transition reportBackFromRogers first rogers if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::signalReport then rogerReport;
        transition seventyThreeInRogers first rogers if acceptedEvent == SequenceEvent::receivedFromPartner and autoSequenceOn and addressedToMe and fromPartner and received == ReceivedKind::seventyThree then completed;
        transition sentRr73 first rogers if acceptedEvent == SequenceEvent::transmittedSignoff and sentTx4 and tx4IsRr73 then completed;
        transition sent73 first signoff if acceptedEvent == SequenceEvent::transmittedSignoff then completed;
        transition otherStationWhileReplying first replying if acceptedEvent == SequenceEvent::partnerWorksOther and autoSequenceOn then replying;
        transition otherStationWhileReport first report if acceptedEvent == SequenceEvent::partnerWorksOther and autoSequenceOn and startedWithTx1Skipped then report;
        transition cancelCalling first calling if acceptedEvent == SequenceEvent::cancel or acceptedEvent == SequenceEvent::halt or acceptedEvent == SequenceEvent::watchdogExpired then idle;
        transition cancelReplying first replying if acceptedEvent == SequenceEvent::cancel then cancelled;
        transition cancelReport first report if acceptedEvent == SequenceEvent::cancel then cancelled;
        transition cancelRogerReport first rogerReport if acceptedEvent == SequenceEvent::cancel then cancelled;
        transition cancelRogers first rogers if acceptedEvent == SequenceEvent::cancel then cancelled;
        transition cancelSignoff first signoff if acceptedEvent == SequenceEvent::cancel then cancelled;
        doc /* Transition table (DMR planProcessMessage ~528-655, planAutoSequence ~724;
             MW guiUpdate ~8056-8091). prepareReply is SelectDecodedRow or EnterDxStation;
             firstSlot is the FirstSlotOnSelection result (tx1 replying, tx2 report incl.
             a Tx1-skip start, tx3 rogerReport, tx4 rogers, tx5 signoff). A selection
             while a contact is active first passes ChangeContact (cancel, then
             prepare; Enable Tx unchanged). CallFirst is a prepareReply from calling.
             Next message per state: calling tx6, replying tx1,
             report tx2, rogerReport tx3, rogers tx4, signoff tx5; completed and
             cancelled select tx6 with Enable Tx off.
             Received messages count only when: Auto Seq on, a standard message whose
             'to' is my profile callsign and 'from' the contact's DX call, decoded in the
             partner's period, at any audio frequency (DMR ~724). Messages of other
             stations never change the sequence (DMR ~517-524) but stay visible in the
             Rx Frequency pane. Classification: grid exchange -> grid; report without
             R -> signalReport; R+report -> rogerReport; RRR or RR73 -> rogers; 73 ->
             seventyThree. One decoded row (same validated identity tuple) counts once,
             however often it is delivered or re-read; a re-decode of the same period
             yielding the same partner message also counts once per period.
             Repeats: no retry counter or timeout (WSJT-X has none for FT8, DMR/MW
             ~8844 fast modes only); the next message is sent again each of my periods
             while Enable Tx is on until a counted message changes the state; the Tx
             watchdog (TxWatchdog) bounds unattended repetition. A repeated earlier
             partner message maps back as WSJT-X does: a signalReport in rogers returns
             to rogerReport (resend Tx3); R+report in rogerReport/rogers keeps rogers
             (resend Tx4); rogers in signoff resends Tx5. A 73 in rogerReport (the
             partner skipped RR73 after my R+report) moves to signoff: my 73 is sent once
             and the contact completes on it (#11 supervisor default). A rogers (RRR or
             RR73) moves to signoff in every active state before signoff, as WSJT-X
             (DMR ~585-600: rogerAck selects Tx5; MW ~8237-8249 logs on the first 73
             sent): in rogerReport after my R+report; in rogers after my Tx4 RRR, or after
             a Tx4 RR73 whose transmission did not complete (#69, live stall 2026-11-08:
             the partner's RR73 after my RRR was answered with RRR until a halt); and in
             replying or report, when the partner signs off before I received his report
             or R+report (#69, operator 2026-11-08). In each case my 73 is sent once and
             the contact completes on it and is logged once (sent73, DirectLog); no
             report received leaves RST_RCVD absent. A rogers or 73
             counted while my Tx1-Tx4 is already pending for the next period replaces that
             request with Tx5 until its audio starts; after the audio start the message of
             that period is sent and Tx5 follows in my next period (TransmitSubmission).
             With Auto Seq off a counted partner message changes no state (it still
             updates the received report and TIME_OFF); the step Auto Seq would take is
             offered as ContactSnapshot suggested_slot and the QSO pane shows the Auto
             Seq state and that offer, so a signed-off partner is never silently
             answered with a repeat (#11 live stall 2026-11-02).
             Messages not in the table
             (grid in report.., 73 in replying, report or signoff, anything after
             completed/cancelled) change nothing.
             Completion: transmittedSignoff is TransmitService's confirmed completed
             transmission of a Tx4 RR73 or Tx5 73 of this contact (MW message_is_73
             ~492, m_sentFirst73). On completion Enable Tx turns off (CFG
             disable_TX_on_73 default true ~3746) and the contact is logged once
             (DirectLog, #41). Receiving 73 while in rogers (after Tx4 RRR) completes without
             sending more (DMR ~601-616); receiving RRR or RR73 there sends my 73 first
             (signoff, #69). DIFFERENT: WSJT-X then leaves Enable Tx on
             with Tx6 selected; here Enable Tx turns off because Auto Seq never
             starts another contact (#10).
             partnerWorksOther (DMR planAutoSequence ~775-791, MW ~7427
             auto_sequence(decodedtext,25,50); 50 Hz rule): in replying, or in report
             when the contact started with Tx1 skipped, with Auto Seq on, the DX call's
             decoded message to another call within 50 Hz inclusive of my txOffsetHz
             disarms and stops a transmission already started by an abort
             (WstxTransmit::AbortTransmission, never a halt: #39 2026-11-04, normal flow
             never uses HALT); the state is kept. The stop is recorded with DisarmCause
             partnerWorksOther (CL-111-03). A contact that pauses
             for a busy partner (a manual contact; a run's own contact with busy_pause on;
             TxWatchdog busy pause, BusyPartner) does not disarm here: its Tx moves clear of his
             signal (FT8 100 Hz, FT4 140 Hz between the lower edges) and the call goes on; only a
             refused move disarms as here. A pounce, an MCP policy run and a run with busy_pause off
             keep this stop (50 Hz inclusive).
             halt and watchdogExpired turn Enable Tx off and keep the state (the
             contact can resume after an explicit Enable Tx), except in calling where
             the CQ ends. cancel follows CancelContact. Esc is Abort QSO (AbortQso), not a halt. */
    }
    dependency contactPromise from AutoSequence to WstxRequirements::'FR-007';
}
