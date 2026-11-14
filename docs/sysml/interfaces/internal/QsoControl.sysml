package WstxQsoControl {
    private import ScalarValues::*;
    port def QsoControlPort {
        out item command : QsoCommand;
        in item 'state' : QsoState;
    }
    item def QsoCommand {
        doc /* Auto Seq on or off, a target or message chosen by the operator or an agent,
             Hold Tx, the contest exchange. */
    }
    item def QsoState { doc /* The QSO state. */ }
    item def QsoProgress {
        doc /* Answered, completed, repetition count, busy partner, refused or failed after
             admission. */
    }
    interface def QsoControl {
        doc /* The station service commands the qso function; qso reports its state. */
        end station : QsoControlPort;
        end qso : ~QsoControlPort;
    }
    enum def ContactAction {
        enum select_row; enum enter_dx; enum cancel; enum choose_next; enum edit_message;
        enum set_report; enum set_tx1_skip; enum set_tx4; enum set_frequency; enum set_hold_tx;
        enum set_parity; enum set_auto_seq; enum set_call_first; enum set_watchdogs; enum abort;
        enum set_activity;
        enum enable_tx; enum tune; enum redecode; enum open_log;
        enum reply; enum call_cq; enum call_dx; enum send_next; enum reset_repetitions;
        doc /* discard_review is retired (#41, no log review queue) and refused
             invalid_request with field action. */
    }
    item def ContactCommand :> WstxStationCommands::StationRequest {
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
    item def CommandReceipt :> WstxStationCommands::StationOutcome {
        attribute v : Integer = 1;
        attribute command_id : String;
        attribute contact_revision : Integer;
        attribute accepted : Boolean = true;
        doc /* 202 exactly {v:1,profile_id,boot_id,command_id,contact_revision,accepted:true},
             at most 384 bytes: accepted, not yet confirmed effect. Refusals use the
             existing envelope {error:{code,field}} with code a ContactRefusal and field
             the offending JSON key or null; nothing is changed by a refusal. */
    }
    item def ContactSnapshot :> WstxStationCommands::StationOutcome {
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
}
