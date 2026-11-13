package WstxQsoWire {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-019';
    private import WstxArchitecture::'FR-021';
    private import WstxRequirements::AutomationState;
    private import WstxStandardQso::'TC-007-004';
    private import WstxContact::ContactAction;
    requirement 'CL-010-15' {
        doc /* Expose the contact operations only through the versioned WstxContact wire contract: exact routes, keys and byte caps, command_id idempotency, contact_revision, the ContactRefusal codes, the contact.state and station.tick events, and the stated Thin/Off byte budget, leaving StatusReply and the compressed-route allowlist unchanged. Details: WstxQsoWire::ContactWire, ContactCommand, CommandReceipt, ContactSnapshot, ContactStateEvent, StationTickEvent. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contact_http.rs; server/src/logbook_http.rs; server/src/main.rs";
    }
    dependency CL_010_15_to_FR_019 from 'CL-010-15' to 'FR-019';
    dependency CL_010_15_to_FR_021 from 'CL-010-15' to 'FR-021';
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
    dependency CL_010_15_verified_by_TC_007_004 from 'CL-010-15' to 'TC-007-004';
    dependency CL_010_15_verified_by_TC_007_005 from 'CL-010-15' to 'TC-007-005';

    // ---------------------------------------------------------------- displays
    attribute def OperatorDisplays {
        attribute utcClockText : String;
        attribute periodElapsedSeconds : Integer;
        attribute periodSeconds : Integer = 15;
        attribute transmitting : Boolean;
        attribute rxLevelDb : Integer[0..1];
        assert constraint progressBounds { periodElapsedSeconds >= 0 and periodElapsedSeconds < periodSeconds }
        assert constraint levelBounds { rxLevelDb == null or (rxLevelDb >= 0 and rxLevelDb <= 90) }
        doc /* D11 adopted. UTC clock HH:MM:SS (MW labUTC) from the server's UTC
             observation in the status stream, advanced locally between observations
             for display only; marked stale with the link; never a scheduling input.
             Tx progress (MW ~8388): #50, one period bar only, the QSO pane's NEXT bar
             (its width the elapsed part of the period, FT4-NOTE 7.5) with the countdown or,
             while #9 reports an active transmission, "▶ TX now" with the seconds left
             (#37, QsoPane NEXT); the top bar shows UTC only.
             The bar is red in a period of my Tx parity while Enable Tx is on and whenever
             transmitting is true, green otherwise (WstxQsoPane::QsoPane NEXT).
             StationPeriodClock (#50, operator 2026-11-02): the UTC clock, the bar and the
             countdown run on the station's UTC (the transmit owner's now_utc_ms, system
             clock plus the #43 correction, the clock the transmitter keys on), never on the
             browser's wall clock: each station observation (station.tick utc_ms and the
             ContactSnapshot utc_ms) gives offset = utc_ms - browser monotonic time at its
             receipt; the shown station time is the browser monotonic time plus the
             largest offset received in the last 20 s (a late delivery only lowers an
             offset); an offset more than 500 ms below that estimate is a backward step
             of the station clock (#43) and restarts the estimate at once. The bar is redrawn at least every 100 ms with no animated width
             change, so it restarts at 0 at each period start within 100 ms plus the
             link's one-way delay. Rx level meter (widgets/
             signalmeter.cpp, meterwidget.cpp): 0..90 dB, rxLevelDb = round(10 log10(mean(s^2))) with s
             the canonical receive samples scaled to 16-bit full scale (32768), over the
             last status interval, at most one value per second on the status link;
             labelled "high" above 85 dB and "low" below 15 dB (meterwidget.cpp ~61/~64 thresholds)
             in text and colour; null shows unavailable when audio is not running. #61
             CL-061-04: the station measures no level while on the air and for the rest of
             that Tx period (null then, "Tx · not measured" while transmitting); a level and
             its low/high entry refer to receive periods only. */
    }
    item def ContactCommand :> WstxArchitecture::StationRequest {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute command_id : String;
        attribute contact_revision : Integer;
        attribute commandAction : ContactAction;
        doc /* POST /contact/command, body at most 1024 UTF-8 bytes, exact keys
             {v,profile_id,boot_id,command_id,contact_revision,action} (commandAction is the JSON key action) plus exactly the
             parameters of its action (all required, nullable where stated):
             select_row {row:{source_id,job_id,generation,sequence},replace} plus the optional
             directive_confirmed boolean (WstxStrategy::DirectedCqRule; refused
             directive_not_answerable, 409 with error.reason in the browser's case);
             enter_dx {dx_call,dx_grid|null,replace}; cancel {};
             choose_next {slot:"tx1".."tx6"}; edit_message {slot,text};
             set_report {report}; set_tx1_skip {enabled}; set_tx4 {form:"rrr"|"rr73"};
             set_frequency {rx_hz|null,tx_hz|null} (null = unchanged; pointer actions use
             this with the PointerEffect result); set_hold_tx {enabled};
             set_parity {parity:"even"|"odd"}; set_auto_seq {enabled};
             set_call_first {enabled} (CallFirst);
             set_activity {activity:"none"|"na_vhf"|"eu_vhf"|"ww_digi"|"arrl_digi"|"field_day"|"rtty"|"hound",
             exchange?} (GridExchangeContest, ContestExchange, EuVhfExchange, HoundOperation);
             set_watchdogs {tx_calls,tune_seconds}; enable_tx {enabled,
             safety_revision|null} (safety_revision: the CL-022 safety revision shown in
             the snapshot transmit view; for enabled true a value different from the
             station's current revision is stale_revision with field safety_revision);
             tune {enabled, safety_revision|null, the key optional} (WstxTransmit::SetTune:
             Tune on with another revision than the station's, or none, is stale_revision
             with field safety_revision; Tune off needs none);
             the start actions (StartActions), each with safety_revision|null as enable_tx:
             reply {row, safety_revision} plus the optional directive_confirmed as
             select_row; call_cq {safety_revision}; call_dx {dx_call,dx_grid|null,replace,
             safety_revision}; send_next {slot,safety_revision};
             reset_repetitions {safety_revision};
             redecode {} (last completed interval of the current live
             job; no browser control sends it since #37); open_log {} (manual Log QSO:
             DirectLog of the current contact now).
             replace true is the explicit ChangeContact; false with an active contact is
             contact_active. command_id is a caller UUID: the server retains the last 16
             command receipts per boot; an identical body with a retained command_id
             returns 200 with the same receipt and no effect; a different body with it
             is state_conflict. contact_revision must equal the current revision
             (stale_revision otherwise), except cancel, enable_tx false and tune false,
             which are admitted with any earlier revision. Validation order is the
             WstxOperatingReceive S2 order (route, Origin, TLS/session, size/media/syntax,
             version/enums/UUIDs/safe integers, profile, boot/revision, capability,
             state). Transmit actions on a station without transmit capability, or
             without a current CL-022 grant (a plaintext profile), are
             transmit_unavailable; Enable Tx arms #9 with the confirmed CL-022 safety
             revision it carries (#9 itself refuses a changed revision, reported
             stale_revision with field safety_revision; no check-then-arm race). A transmit outcome refused without a #9 disarm
             (duplicateSequence) disarms with cause refused and is never resubmitted
             unchanged; the engine's own disarms are not shown as refusals. */
    }
    item def CommandReceipt :> WstxArchitecture::StationOutcome {
        attribute v : Integer = 1;
        attribute command_id : String;
        attribute contact_revision : Integer;
        attribute accepted : Boolean = true;
        doc /* 202 exactly {v:1,profile_id,boot_id,command_id,contact_revision,accepted:true},
             at most 384 bytes: accepted, not yet confirmed effect. Refusals use the
             existing envelope {error:{code,field}} with code a ContactRefusal and field
             the offending JSON key or null; nothing is changed by a refusal. */
    }
    item def ContactSnapshot :> WstxArchitecture::StationOutcome {
        attribute v : Integer = 1;
        attribute contact_revision : Integer;
        attribute snapshot_sequence : Integer;
        doc /* GET /contact returns 200 exactly
             {v:1,profile_id,boot_id,contact_revision,snapshot_sequence,monotonic_ms,
             utc_ms,transmit,settings,contact,log,watchdog}, at most 4096 encoded
             bytes (503 snapshot_limit otherwise, never truncated). transmit is #9's read
             view exactly {capability:"unsupported"|"unavailable"|"available",
             arm_state,last_disarm_cause,last_arm_cause,tune,pending_sequence,last_text,
             last_period_utc,halt_state,safety_revision,refusal} (last_arm_cause
             "operator", "auto" or null, WstxTransmit::TransmitArming; safety_revision the
             current CL-022 safety revision of the selected radio scope or null);
             settings exactly {auto_seq,call_first,tx1_skip,
             tx_calls,tune_seconds,rx_hz,tx_hz,hold_tx,parity,report,activity,exchange,
             serial} (exchange the ContestExchange text or null); contact null or
             exactly {id,origin,dx_call,dx_grid,report_sent,report_rcvd,exchange_sent,
             exchange_rcvd,state,next_slot,
             tx4,messages,start_utc,end_utc,saved,suggested_slot,last_rcvd,dialogue} (report_sent the
             report of the last transmitted Tx2/Tx3 rendered, null until one is sent;
             suggested_slot null or the slot AutoSequence would select after the latest
             counted partner message while Auto Seq is off, e.g. tx5 after their RR73 in
             rogerReport; the state and next slot do not change, the QSO pane offers it,
             and choose_next clears it; null outside replying..signoff, #11;
             last_rcvd null or exactly {text,snr,period_utc_ms,count}: the latest partner
             message to my call that the engine counted, or the selected row when it was
             addressed to me, with its rounded SNR or null, its period start (Unix ms) and
             how many consecutive counted messages had that identical text; null for a new
             contact; the QSO pane's last partner message, #37; dialogue (#37, operator
             2026-11-02) an array of at most 16 entries exactly {dir:"rx"|"tx",text,snr,
             period_utc_ms,count}, oldest first: "rx" each partner message the engine
             counted for this contact (as last_rcvd, including the selected row addressed
             to me) with its rounded SNR or null, "tx" each transmission of this contact
             whose audio started (the text as sent, snr null); a message equal in text to the
             newest entry of its dir (also across an entry of the other dir, #39: a partner
             repeating while I repeat keeps both Reps counting) increments that entry's
             count instead, except the first transmission after an operator Enable Tx
             from off, which opens a new entry; selecting a row of the current partner, or entering
             it again, keeps the dialogue, the Tx4 form, each slot's current text when it was already sent,
             also an edited one, and, once the
             current Tx2 or Tx3 text was sent, the report whatever the row's SNR (its
             period_utc_ms stays the first period; its snr becomes the repeat's SNR when
             that is not null, so it is the latest decode's, #60); beyond 16 the oldest entry is dropped;
             empty for a new contact and cleared by CancelContact)
             with messages an array
             of six strings or nulls (Tx1..Tx6, each at most 37 characters); saved true
             when contacts.adi holds the contact's record; log (DirectLog) null until a
             contact of this boot was logged, else exactly {contact_id,call,outcome,error}
             of the latest attempt: outcome saved (stored, replaced or already stored)
             with error null, or unsaved with error storage_unavailable (pending, retried),
             log_queue_full or log_invalid_field (not retried); watchdog exactly {tx_remaining_calls,
             tx_expired,tune_remaining_seconds,busy_with,paused_calls}; tx_remaining_calls is the Tx
             watchdog's only (#97, #91: limit minus the counted repetitions, TxWatchdog), or null
             while the Tx watchdog does not bound the contact (a strategy or contest run's own
             contact while the run is attended, WstxStrategy::StrategyWatchdog), when the browser
             shows no WD (the run's leave label instead, WstxStrategy::LeaveCountLabel; "WD:∞" is
             gone); busy_with and paused_calls per BusyPartner. contact_revision advances on every
             accepted command and every server-side sequence/transmit/watchdog change;
             snapshot_sequence also on clock-free material changes. No content coding:
             /contact, /contacts and /contacts/* are not in the six-route
             WstxHttpContentCoding::ExactCompressedGetRoute allowlist and stay identity. */
    }
    item def ContactStateEvent {
        attribute v : Integer = 1;
        attribute 'type' : String = "contact.state";
        doc /* New versioned WebSocket event on the existing wstx.v1 socket, exactly
             {v:1,type:"contact.state",data:{profile_id,boot_id,contact_revision,
             snapshot_sequence,monotonic_ms,utc_ms,changed}}, at most 2048 bytes, sent when
             the GET /contact snapshot of this peer changes or its contact_revision does (then
             with an empty changed, so the next command has the revision), coalesced to at most one per
             second per peer and always sent within 1 s of a change; below Detailed a change
             of only watchdog.tune_remaining_seconds at most once per 5 s. changed (#10
             2026-11-06, operator rule 2026-11-04): on a peer's first event every field of
             transmit, settings, contact, log and watchdog, null too; later only the
             changed fields, of transmit, settings and watchdog only the changed members,
             of the same contact (id) only the changed members. A contact's dialogue goes
             with dialogue_from, the index of its first row, and only the rows the peer
             lacks: all rows when an earlier row changed; rows over the frame budget follow
             on the next tick. The always-loaded browser client holds the snapshot from these
             events from the socket's first on, so a contact client loading later misses
             none, and shows a snapshot_sequence not older than its own; it reads GET /contact once per socket, with one
             pending GET per browser. After its own command it shows the command's reply
             (accepted, or the refusal with its code) and reads nothing: the next command goes
             at once with the newer of the held and the last receipt's contact_revision, and
             GET /contact is read only when no contact.state holds the receipt's revision
             within 5 s; after a stale_revision refusal of contact_revision the explicit
             gesture (double-click, Reply, CQ) waits up to 2.5 s for a newer revision before
             its retry, outside the command order, after one of another field
             (safety_revision) or an unknown outcome it reads at once. A choice made from the
             held state (Log QSO, a row's selection, CQ) waits for a command and result still
             on their way; Esc and Abort QSO never wait, and after them nothing an earlier
             gesture queued (its retry, its Enable Tx) is sent (#10). It is not a StatusReply:
             station.status stays exactly {v,type,id,data{version,radio}}. Control and
             status keep priority over it as over optional visualization. */
    }
    item def StationTickEvent {
        attribute v : Integer = 1;
        attribute 'type' : String = "station.tick";
        doc /* New versioned WebSocket event, exactly
             {v:1,type:"station.tick",data:{profile_id,boot_id,utc_ms,period_ms,
             transmitting,rx_level_db}}, at most 224 bytes (the exact keys with two UUIDs
             and a 13-digit utc_ms already need 220; corrected from 192 by the #10
             implementation, review required). Rate per peer by its display
             subscription: Detailed 1 per second; Thin and Off 1 per 5 s; plus at most one
             extra event per transmit start/stop. A peer that never chose a display
             subscription (a bare status observer) receives neither event. The browser interpolates the UTC clock
             and Tx progress locally from utc_ms with its monotonic clock between ticks
             (display only); rx_level_db shown is the latest tick value. Budget: Off idle
             with two clients adds at most 2 x (224 + 2 WS + 29 TLS + 160 accounted
             TCP/ACK) / 5 s = 166 B/s per direction, so the status-only idle total stays
             within WstxStationProtocol::ThinLinkBudget 1000 B/s; Thin stays within the
             existing 3000 B/s live envelope. Both are targets judged from
             WstxStationProtocol::LinkTrafficLog (#80). */
    }
    attribute def ContactWire {
        doc /* Routes of WstxContact (selected-profile mode only; environment-only mode
             404 not_found): GET /contact; POST /contact/command; POST /contacts (SaveContact:
             exactly {v,profile_id,boot_id,command_id,record}, body at most 8192 bytes so
             that a 1024-character comment fits with worst-case JSON escaping;
             201 {v:1,contact_id,outcome:"saved"}, 200 alreadySaved, 409 log_conflict,
             400 log_invalid_field with field, 503 storage_unavailable leaving the record
             unsaved; the record may carry app_wstxrust_activity, refused 400
             log_invalid_field field record.app_wstxrust_activity outside its values); GET /contacts (ContactHistory); GET /contacts/export.adi
             (ExportAdi); POST /contacts/imports {v,profile_id,boot_id,import_id,
             total_bytes,sha256} 201/200 reserve; PUT /contacts/imports/{id} chunks;
             GET /contacts/imports/{id} exactly {v:1,id,state,received_bytes,total_bytes,
             added,present,confirmed,skipped,reasons,dropped,error} with reasons and dropped arrays
             of {code,field,count,record} and error null or {code,record,field}; the
             completing chunk answers 201 with that view, a refused update 422
             import_failed (UpdateLogbook); POST /transmit/halt (WstxTransmit::HaltTransmit).
             All use the existing HTTP/TLS authentication, exact Origin on mutations,
             JSON media rules and error envelope; the 1024-byte body cap applies except
             the stated 8192-byte save body and 16384-byte
             update chunks. Mutations are never
             replayed automatically; reconnect reads GET /contact first. MCP uses the
             same station operations. */
    }
}
