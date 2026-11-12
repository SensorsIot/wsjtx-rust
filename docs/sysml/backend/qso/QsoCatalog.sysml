package WstxRequirementsQso {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-011-03' {
        doc /* Complete and log FT4 contacts through the common contact engine with the
             FT4 rules: the contact's mode fixed at preparation and carried in every
             TransmitRequest (7.5 s periods, t mod 15 s parity, 300 ms audio delay and
             the FT4 waveform through the #9 owner), Tx4 always RR73, Tx offset
             200..2916 Hz, TIME_ON one 7.5 s period before the first Tx3, log MODE MFSK
             SUBMODE FT4 and worked-before by effective mode FT4; only rows of the
             contact's mode count. Details: WstxContact::ContactMode, FT4-NOTE rules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs";
    }
    dependency CL_011_03_to_FR_007 from 'CL-011-03' to 'FR-007';
    dependency CL_011_03_to_FR_011 from 'CL-011-03' to 'FR-011';
    dependency CL_011_03_verified_by_TC_007_008 from 'CL-011-03' to 'TC-007-008';
    // #10 standard FT8 contact (decisions: issue #10 comment 6539901776, 2026-10-31);
    // detailed contract in WstxContact. FT4 rules marked FT4-NOTE there belong to #11.
    requirement 'CL-010-01' {
        doc /* Prepare a contact only from an acknowledged decoded row identity or an operator-entered DX Call/Grid that packs as a standard message; preparation sets partner, grid, report, Rx/Tx offsets, period parity and the six standard messages, and never arms or starts transmission; a receive-only station can prepare contacts and log. Details: WstxContact::SelectDecodedRow, EnterDxStation, FirstSlotOnSelection, ChangeContact. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js";
    }
    dependency CL_010_01_to_FR_007 from 'CL-010-01' to 'FR-007';
    // CL-010-04: ExportAdi is streamed (#10, 2026-11-04). #41 retired the #10 log review queue: completion and
    // Log QSO log directly (WstxContact::DirectLog); TIME_ON/TIME_OFF come from the
    // contact engine (server/src/contact.rs).
    // #10 closing reconcile (2026-11-08): CL-010-03 implemented; TC-007-007 was accepted by the
    // operator through the live QSOs (#10 comment 6718939269) and stays automation planned, as a
    // manual live case has no executable binding. MCP exposes the same contact operations
    // through WstxMcp (#12). CL-010-11 and TC-010-008 implemented: the #50 pointer actions (click Tx,
    // double-click Rx and Tx, dragging the lines and strip fields) were accepted live
    // (#50 comment 6719539569); since #37 the browser sends no re-decode, the wire
    // redecode stays refused redecode_unavailable.
    // CL-010-15 implemented (operator 2026-11-08): the Thin/Off byte budget is the browsers'
    // (StationTickEvent), a target judged from the link byte log since #80 (CL-003-05,
    // TC-080-001); MCP traffic is outside that budget.
    requirement 'CL-010-04' {
        doc /* Log every completed contact directly, without a review step (#41, as WSJT-X): at completion and on a manual Log QSO the server stores the contact's record in the profile directory's ADIF 3.1.8 contacts.adi with its contact identity and sends it to the WSJT-X UDP targets as QSO Logged and Logged ADIF; exactly one record per contact identity (an identical re-log adds nothing, completion after an early Log QSO replaces it; each contact is sent to the UDP targets once), a later contact with the same station a new record, Saved only after durable acknowledgement, a failed write visibly unsaved and retried; ADI export and history with the stated limits; and (#10, operator 2026-11-03) Update logbook from ADIF, the one ADI import: an export of another logger (for example Log4OM) is consolidated into the contact log, repeatable and incremental, a record already present (same contact identity, or same call, band and mode/submode with a start within 2 minutes) adding nothing and the stored record winning, only the log's own fields kept, added records marked with their source, QSO confirmation status (LoTW, QSL and eQSL received with their dates and via) kept and, on a rerun, upgraded on records already present (a confirmation is only added, never removed; #10, operator 2026-11-04), so worked-before and award queries tell worked from confirmed per entity, band and mode, invalid records skipped and invalid optional fields dropped with their reasons in the summary, nothing sent to the UDP targets or elsewhere, and the added records feeding worked-before, DXCC and grid status. The former log review queue (OfferLogReview, discard_review, the review form) is retired. Details: WstxContact::LogRecord, DirectLog, SaveContact, UpdateLogbook, ExportAdi, ContactHistory, AdiLimits, WorkedBeforeQuery; WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/logbook.js; client/contact.js";
    }
    dependency CL_010_04_to_FR_011 from 'CL-010-04' to 'FR-011';
    requirement 'CL-010-15' {
        doc /* Expose the contact operations only through the versioned WstxContact wire contract: exact routes, keys and byte caps, command_id idempotency, contact_revision, the ContactRefusal codes, the contact.state and station.tick events, and the stated Thin/Off byte budget, leaving StatusReply and the compressed-route allowlist unchanged. Details: WstxContact::ContactWire, ContactCommand, CommandReceipt, ContactSnapshot, ContactStateEvent, StationTickEvent. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/logbook_http.rs; server/src/main.rs";
    }
    dependency CL_010_15_to_FR_019 from 'CL-010-15' to 'FR-019';
    dependency CL_010_15_to_FR_021 from 'CL-010-15' to 'FR-021';
    requirement 'CL-010-12' {
        doc /* Generate the WSJT-X standard messages Tx1 grid, Tx2 report, Tx3 R+report, Tx4 RRR or RR73, Tx5 73 and Tx6 CQ on the server with the -50..+49 report rendering, operator report override, Tx1 skip and the RRR/RR73 toggle (FT8 default RRR); Now buttons and F11/F12 steps are not offered. Details: WstxContact::StandardMessageSet, ReportRange, OverrideReport, ToggleTx1Skip, ToggleTx4Form. */
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
             Expected (independent hand-written table, not candidate output): selection gives dxCall K1ABC, grid FN42, report -12 rendered "-12", Rx and Tx 1235 Hz, odd parity, next Tx1 "K1ABC HB9BLA JN47", Tx2 "K1ABC HB9BLA -12", Tx3 "K1ABC HB9BLA R-12", Tx4 "K1ABC HB9BLA RRR", Tx5 "K1ABC HB9BLA 73", Tx6 "CQ HB9BLA JN47" and no TransmitRequest before Enable Tx. States/next slots follow WstxContact::AutoSequence exactly: (a) replying/Tx1 -> rogerReport/Tx3 -> signoff/Tx5 -> completed after the completed Tx5 outcome, Enable Tx off, one log offer; (b) RRR from the partner gives signoff/Tx5; the contact completes after the first completed Tx5 transmission (AutoSequence sent73), Enable Tx off, one log offer; (c) calling/Tx6 -> report/Tx2 only after selection -> rogers/Tx4 -> completed on 73 (RRR) or on the completed RR73 transmission, Enable Tx off and no further CQ; (d) repeats resend the same text, report-from-rogers returns to Tx3, no second completion or log offer; (e) other/late rows change nothing; (f) with Tx1 skip, selecting the CQ row enters report directly with next Tx2, overrides -50/+49 accepted and rendered "-50"/"+49", -51/+50 and invalid entries refused with no contact; (g) this manual contact pauses for a busy partner (CL-097-06): his report to another call at 50 Hz and at 51 Hz from my Tx offset (FT8) both move Tx to the nearest candidate at least 100 Hz from his frequency (from 500 Hz), Enable Tx stays on and the call goes on, in replying and in the Tx1-skipped report (99 Hz moves, 100 Hz does not, TC-097-017 (c)), and only a refused move disarms; in a contact that does not pause (a pounce, an MCP policy run, a run with busy_pause off) 50 Hz disarms and 51 Hz does not; watchdog expiry while calling returns to idle; (h) Auto Seq off never changes the next slot; Halt and Alt+H send the halt request first; Esc sends one abort and no halt; last transmitted text changes only on started outcomes and differs visibly from the next message. Each request carries a fresh requestSequence; a duplicated browser action (same command_id) yields one request; one decoded row delivered twice counts once.             2 — Isolated automated functional tests; Windows development PC, actual candidate server and browser, independent decoded-row and transmit-outcome fixtures; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-01';
            verify 'CL-010-02';
            verify 'CL-010-03';
            verify 'CL-010-12';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs";
    }
    verification 'TC-007-005' {
        doc /* TC-007-005 — Pushed contact, transmit and receive state without polling
             CL-010-15
             #80 (operator 2026-11-09): the two-browser 32 kbit/s link workload is retired; the link budgets are targets judged from the link byte log (CL-003-05, TC-080-001). What remains are the unshaped pushed-state cases (WstxStationProtocol::PushedStationState).
             Setup: actual candidate server and Chromium on an unshaped local connection, the contact engine and #9 transmit owner on the recording hardware double, hand-authored result rows published by a test-only control peer, a request recorder.
             Steps: another client changes the contact and the transmit state; an own contact command, a command right after another, a stale safety revision, Esc and CQ during unanswered commands; an older GET /contact held across events; contact.js loaded after the socket's first event; a running Tune on Thin and on Detailed; receive.state with a job, audio and a refused event; contact.state carrying a contact and its dialogue rows.
             Expected: transmit.state and contact.state carry all fields first and then only what changed, shown with no GET /transmit and no GET /contact; an own command reads no GET /contact and a refusal shows its code; the next command goes with the receipt's revision; a stale safety revision is read at once and the CQ retried; nothing queued follows an abort; an older read never replaces a pushed change; a contact client loading after the first event has the state without a read; a Tune countdown alone at most once per 5 s below Detailed; receive.state carries the job and the audio, read again only for a new state, a refused event or a failed read; dialogue rows in order including a continuation at the same sequence.
             2 — Isolated automated functional tests; Windows development PC, real browser/server, no link simulator; no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        attribute executable : String = "tests/contact.test.cjs; server/src/contact_http_tests.rs; server/src/receive_http_tests.rs; tests/ui-operating.test.cjs";
        objective {
            verify 'CL-010-15';
        }
    }
    verification 'TC-011-001' {
        doc /* TC-011-001 — Direct logging, exactly once per contact
             CL-010-04
             Setup: actual server/browser, disposable profile directories, a UDP target socket bound on 127.0.0.1, independent failure injection (failed write, failed atomic replace), contacts with known identities and fields, transmit double.
             Steps: complete a contact (transmitted Tx5 73 after the partner's report; received 73 in rogers); repeat the completion events; manual Log QSO before completion, then the partner's later messages; Log QSO again unchanged; storage failure at completion, then recovery; restart; the same call again as a new contact; SaveContact with power 10 and comment, invalid power -1, comment with CR/LF or 1025 characters, repeat save; second profile; the browser Log QSO button.
             Expected (independent record catalogue and direct file reading): each completion stores exactly one record with the hand-computed CALL, GRIDSQUARE, MODE/SUBMODE, RST_SENT/RST_RCVD, QSO_DATE/TIME_ON (first transmitted Tx2/Tx3 rule), TIME_OFF, BAND, FREQ = dial + Tx offset, STATION_CALLSIGN and MY_GRIDSQUARE, and the UDP target receives one QSO Logged and one Logged ADIF for it; repeated completion and an unchanged Log QSO add no record and no datagram; an early Log QSO closes the contact (completed, Enable Tx off, nothing queued), so the partner's later messages neither replace its record nor send a second datagram pair (#37); Log QSO of a completed contact keeps its completion record even after a location change; a due retry stores the record in the contact step and the datagrams follow; a failed write leaves the record unsaved with storage_unavailable shown and is stored by the retry; nothing is logged again after restart; the second contact with the same call is a separate record; SaveContact identical resave alreadySaved, changed resave conflict, invalid fields refused; the browser shows no review form and sends no POST /contacts; no cross-profile record or browser-clock time.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-04';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/contact.test.cjs; tests/ui-operating.test.cjs; server/src/udp_tests.rs";
    }
    verification 'TC-011-002' {
        doc /* TC-011-002 — ADI interchange, Update logbook from ADIF and boundaries
             CL-010-04
             Setup: hand-authored ADIF ADI fixtures across line/tag/record boundaries and case variations with CALL, GRIDSQUARE, MODE, RST_SENT, RST_RCVD, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, BAND, FREQ, STATION_CALLSIGN, MY_GRIDSQUARE, TX_PWR, COMMENT and APP_WSTXRUST_CONTACT_ID; the confirmation fields LOTW_QSL_RCVD, LOTW_QSLRDATE, QSL_RCVD, QSLRDATE, QSL_RCVD_VIA, EQSL_QSL_RCVD, EQSL_QSLRDATE with valid, invalid (X, a bad date, an unknown via) and QSL_SENT values, a rerun that confirms (N, R, I, absent to Y/V) and one that says N for a confirmed record, a stored log with repeated or invalid verbatim QSL fields; a synthetic export shaped like Log4OM 2 (UTF-8 byte order mark, '#' banner lines, ADIF_VER 3.1.0, PROGRAMID LOG4OM2, non-ASCII NAME/ADDRESS values with LEN in characters, about 60 fields per record, MODE MFSK SUBMODE FT4 and MODE FT4, SSB with SUBMODE LSB/USB, records without FREQ or DXCC); a station log with its own records; records within and beyond 120 s of a stored one (same call, band and effective mode; another band; another mode), a stored contact id with differing fields, two copies in one file; invalid required fields (no CALL, bad QSO_DATE), invalid optional fields (a 5-character GRIDSQUARE, FREQ -1, a non-ASCII COMMENT); malformed lengths and tags, unsupported characters between fields, exactly 64 MiB/100,000 records/1024-character field and each one over, a wrong sha256; a UDP target socket.
             Steps: update the logbook, update again with the same file and with a grown file, retry the same import_id with identical and different total/sha256, export, reopen, page history at cursor 0, total-1 and total with limit 1/10/11; in the browser pick the file in Settings > Logging & Reporting and press Update logbook.
             Expected (independent ADI parser and hand-counted catalogue): the independently counted added/already present/skipped numbers with the skip reasons {code,field} and dropped fields; the stored station records unchanged byte for byte (existing wins) except an upgraded confirmation: a rerun sets Y/V with its date and via on present records (also records added earlier from the same file), never downgrades or removes one, changes no other stored field, and a repeat writes nothing; DirectLog replacing a record keeps its confirmation and SaveContact of it stays already saved; invalid confirmation values are dropped with their reason and QSL_SENT is not stored; the worked set answers worked vs confirmed per DXCC entity, entity x band and entity x band x mode (needed = not worked or not confirmed) and is rebuilt after an upgrade; a rerun of 27,000 QSOs all confirmed upgrades all of them within seconds; a stored log with repeated or invalid verbatim QSL fields stays readable; a record within 120 s of a stored one with the same call, band and effective mode present, one beyond or on another band or mode added; MFSK/FT4 and FT4 consolidated as one mode; added records carry APP_WSTXRUST_SOURCE LOG4OM2 and a new contact id and only the kept fields (no NAME, ADDRESS, EMAIL or other field stored); a second update adds nothing, a grown file only its new records; a structural fault or over-limit input publishes zero records with record/field context; same import_id retry has no second effect, different values state_conflict; no datagram reaches the UDP target; the added calls and grids answer worked-before; history pages hold stable indexes, limit 11 refused, at most 16384 bytes; export then update adds nothing; the browser shows "Logbook updated: N added, M already present (C confirmations updated), K skipped" with the reasons, and "Logbook not updated" for a refused file.
             2 — Isolated automated functional tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-010-04';
        }
        attribute executable : String = "server/src/logbook_tests.rs; server/src/logbook_http_tests.rs; tests/ui-operating.test.cjs; server/src/udp_tests.rs";
    }
    dependency CL_010_01_verified_by_TC_007_001 from 'CL-010-01' to 'TC-007-001';
    dependency CL_010_01_verified_by_TC_007_003 from 'CL-010-01' to 'TC-007-003';
    dependency CL_010_01_verified_by_TC_007_007 from 'CL-010-01' to 'TC-007-007';
    dependency CL_010_04_verified_by_TC_011_001 from 'CL-010-04' to 'TC-011-001';
    dependency CL_010_04_verified_by_TC_011_002 from 'CL-010-04' to 'TC-011-002';
    dependency CL_010_04_verified_by_TC_007_007 from 'CL-010-04' to 'TC-007-007';
    dependency CL_010_12_verified_by_TC_007_001 from 'CL-010-12' to 'TC-007-001';
    dependency CL_010_15_verified_by_TC_007_004 from 'CL-010-15' to 'TC-007-004';
    dependency CL_010_15_verified_by_TC_007_005 from 'CL-010-15' to 'TC-007-005';
    requirement 'CL-039-21' {
        doc /* A strategy or contest run never stops its own contact for the Tx watchdog; the leave rule bounds it instead (CL-039-23, CL-097-04), and while the target has not answered Tx moves by the Tx move rule per PSK case (CL-097-05); a target that has answered keeps its slot for the whole exchange. WD:n is the Tx watchdog only: the run's own contact shows the leave label instead (CL-097-04). Manual operation, a pounce and an MCP policy run keep the stop at N, and so does a run's CQ; unattended or past the run limit the stop at N is back at once. Details: WstxStrategy::StrategyWatchdog, TxMoveRule, HearingFeed, FreeTxSlot, LeaveCountLabel; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/freeslot.rs; server/src/pskr.rs";
    }
    dependency CL_039_21_to_FR_007 from 'CL-039-21' to 'FR-007';
    dependency CL_039_21_to_FR_008 from 'CL-039-21' to 'FR-008';
    requirement 'CL-039-23' {
        doc /* Exit (operator grill 2026-11-07, Q6, Q7, Q13-Q16, Q19-Q28). A repetition is a fresh complete publication of the target's parity after an own transmission without progress; any message of the target to my call is progress, also a repeated one, except a selected caller repeating the message it was selected on. Both situations count alike: he repeats, because he does not hear us (decoded, a CQ again or another station), and we repeat, because we do not hear him (not decoded). The run leaves a station by the strategy's leave mode and gives it the retry pause (CL-097-04); a busy target's calls are paused (CL-097-06). Nothing changes before an exit criterion, even for a more valuable station; a caller of my call (in a contest only a non-dupe caller) is answered at once while the target has not answered, with Calling stations are answered on. A contest dupe caller never ends a stay. Details: WstxStrategy::LeaveRule, QuietTime, StrategyRun; WstxContest::ContestRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs; server/src/contest.rs; server/src/pskr.rs";
    }
    dependency CL_039_23_to_FR_007 from 'CL-039-23' to 'FR-007';
    dependency CL_039_23_to_FR_020 from 'CL-039-23' to 'FR-020';
    verification 'TC-039-022' {
        doc /* TC-039-022 — Tx moves at the repetitions of a target that does not hear us, and the run's own contact past the Tx watchdog
             CL-039-21
             Setup: the actual station router, contact engine, automation and #9 transmit owner on the recording hardware double, virtual UTC, a feed without a connection fed hand-authored spots, a dial of 14074000 Hz; Tx watchdog 2; a strategy run with Auto on, on 20 m, leave {calls 4, calls_heard 8} and tx_move_every {heard 0, not_heard 1, no_reports 1}, calling K1ABC (CQ at 1800 Hz) from Tx 1500; hand-authored waterfall rows whose quietest slot changes between periods.
             Steps: 4 repetitions with: no spot; a spot of my call to K1ABC 60 s old, 590 s old, 601 s old, on 40 m; the spot with Use PSK Reporter off; the spot with the feed off. The quietest slot moving 1400, 1300 between repetitions, and staying tied with the current one. The partner's report after the 2nd repetition, then silent periods. The engine alone: the run's own contact past the watchdog limit, then another contact; a run's CQ at the limit. Unattended (no client 60 s) and past the run limit with the spot: N 2 back at once, also without a publication. A refused move.
             Expected (hand-worked from WstxStrategy::FreeTxSlot): every repetition keyed while the run is attended, tx_expired false. The run's own contact shows no WD (tx_remaining_calls null) and the leave label counts the calls left, 4, 3, 2, 1, then the leaving; with the spot from 8 down to 1 (TC-097-013). No spot, 601 s, 40 m, Use off, feed off: Tx and Rx 1400 after the 1st, 1300 after the 2nd; a move never keeps the current slot, so a slot tied with it gives the next quietest (TC-097-010); slot_check hears_us false. Heard (60 s, 590 s): Tx stays 1500, hears_us true. After the partner's report Tx never moves again in that exchange. Engine: the run's own contact sends past N; another contact and the run's CQ stop at N (cause tx_watchdog). Unattended: the stop at N back, no further key, stopped no_client or run_limit. A refused move: unchanged, checked again at the next repetition. Manual stop at N: TC-008-001; a pounce stops at N: TC-039-005.
             #39 holdtx: these steps run with Hold Tx explicitly off (Tx and Rx move together); with Hold Tx on only Tx moves and Rx stays on 1800: TC-039-049.             2 — Isolated automated tests; Windows development PC, no radio, audio or RF, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-21';
        }
        attribute executable : String = "server/src/strategy_tests.rs; server/src/contact_tests.rs; server/src/freeslot_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_039_21_verified_by_TC_039_022 from 'CL-039-21' to 'TC-039-022';
    dependency CL_039_23_verified_by_TC_039_043 from 'CL-039-23' to 'TC-039-043';
    dependency CL_039_23_verified_by_TC_039_044 from 'CL-039-23' to 'TC-039-044';
    dependency CL_039_21_verified_by_TC_039_047 from 'CL-039-21' to 'TC-039-047';
    dependency CL_039_23_verified_by_TC_039_047 from 'CL-039-23' to 'TC-039-047';
    dependency CL_039_23_verified_by_TC_039_048 from 'CL-039-23' to 'TC-039-048';
    dependency CL_039_21_verified_by_TC_039_049 from 'CL-039-21' to 'TC-039-049';
    dependency CL_039_21_verified_by_TC_039_051 from 'CL-039-21' to 'TC-039-051';
    // ---------------------------------------------------------------- #55 DXCC from cty.dat
    requirement 'CL-055-01' {
        doc /* The station resolves each call to its DXCC entity from AD1C's cty.dat exactly as WSJT-X does: exact =CALL entries, the longest matching prefix, operating suffixes (/P, /QRP, /M, a digit and the other WSJT-X suffixes), compound calls by their shorter side, /MM and /AM without entity, the KG4 rule, and the zone, position and continent overrides of the matching entry; names are shown in the WSJT-X short form with WAE entities shown as their DXCC. The cty.dat WSJT-X 3.3.0-beta5 ships (VER20250115) is bundled with its source and permission notice. Details: WstxContact::CountryFile, EntityOfCall. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/dxcc.rs";
    }
    dependency CL_055_01_to_FR_011 from 'CL-055-01' to 'FR-011';
    verification 'TC-055-001' {
        doc /* TC-055-001 — Entity resolution known answers
             CL-055-01
             Setup: the bundled cty.dat; a hand-written file with every override kind; malformed files.
             Steps: effective prefix of WSJT-X's own test_radio_callsign vectors with "", /P, /QRP, /P/QRP; resolve HB9BLA, K1ABC, DL1XYZ, EA8ABC, HB9BLA/P, HB9BLA/QRP, W1AW/4, DL/HB9BLA, HB9BLA/DL, EA8/K1ABC, K1ABC/EA8, HB9BLA/MM, K1ABC/AM, KG4AB, KG4ABC, KG4AB/P, 3D2CR, 3D2CR/P, 3D2AG/P, W1AW/KG4, RA0DAA, RA0ABC, KG4IJS/0, IT9ABC, 4U1VIC, 2M0BDR, GB3LER, FO5ABC, UA3ABC, Q1ABC, a non-ASCII text; parse the override file and each malformed file (also CQ zone 41, ITU zone 91, an empty, a 41-character and a non-ASCII name).
             Expected (from the cited cty.dat lines and AD1CCty.cpp): Switzerland, U.S.A., Germany, Canary Is. with their zones; compound and suffixed calls by their effective prefix; /MM and /AM none; KG4 5 characters Guantanamo Bay, else U.S.A.; exact entries only for the whole call (3D2CR Conway Reef, 3D2CR/P Fiji, 3D2AG/P Rotuma Is.); zone overrides RA0 19/33, RA0A 18/32, KG4IJS/0 4/7; Sicily, Vienna Intl Ctr and Shetland shown as Italy, Austria, Scotland; the first entry of a duplicate key (GB3LER Scotland); version VER20250115, 346 entities; overrides applied; malformed files refused with their line.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-055-01';
        }
        attribute executable : String = "server/src/dxcc_tests.rs";
    }
    dependency CL_055_01_verified_by_TC_055_001 from 'CL-055-01' to 'TC-055-001';

    // Saved Auto Seq and Call 1st (WstxContact::QsoSettingsFile).
    requirement 'CL-110-01' {
        doc /* Auto Seq and Call 1st are kept per profile across station starts (WstxContact::QsoSettingsFile). (1) At a station start the two settings have the values last saved for the selected profile. When nothing usable is saved, both are on. (2) An accepted set_auto_seq or set_call_first is saved before its receipt is returned, whichever client sent it (browser or MCP). After the receipt, a station start on the same profile directory has that value. (3) A value is saved whether it is on or off: after off and on again, the next start has on because on was saved, not because nothing is there. (4) When the save fails, the command is refused storage_unavailable with field null; the setting, the snapshot and contact_revision are unchanged, and the earlier saved values stay as they were. The same command sent again with a new command_id saves once storage is available. In the browser, after a refused set_auto_seq or set_call_first the checkbox shows the station's value again, not the clicked one, in the same step that shows the refusal. (5) Saving does not change the profile document: its revision does not advance. (6) Another profile never has these values: a profile directory holds only its own. (7) Starting with saved values changes nothing else: the transmit state (WstxTransmit::TransmitArming) is off with cause startup, no contact exists, and no TransmitRequest is planned until a start action (enable_tx). (8) Every other setting of ContactSnapshot settings (tx1_skip, tx_calls, tune_seconds, rx_hz, tx_hz, hold_tx, parity, report, activity, exchange, serial) is not saved and has its stated start value at every station start. Details: WstxContact::QsoSettingsFile, Contact. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/main.rs; server/src/profile.rs; client/contact.js";
    }
    dependency CL_110_01_to_FR_007 from 'CL-110-01' to 'FR-007';
    dependency CL_110_01_to_FR_016 from 'CL-110-01' to 'FR-016';
    verification 'TC-110-001' {
        doc /* TC-110-001 — Saved across a station start
             CL-110-01
             Setup: the actual station router on a disposable profile directory (contact_http_tests fixture), profile HB9BLA JN37; values read from GET /contact settings. A new station start is a new station owner (new boot_id) on the same profile directory. For (h) the station with an MCP client (mcp_tests).
             Steps: (a) a newly created profile, no qso-settings.json. (b) set_call_first {enabled:false}; the same body again with the same command_id; a new station start. (c) then set_auto_seq {enabled:false}, a new station start. (d) then both set to true, a new station start. (e) set_call_first false, then set_auto_seq false without a start between them, a new station start. (f) GET /profile revision before (b) and after (d). (g) after (c) on profile A, a newly created profile B. (h) set_call_first {enabled:false} through the MCP tool wstx_contact_command, a new station start.
             Expected (CL-110-01 points 1, 2, 3, 5, 6): (a) auto_seq true, call_first true. (b) 202; the repeated body 200 with the same receipt (guard of the receipt rule); after the start call_first false, auto_seq true. (c) both false. (d) both true, and the file holds auto_seq true and call_first true. (e) both false. (f) the same revision. (g) B has both true. (h) call_first false.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; server/src/mcp_tests.rs";
    }
    dependency CL_110_01_verified_by_TC_110_001 from 'CL-110-01' to 'TC-110-001';
    verification 'TC-110-002' {
        doc /* TC-110-002 — Missing, hand-written and unusable files
             CL-110-01
             Setup: as TC-110-001; a hand-written qso-settings.json is put into the profile directory before the station start; <id> is that profile's UUID.
             Steps: (a) {"schema_version":1,"profile_id":"<id>","auto_seq":false,"call_first":true}. (b) the same object padded with trailing spaces to exactly 256 bytes. (c) padded to 257 bytes. (d) an empty file. (e) truncated JSON ({"schema_version":1,"profile_id":"<id>","auto_seq":fal). (f) schema_version 2. (g) the profile_id of another profile. (h) an extra key ("tx1_skip":true), and a missing key (no call_first). (i) "auto_seq":"false" (a string) and "call_first":0. (j) in each of (c) to (i): GET /contact, then set_call_first {enabled:false}, then a new station start.
             Expected (the WstxContact::QsoSettingsFile format): (a), (b) auto_seq false, call_first true. (c) to (i) both true in each. (j) the station start succeeds and GET /contact returns 200; the command returns 202, the file is the exact object with auto_seq true and call_first false, and the new station start has those values.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
        }
        attribute executable : String = "server/src/contact_http_tests.rs";
    }
    dependency CL_110_01_verified_by_TC_110_002 from 'CL-110-01' to 'TC-110-002';
    verification 'TC-110-003' {
        doc /* TC-110-003 — A failed save
             CL-110-01
             Setup: as TC-110-001, saved state call_first true; fault injected: the replace of qso-settings.json fails (the profile store's test seam), nothing else in the profile directory is touched.
             Steps: (a) with the fault, set_call_first {enabled:false}. (b) fault removed, the same action with a new command_id, then a new station start. (c) with the fault, set_hold_tx {enabled:false}.
             Expected (CL-110-01 point 4): (a) refused storage_unavailable, field null; GET /contact shows call_first true and the same contact_revision as before; the profile directory is unchanged. (b) 202, call_first false, and the new station start has false. (c) 202: only the two saved settings depend on storage.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
        }
        attribute executable : String = "server/src/contact_http_tests.rs";
    }
    dependency CL_110_01_verified_by_TC_110_003 from 'CL-110-01' to 'TC-110-003';
    dependency CL_110_01_verified_by_TC_110_004 from 'CL-110-01' to 'TC-110-004';
    verification 'TC-110-005' {
        doc /* TC-110-005 — The browser after a restart
             CL-110-01
             Setup: Chromium against the candidate server on a disposable profile directory, 1366x768.
             Steps: (a) untick Call 1st; the server process is stopped and started on the same directory; reload. (b) a second browser opened after the restart. (c) in that browser the snapshot is held back (GET /contact and the contact.state push). (d) POST /contact/command with action set_call_first is answered 503 {"error":{"code":"storage_unavailable","field":null}}; Call 1st is unticked; the same for Auto Seq (on a snapshot with an available transmit capability, which enables its box).
             Expected (CL-110-01 points 1, 2, 4): (a) Call 1st unticked and Auto Seq ticked. (b) the same. (c) while the snapshot is held back both checkboxes are disabled and unticked, so no value is shown before the saved one arrives. (d) the result line shows the refusal and the box is ticked again, with the setting true in the snapshot.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_110_01_verified_by_TC_110_005 from 'CL-110-01' to 'TC-110-005';
    verification 'TC-110-006' {
        doc /* TC-110-006 — Live on the station
             CL-110-01
             Setup: HB9BLA, the deployed candidate, the operator's browser; no transmission, the transmit state stays off.
             Steps: (a) the first start after the deploy. (b) untick Call 1st, restart the station task, reload. (c) tick Call 1st again, restart, reload.
             Expected: (a) Auto Seq and Call 1st are both ticked. (b) Call 1st unticked, Auto Seq ticked, transmit state off. (c) both ticked.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-110-01';
        }
    }
    dependency CL_110_01_verified_by_TC_110_006 from 'CL-110-01' to 'TC-110-006';
    requirement 'CL-111-02' {
        doc /* Start actions. The start actions are exactly these. Each is one ContactCommand and carries the safety revision shown to its sender; grant, clock, period and safety-revision checks are unchanged. Reply: double-click or row menu Reply on a Band Activity row, double-click or Enter on a Calling me row: reply {row, directive_confirmed?, safety_revision}. CQ: the CQ button: call_cq {safety_revision}. Call: Enter in the DX call or grid field, and the button beside them: call_dx {dx_call, dx_grid, replace, safety_revision}. Send next: "Send <exchange> next": send_next {slot, safety_revision}. Reset: the Reset button: reset_repetitions {safety_revision}. Auto: a strategy, contest or policy run: reply or call_cq sent by the run, cause auto. The outcome of each start in each state is the table of WstxContact::StartActions. A Hound's call_cq is no_contact. A slot without text is invalid_message, as choose_next. enable_tx is retired: refused invalid_request with field action, for the browser and for MCP clients. select_row, enter_dx and choose_next stay and never start. An MCP client may send reply, call_cq, call_dx and send_next; its start is automatic: after a repetition-limit stop, or when no browser action was seen this boot, it is refused tx_watchdog. A start refused for a stale contact or safety revision, for tx_watchdog, or by a row or call refusal changes nothing: no QSO is prepared. The browser retries a start refused stale_revision at most twice with the reloaded snapshot, as CL-061-02. Not delivered yet: the browser controls and the runs still send select_row or enter_dx and enable_tx, enable_tx is still accepted, and the MCP tool description does not name the starts. Details: WstxContact::StartActions, ContactCommand. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs";
    }
    dependency CL_111_02_to_FR_007 from 'CL-111-02' to 'FR-007';
    dependency CL_111_02_to_FR_008 from 'CL-111-02' to 'FR-008';
    requirement 'CL-111-05' {
        doc /* A start never becomes a CQ. Only call_cq calls CQ. reply and call_dx name their own partner and start that QSO in every state. send_next and reset_repetitions act on the current QSO: when it has ended, was cancelled or never existed they are refused no_contact and nothing is sent (the table of WstxContact::StartActions). Not delivered yet: enable_tx with no partner still calls CQ. Details: WstxContact::StartActions. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs";
    }
    dependency CL_111_05_to_FR_007 from 'CL-111-05' to 'FR-007';
    requirement 'CL-111-08' {
        doc /* Reset. The QSO pane has a Reset button. It is offered only for a QSO with a partner: while it transmits (state on, replying to signoff), and while it is stopped by the repetition limit (state off, cause txWatchdog). It is not offered during an own CQ, in any other state, or after Halt, a lost radio or a refused transmission. While on: the repetition count of the message due next starts anew; the state stays on. While stopped by the limit: the count starts anew, the state goes on, and the message due next, the one that got no answer, is sent from the next own period. Only the operator in the browser may use it: from a run or an MCP client it is refused operator_required. Its other outcomes are the table of WstxContact::StartActions. The limit itself is unchanged: 1..99, default 6; a send that would exceed it is never keyed. Labels: "Reset count" while the state is on; "Reset · send again" while stopped by the limit. Not delivered yet: the button; the command reset_repetitions is. Details: WstxContact::StartActions, TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs";
    }
    dependency CL_111_08_to_FR_007 from 'CL-111-08' to 'FR-007';
    dependency CL_111_08_to_FR_008 from 'CL-111-08' to 'FR-008';
    requirement 'CL-111-10' {
        doc /* Hound limits. While the Hound still calls with Tx1, the transmit state goes off (cause txWatchdog) when 300 s have passed since the last accepted start. Every accepted start restarts the 300 s, a run's start included. reset_repetitions does not restart it. The reply timeout ends at every accepted start and at completion; nothing else about WstxContact::HoundOperation changes, "a Fox report never switches transmission on" included. Details: WstxContact::HoundOperation. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs";
    }
    dependency CL_111_10_to_FR_007 from 'CL-111-10' to 'FR-007';
    dependency CL_111_10_to_FR_008 from 'CL-111-10' to 'FR-008';
    verification 'TC-111-003' {
        doc /* TC-111-003 — Each start in each state
             CL-111-02
             Setup: as TC-111-001, one station built anew for each cell; for the wire the actual station router (contact_http_tests fixture).
             Steps: every cell of the outcome table of WstxContact::StartActions, one command each; call_cq on an own CQ kept off after a lost radio, with the radio back and with the radio still away. Further negatives: a stale safety revision; enable_tx; a Hound's call_cq.
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
    verification 'TC-111-016' {
        doc /* TC-111-016 — Hound 300 s
             CL-111-10
             Setup: as TC-111-001, the activity hound, a Fox KH7Z, the repetition limit 99; the Hound calling with Tx1.
             Steps: the start; a second reply at 150 s; a run's start at 150 s; reset_repetitions at 150 s; the Fox's report before 300 s (Tx3 next).
             Expected (CL-111-10): off with txWatchdog at 300 s after the start, not at 299 s; the second reply moves it to 450 s; a run's start restarts it the same way; reset_repetitions does not move it; with Tx3 next nothing stops at 300 s.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-10';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_10_verified_by_TC_111_016 from 'CL-111-10' to 'TC-111-016';
    requirement 'CL-024-02' {
        doc /* #24 S2a. An operator-chosen special activity of none, WW Digi, ARRL Digi or NA VHF generates "CQ WW"/"CQ TEST" and the grid exchange (Tx2 grid, Tx3 "R grid"), sequences on the received grid and R+grid, logs on RRR/RR73/73 like any contact and shows dupes through the existing worked-before indication per band and mode; UDP Status carries the activity as WSJT-X's special operation value; station automation does not start in a contest activity (observe only). Details: WstxContact::GridExchangeContest. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/udp.rs; client/contact.js";
    }
    dependency CL_024_02_to_FR_024 from 'CL-024-02' to 'FR-024';
    verification 'TC-024-005' {
        doc /* TC-024-005 — Grid-exchange contests through the contact engine
             CL-024-02
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); hand-authored standard rows; HB9BLA JN47AA; the station fixture over POST /contact/command and its UDP Status.
             Steps: (a) set_activity ww_digi, Enable Tx with no partner, select the caller "HB9BLA S52XYZ JN76", the partner sends "HB9BLA S52XYZ RR73"; (b) set_activity na_vhf, select "CQ TEST K1ABC FN42", Enable Tx, the CQer sends "HB9BLA K1ABC R FN42"; (c) arrl_digi with my call DL/HB9BLA; (e) during a running CQ with an edited Tx6 set ww_digi, then set_report; with an active contact switch none, ww_digi, none; start station automation with ww_digi set; (d) set_activity none, an unknown activity "q65_pileup" ("eu_vhf" until #99, TC-099-002), and the settings and UDP Status of each activity.
             Expected: (a) Tx6 "CQ WW HB9BLA JN47"; the caller's grid selects Tx3 "S52XYZ HB9BLA R JN47" (rogerReport) with Tx2 "S52XYZ HB9BLA JN47"; after RR73 Tx5 is sent, the contact completes and is logged with grid JN76 and no reports; (b) Tx6 "CQ TEST HB9BLA JN47", "K1ABC HB9BLA JN47" sent (as Tx2 since #24 S2b: Tx1 is disabled in contests), the R FN42 moves to Tx4 "K1ABC HB9BLA RRR", which completes after it is sent and the partner's 73; (c) Tx6 "CQ DL/HB9BLA" and Tx2 "K1ABC <DL/HB9BLA> JN47"; (d) none restores the report exchange (Tx2 "K1ABC HB9BLA -15"), q65_pileup is refused invalid_request field activity, settings.activity reads the choice and UDP Status special operation 0/1/5/8; (e) Tx6 becomes "CQ WW HB9BLA JN47" and a later set_report keeps it, the active contact's Tx2/Tx3 switch between "-NN"/"R-NN" and "JN47"/"R JN47", and automation start is refused not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_02_verified_by_TC_024_005 from 'CL-024-02' to 'TC-024-005';
    verification 'TC-024-006' {
        doc /* TC-024-006 — The Activity choice in the QSO fold-out
             CL-024-02
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out; read the Activity choice with settings.activity ww_digi; choose ARRL Digi.
             Expected: the choice offers None, NA VHF, WW Digi and ARRL Digi (since #24 S2b also Field Day and RTTY Roundup, TC-024-009, since #24 S4b also Hound, TC-024-013, since #99 also EU VHF after NA VHF, TC-099-003) and shows WW Digi; choosing sends set_activity {activity arrl_digi}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_02_verified_by_TC_024_006 from 'CL-024-02' to 'TC-024-006';
    requirement 'CL-024-03' {
        doc /* #24 S2b. Field Day (i3=0 n3=3/4) and FT/RTTY Roundup (i3=3) exchanges come from the configured class/section and state/province or DX serial, with 5x9 reports, FT4 "TU;", and pack/unpack identical to ft8code. Contest exchange values go into ADIF CONTEST_ID/STX/SRX/STX_STRING/SRX_STRING/CLASS/ARRL_SECT/STATE as WSJT-X AdifQso writes them. Slice S2b1: the two packer families, exact against ft8code and ft4sim (WstxTransmit::PackMessage), so the transmit owner accepts such a message; the contact engine still refuses them in its slots; unpack and pack share the WSJT-X 3.3.0-beta5 section (86) and RTTY exchange (171) tables, which replace the QEX 2020 tables (WstxOfflineDecode sectionTable/stateProvinceTable). Slice S2b2: the field_day and rtty activities with their configured exchange and the contest serial, the 5x9 mapping, FT4 TU;, the Tx2 start of every contest activity, sequencing on the received exchange, the contact's exchange_sent/exchange_rcvd, the ADIF contest fields of the log (WstxContact::ContestExchange, LogRecord), UDP Status special operation 3/4 and the Activity choice with its Exchange entry; station automation still does not start in a contest activity. Cabrillo is not offered (operator decision S2b-1). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/pack.rs; server/src/decoder/payload.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs; server/src/logbook_http.rs; client/contact.js";
    }
    dependency CL_024_03_to_FR_004 from 'CL-024-03' to 'FR-004';
    dependency CL_024_03_to_FR_024 from 'CL-024-03' to 'FR-024';
    dependency CL_024_03_to_FR_005 from 'CL-024-03' to 'FR-005';
    verification 'TC-024-007' {
        doc /* TC-024-007 — Field Day and RTTY Roundup messages pack exactly as WSJT-X
             CL-024-03
             Setup: fixtures/transmit/ft8code-vectors.json and fixtures/transmit/ft4/ft4sim-vectors.json regenerated by fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe (beta4 output identical) and ft4sim.exe, with 20 Field Day and RTTY Roundup messages WSJT-X encodes unaltered (counts 1, 10, 16, 17, 32; classes A-F; R; sections EMA, NB, WI, DX; TU;; serials 0001, 0013, 7999; multipliers MA, WI, ON, PEI, X99) and 19 contest shapes it alters or rejects (a nonstandard, /R or <CALL> call slot; counts 0, 06, 33; class G; Q-prefix call; serials 0000, 8000; reports 519; exchanges 13, DX; TU; without an exchange, a repeated TU;, a missing exchange).
             Steps: pack and encode every fixture message for FT8 and FT4; read the family, i3/n3 and refusal of named messages; unpack the fixed payload-boundary cases of fixtures/decoder/payload-boundary-cases.json (fixtures/decoder/independent-vector-tool/boundary_cases.py) for section 84/85/86/87 and exchange 8065/8066/8171/8172.
             Expected: for every message the oracle encodes unaltered as 0.3, 0.4 or 3., bits, CRC, parity and tones (FT8) and bits, codeword and tones (FT4) equal the oracle and the text equals its rendering; families fieldDay (n3 3 for counts 1-16, 4 for 17-32) and rttyRoundup; every altered or rejected contest shape is refused, a hashed contest call slot (PJ4/K1ABC, K1ABC/R) as notExact, "K1ABC RR73; W9XYZ <KH1/KH7Z> -08" still unsupportedFamily; sections 84 DX, 85 PE and 86 NB and exchanges 8065 DC, 8066 DR and 8171 X99 decode, 87 and 8172 are invalid_payload.
             2 — Isolated automated tests; Windows development PC, no radio, audio, RF or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs; server/tests/transmit_ft4_vectors.rs; server/tests/decoder_vectors.rs";
    }
    dependency CL_024_03_verified_by_TC_024_007 from 'CL-024-03' to 'TC-024-007';
    verification 'TC-024-008' {
        doc /* TC-024-008 — Field Day and RTTY Roundup through the contact engine and the log
             CL-024-03
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, unpack, row reader); HB9BLA JN47AA; the station fixture over POST /contact/command with its log and UDP Status; the logbook record validation.
             Steps: (a) set_activity field_day "1a  ema", Enable Tx with no partner, select the caller "HB9BLA K1ABC 2A WI", the partner answers my Tx3 with "HB9BLA K1ABC RR73"; (b) set_activity rtty "DX", select "CQ RU W9XYZ EN37" with SNR -3, Enable Tx, the CQer sends "TU; HB9BLA W9XYZ R 579 MA", then a second selection; (c) rtty "MA" in FT4: after my Tx3 and the partner's RR73, select the next caller 0.5 s after the RR73 was counted, and in a second run 3 s after it; (d) refusals: field_day without an exchange or with "0A EMA", "33A EMA", "1G EMA", "1A XX" or a non-ASCII character; rtty "DXX" or "8000" (a fixed "0013" is accepted); an exchange with ww_digi; a nonstandard DX call in field_day; a Field Day row while rtty is set; (e) settings and contact snapshot keys, UDP Status special operation; edit_message tx2 "K1ABC HB9BLA 3A WI"; (f) validate_record of the logged records, RST 519 and a contest field with '<'; history record keys.
             Expected: (a) exchange "1A EMA", Tx6 "CQ FD HB9BLA JN47", the caller's exchange selects Tx3 "K1ABC HB9BLA R 1A EMA" with exchange_rcvd "2A WI"; after their RR73 Tx5 is sent, the contact completes and is logged with STX_STRING "1A EMA", CONTEST_ID ARRL-FIELD-DAY, SRX_STRING "2A WI", CLASS 2A, ARRL_SECT WI and no RST; serial 2 afterwards; (b) Tx6 "CQ RU HB9BLA JN47", the selection starts with Tx2 "W9XYZ HB9BLA 559 0001" (Tx1 disabled), the R exchange moves to Tx4, exchange_rcvd "579 MA", the record has RST_SENT 559, RST_RCVD 579, STX 0001, STATE MA; the second selection's Tx2 carries 0002; (c) Tx3 "TU; W9XYZ HB9BLA R 559 MA" in the first run only; (d) invalid_request field exchange, invalid_call, the row is classified other; (e) settings activity/exchange/serial, contact exchange_sent/exchange_rcvd, special operation 3 and 4; the edited Field Day text is accepted unaltered; (f) the records are valid, RST 519 and '<' are refused, history records carry stx..state.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/logbook_tests.rs";
    }
    dependency CL_024_03_verified_by_TC_024_008 from 'CL-024-03' to 'TC-024-008';
    verification 'TC-024-009' {
        doc /* TC-024-009 — The Field Day / RTTY Roundup choice and its Exchange entry
             CL-024-03
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity rtty, exchange DX, serial 7; enter "1A EMA" in the Exchange entry and choose Field Day; change the exchange to "2B WI".
             Expected: the choice offers None, NA VHF, WW Digi, ARRL Digi, Field Day and RTTY Roundup (since #99 also EU VHF, TC-099-003); it shows RTTY Roundup, the entry DX and the next serial 0007; choosing sends set_activity {activity field_day, exchange "1A EMA"}, the change sends {field_day, "2B WI"}; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-03';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_03_verified_by_TC_024_009 from 'CL-024-03' to 'TC-024-009';
    requirement 'CL-024-04' {
        doc /* #24 S4. Classic Hound follows HoundTransmissionPolicy: second-period only, Tx1/Tx3 only, random 1000-2998 Hz calling when the Tx offset is below 999 Hz, Tx3 on the Fox frequency after the Fox's report and Fox +-300 Hz on a repeat, completion and logging on the Fox's RR73 in standard or 0.1 form, the reply timeout and the Hound watchdog, and Fox selection limited to rows decoded at :00/:30 (not R+report rows of other Hounds). set_activity hound is FT8 only; UDP Status special operation 7; station automation does not start as a Hound. Slice S4a is the 0.1 hashdx10 rule (CL-024-01, TC-024-010); slice S4b is the Hound operation (WstxContact::HoundOperation). SuperFox (S5) stays excluded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_024_04_to_FR_024 from 'CL-024-04' to 'FR-024';
    verification 'TC-024-011' {
        doc /* TC-024-011 — Classic Hound through the contact engine
             CL-024-04
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, or 0.1 payloads built from their fields, unpack, HashTable fill-in with my call HB9BLA and the DX call, row reader); a deterministic random source; HB9BLA JN47AA; Fox KH7Z.
             Steps: (a) set_activity hound with parity even and Tx 800 Hz; select "CQ KH7Z BL01" at 812 Hz (:00) with SNR -9, Enable Tx; the Fox sends "HB9BLA KH7Z -12" at 812 Hz with SNR -7; my Tx3 is sent; the Fox is silent one period; it sends "HB9BLA KH7Z RR73"; (b) the same with the Fox at 450 Hz, its report inside "W9XYZ RR73; HB9BLA <KH7Z> -12" and its RR73 inside "HB9BLA RR73; K1ABC <KH7Z> -08"; a repeated Fox report after my first Tx3; (c) refusals: Enable Tx without a DX call, a row at :15, "KH7Z W9XYZ R-05" at :00, a 0.1 row, set_parity even, choose_next tx2/tx4/tx5/tx6, choose_next tx1 with Skip Tx1 on; a station mode change to FT4, then set_activity hound; (d) not counted: "HB9BLA K1ABC RR73" (not the DX call), a 0.1 RR73 and a 0.1 report to me with another hashed call, a Fox report while Tune is on (the transmit owner armed with Tune and no request); (e) the reply timeout 165 s after the Fox's report, and again with Enable Tx turned off and on 150 s after it, the Hound watchdog after 300 s of Tx1, and a station Tx watchdog of 1 unanswered call while Tx3 repeats (99 calls for the Hound watchdog case); (f) with Tx 1500 Hz Tx1 keeps its offset.
             Expected: (a) parity odd and Hold Tx on; the selection keeps Tx 800 Hz and gives Tx1 "KH7Z HB9BLA JN47"; Tx1 goes out in the odd period at the random offset within 1000..2998 Hz; the report gives report_rcvd -12, Tx3 "KH7Z HB9BLA R-07" at 812 Hz, the repeat at 512 Hz; the RR73 completes the contact with Enable Tx off (contactCompleted) and logs KH7Z with RST_SENT -07 and RST_RCVD -12; (b) Tx3 at 450 Hz, the repeat at 750 Hz, a repeated report back to 450 Hz, the 0.1 RR73 completes and logs; (c) no_contact for Enable Tx, row_not_standard for the 0.1 row, state_conflict for the others, Tx1 stays next with Skip Tx1, the activity reads none after the change to FT4 and hound is then state_conflict; (d) nothing changes; while Tune only the Fox frequency is recorded; (e) Enable Tx off with cause txWatchdog at each deadline, not before; the slot stays tx3 after the reply timeout, the re-armed station stays armed past 165 s, tx1 after the Hound watchdog (Tx watchdog not expired), and the expired Tx watchdog returns the slot to tx1; (f) 1500 Hz unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_011 from 'CL-024-04' to 'TC-024-011';
    verification 'TC-024-012' {
        doc /* TC-024-012 — Hound through the station: wire, UDP Status, automation and the 0.1 row reader
             CL-024-04
             Setup: the station fixture over POST /contact/command and GET /contact with its UDP Status; the station's row reader on published 0.1 records; station automation readiness.
             Steps: set_activity hound, then with an exchange; read settings and UDP Status; read a published "HB9BLA RR73; K1ABC <KH7Z> -08" record; start station automation with hound set.
             Expected: settings.activity hound, parity odd, hold_tx true; an exchange is refused invalid_request field exchange; UDP Status special operation 7; the row reader gives the 0.1 fields (RR73 to HB9BLA, report to K1ABC -08, hashed <KH7Z>) and no standard message; automation start not_ready activity.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_012 from 'CL-024-04' to 'TC-024-012';
    verification 'TC-024-013' {
        doc /* TC-024-013 — The Hound choice in the QSO fold-out
             CL-024-04
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded.
             Steps: open the fold-out with settings activity hound; choose Hound from None.
             Expected: the choice offers Hound after RTTY Roundup and shows it; choosing sends set_activity {activity hound} without an exchange; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_04_verified_by_TC_024_013 from 'CL-024-04' to 'TC-024-013';
    verification 'TC-024-014' {
        doc /* TC-024-014 — Hound QSO with a scripted Fox over an audio loopback (no RF)
             CL-024-04
             Setup: the strongest automated equivalent of two station instances over an audio loopback: the Hound is the actual contact engine and #9 transmit owner core on a virtual UTC clock whose hardware double captures the 48 kHz waveform it plays (no PTT, audio device or radio); the scripted Fox synthesizes its FT8 frames (standard texts packed, its 0.1 frames built from their fields) with the station's waveform generator. Each 15 s period is the sum of the frames of that period plus noise at 12 kHz (the Hound's own audio decimated from 48 kHz), decoded by the station's FT8 decoder; the Hound's records pass the station's HashTable (my call, learned calls, the DX call) and row reader, the Fox decodes the Hound's audio with the same decoder. No second process, sound card or virtual cable.
             Steps: Fox "CQ KH7Z BL01" at 800 Hz; the operator selects it and enables Tx with Tx 700 Hz; the Fox answers the decoded Tx1 with "W9XYZ RR73; HB9BLA <KH7Z> -12"; it ignores the first decoded Tx3 for one period and answers the repeat with "HB9BLA RR73; K1ABC <KH7Z> -08".
             Expected: the Fox decodes "KH7Z HB9BLA JN47" in the odd period at a frequency within 1000..2998 Hz (+-3 Hz of the planned random offset); the Hound decodes the 0.1 report with <KH7Z> filled in; the Fox decodes the Hound's "KH7Z HB9BLA R-NN" at 800 Hz (+-3 Hz) and the repeat at 500 Hz; after the 0.1 RR73 the Hound's contact is completed, Enable Tx off and KH7Z logged with RST_RCVD -12; the Hound never transmitted in an even period.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. The level-4 acceptance (two station processes over a physical or virtual audio loopback) and the level-5 on-air QSO with a classic DXpedition are opportunistic and not part of this test. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-04';
        }
        attribute executable : String = "server/src/contact_tests.rs";
    }
    dependency CL_024_04_verified_by_TC_024_014 from 'CL-024-04' to 'TC-024-014';
    // #99 EU VHF contest message: send (#24 S3, operator 2026-11-09).
    requirement 'CL-099-01' {
        doc /* #99. The transmit packer accepts the WSJT-X EU VHF contest message (i3=5) "<CALL1> <CALL2> [R] 5nSSSS GRID6" exactly as WSJT-X 3.3.0-beta5 packs it (two hashed calls of 3-11 characters, report 52-59, serial 0001-2047, 6-character locator), with bits, CRC, parity and tones identical to ft8code and ft4sim, and refuses every shape WSJT-X rejects for this family. Details: WstxTransmit::PackMessage (family euVhf). */
        attribute implementation : String = "server/src/transmit/pack.rs";
        attribute coverage : ImplementationState = ImplementationState::implemented;
    }
    dependency CL_099_01_to_FR_024 from 'CL-099-01' to 'FR-024';
    dependency CL_099_01_to_FR_004 from 'CL-099-01' to 'FR-004';
    requirement 'CL-099-02' {
        doc /* #99. The operator-chosen activity eu_vhf (refused without a 6-character profile locator or with a profile callsign over 11 characters; no contact starts whose two calls exceed 16 characters together, the 37-character limit of Tx3) generates CQ TEST, Tx1 with the full calls, Tx2/Tx3 "<DX> <MYCALL> [R] 5nSSSS GRID6" from the report, the station contest serial and the profile locator's first six characters, sequences on the partner's EU VHF message counted by the hashes of my call and the DX call, makes EU VHF rows selectable, logs STX, SRX, the two-digit RS and the 6-character grid, carries UDP Status special operation 2, answers CQ TEST as its own directive and is offered in the Activity choice. Details: WstxContact::EuVhfExchange. */
        attribute implementation : String = "server/src/contact.rs; server/src/contact_http.rs; server/src/logbook.rs; server/src/mcp.rs; client/contact.js";
        attribute coverage : ImplementationState = ImplementationState::implemented;
    }
    dependency CL_099_02_to_FR_024 from 'CL-099-02' to 'FR-024';
    dependency CL_099_02_to_FR_005 from 'CL-099-02' to 'FR-005';
    verification 'TC-099-001' {
        doc /* TC-099-001 — EU VHF messages pack exactly as WSJT-X
             CL-099-01
             Setup: fixtures/transmit/ft8code-vectors.json and fixtures/transmit/ft4/ft4sim-vectors.json extended by fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe and ft4sim.exe (the independent oracle; the station's code never produces a vector), with EU VHF messages WSJT-X encodes unaltered: "<K1ABC> <HB9BLA> 550001 JN37VL", "<HB9BLA> <K1ABC> R 590003 FN42AX", "<G4ABC/P> <HB9BLA> 522047 IO91NP" (lowest report, highest serial, a /P call), "<PJ4/K1ABC> <HB9BLA> 590123 FK52UD" (a compound call), "<ABC> <ABCDEFGHIJK> 570010 AA00AA" (3 and 11 characters, lowest grid), "<HB9BLA> <K1ABC> 590001 RR99XX" (highest grid) and the lower-case "<k1abc> <hb9bla> 550001 jn37vl"; and shapes it rejects or alters for this family: serials 0000 and 2048, reports 51 and 60 (510001, 600001), a five- and a seven-digit exchange, a 4-character grid, grid "SS00AA", one call without brackets, a call of 2 characters ("<AB> <HB9BLA> 550001 JN37VL") and one of 12 characters in brackets, "X" in place of R, a sixth word, and the 38-character "<K1ABCDEFGHI> <HB9BLA> R 550001 JN37VL" (11 + 6 call characters with R; a direct case against the contract limit, not an oracle vector, since ft8code takes at most 37 characters) beside the 37-character "<K1ABCDEFGH> <HB9BLA> R 550001 JN37VL" (10 + 6), which is encoded.
             Steps: pack and encode every fixture message for FT8 and FT4; read family, i3 and refusal; unpack each packed payload with a hash table that knows the two calls and with none.
             Expected: for every message the oracle encodes unaltered as i3=5 the family is euVhf, i3 5, and bits, CRC, parity and tones (FT8) and bits, codeword and tones (FT4) equal the oracle; the text equals its normalized rendering; the unpack with the table renders the same tokens and with none "<...> <...> R 590003 FN42AX"; every rejected shape is not packed as euVhf (it is refused, or packed in the family the oracle chose, with the oracle's bits); the 38-character message is refused tooLong.
             2 — Isolated automated tests; Windows development PC, no radio, audio, RF or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-01';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs; server/tests/transmit_ft4_vectors.rs";
    }
    dependency CL_099_01_verified_by_TC_099_001 from 'CL-099-01' to 'TC-099-001';
    verification 'TC-099-002' {
        doc /* TC-099-002 — EU VHF contacts through the contact engine and the log
             CL-099-02
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built the way the station builds them (pack, unpack, HashTable fill-in with my call and learned calls, row reader); profile HB9BLA JN37VL; the station fixture over POST /contact/command with its log and UDP Status; the logbook record validation.
             Steps: (a) set_activity eu_vhf, Enable Tx with no partner; the caller "HB9BLA K1ABC FN42" with SNR -6 is answered; the partner sends "<HB9BLA> <K1ABC> R 590007 FN42AX", then "HB9BLA K1ABC 73"; (b) select "CQ TEST W9XYZ EN37" with SNR +3, Enable Tx; the CQer sends "<HB9BLA> <W9XYZ> 590003 EN37AB", then "HB9BLA W9XYZ RR73"; (c) the same as (a) in FT4; (d) not counted while in a contact with K1ABC: an EU VHF message to me from another call, one from K1ABC to another call, one with an unresolved 'from', and an EU VHF message to me while the activity is none; (e) refusals: set_activity eu_vhf with the profile locator JN37 and with an empty locator, with the 12-character profile callsign VP2E/HB9BLAX, and with an exchange; enter_dx of a 12-character DX call; a serial of 2048, then set_report; the profile locator changed to JN37 after the choice during a contact with K1ABC, then set_report -10; select an EU VHF row with an unresolved 'from', and one while the activity is ww_digi; (f) select the EU VHF row "<HB9BLA> <DL1ABC> 590012 JO62QM" addressed to me, and "<W9XYZ> <DL1ABC> R 570004 JO62QM" not addressed to me; edit_message tx2 "<K1ABC> <HB9BLA> 590001 JN37VL" and "<K1ABC> <HB9BLA> 590000 JN37VL"; (g) settings, contact snapshot, UDP Status, the directive of "CQ TEST K1ABC FN42"; validate_record of the logged records and of an RST "51" and "60"; (h) the 37-character limit with my call HB9BLA: enter_dx 3D2AG/K1AB (16 call characters together) and 3D2AG/K1ABC (17), then select a row "CQ 3D2AG/K1ABC" (i3=4); with the activity none, a contact with 3D2AG/K1ABC, then set_activity eu_vhf; (i) the profile locator JN37VL12, set_activity eu_vhf, select "CQ TEST K1ABC FN42" with SNR -6.
             Expected: (a) Tx6 "CQ TEST HB9BLA JN37"; the caller's grid gives Tx2 "<K1ABC> <HB9BLA> 550001 JN37VL" (report -06, n 5); the R exchange moves to Tx4 "K1ABC HB9BLA RRR", exchange_rcvd "590007 FN42AX", dx_grid FN42AX; after the 73 the contact completes and the record has GRIDSQUARE FN42AX, STX 0001, SRX 0007, RST_SENT 55, RST_RCVD 59, no STX_STRING/SRX_STRING; settings.serial 2; (b) the selection starts with Tx1 "W9XYZ HB9BLA JN37" (Tx1 enabled); the exchange moves to Tx3 "<W9XYZ> <HB9BLA> R 560002 JN37VL" (report +03, n 6); after RR73 Tx5 "W9XYZ HB9BLA 73" is sent, completed, STX 0002, SRX 0003; (c) the same texts with Tx4 RR73 and FT4 requests; (d) nothing changes; (e) profile_incomplete field locator (twice), invalid_call field callsign and invalid_request field exchange, the activity unchanged each time; invalid_call; out_of_range field serial for set_report, the report and messages unchanged; profile_incomplete field locator for set_report -10, the report and all six messages unchanged; row_not_standard (twice); (f) DL1ABC with dx_grid JO62QM, exchange_rcvd "590012 JO62QM" and first slot tx3; then DL1ABC from the second row with first slot tx1 and exchange_rcvd null; the valid edit is accepted unaltered, serial 0000 invalid_message; (g) settings.activity eu_vhf with exchange null and the serial, contact exchange_sent/exchange_rcvd, UDP Status special operation 2, the CQ TEST answerable without directive_confirmed; the records are valid, RST "51" and "60" are refused; (h) 3D2AG/K1AB is accepted and its Tx3 "<3D2AG/K1AB> <HB9BLA> R 530001 JN37VL" has 37 characters and packs; 3D2AG/K1ABC is refused invalid_call by enter_dx and by the selection, no contact starts and the previous one is unchanged; set_activity eu_vhf is refused invalid_call field dx_call and the activity stays none; (i) Tx6 "CQ TEST HB9BLA JN37", Tx1 "K1ABC HB9BLA JN37", Tx2 "<K1ABC> <HB9BLA> 550001 JN37VL".
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/strategy_tests.rs";
    }
    dependency CL_099_02_verified_by_TC_099_002 from 'CL-099-02' to 'TC-099-002';
    verification 'TC-099-003' {
        doc /* TC-099-003 — The EU VHF choice in the QSO fold-out
             CL-099-02
             Setup: the browser fixture of the operating screen with a hand-written contact snapshot; contact commands are recorded; a recorded refusal reply.
             Steps: open the fold-out with settings activity eu_vhf, serial 12; choose EU VHF from None; answer the choice with the refusal profile_incomplete field locator.
             Expected: the choice offers EU VHF after NA VHF and shows it; the next serial 0012 is shown and the Exchange entry is not sent; choosing sends set_activity {activity eu_vhf} without an exchange; the refusal is shown in the error field and the choice returns to the station's setting; nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-099-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_099_02_verified_by_TC_099_003 from 'CL-099-02' to 'TC-099-003';
    verification 'TC-099-004' {
        doc /* TC-099-004 — EU VHF QSO with a WSJT-X station on the air
             CL-099-01, CL-099-02
             Setup: HB9BLA IC-7300 at 1 W on 10, 15, 20 or 40 m (the antenna's bands), profile locator JN37VL, eu_vhf chosen, during a contest that uses EU VHF (SARL HF Digital, WIA Ross Hull) or a scheduled partner running WSJT-X in EU VHF Contest mode.
             Steps: call CQ TEST and complete a QSO with a caller; answer a CQ TEST and complete a QSO.
             Expected: the partner's WSJT-X decodes the station's Tx2/Tx3 with both calls resolved and moves on them; both QSOs complete and are logged with STX, SRX, RS and the partner's 6-character locator; the partner's log (or the contest's log check) shows my serial and JN37VL.
             5 — Tests with external effects and explicit operator consent; HB9BLA radio PC, physical IC-7300. Opportunistic, not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-099-01';
            verify 'CL-099-02';
        }
    }
    dependency CL_099_01_verified_by_TC_099_004 from 'CL-099-01' to 'TC-099-004';
    dependency CL_099_02_verified_by_TC_099_004 from 'CL-099-02' to 'TC-099-004';
    requirement 'CL-063-01' {
        doc /* The station holds one profile per contest from the official rules: WW Digi, ARRL Digi, ARRL Field Day, ARRL January, June and September VHF, IARU R1 50 MHz and 70 MHz MGM and FT8 Activity, usable everywhere in the world; a limit that depends on the location or the entry class is a note, not a refusal. Each profile holds the schedule rule, bands, modes, exchange, dupe, points and multiplier rules, the automation clause as the rules word it, notes and the source, as data, so that a new contest is one more entry. Its period is pre-computed from the schedule rule for the current or next occurrence; ARRL January VHF is not computed. GET /strategy/contests reads them. Details: WstxContest::ContestProfile, ScheduleRule, AutomationClause, ProfileTable, ContestHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; server/src/main.rs";
    }
    dependency CL_063_01_to_FR_024 from 'CL-063-01' to 'FR-024';
    requirement 'CL-063-02' {
        doc /* In a contest activity a CQ with the activity's own word (na_vhf, eu_vhf (#99) and arrl_digi CQ TEST, ww_digi CQ WW, field_day CQ FD, rtty CQ RU) is answerable: it is no longer greyed and an operator's selection needs no confirmation. Outside the matching activity it stays not answerable, with the warning of CL-039-03. Details: WstxContest::ContestDirective, WstxStrategy::DirectedCqRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/contact.rs";
    }
    dependency CL_063_02_to_FR_024 from 'CL-063-02' to 'FR-024';
    dependency CL_063_02_to_FR_007 from 'CL-063-02' to 'FR-007';
    verification 'TC-063-001' {
        doc /* TC-063-001 — The profile table
             CL-063-01
             Setup: the profile table as compiled; an expected table written by hand from the rule sources listed on #63.
             Steps: read id, activity, dupes, points, multipliers, automation clause, bands, Cabrillo mark and the notes of each profile.
             Expected: the nine ids in selector order; WW Digi bands 160 to 10 m, dupes per band, 1 + 1 per 3000 km, grid field per band, forbidden; ARRL Digi with 6 m, 1 + 1 per 500 km rounded up, no multiplier, forbidden; Field Day per band and mode class, forbidden, check-log note, Cabrillo unconfirmed; the three VHF per band and grid, grid per band, forbidden, W/VE note; Field Day and VHF with every ADIF band from 50 MHz (6 m, 5 m, 4 m, 2 m up to submm); IARU 6 m and 4 m, kilometres, grid per band, silent, 6 hours note; FT8 Activity 2 m, 70 cm, 23 cm, one per call, silent; no RTTY Roundup; no id twice.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_001_the_profile_table_holds_the_rule_facts";
    }
    dependency CL_063_01_verified_by_TC_063_001 from 'CL-063-01' to 'TC-063-001';
    verification 'TC-063-002' {
        doc /* TC-063-002 — The period from the schedule rule
             CL-063-01
             Setup: instants chosen by a calendar, not by the code.
             Steps: the current or next occurrence of each profile at 2026-01-01; WW Digi during and at the end of its period; WW Digi 2024 and ARRL Digi 2025 for the full-weekend edge; FT8 Activity at the start and between its rounds and across the year end.
             Expected: WW Digi 2026-08-29 12:00 to 08-30 12:00, ARRL Digi 2026-06-06 18:00 to 06-08 00:00, Field Day 2026-06-27 18:00 to 06-28 21:00, June VHF 2026-06-13 18:00 to 06-15 03:00, September VHF 2026-09-12 18:00 to 09-14 03:00, IARU 2026-04-18 and 2026-05-16 14:00 to 14:00, end exclusive; January VHF none; at the end the next year's 2027-08-28; 2024-08-24 and 2025-06-07; FT8 Activity 2026-11-04 2 m, 11-11 70 cm, 11-18 23 cm, 2027-01-06 2 m, 17:00 to 21:00.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_002_the_period_comes_from_the_rule";
    }
    dependency CL_063_01_verified_by_TC_063_002 from 'CL-063-01' to 'TC-063-002';
    verification 'TC-063-003' {
        doc /* TC-063-003 — GET /strategy/contests
             CL-063-01
             Setup: the pure list at 2026-08-01; the actual station router on a disposable selected HTTPS profile with one grant.
             Steps: the list; GET with the browser cookie, without credentials and with a query; POST.
             Expected: the nine ids in order, WW Digi with period {2026-08-29T12:00Z, 2026-08-30T12:00Z, band null}, its activity and rule names; January VHF period null; the route returns v 1, the profile id and the list with a period that has not ended; 401 unauthorized; 400 invalid_request; 405.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-01';
        }
        attribute executable : String = "server/src/contest_tests.rs::tc_063_003_the_list_names_each_profile_with_its_period; server/src/strategy_tests.rs::tc_063_003_the_contests_route";
    }
    dependency CL_063_01_verified_by_TC_063_003 from 'CL-063-01' to 'TC-063-003';
    verification 'TC-063-004' {
        doc /* TC-063-004 — The directive rule in a contest activity
             CL-063-02
             Setup: a hand table of activity, directive and answerable; the actual router with an injected FT8 live job for the selection.
             Steps: the table with EU and NA continents and with my continent unknown; the verdict of CQ WW K1ABC with and without the activity; the browser's select_row of that row in none and in ww_digi.
             Expected: TEST answerable in na_vhf and arrl_digi only, WW in ww_digi, FD in field_day, RU in rtty, not in another activity or hound; NA stays not answerable and EU answerable in an activity; greyed without the activity, rank 0 with it; 409 directive_not_answerable in none, accepted in ww_digi without directive_confirmed.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_004_the_directive_table_in_a_contest_activity; server/src/strategy_tests.rs::tc_063_004_a_selection_of_the_activitys_cq_needs_no_confirmation";
    }
    dependency CL_063_02_verified_by_TC_063_004 from 'CL-063-02' to 'TC-063-004';
    requirement 'CL-063-06' {
        doc /* The safety of a contest run stays on the server and is that of a strategy run: HALT from any source ends it and turns Auto off (the contest stays), Abort QSO (Esc) ends the QSO only, the Tx watchdog stops its CQ, with no client for 60 s or after 8 hours it starts nothing new, finishes the QSO in progress and its own CQ ends at once, only the browser's Auto on starts it, and a double-click is a manual intervention it resumes after. Details: WstxContest::ContestRun, WstxStrategy::StrategyRun, AutoToggle, ManualIntervention, WatchdogFromOperator. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/automation.rs; server/src/strategy.rs";
    }
    dependency CL_063_06_to_FR_024 from 'CL-063-06' to 'FR-024';
    dependency CL_063_06_to_FR_020 from 'CL-063-06' to 'FR-020';
    verification 'TC-063-011' {
        doc /* TC-063-011 — The safety of a contest run
             CL-063-06
             Setup: as TC-063-010, the run calling CQ with Auto on.
             Steps: an MCP configure with strategy true; a browser's replace selection of a CQ; Abort; HALT by route; Auto on, the clock past 8 hours; Auto on, every session gone and the clock past 60 s; Auto on, then Auto off, then Auto on; a watchdog limit of 2 with two CQs sent, the third period and a caller; Auto on, Enable Tx off, Auto off, Auto on.
             Expected: operator_required; manual with the operator's contact; after Abort calling_cq; halted, Auto off, the contest and its strategy kept, disarmed; run_limit and no_client, disarmed, Auto off, the contest selected with its strategy; stopped and disarmed at Auto off, calling_cq again with no CQ left behind; tx_watchdog, not keyed again, still disarmed with the caller, Auto off, the contest selected with its strategy; transmit_stopped, then calling_cq again.
             2 — Isolated automated functional tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-063-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs::tc_063_011_the_safety_of_a_contest_run_stays_on_the_server; server/src/strategy_tests.rs::tc_063_011_the_tx_watchdog_stops_a_run_on_a_silent_band";
    }
    dependency CL_063_06_verified_by_TC_063_011 from 'CL-063-06' to 'TC-063-011';
    requirement 'CL-097-02' {
        doc /* (#97 decisions 1 and 2, ranking only) Band: off the strategy's bands (all by default) every verdict has rank null, why "band not in the strategy" or "band unknown"; it never switches bands. Filters, every line must hold: what must be new (DXCC entity, call, grid, CQ zone, ITU zone, continent, prefix; any chosen one counts) per ever, band or band and mode, new meaning not worked or not confirmed (QSL/LoTW); region; minimum SNR; worked since (any time, today, from-to); Treat 73 as CQ; prefix/country include and exclude lists (an entry optionally per band; country names from the country table); US state include and exclude (the state from the message exchange where it carries one, else the log's STATE, a confirmed record first; unknown fails an include list; FCC/ISED and grid are #101); CQ target include and exclude (POTA, SOTA, EU, DX ...; a word on the include list makes that CQ's verdict not grey for this strategy: Band Activity marks it without strike-through, and Alert records it; the operator's own selection keeps its warning). Callers of my call must pass the filters too; a started QSO is always finished (#81). A contest strategy applies its contest's verdict first, then the country, US state and CQ target lists. Each failing line is named in the verdict's reason. Details: WstxStrategy::StrategyBands, Candidate, NewNeeded, CallerOfMyCall, CountryList, UsStateFilter, UsStateOf, CqTargetList, Verdict. */
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/automation.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_02_to_FR_007 from 'CL-097-02' to 'FR-007';
    dependency CL_097_02_to_FR_011 from 'CL-097-02' to 'FR-011';
    requirement 'CL-097-03' {
        doc /* (#97 decision 3) Order: dropdown rows of criteria, the first decides and the next breaks a tie: Most wanted (Club Log rank); New DXCC, on band, on band and mode; New call, on band; New grid, on band; New CQ zone; New ITU zone; New continent; New prefix; SNR bucket (above 0 dB, -10..0 dB, below -10 dB); SNR (stronger first); Distance (farthest first); Hears us first (a PSK Reporter spot of my call at that station at most 600 s old). Then always SNR, then for an exact tie the lower audio frequency and the call; decode order is never a ranking. With "Calling stations are answered" on, the callers that pass the filters come first, ranked among themselves; with it off a caller of my call has rank null, why "calls my call · not answered" (decided as WSJT-X, whose CQ response None answers no caller automatically and whose "Calling CQ forces Call 1st" is off by default). A contest strategy has no order: it ranks by ContestValueOrder, under the same rule for callers. Details: WstxStrategy::ValueOrder, ValueCriterion, CallerOfMyCall, Verdict; WstxContest::ContestValueOrder. */
        attribute implementation : String = "server/src/strategy.rs; server/src/contest.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_03_to_FR_007 from 'CL-097-03' to 'FR-007';
    requirement 'CL-097-05' {
        doc /* (#97 decision 6, operator #94 and #90) Tx frequency while a run calls a target that has not answered, per PSK Reporter case (he reports and hears us; he reports and does not hear us; he does not report or it is unknown): stay, move every call, or move every n-th call (a busy-paused call not counted). A move goes to another quiet slot (never the current one), never within 50 Hz of a frequency he reports decoding in my Tx parity (no fallback: with none left Tx stays and it is tried at the next call), never below 500 Hz; Hold Tx on moves Tx alone, off Rx and Tx together; after his answer Tx never moves in that exchange. Auto never chooses a slot below 500 Hz; the upper edge (a signal reaching above 2400 Hz) is allowed but loses every tie. The open-slot marks still mark from 300 Hz. Details: WstxStrategy::TxMoveRule, FreeTxSlot, HearingFeed, PskrUse. */
        attribute implementation : String = "server/src/automation.rs; server/src/freeslot.rs; server/src/pskr.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_05_to_FR_007 from 'CL-097-05' to 'FR-007';
    dependency CL_097_05_to_FR_020 from 'CL-097-05' to 'FR-020';
    verification 'TC-097-004' {
        doc /* TC-097-004 — The strategy's bands
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and hand-authored codec-packed rows; a strategy with bands ["20m", "40m"]. The run's steps off the bands are TC-097-018's.
             Steps: evaluate with the station band 20m, 15m and unknown; the same strategy with bands null on 15m.
             Expected: on 20m the candidates ranked; on 15m every verdict rank null with why "band not in the strategy", unknown "band unknown"; bands null ranks on 15m. Red on the parent: bands is refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_02_verified_by_TC_097_004 from 'CL-097-02' to 'TC-097-004';
    verification 'TC-097-005' {
        doc /* TC-097-005 — What must be new, new per, new means and worked since
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and a hand log (worked and confirmed QSOs per band, mode and date, with and without grid) for HB9BLA JN37VL on 20m FT8; the expected verdicts hand-worked in the test from the log and the cty.dat entries.
             Steps: each NewWhat alone with each new_per and each new_means: dxcc; call; grid (no grid in the message, a logged QSO without grid); cq_zone; itu_zone (an entity whose cty.dat entry overrides the ITU zone); continent; prefix (the WpxPrefix table cases); two whats (either counts); worked_since today and from_to with an undated record; region dx and selected; min_snr_db; treat_73_as_cq on and off; the station band unknown with new_per band.
             Expected: the hand-worked tables: each what new exactly where the log lacks its key per the chosen per and means; D13 grid rules; the override zone used; an undated record counts only for any time; band unknown: nothing new per band or band_mode; RR73 to another counted as calling only with treat_73_as_cq. Red on the parent: the keys are refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_02_verified_by_TC_097_005 from 'CL-097-02' to 'TC-097-005';
    verification 'TC-097-006' {
        doc /* TC-097-006 — Country, US state and CQ target lists
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture; a hand log with STATE fields (W6ABC: a confirmed record STATE CA and a newer unconfirmed STATE NV); rows CQ POTA K1ABC FN42, CQ SOTA W7XYZ DN31, CQ DX JA1XYZ PM95, CQ EU DL1XYZ JO62, plain CQ W6ABC CM87, CQ VE3ABC FN03, an RTTY Roundup exchange of K1RU carrying MA, CQ K9NOR EN52 with no log record; a VK9 call and a call of Lord Howe Island; the station band 20m then 40m.
             Steps: countries include [prefix VK9]; include [country "Lord Howe Island"]; include [prefix DL, bands [40m]] on 20m and on 40m; exclude [country "United States"]; include [prefix W] with exclude [prefix W6]; a PUT with country "Atlantis"; states include [CA]; include [MA]; exclude [CA]; cq_targets include [POTA]; exclude [DX]; the built-in POTA/SOTA on the same rows with K1ABC also logged on 20m yesterday and W7XYZ logged on 20m today; the Band Activity rows and the alert history under POTA/SOTA and under another strategy (browser case with routed verdicts). The run's own select_row of CQ POTA and the directive refusals are TC-097-018's.
             Expected (hand-worked from WstxStrategy::CountryList, UsStateFilter, UsStateOf, CqTargetList): prefix by the start of the call, country by the entity; the DL entry only on 40m; exclude wins over include; "Atlantis" refused 400 at its field path; CA for W6ABC (confirmed before newer unconfirmed), MA for K1RU from the exchange; K9NOR (unknown) and VE3ABC fail include and pass exclude; with include [POTA] only CQ POTA is ranked (answerable for the strategy although DirectedCqRule greys it), the plain CQ and CQ DX fail with why "CQ target"; exclude [DX] fails CQ DX only; POTA/SOTA ranks K1ABC (worked yesterday, new today; grey false) and not W7XYZ (worked today, "not new"), and nothing else of the rows; in Band Activity the CQ POTA row marked and not struck through under POTA/SOTA, struck through under the other strategy; one alert for K1ABC under POTA/SOTA. Red on the parent: the lists are refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_02_verified_by_TC_097_006 from 'CL-097-02' to 'TC-097-006';
    verification 'TC-097-007' {
        doc /* TC-097-007 — Callers of my call pass the filters and are answered only when Calling stations are answered is on
             CL-097-02, CL-097-03
             Setup: the evaluator with the pinned cty.dat fixture, HB9BLA on 20m; the built-in Casual (call, per band, not worked; Calling stations are answered on); a log with W1AW worked on 20m; rows HB9BLA W1AW FN31 (+5), HB9BLA N1NEW FN31 (-9), CQ K1ABC FN42 (-1). The run's steps with callers are TC-097-018's.
             Steps: evaluate Casual; the same with Calling stations are answered off and order [snr]; a caller failing region dx, min SNR -5, a country exclude, a state include.
             Expected (oracle: the operator's decision 2 on #97, CL-097-03, WstxStrategy::Verdict; WSJT-X with the CQ response None answers no caller automatically, widgets/mainwindow.cpp 7481-7496): W1AW rank null, why "calls my call · not new"; N1NEW first with callers on, then K1ABC; with callers off N1NEW has rank null, kind none, why "calls my call · not answered", and K1ABC alone is ranked; each failing caller names its line ("calls my call · region", "· below min SNR", "· country list", "· state list"). Red on the parent: with callers off N1NEW is ranked by SNR after K1ABC.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-02';
            verify 'CL-097-03';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    dependency CL_097_02_verified_by_TC_097_007 from 'CL-097-02' to 'TC-097-007';
    dependency CL_097_03_verified_by_TC_097_007 from 'CL-097-03' to 'TC-097-007';
    verification 'TC-097-008' {
        doc /* TC-097-008 — The order criteria
             CL-097-03
             Setup: the evaluator with the TC-039-040 rows extended by stations at SNR +1, 0, -10, -11 and unknown; a feed without a connection fed hand-authored spots of my call at JA1XYZ and VK2ABC; the expected orders hand-worked in the test (distances by the haversine formula written there).
             Steps: order [snr_bucket]; [snr_bucket, distance]; [hears_us] with PskrUse on and off; [new_cq_zone], [new_itu_zone], [new_continent], [new_prefix], [new_dxcc_band_mode] each before [snr]; [most_wanted, snr]; a contest strategy evaluated; the WW Digi built-in (contest_tests: WW Digi in force on 20m, K1OLD logged in the period) with CQ WW JA1XYZ PM95, the non-dupe caller HB9BLA VK2ABC QF56 and the dupe caller HB9BLA K1OLD FN20, with Calling stations are answered on and off.
             Expected: +1 first; 0 and -10 in the middle bucket; -11 last; unknown after them; inside a bucket SNR, frequency, call (alone) or farthest first (with distance); JA1XYZ and VK2ABC first with PskrUse on, the plain SNR order with it off; each new criterion puts the new stations first with SNR order inside; the contest strategy ranks by ContestValueOrder; decode order never changes an order. WW Digi: on, VK2ABC rank 0 and JA1XYZ rank 1; off, VK2ABC rank null with why "calls my call · not answered" and JA1XYZ rank 0; K1OLD rank null either way. Red on the parent: with callers off the non-dupe caller VK2ABC keeps a rank (ranked among the others).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-03';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/contest_tests.rs";
    }
    dependency CL_097_03_verified_by_TC_097_008 from 'CL-097-03' to 'TC-097-008';
    verification 'TC-097-010' {
        doc /* TC-097-010 — Tx moves per PSK case and Auto's slot choice
             CL-097-05
             Setup: as TC-039-022 (the actual router, contact engine and #9 owner on the recording hardware double, virtual UTC, a dial of 14074000 Hz, hand-authored waterfall rows on a flat floor of 20 with raised bands), a feed without a connection fed hand-authored spots (of my call at K1ABC; of other senders received by K1ABC at given offsets and parities); Hold Tx on and off; FT8 and FT4; the run calling K1ABC (CQ at 1800 Hz) from Tx 1500; the slot tables written in the test.
             Steps: case heard (a spot of my call 60 s old); case not_heard (K1ABC reports another sender 120 s ago, and 600 s ago, no spot of my call); K1ABC's only report 601 s old (no_reports); case no_reports (no spot; PskrUse off; the feed off; a call with a slash); each with tx_move_every {0, 0, 0}, {1, 1, 1}, {2, 2, 2} and {0, 1, 2} over 6 calls; a move whose quietest slot is the current one; a move whose quiet candidates all lie within 50 Hz of his reported frequencies of my Tx parity; his reported frequency in the other parity; free slots at 400, 480 and 520 Hz only; free slots at 1700 and 2420 Hz of equal value; 2420 strictly quieter than 1700; FT8 free slots only at 2350 (signal to 2400 Hz) and 2360 (to 2410 Hz) of equal value, the current Tx 2400; a held Tx at 400 (Hold Tx on) at the selection and at a move; the case changing from no_reports to heard after the 1st call; K1ABC answering after the 2nd call; a busy-paused call between two calls.
             Expected (hand-worked from WstxStrategy::TxMoveRule and FreeTxSlot): slot_check.case not_heard for the reports 120 s and 600 s old, no_reports for the one 601 s old; k 0 never moves; k 1 moves at every call and k 2 at every second, each move to another slot than the current (never overlapping it), never within 50 Hz of his frequency of my Tx parity; all candidates near his frequencies: Tx stays, slot_check moved false, tried again at the next call; the other parity's frequency does not exclude; 520 chosen, never 400 or 480; 1700 over 2420 on the tie, 2420 when strictly quieter; 2350 (not the upper edge) over the nearer 2360 (upper edge); the held 400 kept at the selection and moved into 500..2650 at a move; after the case change to heard no move; no move after the answer; the paused call not counted toward k; Hold Tx on moves Tx alone with Rx on K1ABC, off both; slot_check carries case, hears_us, moved and hz; the open-slot marks (FreeTxSlots) still list an open range below 500 Hz. Red on the parent: moves at every call regardless of the case, 400 chosen, 2420 on the tie.
             2 — Isolated automated tests; Windows development PC, transmit and radio doubles; no RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-05';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/freeslot_tests.rs; server/src/pskr_tests.rs";
    }
    dependency CL_097_05_verified_by_TC_097_010 from 'CL-097-05' to 'TC-097-010';
    dependency CL_097_02_verified_by_TC_097_016 from 'CL-097-02' to 'TC-097-016';
    dependency CL_097_03_verified_by_TC_097_016 from 'CL-097-03' to 'TC-097-016';
    dependency CL_097_05_verified_by_TC_097_016 from 'CL-097-05' to 'TC-097-016';
    dependency CL_097_02_verified_by_TC_097_019 from 'CL-097-02' to 'TC-097-019';
    dependency CL_097_03_verified_by_TC_097_019 from 'CL-097-03' to 'TC-097-019';
}
