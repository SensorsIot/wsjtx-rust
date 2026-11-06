package WstxStrategy {
    private import ScalarValues::*;
    doc /* Canonical contract of the strategy engine (issue #39, CL-039-01..07 in
         WstxRequirements; verification TC-039-001..007; the complete New matrix of
         issue #42, CL-042-01 and TC-042-001; its ignore lists, CL-042-02 and
         TC-042-002..003; Pounce, CL-042-03 and TC-042-004..005; Alert, CL-042-04 and
         TC-042-006..007): named strategies, the
         directed-CQ rule, Highlight in Band Activity, the strategy editor popup and Auto
         strategy runs of WstxMcp::OperatingAutomation. Nothing here is an execution
         result.

         Decisions (operator design interview on #37 and comments on #39/#42, 2026-11-01;
         defaults chosen by the implementing CR where the record left a choice open,
         listed on #39):
         D1 One evaluator: the station evaluates every strategy (Evaluate). The browser
            shows verdicts (POST /strategy/evaluate) and never evaluates a rule itself;
            Auto uses the same verdicts.
         D2 Data in this slice: worked status from the internal log (call and 4-character
            grid, ever or on this band and mode, WstxContact::WorkedBeforeQuery); the
            continent of a station is its cty.dat entity's (ContinentOfCall, #55, also
            without a grid); distance and azimuth come from the grid in its message
            (none without a grid). #42 completes the New matrix: new DXCC entity,
            continent, CQ zone and ITU zone of the sender's entity, ever or on this band
            and mode (NewEntity). DXCC and CQ/ITU zone list conditions and the rarest
            sort are not offered yet (CL-039-07).
         D3 Treat 73 as CQ: an RR73 or 73 that ends another station's QSO counts as
            calling for message type cq, in Highlight and Auto; Auto answers from its free
            Tx slot (FreeTxSlot) so the answer never lands on the final 73.
         D4 Auto roles in the first version: Auto Call (answer the best matching CQ),
            Auto CQ (call CQ, answer the best caller) and Alternate (switch between them
            after switch_after consecutive tries without a contact).
         D5 No QSO or time limit is offered: the Tx watchdog bounds Auto
            (WatchdogFromOperator). The browser's Auto sends the WstxMcp run bounds at
            their maxima (max_contacts 100, max_run_minutes 480).
         D6 Skip after N: a station given up after skip_after partner periods without an
            answer is skipped for the rest of the run; the run goes on (no stop).
         D7 Manual intervention (operator decision #39, 2026-11-04): a double-click is
            always possible, also during a strategy; the strategy stays selected and resumes
            after the manual QSO (ManualIntervention). The first Auto use in a page session
            asks for confirmation once.
         D8 Out (operator decision on #42): band hopping, also as a suggestion; Rapid
            RR73; unauthenticated UDP control; shell-command alerts.
         D9 Ignore lists (#42, IgnoreLists): a permanent list in Settings > General and a
            session list filled from Band Activity (right-click Ignore), with a timed
            expiry and cleared on a band change. They govern the strategy only
            (Highlight, Auto Call, Auto CQ); a manual Reply, Select or double-click of an
            ignored station is still the operator's explicit choice and is not refused.
         D10 Pounce (#42, Pounce; WSJT-Z's "wait for one call"): an operator action arms a
            watch for exactly one call on the current band and mode; when that station
            calls CQ or ends a QSO with RR73/73 the station answers it as a double-click
            does (select, Enable Tx, Auto Seq). It is a WstxMcp::OperatingAutomation run
            (one run at a time: never beside Auto Call or Auto CQ), needs no strategy and
            ends on success, a band change, HALT, the Tx watchdog or the operator.
         D11 Alert (#42, Alert): a third action beside Highlight and Auto. A rule marked
            alert makes the station record an alert for each decode that matches it
            (ignore lists and the directed-CQ rule apply first; one alert per call and
            band in 10 minutes) in a bounded alert history in station memory; the
            browser plays a short sound and/or shows a browser notification as the
            operator chose (both off by default). An alert never transmits and changes no
            contact or automation state. Shell-command alerts stay out (D8). */

    enum def MessageType { enum cq; enum directed_cq; enum to_me; enum signoff; }
    enum def NewScope { enum ever; enum band; }
    enum def ConditionKind {
        enum 'message'; enum new_call; enum new_grid; enum continent; enum distance_km;
        enum azimuth_deg; enum snr_db; enum dt_s; enum audio_hz; enum call; enum cq_target;
        enum band; enum new_dxcc; enum new_continent; enum new_cq_zone; enum new_itu_zone;
    }
    enum def SortOrder { enum strongest; enum weakest; enum furthest; enum newest; }
    enum def AutoRole { enum call; enum cq; enum alternate; }
    attribute def Condition {
        attribute kind : ConditionKind;
        attribute negate : Boolean;
        doc /* Wire keys: {kind, negate} plus value (message: MessageType; new_call,
             new_grid, new_dxcc, new_continent, new_cq_zone, new_itu_zone: NewScope), or values (continent: unique AF AN AS EU NA OC SA; call:
             unique 1..13 of A-Z 0-9 /, a prefix match on the sender's call; cq_target:
             unique 1..4 of A-Z 0-9, the word after "CQ "; band: unique ADIF band names,
             stored lower case), 1..32 entries; or min and max (null or a number, at least
             one set; distance_km 0..20038, azimuth_deg 0..360 where min > max wraps
             through north, snr_db -50..49, dt_s -7.5..7.5, audio_hz 0..3500; min <= max
             otherwise; bounds inclusive). Exactly these keys.
             Holds (before negation), for a decoded standard message from a resolved call:
             message cq: a CQ (to token "CQ" or "CQ x"), or with treat_73_as_cq an RR73/73
             to a call other than mine; directed_cq: "CQ x"; to_me: to my call; signoff:
             exchange RR73 or 73. new_call ever: the sender is not in the log; band: not
             worked on this band and mode. new_grid: as new_call for the message's grid
             square (no grid: false). new_dxcc, new_continent, new_cq_zone,
             new_itu_zone: NewEntity of the sender. continent: ContinentOfCall of the sender is listed
             (no entity: false). distance_km/azimuth_deg: great circle from my locator
             to the message grid in whole km / whole degrees (no grid: false). snr_db,
             dt_s, audio_hz: the record's value (unknown: false). call: a listed prefix
             starts the sender's call. cq_target: a CQ whose target is listed. band: the
             station band (CAT dial band, else the operating selection band) is listed.
             negate true inverts the result. */
    }
    attribute def Strategy {
        attribute name : String;
        attribute sort : SortOrder;
        attribute treat73AsCq : Boolean;
        attribute applyToCallers : Boolean;
        attribute skipAfter : Integer;
        attribute autoRole : AutoRole;
        attribute switchAfter : Integer;
        assert constraint skipRange { skipAfter >= 1 and skipAfter <= 20 }
        assert constraint switchRange { switchAfter >= 1 and switchAfter <= 20 }
        doc /* Wire keys exactly name (1..32 printable ASCII, no leading/trailing space,
             unique ignoring case), rules (1..8, each {conditions: 0..12 Condition} plus
             the optional alert (#42 Alert: a boolean, absent = false; the snapshot names
             alert only as true on an alert rule, so a false or absent alert reads back
             without the key); rule
             order is priority, rule 1 highest; an empty rule holds for every message),
             sort, treat_73_as_cq, apply_to_callers, skip_after, auto_role, switch_after. */
    }
    attribute def StrategyConfiguration {
        attribute continent : String[0..1];
        attribute active : String[0..1];
        attribute highlight : Boolean;
        attribute strategiesMax : Integer = 16;
        attribute ignoreCallsMax : Integer = 100;
        attribute sessionIgnoreMinutes : Integer = 30;
        assert constraint sessionMinutesRange { sessionIgnoreMinutes >= 1 and sessionIgnoreMinutes <= 720 }
        doc /* Wire keys exactly continent (null: ContinentOfCall of my callsign, else one of
             the seven codes: my continent for the directed-CQ rule), active (null or the
             name of a listed strategy), highlight, strategies (0..16 Strategy),
             ignore_calls (#42 the permanent ignore list: 0..100 unique calls of 1..13
             A-Z 0-9 /, IgnoreLists) and session_ignore_minutes (#42 the session list
             expiry, an integer 1..720, default 30). Persisted
             as strategy.json beside profile.json: {schema_version 1, profile_id, revision,
             configuration}, written atomically like udp.json; missing: the default
             {null, null, false, [], [], 30} at revision 0; a saved configuration written
             before #42 that has neither ignore_calls nor session_ignore_minutes reads
             with [] and 30 (with exactly one of them: malformed); foreign, malformed or larger than
             262144 bytes: configuration null with configuration_error
             invalid_configuration until a PUT replaces it. */
    }
    calc def ContinentOfCall {
        in call : String;
        return continent : String[0..1];
        doc /* #55: the continent of WstxContact::EntityOfCall for the call (with a {cont}
             override of the matching cty.dat entry applied); none when the call has no
             entity (/MM, /AM, unknown prefix). It replaces the earlier locator-rectangle
             approximation: the message grid no longer decides a station's continent.
             The snapshot's derived_continent is ContinentOfCall of my callsign. */
    }
    calc def NewEntity {
        in call : String;
        in scope : NewScope;
        return isNew : Boolean;
        doc /* #42 (CL-042-01), the entity part of the New matrix. The category key of a
             call comes from its WstxContact::EntityOfCall (with the entry's overrides):
             new_dxcc the entity full name (WAE entities by their own name, as
             WstxContact::DecodedEntity new_dxcc), new_continent its continent,
             new_cq_zone its CQ zone, new_itu_zone its ITU zone. The condition holds when
             no logged contact has the sender's key: ever, among all logged contacts;
             band, among the logged contacts on the station band (CAT dial band, else the
             operating selection band) in the operating mode (ADIF MODE, an MFSK record by
             its SUBMODE), the same scope as new_call and new_grid (the #55 decode colours
             keep the WSJT-X band-only rule). A logged call without an entity counts for
             nothing; a logged contact without a band counts only for ever. False when
             the sender has no entity (/MM, /AM, unknown prefix), for band when the
             station band is unknown, and when the log is unreadable (no claim of new).
             The worked set is the log's cached one, rebuilt when the log or the country
             table changes. */
    }
    attribute def IgnoreLists {
        attribute sessionEntriesMax : Integer = 64;
        doc /* #42 (CL-042-02). A sender is ignored when its call (exactly, not as a prefix)
             is on the permanent list (configuration ignore_calls) or on the session list.
             The session list lives in station memory only (never persisted; a station
             restart empties it): at most 64 entries in the order added, each {call, band,
             expiry}, the band being the station band (CAT dial band, else the operating
             selection band; null when unknown) and the expiry session_ignore_minutes
             after the add, both taken when added (adding a listed call again renews
             them and moves it last; adding a 65th call drops the oldest). An entry ends
             at its expiry.
             Band change: the station's contact step (every 50 ms, whether or not a
             browser is connected) compares the station band with the band it saw last;
             any change (also to or from unknown) empties the session list, so it is
             empty before the next Highlight evaluation or Auto step on the new band.
             Effect: an ignored sender's verdict has rank null and is not greyed, why
             "<call> is ignored (session list)" or "(permanent list)" (session first when
             on both); so Highlight gives it no mark and Auto Call never selects it; Auto
             CQ never answers an ignored caller, also when apply_to_callers is off. A
             contact already in progress is not changed by ignoring its partner.
             Band Activity: the right-click menu offers "Ignore <call>" for a row with a
             resolved sender (session list), "Stop ignoring <call>" when that call is on
             the session list, and no ignore item for other rows. Settings > General: the
             permanent list (calls separated by spaces or commas, saved on change with
             PUT /strategy), the session expiry in minutes (saved on change), and the
             session list with each call's remaining minutes and a remove control; the
             list is read again when the drawer opens. */
    }
    attribute def Pounce {
        doc /* #42 (CL-042-03). A pounce is a WstxMcp::OperatingAutomation run whose
             AutomationConfiguration has pounce = <call> (strategy false): one run at a time,
             so at most one pounce and never beside an Auto strategy run (configure and
             start are refused state_conflict run while any run is active). Start also
             needs a known station band (station_band: CAT dial band, else the operating
             selection band; unknown: not_ready band) and captures it with the mode; it
             needs no active strategy. The run snapshot names it: pounce {call, band}
             (null for other runs).
             Each station step, after the WstxMcp checks (halt, context and mode, authority,
             time limit): a station band other than the captured one stops band_changed
             (a contact armed by the run is disarmed).
             Waiting: on each fresh complete publication the candidates are the decoded
             standard records from exactly the pounce call that are a CQ not greyed by
             DirectedCqRule (MyContinent), or an RR73/73 to another call than mine (D3, always
             for a pounce), and whose sender is not ignored (IgnoreLists, both tiers; the
             ignore lists win). The first by sequence is
             answered exactly as Auto Call answers (select_row {replace false}, FreeTxSlot,
             enable_tx with the run's safety revision), so the contact engine calls it in the next own period
             and Auto Seq runs the QSO; last_decision as for every run. Nothing from the
             call: the run keeps waiting (no try is counted, no stop).
             In the contact: completed stops completed (the pounce ends on success,
             whatever completion_action says); max_unanswered_periods partner periods
             without progress disarm and cancel the contact and return to waiting for the
             same call (the pounce stays armed). Every other WstxMcp stop (halted,
             context_changed, authority_lost, time_limit, contact_changed, transmit_stopped,
             tx_watchdog, transmit_refused, provider_error, an explicit stop) is unchanged.
             Browser: the Band Activity right-click menu offers "Pounce <call>" for a row
             with a resolved sender, disabled without transmit capability, outside FT8/FT4
             receive or while another run is active, and "Stop pouncing <call>" while a
             pounce on that call runs (it sends stop). Pounce asks the page session's one
             Auto confirmation (shared with Auto), then sends configure {modes [the live
             mode], ranking first_seen, min_snr_db null, allowed_calls [], blocked_calls [],
             max_contacts 1, max_unanswered_periods 5, completion_action stop,
             max_run_minutes 480, strategy false, pounce <call>} and start with the shown
             safety revision; the browser never sends enable_tx for it. While the pounce
             runs, the QSO pane shows "Pouncing on <call> (<band>) · waiting for CQ or 73"
             or "· in QSO" with a Stop pounce button (stop), and the strategy element's
             status "Pounce <call> waiting" or "in QSO" with "HALT ends it"; the Auto button
             is disabled meanwhile. */
    }
    attribute def Alert {
        attribute historyMax : Integer = 100;
        attribute dedupeMinutes : Integer = 10;
        doc /* #42 (CL-042-04). Station side: the station's contact step (every 50 ms,
             whether or not a browser is connected) reads the records of the current live
             job past its alert cursor once each (a job not seen before from its first
             retained record); the cursor advances also while no strategy is active or no
             rule is marked alert, so marking a rule later never alerts on older decodes.
             With an active strategy that has an alert rule, each new decoded standard
             record with a resolved sender other than my call is evaluated with the
             station facts of Evaluate: an ignored sender (IgnoreLists, both tiers) and a
             CQ greyed by DirectedCqRule never alert; else its alert rule is the first
             rule marked alert all of whose conditions hold (a higher rule without alert
             that also holds does not hide it); none: no alert. Dedupe: no alert when the
             station recorded one for the same call and the same station band
             (station_band at that time; unknown counts as its own band) whose period
             start lies less than 10 minutes before this record's period start (exactly
             10 minutes later alerts again); this memory is kept apart from the history,
             so Clear does not reset it. An alert never transmits, never selects, arms or
             changes a contact, the automation run, the Tx watchdog or the strategy
             store.
             History: station memory only (it survives page reloads, a station restart
             empties it), the last 100 alerts in the order recorded (the 101st drops the
             oldest), each {id (1, 2, ... since the station started), utc (the record's
             period_start_utc), call, message (the record text), rule ("<strategy name>
             rule <n>", n 1-based), band (station band, null when unknown), mode (the live
             job mode, ft8 or ft4), snr_db (null when unknown), dxcc (the full entity name
             of WstxContact::EntityOfCall, null without an entity)}; revision counts every
             alert recorded and every clear since the station started.
             Routes (the StrategyHttp rules for Origin, authorization, media and size): GET
             /strategy/alerts (operating access, no query, empty body) -> {v 1,
             profile_id, boot_id, revision, alerts (oldest first)}. POST
             /strategy/alerts/clear {v, profile_id, boot_id}: exact keys, the refusals of
             POST /strategy/ignore (400 invalid_request with the field,
             unsupported_version, 403 wrong_profile, 409 state_conflict boot_id); it
             empties the history, revision + 1, and returns the alerts snapshot. No MCP
             tool dispatches to the clear (an MCP principal is refused, #58); wstx_read
             view alerts reads GET /strategy/alerts (WstxMcp::ToolCatalog).
             Event: a display-subscribed peer receives alert.state {v 1, type
             "alert.state", data {profile_id, boot_id, alert_revision}} when the revision
             changes after it subscribed (never on subscription itself), paced with
             contact.state; the browser then reads GET /strategy/alerts.
             Browser: the editor offers each rule an "Alert" checkbox (StrategyEditor).
             Settings > General shows an Alerts section: "Sound" and "Browser
             notification" checkboxes, both off by default, kept per browser and profile
             in localStorage (wstx.alerts.v1:<profile_id> = {sound, notify}; unreadable:
             both off); checking Browser notification is the only place that asks for the
             browser's notification permission (Notification.requestPermission on that
             click, never otherwise); a permission other than granted leaves it unchecked
             with the reason. The history list, newest first, each line "<HH:MM:SS> <call>
             <message> · <rule> · <band> <MODE> · <snr> dB · <dxcc>" (unknown parts left
             out), and a Clear button (POST /strategy/alerts/clear). An alert counts as new
             when its id is above the highest id this page has seen (the history read at
             page load or reconnect announces nothing): for each new alert a short tone
             (Web Audio, about 0.15 s) only when Sound is on and the page is visible, and a
             notification titled "Alert <call>" with body "<message> · <rule>" when Browser
             notification is on and permission is granted (also while the page is hidden);
             with both off nothing is announced (the history still lists it). */
    }
    calc def DirectedCqRule {
        in target : String[0..1];
        in myContinent : String[0..1];
        in senderContinent : String[0..1];
        return answerable : Boolean;
        doc /* The one directive rule of strategies and the operator (operator decision #39,
             2026-11-04), applied before any strategy and one function in the station. A CQ
             is answerable when its directive does not exclude me: a plain CQ (no target);
             "CQ x" with x my continent; "CQ DX" when both continents are known and differ.
             Every other directive is not answerable: another continent or region (NA, JA,
             SA, ...), any other word (TEST, POTA, a number), CQ DX from my own or an unknown
             continent, and with my continent unknown every directive. A record that is no
             CQ has no directive and is answerable. Its text is "CQ x — not for <my continent>"
             ("not for this station" when unknown).
             My continent: MyContinent.
             A strategy skips a CQ that is not answerable: it is greyed in Band Activity,
             never matches a rule and is never answered by a run or a pounce. An operator's
             selection of such a row (double-click, Reply, Select, the other-calls list) is
             refused directive_not_answerable (409 with error.reason = this text); the
             browser shows it as a warning the operator can confirm, and only then sends
             select_row again with the optional directive_confirmed true. A command that is
             not the browser's (automation, MCP, UDP) can never confirm it: its select_row is
             refused directive_not_answerable also with directive_confirmed. */
    }
    calc def MyContinent {
        in configured : String[0..1];
        in callsign : String[0..1];
        in locator : String[0..1];
        return continent : String[0..1];
        doc /* The configured continent (StrategyConfiguration continent) when set; else
             ContinentOfCall of the profile callsign; else, when the call has no entity
             (/MM, /AM, unknown prefix), the continent of the cty.dat entity whose centre
             is nearest to the centre of the profile locator; else none. */
    }
    attribute def ManualIntervention {
        doc /* A strategy run (OperatingAutomation with strategy true) and a manual contact
             (operator decision #39, 2026-11-04). The run never disarms or cancels it and
             does not stop: when a contact it did not select is on the engine (a double-click,
             Reply or DX entry replacing its contact, or made while it waits), the run state
             is manual until that contact is no longer active (completed, cancelled or
             logged), then waiting: it resumes. While manual it selects nothing. The operator
             cancelling or aborting the run's own contact (F4, Esc) gives that station up for
             the rest of the run (it is not selected again) and the run goes on waiting; a
             cancelled own CQ of a run in role cq or alternate lets the run call CQ again at
             its next step. A command of the run refused because the operator's contact
             arrived first (the double-click racing its select_row or enable_tx) makes it
             manual too: it cancels and disarms nothing.
             A pounce and an MCP run keep their contact_changed stop. HALT stops every run. */
    }
    attribute def Verdict {
        attribute sequence : Integer;
        attribute rank : Integer[0..1];
        attribute grey : Boolean;
        doc /* One per decoded standard record with a resolved sender (others have none):
             an ignored sender (IgnoreLists) has rank null, grey false; else grey per
             DirectedCqRule; else rank = index (0-based) of the first rule all of
             whose conditions hold, null when none. why (explain only): "matches rule n",
             "no match (rule n: <first failing condition>; ...)", the DirectedCqRule text
             "CQ x — not for c" or "<call> is ignored (session list)" /
             "(permanent list)". Display order: rank ascending, then the sort
             (strongest: SNR descending, weakest: SNR ascending, furthest: distance
             descending, newest: sequence descending; unknown values last), then sequence;
             records without a rank follow in sequence order. */
    }
    attribute def StrategyHttp {
        attribute bodyBytesMax : Integer = 32768;
        attribute evaluateRecordsMax : Integer = 2048;
        doc /* GET /strategy (operating access, no query, empty body): {v 1, profile_id,
             boot_id, revision, configuration (or null), configuration_error, my_continent
             (configured, else derived; null when unknown), derived_continent,
             session_ignore (#42: the session list in the order added without ended
             entries, each {call, band, remaining_s: whole seconds to its expiry, rounded
             up})}.
             POST /strategy/ignore {v, profile_id, boot_id, call, ignore} (#42): exact
             keys; same Origin/authorization/media/size rules and refusal codes as PUT
             /strategy (400 invalid_request with the field, unsupported_version, 403
             wrong_profile, 409 state_conflict boot_id); call 1..13 of A-Z 0-9 /; ignore
             true adds the call to the session list (or renews it), false removes it (not
             listed: no change). It changes no revision, is allowed while Auto runs and
             applies at the next evaluation; returns the snapshot. No MCP tool dispatches
             to it (an MCP principal is refused, #58 principal guard).
             PUT /strategy {v, profile_id, boot_id, expected_revision, configuration}:
             exact keys; same Origin/authorization/media/size rules and refusal codes as
             PUT /udp (400 invalid_request with the field, unsupported_version, 403
             wrong_profile, 409 state_conflict boot_id, 409 stale_revision, 409
             state_conflict active when the active name would change while an Auto
             strategy run is active); returns the snapshot with revision + 1.
             POST /strategy/evaluate {v, profile_id, boot_id, source_id, job_id,
             generation, first_sequence, next_sequence (0 <= next - first <= 2048),
             strategy (null: the saved active strategy, else a draft Strategy), explain}:
             the verdicts of the retained live records [first, next) of exactly that live
             job (another job: 409 stale_request job_id; no active strategy: 409
             not_configured strategy) in display order: every one when explain, else only
             those with a rank or grey. Never changes station state. */
    }
    attribute def HighlightView {
        doc /* Highlight on (configuration highlight with an active strategy): after a
             period is complete (or at most every 15 s while it loads) the browser asks
             POST /strategy/evaluate for the shown sequences of the current live identity
             once; matching rows get the strategy mark and rule number and move to the top
             of their period block in display order; greyed rows are dimmed and struck
             through; other rows keep the ActivityOrdering. Highlight off: no evaluation
             request and no mark. An ignored sender (IgnoreLists) gets no mark; after an
             Ignore or Stop ignoring the shown rows are evaluated again. Choosing a strategy or toggling Highlight is one PUT
             /strategy; it never restarts receive. */
    }
    attribute def StrategyEditor {
        doc /* The edit (pencil) popup (a modal dialog carrying its own HALT with the top-bar HALT's
             action and enabled state; receive keeps running): choose, add, duplicate and
             delete strategies; name; rules with conditions (kind, not, value) in priority
             order, each rule with its "Alert" checkbox (#42 Alert: sound or notification,
             never transmits); sort; Treat 73 as CQ; Auto role, switch after, skip after,
             Auto CQ answers only matching callers. The live preview evaluates the unsaved draft
             against the latest period (POST /strategy/evaluate with explain, 400 ms after
             an edit) and shows each decode's rank and why. Save sends one PUT /strategy
             and applies at once (also to a running Auto run); the edited strategy becomes
             active when none is. My continent is set in Settings > General
             (StrategyConfiguration continent, saved by PUT /strategy). */
    }
    attribute def AutoStrategyRun {
        doc /* The Auto button: the first use in a page session asks once (popup naming the
             strategy, the role and the watchdog); then AutomationCommand configure with
             {modes [current mode], ranking first_seen, min_snr_db null, empty call lists,
             max_contacts 100, max_unanswered_periods 20, completion_action
             next_candidate, max_run_minutes 480, strategy true} and start with the shown
             safety revision. While the run is active the button shows its state (waiting,
             CQ, the partner call), the strategy cannot be switched, and a click sends stop.
             The browser itself never sends enable_tx for Auto.
             At the station a strategy run (WstxMcp::OperatingAutomation with strategy
             true) needs the active strategy at start (else not_configured strategy) and
             reads it at every step (none: stop strategy_missing). Role Call or Alternate
             starts as Auto Call, Cq as Auto CQ; a saved role other than alternate applies
             at the next step.
             Auto Call (waiting): on each fresh complete publication the candidates are
             the verdicts with a rank, cq-like (D3), not greyed (DirectedCqRule), a sane call (SaneCall), not ignored (IgnoreLists: no
             rank),
             not mine, not completed or skipped in this run, one per call, in display
             order; the first is selected (select_row), Tx takes its free slot (FreeTxSlot)
             and it is armed (enable_tx). No candidate: one try.
             Auto CQ (waiting in role cq): FreeTxSlot, then enable_tx with no contact in
             progress (a new own CQ, calling_cq). On each fresh partner-parity publication the callers are
             the messages to my call that are not RR73/73 (no tailender after their sign-
             off), from a sane, not ignored (IgnoreLists), not completed or skipped call, matching the strategy only
             when apply_to_callers, in display order (all rank 0 otherwise); the first is
             selected (the armed CQ becomes that contact). No caller: one try.
             Alternate: switch_after consecutive tries switch Call -> CQ or CQ -> Call
             (the CQ is cancelled); a contact resets the tries.
             A contact the run did not select: ManualIntervention.
             In a contact: completion counts and returns to waiting (CQ again in role
             cq); skip_after partner periods without progress give the station up (D6),
             disarm and cancel the contact and count a try. All other WstxMcp stops
             (halted, context, authority, time, transmit stopped) are
             unchanged; a disarm by the Tx watchdog stops tx_watchdog. */
    }
    attribute def FreeTxSlot {
        doc /* A strategy run or a pounce (not a plain MCP policy run, not manual operation)
             calls from a free audio slot (operator decision 2026-11-04, #39). Decided once
             per call, between QSOs: when Auto Call or a pounce has selected its candidate,
             and when Auto CQ starts a new own CQ; never during a contact or a running CQ.
             Occupied: every decoded record of the last 4 periods of my Tx parity (the
             parity after the selection) that decoded anything, among the records of
             complete publications; a period I transmitted in decodes nothing and is not
             counted, so older periods are used rather than none. Fewer periods: those
             there are. Auto Call and a pounce add the called station's frequency, which is
             not on my parity.
             Signal width, from the record's frequency_hz upwards: FT8 50 Hz, FT4 90 Hz,
             mine alike. A slot is free when 50 Hz or more separate my signal from every
             occupied signal, and my whole signal lies inside 300..2700 Hz within the Tx
             range (FrequencyControls): FT8 slots 300..2650, FT4 300..2610.
             Choice: the free slot nearest the current Tx, then the lowest, so a free
             current Tx is kept and a new slot is chosen only when the current one has
             become busy. The decision may instead be asked for the free slot nearest a list
             of preferred frequencies, then nearest the current Tx, then the lowest.
             No free slot: Tx keeps the current frequency, the call still goes out (no
             refusal), and the status says so: the run's tx_slot {hz, free} (WstxMcp), and
             "no free Tx slot" in the station bar's automation text.
             Tx is moved with set_frequency only when it is not on the slot (with Hold Tx
             off the selection has moved it to the station: it goes back). The Tx stays on
             the slot for the whole QSO: answering a caller of my CQ never moves it, also
             when the caller calls on my frequency, and the "may" of the operator's rule (Tx
             to the partner's frequency once the QSO is established) is not taken, so
             there is nothing to return from. The next decision starts from the Tx the
             operator may have set meanwhile. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    attribute def WatchdogFromOperator {
        doc /* The Tx watchdog counts unanswered own transmissions (WstxContact::TxWatchdog,
             operator redefinition 2026-11-04) and is never paused or reset by
             automation. Only an answer (a decoded message addressed to my call from the
             partner, or from anyone to my CQ) or a human action in the browser resets
             it: an Enable Tx, any accepted ContactCommand or an Auto start sent by the
             browser (principal browser, WstxProfiles::RequestPrincipalRule: read from
             the credential at the auth boundary, so an MCP client is never one on any
             route, #58). Never operator actions: commands of a run (select_row,
             set_frequency, enable_tx, cancel, disarm), any MCP request (also starting or
             restarting a run) and any UDP command (Reply, Free Text). Such an enable_tx
             arms with the count kept and is refused tx_watchdog when the limit is used
             up or no browser action was seen this boot (until a human acts in the
             browser; after a watchdog stop an answer no longer resets it); a run selecting a new station does not reset
             it; only the browser may change the watchdog setting (set_watchdogs from any
             other source is refused operator_required). At the limit Enable Tx goes off
             without a halt and a run stops tx_watchdog.
             Halt from any source stops the run; grant, clock, period and safety-revision
             checks are unchanged. */
    }

    dependency storeClause from StrategyConfiguration to WstxRequirements::'CL-039-01';
    dependency evaluateClause from Verdict to WstxRequirements::'CL-039-02';
    dependency newEntityClause from NewEntity to WstxRequirements::'CL-042-01';
    dependency ignoreClause from IgnoreLists to WstxRequirements::'CL-042-02';
    dependency pounceClause from Pounce to WstxRequirements::'CL-042-03';
    dependency pouncePath from Pounce to WstxMcp::OperatingAutomation;
    dependency alertClause from Alert to WstxRequirements::'CL-042-04';
    dependency directedClause from DirectedCqRule to WstxRequirements::'CL-039-03';
    dependency myContinentClause from MyContinent to WstxRequirements::'CL-039-03';
    dependency manualClause from ManualIntervention to WstxRequirements::'CL-039-05';
    dependency highlightClause from HighlightView to WstxRequirements::'CL-039-04';
    dependency editorClause from StrategyEditor to WstxRequirements::'CL-039-04';
    dependency autoClause from AutoStrategyRun to WstxRequirements::'CL-039-05';
    dependency freeSlotClause from FreeTxSlot to WstxRequirements::'CL-039-09';
    dependency freeSlotRun from AutoStrategyRun to FreeTxSlot;
    dependency freeSlotPounce from Pounce to FreeTxSlot;
    dependency watchdogClause from WatchdogFromOperator to WstxRequirements::'CL-039-06';
    dependency automationPath from AutoStrategyRun to WstxMcp::OperatingAutomation;
    dependency watchdogOwner from WatchdogFromOperator to WstxContact::TxWatchdog;
}
