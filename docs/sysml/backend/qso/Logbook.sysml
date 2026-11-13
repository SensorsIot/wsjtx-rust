package WstxLogbook {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-011';
    private import WstxRequirements::AutomationState;
    private import WstxStandardQso::'TC-007-007';
    private import WstxRequirements::'FR-016';
    private import WstxContact::'CL-011-04';
    private import WstxStandardQso::'CL-010-02';
    private import WstxContact::'CL-010-17';
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
        doc /* Log every completed contact directly, without a review step (#41, as WSJT-X): at completion and on a manual Log QSO the server stores the contact's record in the profile directory's ADIF 3.1.8 contacts.adi with its contact identity and sends it to the WSJT-X UDP targets as QSO Logged and Logged ADIF; exactly one record per contact identity (an identical re-log adds nothing, completion after an early Log QSO replaces it; each contact is sent to the UDP targets once), a later contact with the same station a new record, Saved only after durable acknowledgement, a failed write visibly unsaved and retried; ADI export and history with the stated limits; and (#10, operator 2026-11-03) Update logbook from ADIF, the one ADI import: an export of another logger (for example Log4OM) is consolidated into the contact log, repeatable and incremental, a record already present (same contact identity, or same call, band and mode/submode with a start within 2 minutes) adding nothing and the stored record winning, only the log's own fields kept, added records marked with their source, QSO confirmation status (LoTW, QSL and eQSL received with their dates and via) kept and, on a rerun, upgraded on records already present (a confirmation is only added, never removed; #10, operator 2026-11-04), so worked-before and award queries tell worked from confirmed per entity, band and mode, invalid records skipped and invalid optional fields dropped with their reasons in the summary, nothing sent to the UDP targets or elsewhere, and the added records feeding worked-before, DXCC and grid status. The former log review queue (OfferLogReview, discard_review, the review form) is retired. Details: WstxLogbook::LogRecord, DirectLog, SaveContact, UpdateLogbook, ExportAdi, ContactHistory, AdiLimits, WorkedBeforeQuery; WstxUdp::OutboundRules. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/logbook.rs; server/src/logbook_http.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/main.rs; client/logbook.js; client/contact.js";
    }
    dependency CL_010_04_to_FR_011 from 'CL-010-04' to 'FR-011';
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
    dependency CL_010_04_verified_by_TC_011_001 from 'CL-010-04' to 'TC-011-001';
    dependency CL_010_04_verified_by_TC_011_002 from 'CL-010-04' to 'TC-011-002';
    dependency CL_010_04_verified_by_TC_007_007 from 'CL-010-04' to 'TC-007-007';

    // Saved Auto Seq and Call 1st (WstxContact::QsoSettingsFile).
    requirement 'CL-110-01' {
        doc /* Auto Seq and Call 1st are kept per profile across station starts (WstxLogbook::QsoSettingsFile). (1) At a station start the two settings have the values last saved for the selected profile. When nothing usable is saved, both are on. (2) An accepted set_auto_seq or set_call_first is saved before its receipt is returned, whichever client sent it (browser or MCP). After the receipt, a station start on the same profile directory has that value. (3) A value is saved whether it is on or off: after off and on again, the next start has on because on was saved, not because nothing is there. (4) When the save fails, the command is refused storage_unavailable with field null; the setting, the snapshot and contact_revision are unchanged, and the earlier saved values stay as they were. The same command sent again with a new command_id saves once storage is available. In the browser, after a refused set_auto_seq or set_call_first the checkbox shows the station's value again, not the clicked one, in the same step that shows the refusal. (5) Saving does not change the profile document: its revision does not advance. (6) Another profile never has these values: a profile directory holds only its own. (7) Starting with saved values changes nothing else: the transmit state (WstxTransmit::TransmitArming) is off with cause startup, no contact exists, and no TransmitRequest is planned until a start action (enable_tx). (8) Every other setting of ContactSnapshot settings (tx1_skip, tx_calls, tune_seconds, rx_hz, tx_hz, hold_tx, parity, report, activity, exchange, serial) is not saved and has its stated start value at every station start. Details: WstxLogbook::QsoSettingsFile, Contact. */
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
             Expected (the WstxLogbook::QsoSettingsFile format): (a), (b) auto_seq false, call_first true. (c) to (i) both true in each. (j) the station start succeeds and GET /contact returns 200; the command returns 202, the file is the exact object with auto_seq true and call_first false, and the new station start has those values.
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
    verification 'TC-007-008' {
        doc /* TC-007-008 — FT4 contact, logging and mixed-mode isolation
             CL-011-03, CL-011-04
             Setup: the contact engine against the actual #9 transmit owner core on a
             virtual UTC clock with a recording hardware double (no audio, PTT or
             radio); the actual router with live FT4 and FT8 fixture jobs; two
             independent station fixtures at once; profile HB9BLA/JN47; hand-authored
             rows packed with the real codec.
             Steps: (a) FT4 responder: select "CQ K1ABC FN42" (even FT4 period P0,
             -12.4 dB, 1234.6 Hz), Enable Tx, feed "HB9BLA K1ABC -05" and
             "HB9BLA K1ABC RR73" in the partner's FT4 periods; (b) FT4 caller: CQ, select
             the "HB9BLA K1ABC FN42" reply, feed "HB9BLA K1ABC R-07"; set_tx4 rrr; Tx
             2916 and 2917 Hz; (c) an FT4 row reaching an FT8 contact; (d) switch the
             station mode with an armed FT8 contact and a pending request and a
             2940 Hz Tx offset, and with a completed unsaved FT8 contact, then Enable Tx
             in FT4; (e) an FT4 and an FT8 station prepare and review contacts at the
             same time; (f) the FT8 contact tests of TC-007-001 unchanged; (g) an armed
             FT8 request pending, the station mode set to FT4 in the #9 owner only, the
             owner run across the period start without any contact step, then a new FT8
             request; (h) #11 IW9FRA replay (live 2026-11-02 13:44-13:46 UTC): select
             "CQ IW9FRA JM68" (+10 dB, 1838 Hz, even period P0), Hold Tx at 2439 Hz,
             Enable Tx, partner rows "+10", "+10", then three "RR73" (or "73") in the
             partner's periods, counted +6.7, +7.0, +7.3 s and +8.2 s after their period
             start, with and without the operator re-selecting the first "+10" row; the
             same in FT8 with RR73, RRR and 73; the same FT4 sequence through the station
             step and router on a virtual UTC (records published +7.0 s); (i) the same
             FT4 sequence with Auto Seq off, Tx3 chosen by the operator, then the offered
             Tx5 chosen; (j) the QSO pane (stubbed snapshot) with Auto Seq off in
             roger_report, without and with suggested_slot tx5.
             Expected (independent hand-written values): (h) transmissions Tx1
             "IW9FRA HB9BLA JN47" in my period 1, "R+10" in 3 and 5, "73" in 7, then
             completed with Enable Tx off and one completion log (IW9FRA, JM68, sent and
             received +10); counted after my audio start (+8.2 s) each message goes out one
             of my periods later (Tx1 1 and 3, R+10 5 and 7, 73 9); a re-selection keeps
             grid JM68; (i) every counted message keeps the state, TIME_OFF follows each
             counted RR73, suggested_slot tx3 after the report and tx5 after each RR73,
             choose_next clears it, 73 is sent in period 9 and the contact completes;
             (j) the "Auto Seq off" line (warning style), then "Send 73
             next" (title "Send IW9FRA HB9BLA 73 next") sending choose_next tx5 and
             enable_tx; at 1366x768 no page scroll and, in the compact QSO pane (#37, no
             Last row), the line, the 73 and Log QSO buttons fully visible; no horizontal
             overflow at 360 px; Auto Seq on sending set_auto_seq true; the line hidden
             with Auto Seq on and nothing offered. (j) runs in headless Chromium against
             the actual server binary with a stubbed contact snapshot. A manual entry of
             the same partner without a grid clears the grid (only a decoded row keeps it).
             Expected for (a)-(g) (independent hand-written values): (a) Tx4 text
             "K1ABC HB9BLA RR73", transmissions only in odd FT4 periods P0+7.5 s,
             P0+22.5 s, P0+37.5 s with audio 300 ms after the period start and 241920
             samples at 48 kHz, states replying -> rogerReport -> signoff -> completed
             after the completed Tx5, one log offer with mode FT4, TIME_ON P0+15 s (one
             7.5 s period before the first Tx3), TIME_OFF P0+45 s, review MODE MFSK
             SUBMODE FT4; (b) report/Tx2 -> rogers/Tx4 RR73 -> completed on the
             completed RR73 transmission; set_tx4 rrr refused out_of_range field form
             with tx4 unchanged; 2916 accepted, 2917 refused out_of_range; (c) no state
             change; (d) Enable Tx off with DisarmCause contactCancelled, no key after
             the switch, contact cancelled, Tx offset 2916, the completed contact's
             review kept with MODE FT8, a later CQ transmitted in FT4 periods;
             (e) each station keeps its own contact, messages, arm state and review mode
             (FT4 MFSK/FT4, FT8 FT8); (f) FT8 results identical to TC-007-001; (g) no
             PTT key and no audio, the pending request refused staleRequest and Enable
             Tx off, the new FT8 request refused staleRequest.
             2 — Isolated automated functional tests; Windows development PC, actual
             engine, #9 owner core and router, independent row and outcome fixtures; no
             RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-011-03';
            verify 'CL-011-04';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; tests/ui-operating.test.cjs";
    }
    verification 'TC-110-004' {
        doc /* TC-110-004 — The restored values govern the station
             CL-110-01, CL-010-17, CL-010-02
             Setup: the contact engine against the actual transmit owner core on a virtual UTC clock (contact_tests), profile HB9BLA JN47, the engine as a station start creates it on a profile directory holding a hand-written qso-settings.json; hand-authored rows. For the strategy step the station with a strategy run (strategy_tests).
             Steps: (a) saved call_first false; Enable Tx with no partner (own CQ); "HB9BLA EA4HTI IM69" in the partner's period. (b) saved call_first true, the same row. (c) saved auto_seq false; a contact with K1ABC in replying, Enable Tx on; "HB9BLA K1ABC -05". (d) saved both true, and saved both false: 3 own periods without a start action. Also: saved auto_seq false; a strategy switched to Auto.
             Expected (WstxStandardQso::CallFirst, AutoSequence, CL-009-04): (a) still calling, the next own period sends "CQ HB9BLA JN47". (b) EA4HTI in report with Tx2 next, as TC-010-010. (c) state and next slot unchanged, suggested_slot tx3. (d) directly after the start the transmit state is off with cause startup, no contact exists, and no TransmitRequest appears in the 3 own periods (guard of CL-009-04). Also: the run is waiting with reason auto_seq (guard of the automation readiness).
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-110-01';
            verify 'CL-010-17';
            verify 'CL-010-02';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/strategy_tests.rs";
    }
    attribute def QsoSettingsFile {
        attribute schemaVersion : Integer = 1;
        attribute profileId : String;
        attribute autoSeq : Boolean;
        attribute callFirst : Boolean;
        attribute bytesMax : Integer = 256;
        doc /* CL-110-01. The saved Auto Seq and Call 1st of one profile: qso-settings.json
             in the selected profile directory, exactly {schema_version, profile_id,
             auto_seq, call_first}: schema_version the integer 1, profile_id the profile's
             UUID, auto_seq and call_first JSON booleans; at most bytesMax bytes; written
             atomically like udp.json (WstxUdp::UdpConfiguration) under the profile's own
             lock (WstxProfiles), so that saving it does not advance the profile revision.
             A missing file leaves both at the start values of Contact. So does a file
             that is unreadable, larger than bytesMax bytes, not this exact object, of
             another schema_version or of another profile_id: the station starts as
             usual, no error is displayed, and the next accepted set_auto_seq or
             set_call_first replaces the file with a valid one. No other setting of
             ContactSnapshot settings is in the file.
             The contact station reads the file once, when it is created at the station
             start, and the ContactCommand path writes both values before the engine
             takes the changed one and before the receipt; a failed write refuses the
             command storage_unavailable (ContactRefusal) and changes nothing. */
    }

    // ---------------------------------------------------------------- log
    attribute def LogRecord {
        attribute contactId : String;
        attribute call : String;
        attribute gridsquare : String[0..1];
        attribute mode : String;
        attribute submode : String[0..1];
        attribute rstSent : String[0..1];
        attribute rstRcvd : String[0..1];
        attribute qsoDate : String;
        attribute timeOn : String;
        attribute qsoDateOff : String;
        attribute timeOff : String;
        attribute band : String[0..1];
        attribute freqMHz : String[0..1];
        attribute stationCallsign : String;
        attribute myGridsquare : String[0..1];
        attribute txPwrW : String[0..1];
        attribute commentText : String[0..1];
        attribute contestFields : String[0..8];
        attribute confirmationFields : String[0..7];
        attribute activity : String[0..1];
        doc /* ADIF 3.1.8 ADI fields (field set follows ADQ to_adif ~50-75 and LQ, D10):
             CALL, GRIDSQUARE (only when known; DIFFERENT from WSJT-X writing it empty),
             MODE FT8 (FT4-NOTE MODE MFSK, SUBMODE FT4), RST_SENT = report of the last
             transmitted Tx2/Tx3 (MW ~8105-8127), RST_RCVD = the partner's last counted
             report, both rendered as in ReportRange; QSO_DATE/QSO_DATE_OFF YYYYMMDD,
             TIME_ON/TIME_OFF HHMMSS UTC; BAND from the confirmed dial frequency per the
             ADIF band enumeration (e.g. 20m), absent when the dial is not confirmed;
             FREQ in MHz with six decimals = confirmed dial + Tx offset (LQ ~384,
             mainwindow_slots.cpp ~545), absent when unconfirmed; STATION_CALLSIGN and
             MY_GRIDSQUARE the profile locator; TX_PWR watts (decimal >0, optional, D10); COMMENT single
             line, printable ASCII without '<' and '>', at most 1024 characters
             (optional, D10); a COMMENT containing '<' or '>' is refused (DIFFERENT from
             WSJT-X to_adi_text stripping them: a supplied record is never altered).
             DirectLog writes neither TX_PWR nor COMMENT (no power or comment entry
             since #41 retired the review); SaveContact and UpdateLogbook may carry them.
             Contest fields (#24 S2b, ContestExchange; D10 reversed for these only), in
             this order after COMMENT: STX, STX_STRING, SRX, CONTEST_ID, SRX_STRING, CLASS,
             ARRL_SECT, STATE; each at most 32 printable ASCII characters without '<' and
             '>' (STX/SRX 1-4 digits). Confirmation fields (#10, operator 2026-11-04, for
             the strategies of class strategy), in this order after the contest fields:
             LOTW_QSL_RCVD, LOTW_QSLRDATE, QSL_RCVD, QSLRDATE, QSL_RCVD_VIA, EQSL_QSL_RCVD,
             EQSL_QSLRDATE; the statuses the ADIF 3.1 QSL Rcvd enumeration Y, N, R, I, V,
             the dates YYYYMMDD, QSL_RCVD_VIA the QSL Via enumeration B, D, E, M (values
             case-insensitive, stored as written). A record is confirmed when any of the
             three statuses is Y or V; N, R, I and absent are not confirmed. Only
             UpdateLogbook sets them; DirectLog and SaveContact never write them, a DirectLog
             replacement keeps the stored ones, and the one-record-per-contactId
             comparison ignores them. In the stored log a confirmation field that is invalid
             or repeated (a log kept verbatim before #10) stays an unknown field. RST_SENT/RST_RCVD are a ReportRange report, a
             5n9 RST (n 2-9) or a 5n RS 52..59 (EuVhfExchange, #99, operator 2026-11-09). APP_WSTXRUST_CONTACT_ID = contactId; APP_WSTXRUST_SOURCE (a
             token of 1..32 letters, digits or '-') marks a record added by UpdateLogbook
             with the program it came from and is absent on the station's own records.
             APP_WSTXRUST_ACTIVITY (activity) is the contact's activity at logging time,
             one of field_day, rtty, eu_vhf, na_vhf, ww_digi, arrl_digi, hound, absent for
             none (WstxUdp::'CL-112-05'). App fields follow the fields above in this
             order: APP_WSTXRUST_CONTACT_ID, APP_WSTXRUST_SOURCE, APP_WSTXRUST_ACTIVITY, then
             the preserved unknown fields; they are read back on load and are outside the
             one-record-per-contactId comparison.
             Name, operator, propagation and satellite fields are not adopted (D10; WSJT-X
             writes OPERATOR
             only with a configured operator call, which this product does not have).
             Start time (MW set_dateTimeQSO ~8944): the UTC start of the period of this
             contact's first transmitted Tx2, or one period before its first
             transmitted Tx3; otherwise the start of its first transmitted message's
             period. End time: the UTC end of the last period in which a counted
             message of the contact was transmitted or received. Both server-owned;
             the browser never substitutes its clock. */
    }
    enum def LogOutcome { enum saved; enum alreadySaved; enum invalidField; enum conflict; enum storageFailed; }
    action def DirectLog {
        doc /* #41 (operator design interview on #37, 2026-11-01: no log review queue;
             each completed QSO goes straight to the internal ADIF log, as WSJT-X, and
             to the external programs). Retires the #10 OfferLogReview queue, its
             discard_review action and the browser review form.
             Automatic: once per contactId when it completes (AutoSequence completed:
             after a confirmed transmitted Tx4 RR73 or Tx5 73, or a received 73 in
             rogers), which is when WSJT-X prompts to log (MW guiUpdate ~8056). A
             contact completed without a received report (a selected RR73/73 row, or the
             partner's RRR/RR73 answered in replying or report, #69) is logged the same
             way with RST_RCVD absent. The server builds the LogRecord at completion: CALL,
             GRIDSQUARE when known, MODE/SUBMODE by ContactMode, RST_SENT/RST_RCVD,
             QSO_DATE/TIME_ON and QSO_DATE_OFF/TIME_OFF by the LogRecord time rules, BAND
             and FREQ from the dial confirmed at completion plus the Tx offset (absent when
             unconfirmed), STATION_CALLSIGN and MY_GRIDSQUARE; it is stored without any
             browser, whether or not one is connected. Manual Log QSO (button, Alt+Q,
             open_log): the station accepts it whenever a contact has a DX call, in any
             state; the QSO pane offers the button and Alt+Q only while a QSO runs
             (WstxOperatingLayout::QsoPane, #37); it logs
             that contact now the same way with the times observed so far, without a
             form. Log QSO of an unfinished contact (replying..signoff) also closes it
             (#37, 2026-11-02): it becomes completed with Tx6 selected, Enable Tx turns off
             (disarm cause contactCompleted), nothing stays queued, and it counts as logged
             at completion, so later partner messages neither advance nor log it again.
             One record per contactId: logging a contactId already stored with
             identical fields adds nothing (alreadySaved); with different fields the
             contact's record is replaced in place (replaced), keeping its index. Log QSO of a contact already logged at
             its completion (stored or pending) changes nothing: the record keeps the
             dial, Tx offset and location of completion. A second contact with the same
             station is a new contactId and a new record (WSJT-X LogBook::add appends
             without a dupe check). Only the first store of a contactId (saved) is sent
             to the WstxUdp targets as QSO Logged then Logged ADIF, so each contact
             reaches the external programs once; a replacement stays internal. They are
             sent by the station step, never from inside a command. Idempotence: a retried command_id has no second
             effect, a repeated completion logs once, and a restart starts no contact,
             so it logs nothing again; stored records survive in contacts.adi.
             Storage failure: the record stays pending in the station process, at most 64
             (a 65th drops the oldest pending record with error log_queue_full), retried
             at most every 5 s; pending records do not survive a restart. A record that
             fails the LogRecord domains (for example no profile callsign) is not stored
             (error log_invalid_field). ContactSnapshot log shows the latest attempt.
             Publication runs under the station's authorization lock without a request
             grant: it follows a contact that granted operating requests drove.
             Logged records are not edited here (ContactHistory stays read-only). */
    }
    action def SaveContact {
        in supplied : LogRecord;
        out outcome : LogOutcome;
        doc /* Exactly once per contactId per profile. Storage: the selected profile
             directory's file contacts.adi (ADIF 3.1.8 ADI with header), written as a
             complete new file in the same directory, flushed and atomically replaced,
             as WstxProfiles::SaveSelectedProfile; saved is acknowledged only after the
             replace succeeds. A repeated save of the same contactId with identical
             fields returns alreadySaved and adds nothing; different fields after a
             save return conflict (history is read-only). Failure leaves the request
             visibly unsaved with retry under the same contactId. A new contact with a
             call already in the log is a separate contact (no dupe refusal; WSJT-X
             LogBook::add appends without a dupe check). Since #41 no browser control
             sends it: completed contacts are stored by DirectLog; POST /contacts stays
             the explicit save of a supplied record. */
    }

    // ---------------------------------------------------------------- worked before
    enum def WorkedStatus { enum notWorked; enum workedOtherBandOrMode; enum workedThisBandAndMode; enum unknown; }
    action def WorkedBeforeQuery {
        in call : String;
        in band : String;
        in mode : String;
        out status : WorkedStatus;
        doc /* D9 adopted (WB indexes calls keyed by band+mode and band; LogBook::match).
             Determined by the server from the profile's contacts.adi including contacts
             saved this session and records added by UpdateLogbook (#10, 2026-11-03),
             through an index of the log by call and by grid square that is rebuilt only
             when the log changes, so a record costs a lookup of its call, not a scan
             of the log: workedThisBandAndMode when a record has the same CALL,
             BAND and MODE/SUBMODE; workedOtherBandOrMode when only CALL matches; else
             notWorked. Calls compare case-insensitively on the full call. DXCC entity,
             continent and zone status come with each decoded record instead
             (DecodedEntity, #55); LoTW highlighting is not adopted (B-list of #25). The
             station determines it on each decoded record it serves (worked_status,
             DecodedEntity) and the browser sends no query (#10
             WstxStationProtocol::PushedStationState); a row without the key shows unknown
             (no indicator): a hashed or absent call, or no band known. Indication uses a
             text/icon label plus colour; it changes no decoding, sequence or log.
             Award standing (#10, operator 2026-11-04, consumed by the #39 award
             strategies): the worked set of DecodedEntity holds, for each DXCC entity
             (and continent, CQ and ITU zone) ever, per band and per band and mode, whether
             it is worked and whether a confirmed record (LogRecord confirmationFields)
             holds it, from the same lookup; an entity is needed in a scope when it is not
             worked or not confirmed there. It is rebuilt with the worked set when the log
             changes, including a confirmation upgrade. */
    }

    // ---------------------------------------------------------------- ADI log
    attribute def AdiLimits {
        attribute importBytesMax : Integer = 67108864;
        attribute importRecordsMax : Integer = 100000;
        attribute fieldCharactersMax : Integer = 1024;
        attribute fieldNameCharactersMax : Integer = 64;
        attribute importChunkBytesMax : Integer = 16384;
        attribute historyPageRecordsMax : Integer = 10;
        attribute historyPageBytesMax : Integer = 16384;
        doc /* Application admission limits (#10 text; not ADIF limits). Exactly at a
             limit is admitted, one over is refused: a file over importBytesMax or
             importRecordsMax, or a field name over fieldNameCharactersMax, refuses the
             whole update and publishes no record of it; a field value over
             fieldCharactersMax is a fault of that field only (UpdateLogbook). Inside a
             record only white space is permitted between a field value and the next
             tag; any other text there is a lengthMismatch fault of the field before it
             (an inexact LEN is never silently truncated: that value is not taken; the
             stored log refuses such a file, UpdateLogbook judges the field as below;
             Log4OM 2.42 writes CNTY values longer than their LEN). A logger export of about 27,000 QSOs with about 60
             fields each (Log4OM 2: about 28 MB) is inside these limits. The stored log is
             not limited by one update's record count. */
    }
    enum def AdiError {
        enum malformed; enum lengthMismatch; enum unsupportedCharacter; enum fieldTooLong;
        enum tooManyRecords; enum tooLarge; enum missingRequiredField; enum invalidValue;
        enum integrityMismatch;
    }
    action def UpdateLogbook {
        in importId : String;
        in totalBytes : Integer;
        in sha256 : String;
        out added : Integer;
        out present : Integer;
        out confirmed : Integer;
        out skipped : Integer;
        out error : AdiError[0..1];
        doc /* #10 operator request 2026-11-03 ("updating the logbook"): consolidate the
             log of another logger, exported as ADIF ADI (for example Log4OM 2), into
             the station's contact log, so one log without duplicates feeds
             worked-before, DXCC and grid status. Settings > Logging & Reporting >
             "Update logbook from ADIF": the operator picks the file and presses Update
             logbook. It is the one ADI import of the station: it replaces the former
             ImportAdi and retires its all-or-nothing conflict rule and its verbatim
             unknown fields (decision on #10: one function for any logger; a repeated
             update from a grown export adds only what is new).
             File (any ADIF 3.x ADI writer): UTF-8, a leading byte order mark ignored;
             an optional header (any text, such as '#' banner lines, and fields) ended
             by <EOH>; records end <EOR>; tags case-insensitive <NAME:LEN[:TYPE]> with
             exact LEN in characters; only white space between the fields of a record,
             see AdiLimits. Header fields are not stored; the header PROGRAMID, when it
             is a token of 1..32 letters, digits or '-', is the source marker, else ADIF.
             Refused as a whole, publishing nothing, with error {code,record,field}:
             integrityMismatch (sha256 of the received bytes, checked first); bytes
             that are no UTF-8, or a control character other than TAB/CR/LF outside a
             field value (unsupportedCharacter); a broken tag or a missing <EOH> or
             <EOR> (malformed); a LEN past the end of the file (lengthMismatch);
             tooLarge; tooManyRecords; a field name over the limit (fieldTooLong).
             Per record, after that structural check:
             - Kept fields: only the LogRecord fields (CALL, GRIDSQUARE, MODE, SUBMODE,
               RST_SENT, RST_RCVD, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, BAND,
               FREQ, STATION_CALLSIGN, MY_GRIDSQUARE, TX_PWR, COMMENT and the #24
               contest fields STX, STX_STRING, SRX, CONTEST_ID, SRX_STRING, CLASS,
               ARRL_SECT, STATE), the confirmation fields (LOTW_QSL_RCVD, LOTW_QSLRDATE,
               QSL_RCVD, QSLRDATE, QSL_RCVD_VIA, EQSL_QSL_RCVD, EQSL_QSLRDATE; #10,
               2026-11-04), a valid APP_WSTXRUST_CONTACT_ID, APP_WSTXRUST_SOURCE and
               APP_WSTXRUST_ACTIVITY (an invalid one is dropped). Every other field
               (names, addresses, e-mail, QSL sent and upload states, other APP_ fields) is
               not stored, so the update does not widen the personal data the station
               keeps.
             - A record is skipped, with reason {code,field}, when CALL, QSO_DATE
               (valid YYYYMMDD), TIME_ON (HHMM or HHMMSS) or MODE is missing
               (missingRequiredField) or invalid (invalidValue; unsupportedCharacter
               for a value that is not printable ASCII; fieldTooLong; lengthMismatch
               for text after its value), or when a kept
               field occurs twice in it (malformed).
             - An optional kept field whose value fails its domain (FREQ and TX_PWR
               positive decimals, GRIDSQUARE and MY_GRIDSQUARE 2/4/6/8 Maidenhead, BAND
               the ADIF enumeration, RST at most 16 characters, SUBMODE a token,
               STATION_CALLSIGN 1..32 letters, digits or '/', the #24 contest fields as
               SaveContact admits them in LogRecord (STX and SRX 1-4 digits, the others
               at most 32 printable characters without '<' and '>'; coordinator
               decision on #10, 2026-11-04), the confirmation fields their LogRecord
               enumerations and dates, a contact id a UUID, a
               source a token; every value printable ASCII and at most
               fieldCharactersMax, with no text after it) is left out of that record,
               which is still added;
               the summary lists it as dropped {code,field}.
             Values are stored as written (no case or mode rewriting): MODE FT4 and
             MODE MFSK with SUBMODE FT4 are both FT4 for consolidation and
             worked-before (effective mode: SUBMODE when MODE is MFSK, else MODE).
             Consolidation (the record is already present, counted present, nothing
             changes): a record whose APP_WSTXRUST_CONTACT_ID is stored or was added
             earlier from the same file; or a stored record, or an earlier added record
             of the same file, with the same CALL (case-insensitive), effective band
             (BAND, or without BAND the ADIF band of FREQ, or none) and effective mode,
             whose start (QSO_DATE + TIME_ON) is at most 120 s from this record's start
             (WSJT-X/ADIF practice: loggers differ in seconds and rounding). The stored
             (or earlier added) record wins, so the station's own records keep all their
             fields, except that its confirmation is upgraded (#10, operator 2026-11-04):
             for each of LoTW (LOTW_QSL_RCVD, LOTW_QSLRDATE), paper QSL (QSL_RCVD,
             QSLRDATE, QSL_RCVD_VIA) and eQSL (EQSL_QSL_RCVD, EQSL_QSLRDATE) whose status
             is Y or V in this record and not Y or V in the present one, the present
             record takes this record's status and, where this record has them, its date
             and via. A confirmation is only added, never removed or downgraded; Y and V
             are both confirmed and do not replace each other; nothing else changes. The
             upgraded stored records are replaced in place (their indexes kept) in the
             same atomic replace as the added records. Otherwise the record is added: a new contact id when it has
             none, APP_WSTXRUST_SOURCE the file's marker unless it carries one. Added
             records are appended in file order in one atomic replace of contacts.adi
             (as SaveContact); a failed replace adds none.
             Repeatable and incremental: updating again with the same or a grown export
             adds only the records not yet present; export then update of the station
             log adds none.
             Nothing leaves the station: no WstxUdp QSO Logged or Logged ADIF, no other
             forwarding or upload; only DirectLog and SaveContact send logged contacts
             (SaveContact resends a contact a logging program missed).
             Summary: added, present, confirmed (the present records whose confirmation
             this update upgraded), skipped, reasons (the skipped records grouped by
             {code,field} with count and first record index) and dropped (the dropped
             fields grouped likewise), each at most 16 groups in order of first
             occurrence (skipped is always the full count). The browser shows "Logbook
             updated: N added, M already present (C confirmations updated), K skipped"
             ("1 confirmation updated" for one) with the reasons and the
             dropped fields, or "Logbook not updated" with the error and its
             record/field.
             Retry identity: importId is a caller-chosen UUID. Reserving the same
             importId with identical totalBytes and sha256 returns the existing
             resource or its final result without a second effect; different values are
             state_conflict. One update per profile at a time; the resource is retained
             until the next reservation or restart. Chunks follow the
             WstxRecordingReceive import pattern: exact Content-Range, at most
             importChunkBytesMax each, in order. Bulk transfer yields to status/control
             and never delays HaltTransmit. Authorization: an operator action with the
             configuration access of the other log routes.
             Workload (#10): a 28 MB export of about 27,000 QSOs is consolidated within
             seconds of its last chunk, also when a rerun upgrades the confirmation of
             all of its records, and worked-before stays an index lookup
             (WorkedBeforeQuery). */
    }
    action def ExportAdi {
        doc /* GET /contacts/export.adi streams the whole profile log as ADIF 3.1.8 ADI:
             header with ADIF_VER 3.1.8, PROGRAMID WSTXRUST and CREATED_TIMESTAMP, then
             every stored record in storage order with its supported fields (LogRecord
             set, including the confirmation fields), its app fields in the LogRecord order
             and preserved unknown fields verbatim. Content
             type application/octet-stream with attachment filename contacts.adi; no
             content coding; streamed with backpressure behind status/control: the log
             as it is at the request (a snapshot that holds no lock, so a save or update
             during the export succeeds and appears in the next export), sent with chunked
             transfer and no Content-Length, the header with the first 128 records and then
             128 records per chunk, each formatted only when the connection takes it, so a
             log of about 27,000 QSOs is never built in memory as one document (#10,
             2026-11-04). Export then UpdateLogbook of the same file adds no record (all
             already present). */
    }
    action def ContactHistory {
        in cursor : Integer;
        in limit : Integer;
        doc /* GET /contacts?cursor=&limit= returns exactly
             {v:1,profile_id,total,cursor,next,more,records}; records are the stored
             records in append (storage) order with index cursor..; records are only
             appended, and a DirectLog replacement keeps its record's index, so indexes
             are stable. limit 1..10 (default 10),
             cursor 0..total (total returns an empty page), page at most 16384 encoded
             bytes. Each record is exactly {index,contact_id,call,gridsquare,mode,
             submode,rst_sent,rst_rcvd,qso_date,time_on,qso_date_off,time_off,band,freq,
             station_callsign,my_gridsquare,tx_pwr,comment,stx,stx_string,srx,contest_id,
             srx_string,class,arrl_sect,state,unknown_field_count} with
             absent values null, rendered literally (not the LogRecord confirmation
             fields; ExportAdi carries them). Read-only inspection; no edit or
             delete. */
    }
    dependency qsoSettingsOwner from QsoSettingsFile to WstxArchitecture::QsoAndLogging;
    dependency qsoSettingsClause from QsoSettingsFile to WstxLogbook::'CL-110-01';
    dependency logPromise from LogRecord to WstxRequirements::'FR-011';
    dependency directLogClause from DirectLog to WstxLogbook::'CL-010-04';
}
