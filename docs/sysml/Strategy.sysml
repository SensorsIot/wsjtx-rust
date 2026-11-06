package WstxStrategy {
    private import ScalarValues::*;
    doc /* Canonical contract of the strategy engine (issue #39, CL-039-01..07 in
         WstxRequirements; verification TC-039-001..007, TC-039-030..031 and TC-039-033; the ignore
         lists of issue #42, CL-042-02 and TC-042-002..003; Pounce, CL-042-03 and
         TC-042-004..005; Alert, CL-042-04 and TC-042-006..007): the award strategies, the
         directed-CQ rule, the value order in Band Activity, the strategy editor popup and
         the strategy runs of WstxMcp::OperatingAutomation. Nothing here is an execution
         result.

         Decisions (operator decisions on #39, 2026-11-04 to 2026-11-06, comments
         6626205191, 6626483800, 6626497059, 6626745310, 6626929588, 6626981068,
         6627875105, and the implementing CR's defaults, listed on #39):
         D1 One evaluator: the station evaluates every strategy (Verdict). The browser
            renders the verdicts (POST /strategy/evaluate) and never evaluates anything
            itself; a run uses the same verdicts.
         D2 What a strategy is: the goal of a strategy is to auto-call. Exactly one strategy
            is active, or none (manual operation). Selecting it starts it (no separate
            Highlight, Auto or Start); None stops it. The browser sends only the selection. Only the class award has behaviour;
            contest is #63 and is refused on the wire until then (StrategyClass).
         D3 Treat 73 as CQ: an RR73 or 73 that ends another station's QSO counts as calling;
            the run answers from its free Tx slot (FreeTxSlot) so the answer never lands on the
            final 73.
         D4 An award strategy never calls CQ. It waits for the next opportunity and goes on
            after each QSO without a limit (no QSO limit; the WstxMcp run bounds and the
            transport's 8 h do not apply to it; its own limit is 8 hours from the selection,
            operator decision 2026-11-06, StrategyRun, which replaces the former "no time limit").
            The grant and every safety check still apply.
         D5 Stations calling my callsign are always answered, independent of goal, region
            and SNR, and come first (CallerOfMyCall).
         D6 No skip: a station is never skipped after N calls. calls_per_station is the
            number of consecutive calls before the run goes to the best other candidate of
            the next publication; it may come back. Only the operator gives a station up
            for a run (ManualIntervention).
         D7 Manual intervention (#39, 2026-11-04): a double-click is always possible, also
            during a strategy; the strategy stays selected and resumes after the manual
            QSO (ManualIntervention).
         D8 Out (operator decision on #42): band hopping, also as a suggestion; Rapid
            RR73; unauthenticated UDP control; shell-command alerts.
         D9 Ignore lists (#42, IgnoreLists): a permanent list in Settings > General and a
            session list filled from Band Activity (right-click Ignore), with a timed
            expiry and cleared on a band change. They govern the strategy only (marks,
            runs); a manual Reply, Select or double-click of an ignored station is still
            the operator's explicit choice and is not refused.
         D10 Pounce (#42, Pounce; WSJT-Z's "wait for one call"): an operator action arms a
            watch for exactly one call on the current band and mode; when that station
            calls CQ or ends a QSO with RR73/73 the station answers it as a double-click
            does (select, Enable Tx, Auto Seq). It is a WstxMcp::OperatingAutomation run
            (one run at a time: never beside a strategy run), it is not a strategy, and it
            ends on success, a band change, HALT, the Tx watchdog or the operator.
         D11 Alert (#42, Alert): without a setting. The station records an alert for each
            new candidate of the active strategy in a bounded history in station memory;
            the browser plays a short sound and/or shows a browser notification as the
            operator chose (both off by default). An alert never transmits and changes no
            contact or automation state.
         D12 Most Wanted list (#39 6626483800, MostWantedList): the operator asked for
            "download and refresh like cty.dat". This project's cty.dat has no automatic
            download (bundled file plus Settings upload, WstxContact country file), so the
            list is kept simple (operator 2026-11-06: "Most wanted countries stay forever. They do
            not change a lot. We have to find an extremely simple way to update it from time to
            time."): a Settings section with one button "Update Most Wanted" beside the list's
            date that fetches it once on the operator's click. There is no upload (operator:
            "Why would we upload something?"); a failed download keeps the list.
            Terms check (2026-11-06): the clublog.org pages mostwanted.php, need_api and
            requestapikey state no terms and no limits; the footer says "Club Log (c)
            Michael Wells G7VJR"; need_api says "You do not need a key unless you write
            software which integrates with Club Log", requestapikey says "A developer API
            key is no longer required". Permission to redistribute or fetch automatically
            is not established, and the operator ruled (#39 comment 6685317139): no automatic
            refresh and nothing bundled. Everything works without a list.
         D14 Built-in strategies (operator 6626205191 (5)) are the slice presets, the next slice
            on #39; until it lands the selector offers None and the user's strategies.
         D13 Grids are a known-unknown: only 6,729 of the operator's 26,902 Log4OM QSOs carry
            a grid, so a missing grid is unknown, never new (GoalNeeded grid). */

    enum def StrategyClass {
        doc /* award: the only class with behaviour. contest (#63) is refused on the wire
             (400 invalid_request, field ...class) until #63 defines it. */
        enum award;
    }
    enum def Goal { enum dxcc; enum dxcc_band; enum dxcc_slot; enum waz; enum wpx; enum grid; enum new_call; }
    enum def Needed { enum not_worked; enum not_confirmed; }
    enum def RegionKind { enum 'all'; enum dx; enum selected; }
    enum def WindowKind { enum 'all'; enum today; enum from_to; }
    attribute def Strategy {
        attribute name : String;
        attribute strategyClass : StrategyClass;
        attribute needed : Needed;
        attribute minSnrDb : Integer[0..1];
        attribute callsPerStation : Integer = 3;
        attribute treat73AsCq : Boolean;
        assert constraint callsRange { callsPerStation >= 1 and callsPerStation <= 20 }
        doc /* Wire keys exactly: name (1..32 printable ASCII, no leading/trailing space,
             unique ignoring case); class "award"; goals (1..7 unique Goal, multiple choice,
             a station is needed when at least one goal is needed); needed; region {kind all}
             | {kind dx} | {kind selected, continents: 1..7 unique of AF AN AS EU NA OC SA};
             min_snr_db (null or an integer -50..49); calls_per_station (1..20; the browser's
             new strategy starts with 3); treat_73_as_cq (boolean); window {kind all} |
             {kind today} | {kind from_to, from, to}: from and to are real calendar dates
             "YYYY-MM-DD" between 1930-01-01 and 2099-12-31 with from <= to. Each refusal
             names its field path (strategies[0].window.to). Nothing else exists: rules,
             conditions, sort, auto role, switch after, skip after and callers are gone. */
    }
    attribute def StrategyConfiguration {
        attribute continent : String[0..1];
        attribute active : String[0..1];
        attribute strategiesMax : Integer = 16;
        attribute ignoreCallsMax : Integer = 100;
        attribute sessionIgnoreMinutes : Integer = 30;
        assert constraint sessionMinutesRange { sessionIgnoreMinutes >= 1 and sessionIgnoreMinutes <= 720 }
        doc /* Wire keys exactly continent (null: ContinentOfCall of my callsign, else one of
             the seven codes: my continent for the directed-CQ rule and region dx), active
             (null or the name of a listed strategy), strategies (0..16 Strategy),
             ignore_calls (#42 the permanent ignore list: 0..100 unique calls of 1..13
             A-Z 0-9 /, IgnoreLists) and session_ignore_minutes (#42 the session list
             expiry, an integer 1..720, default 30). Persisted as strategy.json beside
             profile.json: {schema_version 2, profile_id, revision, configuration}, written
             atomically like udp.json; missing: the default {null, null, [], [], 30} at
             revision 0; foreign, malformed or larger than 262144 bytes: configuration null
             with configuration_error invalid_configuration until a PUT replaces it.
             active does not survive a station restart: the file always holds active null
             and any active read is None, so the station never transmits after a restart
             without a human selection.
             Upgrade: a file of schema_version 1 (the configuration with rules, sort, auto
             role and highlight) reads as: strategies dropped, active None, continent and
             the ignore keys kept at its revision (one written before #42 with neither
             ignore key reads [] and 30; with exactly one of them, or a bad continent, it
             is malformed). It is written as schema 2 by the next PUT. */
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
    calc def GoalNeeded {
        in strategy : Strategy;
        in goal : Goal;
        in sender : String;
        return needed : Boolean;
        doc /* Whether one goal is needed for a decoded sender, against WorkedWindow of the
             strategy, needed = not_worked: not worked; not_confirmed: not worked or not
             confirmed (dxcc::Standing). dxcc: the sender's entity (WstxContact::EntityOfCall,
             WAE entities by their own full name) ever. dxcc_band: that entity on the station
             band in any mode. dxcc_slot: that entity on the station band and in the operating
             mode (ADIF MODE, an MFSK record by its SUBMODE). waz: the CQ zone of the sender's
             entity (with the entry's overrides) ever. wpx: WpxPrefix of the call ever.
             new_call: the call ever. grid: the 4-character grid square in the decoded message
             ever, with the rule of D13: no grid in the message is not needed; a sender with a
             logged QSO without a grid (in the window) has an unknown grid status and is not
             needed. False without an entity (dxcc, dxcc_band, dxcc_slot, waz; /MM, /AM,
             unknown prefix), without a known station band (dxcc_band, dxcc_slot) and when
             the log is unreadable (no claim of needed). A logged call without an entity
             counts for nothing; a logged contact without a band counts only for ever. */
    }
    calc def WpxPrefix {
        in call : String;
        return prefix : String;
        doc /* The CQ WPX prefix of a call, from the CQ WPX Contest rules: the letters and
             digits up to and including the last digit (N8BJQ N8, HG19ABC HG19, LY1000X LY1000,
             3DA0RU 3DA0, 9A1A 9A1). A call without a digit: its first two letters and a zero
             (XEFTJW XE0). Portable: /P /M /MM /AM /A /E /J /QRP /B and /R do not count
             (N8BJQ/P N8); a single digit replaces the call's last digit (N8BJQ/3 N3); another
             designator is the prefix: with a digit up to its last digit (N8BJQ/KH9 KH9,
             KH9/N8BJQ KH9), without one its first two letters and a zero (PA/N8BJQ PA0).
             The designator is the shorter part, the left one when both are equally long.
             Upper case. */
    }
    attribute def WorkedWindow {
        doc /* window all: the log's cached worked set (rebuilt after a log or country table
             change). today (the current UTC date) and from_to: a worked set built only from
             the records whose QSO_DATE lies in the window, inclusive; cached per (log
             revision, country table, first date, last date; today is its UTC date), at most 4
             windows, so it is not rebuilt per evaluation. A record without a date counts only
             for all. A rebuild takes about 100 ms with 26,902 QSOs (measured 2026-11-06, release
             build, two station steps), so it never runs on the station step: the step uses the
             last built set of the window at once, and a set missing or behind the log is
             built on its own thread for a later step. A selection and POST /strategy/evaluate
             (blocking threads) wait for the current set. With no set yet nothing is
             needed in that step (no claim of needed). */
    }
    attribute def CallerOfMyCall {
        doc /* A decoded standard message with a resolved sender, addressed to my call, other
             than the sender's RR73/73, whose sender is not ignored (IgnoreLists). It is always
             answered: no goal, region, SNR or callsign guard applies. In a run it is only
             excluded when completed in this run on this band and mode, or given up by the operator
             (ManualIntervention). */
    }
    attribute def Candidate {
        doc /* A decoded standard message with a resolved sender, not mine, passing SaneCall,
             not ignored (IgnoreLists), not greyed (DirectedCqRule), a CQ, or with
             treat_73_as_cq an RR73/73 addressed to someone else; region holds (all; dx: my
             continent and the sender's are known and differ; selected: the sender's continent
             is listed); min_snr_db null or the SNR known and >= it; and GoalNeeded for at
             least one goal. */
    }
    attribute def ValueOrder {
        doc /* The order the station ranks in. Band Activity: the partner (#50, on top by the
             browser's partner rows), then callers (CallerOfMyCall), candidates most valuable
             first, then the rest. Callers among themselves: SNR strongest (unknown last), then
             sequence. Candidates: on the Most Wanted list first, by its rank ascending; then
             the others, and all of them without a list, SNR strongest (operator 2026-11-06, which
             replaces a DXCC-new rank); then sequence. */
    }
    attribute def MostWantedList {
        attribute entriesMax : Integer = 1000;
        doc /* D12. Source https://clublog.org/mostwanted.php?api=1: JSON {"1":"344","2":"123",
             ...}, rank to ADIF DXCC number (340 entries, verified 2026-11-06). Parsed exactly:
             an object of 1..1000 keys, each a positive integer in text, each value a positive
             integer below 10000 in text or as a number, no number twice; else the update fails,
             nothing changed. Stored in the profile folder as
             most_wanted.json {schema_version 1, profile_id, date (UTC date of the download), list}. cty.dat has no ADIF numbers: the
             table most_wanted::ENTITIES maps cty.dat entity full names to ADIF numbers (the
             340 current entities; WAE-only entities, Sicily, African Italy, Bear Island,
             Shetland Islands, European Turkey and Vienna Intl Ctr, carry their DXCC parent's
             number). A number of the list without a table entry is ignored and counted as
             unmapped in the status. An entity not in the table or not on the list has no rank
             (ValueOrder sorts it after the listed ones). A list once fetched stays until the next
             update. The file is read off the station step (the first
             GET /strategy, POST /strategy/evaluate or selection, on a blocking thread); the
             step only reads a parsed Arc behind a leaf lock. An unreadable file: no list,
             most_wanted_unreadable true.
             Status in the GET /strategy snapshot: most_wanted null or {date, entries,
             unmapped}, most_wanted_unreadable, most_wanted_attribution "Club Log Most Wanted
             list, Club Log (c) Michael Wells G7VJR, clublog.org".
             Browser, Settings > General: "List from <date> · <entries> entries" (and how many
             are not mapped), or "No list; strategies call the strongest first", with beside it one
             button "Update Most Wanted"; one click does everything. A failure keeps the list and shows the
             reason in one line.
             POST /strategy/most-wanted/download {v, profile_id, boot_id}:
             the station fetches the source once on the operator's click, with the User-Agent
             of most_wanted::USER_AGENT naming this project; a failure or a reply that is no list is 502 download_failed with
             error.reason, nothing changed. Exact keys, with the refusals of POST /strategy/ignore, and
             it returns the snapshot; no MCP tool dispatches to it. There is no automatic
             refresh. */
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
             empty before the next evaluation or run step on the new band.
             Effect: an ignored sender's verdict has rank null and is not greyed, why
             "<call> is ignored (session list)" or "(permanent list)" (session first when
             on both); so it gets no mark, a run never selects it, also when it calls me. A
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
             so at most one pounce and never beside a strategy run (configure and
             start are refused state_conflict run while any run is active; selecting a strategy
             ends a running pounce). Start also
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
             answered exactly as a strategy run answers (select_row {replace false}, FreeTxSlot,
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
             pounce on that call runs (it sends stop). Pounce asks once per page session,
             then sends configure {modes [the live
             mode], ranking first_seen, min_snr_db null, allowed_calls [], blocked_calls [],
             max_contacts 1, max_unanswered_periods 5, completion_action stop,
             max_run_minutes 480, strategy false, pounce <call>} and start with the shown
             safety revision; the browser never sends enable_tx for it. While the pounce
             runs, the QSO pane shows "Pouncing on <call> (<band>) · waiting for CQ or 73"
             or "· in QSO" with a Stop pounce button (stop), and the strategy element's
             status "Pounce <call> waiting" or "in QSO" with "HALT ends it". */
    }
    attribute def Alert {
        attribute historyMax : Integer = 100;
        attribute dedupeMinutes : Integer = 10;
        doc /* #42 (CL-042-04, without a setting since #39 2026-11-06). Station side: the
             station's contact step (every 50 ms, whether or not a browser is connected) reads
             the records of the current live job past its alert cursor once each (a job not seen
             before from its first retained record); the cursor advances also while no strategy
             is active, so a later selection never alerts on older decodes. With an active
             strategy, each new record that is a Candidate of it (Verdict, its window and list)
             records an alert; a caller of my call, an ignored sender and a CQ greyed by
             DirectedCqRule never alert. Dedupe: no alert when the
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
             period_start_utc), call, message (the record text), rule (the strategy name),
             band (station band, null when unknown), mode (the live
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
             Browser: Settings > General shows an Alerts section: "Sound" and "Browser
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
             is never a Candidate and is never answered by a run or a pounce. An operator's
             selection of such a row (double-click, Reply, Select, the other-calls list) is
             refused directive_not_answerable (409 with error.reason = this text); the
             browser shows it as a warning the operator can confirm, and only then sends
             select_row again with the optional directive_confirmed true. The directive is checked
             before contact_active, so during a contact a plain click (select_row without replace) on
             such a row is refused this way too and offers nothing (CL-037-05); a double-click warns. A command that is
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
             the rest of the run (it is not selected again, also not when it calls me) and the
             run goes on waiting. A command of the run refused because the operator's contact
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
             DirectedCqRule; a caller (CallerOfMyCall) and a Candidate have rank = the position
             (0-based) in ValueOrder among the evaluated records; every other record rank null.
             why (explain only): "calls my call", "needed: dxcc, grid", with " · Most Wanted
             #n" when ranked by the list, "not needed", "not a CQ", "region", "below min SNR",
             "my own message", "callsign guard", the DirectedCqRule text "CQ x — not for c" or
             "<call> is ignored (session list)" / "(permanent list)". Display order: rank
             ascending; records without a rank follow in sequence order. */
    }
    attribute def StrategyHttp {
        attribute bodyBytesMax : Integer = 32768;
        attribute evaluateRecordsMax : Integer = 2048;
        doc /* GET /strategy (operating access, no query, empty body): {v 1, profile_id,
             boot_id, revision, configuration (or null), configuration_error, my_continent
             (configured, else derived; null when unknown), derived_continent,
             session_ignore (#42: the session list in the order added without ended
             entries, each {call, band, remaining_s: whole seconds to its expiry, rounded
             up}) and the MostWantedList status}.
             POST /strategy/ignore {v, profile_id, boot_id, call, ignore} (#42): exact
             keys; same Origin/authorization/media/size rules and refusal codes as PUT
             /strategy (400 invalid_request with the field, unsupported_version, 403
             wrong_profile, 409 state_conflict boot_id); call 1..13 of A-Z 0-9 /; ignore
             true adds the call to the session list (or renews it), false removes it (not
             listed: no change). It changes no revision, is allowed while a strategy runs and
             applies at the next evaluation; returns the snapshot. No MCP tool dispatches
             to it (an MCP principal is refused, #58 principal guard).
             PUT /strategy {v, profile_id, boot_id, expected_revision, configuration}:
             exact keys; same Origin/authorization/media/size rules and refusal codes as
             PUT /udp (400 invalid_request with the field, unsupported_version, 403
             wrong_profile, 409 state_conflict boot_id, 409 stale_revision); returns the
             snapshot with revision + 1. It is a browser action: an MCP principal is refused 401
             at the boundary (#58 principal guard) and no MCP tool dispatches to it, so an MCP
             client can never select a strategy. A changed active starts or stops a run
             (StrategyRun); saving anything else leaves a running strategy running and applies
             at its next step.
             strategy.state {v 1, type "strategy.state", data {profile_id, boot_id,
             strategy_revision}}: a display-subscribed peer receives it when the revision
             changes after it subscribed (never on subscription itself), paced with
             contact.state; the browser then reads GET /strategy. So a HALT's None and another
             browser's selection are pushed.
             POST /strategy/evaluate {v, profile_id, boot_id, source_id, job_id,
             generation, first_sequence, next_sequence (0 <= next - first <= 2048),
             strategy (null: the saved active strategy, else a draft Strategy), explain}:
             the verdicts of the retained live records [first, next) of exactly that live
             job (another job: 409 stale_request job_id; no active strategy: 409
             not_configured strategy) in display order: every one when explain, else only
             those with a rank or grey. Never changes station state. */
    }
    attribute def ValueView {
        doc /* While a strategy is active the browser renders the station's verdicts in Band
             Activity: after a new publication event (never on a timer) it asks POST
             /strategy/evaluate once for the shown sequences of the current live identity; rows
             arriving during an evaluation are asked for when it ends.
             A row with a rank has the existing strategy mark (colour stays per
             WstxOperatingLayout::BandActivityColours: only interesting stations); greyed rows
             are dimmed and struck through; other rows have no mark. With the sort on value (the
             default, the visible "Value" control in the strategy element) rows are ordered in
             their period block by ValueOrder: the partner rows stay on top (#50), rows to my
             call next, then rows with a rank by rank, then the rest in ActivityOrdering.
             Clicking a column header sorts by that column until the operator returns to Value
             (ActivityOrdering; the marks stay). No active strategy: no evaluation request and
             no mark. After an Ignore or Stop ignoring the shown rows are evaluated again.
             Selecting a strategy never restarts receive. */
    }
    attribute def StrategyEditor {
        doc /* The edit (pencil) popup (a modal dialog carrying its own HALT with the top-bar HALT's
             action and enabled state; receive keeps running): choose, add, duplicate and
             delete strategies; exactly the settings of Strategy: name; goals (checkboxes);
             needed (not worked / not confirmed); region (all, DX, selected with continent
             checkboxes); minimum SNR (empty: none); calls per station; Treat 73 as CQ; worked
             window (all time, today UTC, from/to UTC dates). The live preview evaluates the
             unsaved draft against the latest period (POST /strategy/evaluate with explain,
             400 ms after an edit, one request per edit, no timer otherwise) and shows each
             decode's rank and why. Save sends one PUT /strategy, applies at once (also to a
             running strategy) and never selects a strategy. My continent is set in
             Settings > General (StrategyConfiguration continent, saved by PUT /strategy). */
    }
    attribute def HearingFeed {
        attribute heardWindowSeconds : Integer = 600;
        doc /* The read-only PSK Reporter MQTT feed (#39, the operator's agreement of
             2026-11-04): whether the current target hears my call and which frequencies it
             decodes. Everything works without it: no connection is unknown, never an error
             for the operator, and receive and the 50 ms station step never wait on it (its
             own thread does all network waiting; the station reads a short-held lock).
             Broker: mqtt.pskreporter.info port 1884, MQTT 3.1.1 over TLS, trusting only the
             compiled-in ISRG Root X1 and X2 with the name checked (that chain validated on
             2026-11-06); a broker moved to another CA shows an error in Settings and needs
             a new build. The broker's page states no formal terms and no rate limit, says
             "No account and no polling", is provided by Tom M0LTE, and says the feed
             originates from Philip Gladstone at pskreporter.info, used with permission.
             Client id: wstx, my call and 4 characters of the boot id (alphanumeric, at most
             23 bytes), so that the operator of the broker can identify the station. No
             user name, password or will. QoS 0, clean session.
             The station sends only the MQTT handshake, keep-alive pings every 45 s of
             silence (keep-alive 60 s), its subscriptions and DISCONNECT. Exactly two filters
             of the filtered feed, never the raw feeds: pskr/filter/v2/+/+/<my call>/+/#
             and, only while a strategy run's own contact has a DX call (not a pounce, an MCP
             policy run or a manual contact),
             pskr/filter/v2/+/+/+/<target>/#, replaced when the target changes. A call
             forms a topic segment only as 1..16 of A-Z 0-9; any other call, such as one
             with a slash or anything decoded with an MQTT wildcard, gets no subscription and
             stays unknown (the broker documents no form for it).
             Reconnect: 5 s after every session end, doubling to 300 s; it starts over only
             after a session of 60 s, and no change of a setting skips the wait. 90 s without
             any packet ends a session. A packet over 4096 bytes or outside the subset is a
             protocol error and ends the session; a payload that is no spot is dropped.
             A spot: f (Hz), md, b, sc, rc and t_tx (or t when absent), fields of 1..16
             characters. The payload decides, not the topic: a spot neither from my call nor
             to the current target is dropped. A time ahead of the station counts as now.
             Hearing: the target hears us when a spot from my call to that receiver on the
             station's mode and band is at most heardWindowSeconds old. 600 s because
             reporters upload in batches up to about 5 minutes late, so a spot can only be
             expected within that delay plus one more upload; an older spot no longer
             describes this path. Newest time per (receiver, band, mode), at most 256 entries,
             the oldest going first.
             Frequencies the target decodes: spots to the current target from other senders
             (at most 128, forgotten when the target changes), as audio offset = f minus the
             radio's confirmed dial of this band, only for the station's mode and band, at most
             heardWindowSeconds old, inside the free slot range of the mode, newest first and
             distinct, at most 32. A spot on another band or mode is ignored. An unknown dial
             or band gives none.
             Setting: on by default, because the operator agreed to this read-only
             subscription; pskr.json {schema_version 1, profile_id, enabled} beside
             profile.json (a foreign or broken file reads as on, naming invalid_pskr). Off
             disconnects and forgets everything the feed said. Each change of the switch ends the
             session of the earlier setting; the status shows connecting while the switch
             is on and the station waits for its next attempt, and off only when no connection
             can be made.
             GET /pskr {v 1, profile_id, boot_id, enabled, state off|connecting|connected|error,
             error (code or null), last_spot_utc_s, storage_error}, read once on each
             connection; POST /pskr {v 1, profile_id, boot_id, enabled} (operating access,
             the browser only) saves the switch; a display-subscribed peer receives pskr.state
             with the same data on a change, for spots at most once per 30 s, and renders the
             age from station.tick. No polling (WstxStationProtocol::PushedStationState).
             Tests: WSTX_PSKR=off opens no connection; WSTX_PSKR=tcp:<loopback>:<port> speaks
             plain MQTT to a local peer; nothing else can replace the broker. */
    }
    attribute def StrategyWatchdog {
        doc /* In a strategy run (not a pounce, an MCP policy run, a contact the run did not
             select, or manual operation, which keep the stop at N) the Tx watchdog never
             stops transmitting (operator decisions 6626745310, 6626799951 on #39). The engine
             sends past the limit for the run's own contact only, and the status counts down
             to the next check. Each time the Rep of the message due next (WstxContact::TxWatchdog)
             has grown by N, the Tx watchdog limit, or by calls_per_station when that is less,
             since the last check of this message (implementer default, not yet the operator's
             word: leaving a station restarts its Rep, so a check at N alone would never come
             with the default 3 calls and N 6, and 6626618984 asks to "immediately call it
             again, but on a different free slot"):
             the target known to hear us (HearingFeed, on this band and mode) keeps the same
             slot, with no limit; a target not known to hear us (no spot, the feed off or
             unreachable, the band unknown, a call without a subscription) takes a new free
             slot near the frequencies the target decodes and goes on. The new slot is
             FreeTxSlot's choice with the slot it leaves also occupied and those frequencies
             preferred, so this is the one case in which Tx moves within a contact; no free
             slot keeps the current one and says so in the status. A refused move
             changes nothing and is checked again N repetitions later. The Rep goes on over a
             move: the message is the same; a station the run left and came back to keeps
             the new slot, since FreeTxSlot stays on a current slot that is free. A target known to hear us is also not left
             for another candidate after its calls ("we are in the queue"), but only while the
             run may go on: with no client (CLIENT_GONE) or past the run limit its
             calls_per_station count again, so the contact ends and the run stops no_client
             or run_limit. The run shows the last check as slot_check {repetitions, hears_us,
             hz, free} and tx_slot {hz, free}. WD:n counts down to the next check. */
    }
    attribute def StrategySelector {
        doc /* The strategy element in the operating view: a selector with None and the
             strategy names. A change sends PUT /strategy with the new active and nothing else:
             it asks nothing, it starts or stops (StrategyRun). HALT is always on screen. A
             refused start leaves the selector on the strategy with the reason beside it. The
             element shows the run state from GET /automation, read only on an automation.state
             event: "Strategy <name> waiting", "· <call>", "· your QSO", a waiting reason, or
             the stop reason. No client polling. */
    }
    attribute def StrategyRun {
        doc /* A WstxMcp::OperatingAutomation run with strategy true; one run at a time.
             Selection: a PUT /strategy from the browser with a changed active ends any strategy
             run (a contact the run armed is disarmed, and cancelled when another strategy
             is selected so that it can start; a manual contact is left alone), also a
             running pounce or MCP run (the operator's selection wins); when not null it starts a
             run through the same internal path as AutomationCommand configure and start,
             with the request's grant, the current safety revision and the operator's watchdog
             activity (WatchdogFromOperator), as the station's decision: the client sends only
             the selection. Without a grant transport or transmit owner no run starts:
             the strategy stays selected and the snapshot's strategy_refusal names the reason
             (transmit_unavailable) until the next selection.
             max_contacts and max_run_minutes do not apply and read null. Run limit (operator
             decision 2026-11-06; the constant automation::STRATEGY_RUN_MAX, no setting): a run lasts
             at most 8 hours from its selection, also with a browser open; a new selection
             starts a new 8 hours. At the limit it selects no new station: a contact in progress
             ends its normal way, a manual one is left alone, and when it next waits the run
             stops run_limit; the strategy stays selected with the reason shown and only a
             selection restarts it. The run checks the grant, not the transport of the selecting request: a page load, a
             second tab or a 401 recovery (a new proof) and the transport's own 8 h deadline do
             not end it; a revoked grant or a safety edit does (authority_lost).
             Unattended (operator decision 2026-11-06, #39 comment 6685226511; the
             constant automation::CLIENT_GONE, no setting): when no authenticated client has
             been there for 60 s, the run selects no new station: a contact in progress ends
             its normal way (completed, calls_per_station), a manual one is
             left alone, and when it next waits the run stops no_client; the strategy stays
             selected with the reason shown and only a selection restarts it. A client is
             there while a status WebSocket session is open (authenticated at its upgrade), and
             at each authenticated POST /mcp, which has only per-request authentication: its
             last request within the 60 s; the selection itself counts. A client back before the
             stop continues the run. So with every browser closed it does not go on calling. The
             run ends only by a HALT, a selection, the grant (authority_lost), no client (no_client), the run limit (run_limit)
             or a refused command (transmit_refused, provider_error):
             the strategy stays selected with the stop reason shown, and only a new
             selection (None, then the strategy) starts it again: an AutomationCommand start
             of a configuration a strategy run left is refused 409 operator_required strategy,
             from an MCP client and from the browser. HALT from any source (button,
             Alt+H, MCP) ends the run and sets active to None in the store, also with no
             run, at the next station step (revision + 1, in memory: active is never read
             from the file), pushed by strategy.state. Esc (Abort QSO) changes neither.
             Receive: a strategy run has no receive identity of its own. Without FT8 or FT4
             receive it waits with reason no_receive; when receive starts or the live identity
             changes it re-identifies and waits (a contact it had armed is disarmed and
             cancelled) instead of stopping; last_decode restarts at the latest publication.
             Waiting reasons (run.reason while state waiting): no_receive, auto_seq (Auto Seq
             off), call (a nonstandard own call, #24 S1b), activity (a contest activity or Hound,
             #24 S2a); it selects nothing until the reason is gone.
             Waiting: on each fresh complete publication the list is the verdicts with a rank,
             not completed in this run on this band and mode and not given up by the operator
             (ManualIntervention), one per call, in ValueOrder (no CQ is ever called). A candidate the
             run left after calls_per_station on this band and mode is passed over when any other
             is listed; a
             caller never is (D5).
             The first is selected (select_row {replace false}), Tx takes its free slot (FreeTxSlot)
             and it is armed (enable_tx). Nothing listed: it
             keeps waiting. A contact the run did not select: ManualIntervention.
             In a contact: completion counts and returns to waiting; calls_per_station partner
             periods without progress disarm and cancel the contact and return to waiting with
             that call passed over once; no stop. A target known to hear us is not left this
             way while the run may go on (StrategyWatchdog). The browser itself never sends enable_tx
             for a strategy. */
    }
    attribute def FreeTxSlot {
        doc /* A strategy run or a pounce (not a plain MCP policy run, not manual operation)
             calls from a free audio slot (operator decision 2026-11-04, #39). Decided once
             per call, between QSOs: when a strategy run or a pounce has selected its station, a
             caller of my call as well (an award strategy never calls CQ); never during a contact.
             Occupied: every decoded record of the last 4 periods of my Tx parity (the
             parity after the selection) that decoded anything, among the records of
             complete publications; a period I transmitted in decodes nothing and is not
             counted, so older periods are used rather than none. Fewer periods: those
             there are. A strategy run and a pounce add the called station's frequency, which is
             not on my parity. When these 4 periods leave no free slot (a busy band), the 3,
             then 2, then the 1 most recent are looked at, with the called station in each
             look; a free slot found so is free.
             Band: a retune on the radio keeps the live job, so on each fresh publication
             the run compares the station band (station_band); from a change on, only
             publications after the one that showed it count. A retune before the run or
             within a band is not seen: the old signals age out with the periods. A new live
             identity (StrategyRun) counts from its first record.
             Signal width, from the record's frequency_hz upwards: FT8 50 Hz, FT4 90 Hz,
             mine alike. A slot is free when 50 Hz or more separate my signal from every
             occupied signal, and my whole signal lies inside 300..2700 Hz within the Tx
             range (FrequencyControls): FT8 slots 300..2650, FT4 300..2610.
             Choice: the free slot nearest the current Tx, then the lowest, so a free
             current Tx is kept and a new slot is chosen only when the current one has
             become busy. The decision may instead be asked for the free slot nearest a list
             of preferred frequencies, then nearest the current Tx, then the lowest.
             No free slot even in the latest period: Tx keeps the current frequency unless it
             is too near the called station (Tx is never on the called station: then the
             slot nearest the current Tx, then the lowest, that is free of that station
             alone), the call still goes out (no refusal), and the status says so: the run's
             tx_slot {hz, free false} (WstxMcp), and "no free Tx slot" in the station bar's
             automation text.
             Tx is moved with set_frequency only when it is not on the slot (with Hold Tx
             off the selection has moved it to the station: it goes back). The Tx stays on
             the slot for the whole QSO: nothing during the exchange moves it, and the "may" of the operator's rule (Tx
             to the partner's frequency once the QSO is established) is not taken, so
             there is nothing to return from. A caller of my call is a called station like any other:
             one on my slot is answered from the slot beside it. The next decision starts from the Tx the
             operator may have set meanwhile. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    attribute def WatchdogFromOperator {
        doc /* The Tx watchdog limits the repetitions of one message
             (WstxContact::TxWatchdog, operator rule 2026-11-06) and is never paused by
             automation; a new message or station restarts the repetition count, so it
             bounds a run per message, not in total (max_run_minutes bounds a policy run; a
             strategy run is bounded by its 8 hour run limit and its grant). A
             human action in the browser is an accepted ContactCommand or a strategy selection
             sent by the browser (principal browser, WstxProfiles::RequestPrincipalRule:
             read from the credential at the auth boundary, so an MCP client is never one
             on any route, #58). Only an Enable Tx or a strategy selection from the browser ends
             a watchdog stop. Never operator actions: commands of a run (select_row,
             set_frequency, enable_tx, cancel, disarm) and any MCP request (also starting or
             restarting a run). Such an enable_tx
             is refused tx_watchdog after a watchdog stop or when no browser action was
             seen this boot; only the browser may change the watchdog setting (set_watchdogs from any
             other source is refused operator_required). At the limit Enable Tx goes off
             without a halt and a pounce or MCP policy run stops tx_watchdog; a strategy
             run's own contact has no stop (StrategyWatchdog).
             Halt from any source stops the run; grant, clock, period and safety-revision
             checks are unchanged. */
    }

    dependency storeClause from StrategyConfiguration to WstxRequirements::'CL-039-01';
    dependency evaluateClause from Verdict to WstxRequirements::'CL-039-02';
    dependency goalClause from GoalNeeded to WstxRequirements::'CL-039-02';
    dependency valueClause from ValueOrder to WstxRequirements::'CL-039-02';
    dependency mostWantedClause from MostWantedList to WstxRequirements::'CL-039-10';
    dependency ignoreClause from IgnoreLists to WstxRequirements::'CL-042-02';
    dependency pounceClause from Pounce to WstxRequirements::'CL-042-03';
    dependency pouncePath from Pounce to WstxMcp::OperatingAutomation;
    dependency alertClause from Alert to WstxRequirements::'CL-042-04';
    dependency directedClause from DirectedCqRule to WstxRequirements::'CL-039-03';
    dependency myContinentClause from MyContinent to WstxRequirements::'CL-039-03';
    dependency manualClause from ManualIntervention to WstxRequirements::'CL-039-05';
    dependency valueViewClause from ValueView to WstxRequirements::'CL-039-04';
    dependency editorClause from StrategyEditor to WstxRequirements::'CL-039-04';
    dependency selectorClause from StrategySelector to WstxRequirements::'CL-039-04';
    dependency runClause from StrategyRun to WstxRequirements::'CL-039-05';
    dependency freeSlotClause from FreeTxSlot to WstxRequirements::'CL-039-09';
    dependency freeSlotRun from StrategyRun to FreeTxSlot;
    dependency freeSlotPounce from Pounce to FreeTxSlot;
    dependency watchdogClause from WatchdogFromOperator to WstxRequirements::'CL-039-06';
    dependency hearingClause from HearingFeed to WstxRequirements::'CL-039-20';
    dependency strategyWatchdogClause from StrategyWatchdog to WstxRequirements::'CL-039-21';
    dependency strategyWatchdogHearing from StrategyWatchdog to HearingFeed;
    dependency strategyWatchdogSlot from StrategyWatchdog to FreeTxSlot;
    dependency strategyWatchdogOwner from StrategyWatchdog to WstxContact::TxWatchdog;
    dependency automationPath from StrategyRun to WstxMcp::OperatingAutomation;
    dependency watchdogOwner from WatchdogFromOperator to WstxContact::TxWatchdog;
}
