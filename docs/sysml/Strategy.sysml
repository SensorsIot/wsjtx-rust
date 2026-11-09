package WstxStrategy {
    private import ScalarValues::*;
    doc /* Canonical contract of the strategy engine (issue #39, CL-039-01..11 and CL-039-20..23 in
         WstxRequirements; verification TC-039-001..010, TC-039-020..022, TC-039-030..033 and
         the strategydef cases TC-039-040..048, the holdtx cases TC-039-049..051, the quiet
         slots of issue #66 TC-066-001..003; the ignore
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
         D2 What a strategy is: exactly one strategy is active, or none (manual operation).
            A strategy has three chapters, the same for strategies and contests (slice
            strategydef, operator grill 2026-11-07 Q1, #39 comment 6705641422): value
            (Candidate, ValueOrder), mode (AutoToggle, PskrUse) and exit (LeaveRule,
            QuietTime). Selecting a strategy marks its candidates in Band Activity; it
            transmits only while Auto is on (AutoToggle, which replaces "selecting it starts
            it"). The browser sends only the selection and the toggles. A saved strategy is of the class award;
            contest strategies are #63 (WstxContest), a selection and no saved class (StrategyClass).
         D3 Treat 73 as CQ: an RR73 or 73 that ends another station's QSO counts as calling;
            the run answers from its free Tx slot (FreeTxSlot) so the answer never lands on the
            final 73.
         D4 An award strategy calls CQ only with its option CQ when no target (Q35, Q40; off
            by default; CqWhenNoTarget). It waits for the next opportunity and goes on
            after each QSO without a limit (no QSO limit; the WstxMcp run bounds and the
            transport's 8 h do not apply to it; its own limit is 8 hours from the selection,
            operator decision 2026-11-06, StrategyRun, which replaces the former "no time limit").
            The grant and every safety check still apply.
         D5 Stations calling my callsign are always answered, independent of goal, region,
            SNR and every other filter line (operator 2026-11-07: "Always answer callers",
            confirming this rule for strategydef; CallerOfMyCall). The strategy option
            Callers of my call first (Q4, on by default) places them: first, and answered at
            once (LeaveRule); off, ranked by the value list among the candidates. A contest
            dupe caller has no rank and is not answered (WstxContest::ContestVerdict).
         D6 No skip: a station is never given up by the run. It is left by LeaveRule after
            its repetitions ("repetitions before leaving", x, which replaces calls per
            station) and may be called again after its QuietTime. Only the operator gives a
            station up for a run (ManualIntervention).
         D15 Strategydef (operator grill 2026-11-07, Q1-Q42, #39 comment 6705641422, the
            operator's "yes, go ahead", and the answers of 2026-11-07 relayed on #39): filter
            and value apart (Candidate, ValueOrder), SNR and distance as value
            criteria, the Auto and Use PSK Reporter toggles, one exit rule (LeaveRule,
            QuietTime) and the quietest Tx slot (FreeTxSlot). It replaces the held #63 slice
            targetrule and keeps its two fixes: a contest dupe caller never ends a stay, and
            a repeated message of the target to my call is progress. Out of scope: a combined
            weighted score, the station changing band or mode, calling several targets at
            once.
         D16 Hold Tx in Auto (slice holdtx, operator report 2026-11-07 "the hold TX does not
            work and TX is shifted to RX"; decisions "Hold Tx on: the automation never moves
            Tx", corrected to "if the other station does not hear us we are allowed to change
            the frequency to a quiet place, but never to the Rx frequency", and "Relative to
            its own usual level"; round 1 on #39: Q1 yes, Q2 "Move 50 Hz away", Q3 "CQ on the
            held Tx", Q4 "lowest over the last 3 periods"; round 2 Q5 "3 of each parity"; round 3 Q6 "Move into the range"; the
            listed defaults D1-D15 of the slice confirmed by the operator). With Hold Tx on a run keeps Tx and
            puts Rx on the station; Tx alone moves at the slot check of a target that does not
            hear us, or 50 Hz clear when the station is within 50 Hz of it; a CQ goes out on the
            held Tx. With Hold Tx off Rx = Tx on the slot as before. Quietness was a slot's rise
            over its own usual level; D17 replaces that. It replaces CL-039-08's "a run's free slot"
            as an explicit Tx action and CL-039-09's "Rx = Tx" for Hold Tx on.
         D17 Quiet slots across the passband (#66, operator 2026-11-08: "We want to have the
            quiet slots overall. Across the entire bandwidth of FT8."; round 1: Q1 the level
            above the WSJT-X passband floor, Q2 leave out slots on a decoded station, Q4 the
            busiest of the last 4 periods; round 2: "judge the parity I will receive in. I
            want to signal the other station a free slot on my side", in every decision,
            "Only if recent"; after implementation, "At or under floor = free"). Slots are
            compared with each other across the whole passband by their level above the
            passband floor, clamped at 0, never by their own usual level, which
            goes; only my Rx periods count, in every decision (FreeTxSlot). It replaces D16's
            "Relative to its own usual level" and CL-039-09's "while only listening the slot
            must be quiet in both parities".
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
         D14 Built-in strategies (operator 6626205191 (5)): BuiltinStrategies.
         D13 Grids are a known-unknown: only 6,729 of the operator's 26,902 Log4OM QSOs carry
            a grid, so a missing grid is unknown, never new (GoalNeeded grid). */

    enum def StrategyClass {
        doc /* award: the saved strategies. A saved strategy of class contest is refused on the
             wire (400 invalid_request, field ...class): contest strategies are profiles and a
             selection (#63, WstxContest::ContestSelection), not saved ones. */
        enum award;
    }
    enum def Goal { enum dxcc; enum dxcc_band; enum dxcc_slot; enum waz; enum wpx; enum grid; enum new_call; enum new_call_band; }
    enum def ValueCriterion {
        doc /* The criteria of ValueOrder (Q2, Q3, Q8), wire names exactly. */
        enum new_dxcc; enum new_dxcc_band; enum new_dxcc_slot; enum new_grid; enum new_grid_band;
        enum new_call; enum new_call_band; enum most_wanted; enum distance; enum snr;
    }
    enum def Needed { enum not_worked; enum not_confirmed; }
    enum def RegionKind { enum 'all'; enum dx; enum selected; }
    enum def WindowKind { enum 'all'; enum today; enum from_to; }
    attribute def Strategy {
        attribute name : String;
        attribute strategyClass : StrategyClass;
        attribute needed : Needed;
        attribute minSnrDb : Integer[0..1];
        attribute repetitions : Integer = 4;
        attribute quietMinutes : Integer = 10;
        attribute callersFirst : Boolean = true;
        attribute cqWhenNoTarget : Boolean = false;
        attribute treat73AsCq : Boolean;
        attribute valueCriteriaMax : Integer = 10;
        assert constraint repetitionsRange { repetitions >= 1 and repetitions <= 20 }
        assert constraint quietRange { quietMinutes >= 1 and quietMinutes <= 120 }
        doc /* Wire keys exactly: name (1..32 printable ASCII, no leading/trailing space,
             unique ignoring case); class "award"; goals (1..8 unique Goal, multiple choice,
             a station is needed when at least one goal is needed); needed; region {kind all}
             | {kind dx} | {kind selected, continents: 1..7 unique of AF AN AS EU NA OC SA};
             min_snr_db (null or an integer -50..49); value (0..10 unique ValueCriterion in
             the operator's order, ValueOrder); callers_first (boolean, Q4);
             cq_when_no_target (boolean, CqWhenNoTarget); repetitions (x, "repetitions
             before leaving", 1..20, LeaveRule; it replaces calls_per_station); quiet_minutes
             (1..120, QuietTime); treat_73_as_cq (boolean); window {kind all} |
             {kind today} | {kind from_to, from, to}: from and to are real calendar dates
             "YYYY-MM-DD" between 1930-01-01 and 2099-12-31 with from <= to. Each refusal
             names its field path (strategies[0].window.to, strategies[0].value[1]). The
             browser's new strategy starts with goals [new_call], value [most_wanted],
             callers_first true, cq_when_no_target false, repetitions 4, quiet_minutes 10.
             Nothing else exists: calls_per_station, rules, conditions, sort, auto role,
             switch after, skip after and callers are refused like any extra key. */
    }
    attribute def BuiltinStrategies {
        doc /* The read-only presets of the award class (operator 6626205191, names as the operator
             listed them; the contest preset is #63; strategydef adds three), one table in
             the station in this order, listed in the GET /strategy snapshot as
             builtin_strategies, each a Strategy with builtin true. All have needed
             not_worked, min_snr_db null, callers_first true, repetitions 4, quiet_minutes 10,
             treat_73_as_cq true, window all, region all, value [most_wanted] and
             cq_when_no_target false unless stated:
             New DXCC (goal dxcc), New DXCC on band (dxcc_band), DXCC slots (dxcc_slot),
             New calls (new_call), DX hunting (new_call, region dx), Strongest new on band
             (new_call_band, value [snr]), Farthest new on band (new_call_band, value
             [distance]), Casual 20 m (new_call_band, window today, value [snr],
             cq_when_no_target true; "not worked on this band today"; 20 m is its name only,
             it works on any band).
             They are not part of the configuration and never written to strategy.json. active
             may name one (exactly as listed): selecting it starts it like any strategy
             (StrategyRun). A PUT cannot edit one: a configuration strategy with a built-in's
             name, also differing in case, is refused 400 invalid_request
             strategies[i].name, and the key builtin is refused like any extra key. In the
             editor a built-in is shown read-only and Duplicate copies it to a user strategy
             named "<name> copy" (StrategyEditor). A saved file that holds a strategy with a
             built-in's name (saved before the presets) reads without it; the built-in keeps
             the name. */
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
             (null or the name of a listed or built-in strategy), strategies (0..16 Strategy),
             ignore_calls (#42 the permanent ignore list: 0..100 unique calls of 1..13
             A-Z 0-9 /, IgnoreLists), session_ignore_minutes (#42 the session list
             expiry, an integer 1..720, default 30) and the optional contest (#63,
             WstxContest::ContestSelection, never persisted). Persisted as strategy.json beside
             profile.json: {schema_version 3, profile_id, revision, configuration}, written
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
             is malformed). A file of schema_version 2 (strategies with calls_per_station,
             before strategydef) reads at its revision with each strategy's
             calls_per_station dropped and value [most_wanted], callers_first true,
             cq_when_no_target false, repetitions 4 and quiet_minutes 10 added; a strategy
             of it that is otherwise malformed makes the file malformed. Either is written
             as schema 3 by the next PUT. */
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
             new_call: the call ever. new_call_band (strategydef): the call on the station
             band in any mode. grid: the 4-character grid square in the decoded message
             ever, with the rule of D13: no grid in the message is not needed; a sender with a
             logged QSO without a grid (in the window) has an unknown grid status and is not
             needed. False without an entity (dxcc, dxcc_band, dxcc_slot, waz; /MM, /AM,
             unknown prefix), without a known station band (dxcc_band, dxcc_slot,
             new_call_band) and when
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
             answered: no goal, region, SNR, window, callsign guard or other line of the
             filter (Candidate) applies (D5, operator 2026-11-07 "Always answer callers"). In a
             run it is only excluded when completed in this run on this band and mode, given up
             by the operator (ManualIntervention) or in its QuietTime. */
    }
    attribute def Candidate {
        doc /* The filter, yes or no (Q2, Q10): every line must hold. A decoded standard
             message with a resolved sender, not mine, passing SaneCall, not ignored
             (IgnoreLists), not greyed (DirectedCqRule), a CQ, or with treat_73_as_cq an
             RR73/73 addressed to someone else; region holds (all; dx: my continent and the
             sender's are known and differ; selected: the sender's continent is listed);
             min_snr_db null or the SNR known and >= it; and GoalNeeded in the strategy's
             window for at least one goal (any chosen goal counts). A run adds: not completed
             in this run on this band and mode, not given up, not in its QuietTime
             (StrategyRun). The filter and the value may use the same field. */
    }
    attribute def ValueOrder {
        doc /* The ranking (Q2, Q3, Q8, Q9). The strategy's value is an ordered list of
             ValueCriterion: the first criterion decides and the next breaks a tie. Each
             criterion, better first:
             new_dxcc, new_dxcc_band, new_dxcc_slot, new_call, new_call_band: GoalNeeded of
             dxcc, dxcc_band, dxcc_slot, new_call, new_call_band with the strategy's needed and
             window; needed before not needed. new_grid: GoalNeeded grid. new_grid_band: the
             message grid needed (the strategy's needed) on the station band in the window, with the rule of D13
             (no grid, an unknown grid status or an unknown band is not needed); needed
             first. most_wanted: on the Most Wanted list by its rank ascending, then the
             stations without a rank (MostWantedList). distance: StationDistance, farther
             first, unknown last. snr: stronger first, unknown last.
             Then always, hidden (Q3, Q9): SNR stronger first (unknown last); then, for an
             exact tie only, the lower audio frequency, then the call in character order.
             Decode order is never a ranking.
             Order of a strategy's list: with callers_first (Q4) the callers of my call
             (CallerOfMyCall) come first, ranked among themselves by the same criteria, then
             the candidates; without it callers and candidates are ranked together by the
             criteria. Band Activity: the partner (#50, on top by the browser's partner rows),
             then that list, then the rest. A contest keeps its own value
             (WstxContest::ContestValueOrder). */
    }
    calc def StationDistance {
        in sender : String;
        in grid : String[0..1];
        return km : Integer[0..1];
        doc /* The distance for the value criterion distance: the great-circle distance from
             the centre of the profile locator to the centre of the 4-character grid in the
             message; otherwise to the sender's entity centre from cty.dat (the approximate
             entity distance of WstxContact::DecodedEntity). Unknown without a profile locator
             or without grid and entity (/MM, /AM, unknown prefix). Whole km, truncated. */
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
             start are refused state_conflict run while any run is active; switching Auto on ends a
             running pounce, WstxStrategy::AutoToggle, and finishes its started QSO, StartedQso;
             a selection with Auto off leaves it and its contact alone). Start also
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
             Contest activity (#63, WstxContest::ContestDirective): the word of the station's
             special activity (WstxContact::SpecialActivity: na_vhf and arrl_digi TEST, ww_digi WW,
             field_day FD, rtty RU) is answerable too, whatever the continents.
             Every other directive is not answerable: another continent or region (NA, JA,
             SA, ...), any other word (TEST, POTA, a number; a contest word outside its activity),
             CQ DX from my own or an unknown
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
             up}), the MostWantedList status and builtin_strategies (BuiltinStrategies)}.
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
             client can never select a strategy. A changed active ends a running run and,
             while Auto is on, starts the new one; None turns Auto off (AutoToggle,
             StrategyRun); saving anything else leaves a running strategy running and applies
             at its next step.
             strategy.state {v 1, type "strategy.state", data {profile_id, boot_id,
             strategy_revision}}: a display-subscribed peer receives it when the revision
             changes after it subscribed (never on subscription itself), paced with
             contact.state; the browser then reads GET /strategy. So a HALT's Auto off and another
             browser's selection or toggle are pushed.
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
             checkboxes); minimum SNR (empty: none); Treat 73 as CQ; worked window (all time,
             today UTC, from/to UTC dates), under the heading "Filter"; under "Value" the
             ordered criteria list (add a criterion from the ValueCriterion names not yet
             listed, remove one, move one up or down; the line "then SNR" under the list,
             not removable) and "Callers of my call first"; under "Exit" "Repetitions before
             leaving" (1..20) and "Quiet time (minutes)" (1..120); and "CQ when no target".
             Labels of the criteria: New DXCC, New DXCC on band, New DXCC on band and mode,
             New grid, New grid on band, New call, New call on band, Most Wanted rank,
             Distance (farther first), SNR (stronger first). The live preview evaluates the
             unsaved draft against the latest period (POST /strategy/evaluate with explain,
             400 ms after an edit, one request per edit, no timer otherwise) and shows each
             decode's rank and why. Save sends one PUT /strategy, applies at once (also to a
             running strategy) and never selects a strategy. A built-in strategy is listed read-only with
             its settings shown and its preview; only Duplicate acts on it. With no user strategy the
             popup opens on the first built-in and Save stores none. My continent is set in
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
             and, only while a strategy or contest run's own contact has a DX call and
             PskrUse is on (not a pounce, an MCP policy run or a manual contact),
             pskr/filter/v2/+/+/+/<target>/#, replaced when the target changes. A call
             forms a topic segment only as 1..16 of A-Z 0-9; any other call, such as one
             with a slash or anything decoded with an MQTT wildcard, gets no subscription and
             stays unknown (the broker documents no form for it).
             Reconnect: 5 s after every session end, doubling to 300 s; it starts over only
             after a session of 60 s, and no change of a setting skips the wait. 90 s without
             any packet ends a session. A packet over 4096 bytes or outside the subset is a
             protocol error and ends the session; a payload that is no spot is dropped.
             A spot: f (Hz), md, b, sc, rc and t_tx (or t when absent), fields of 1..16
             characters, and rp (the receiver's reported SNR in dB, an integer -99..99;
             absent or another value: unknown, the spot still counts). The payload decides, not the topic: a spot neither from my call nor
             to the current target is dropped. A time ahead of the station counts as now.
             Hearing: the target hears us when a spot from my call to that receiver on the
             station's mode and band is at most heardWindowSeconds old. 600 s because
             reporters upload in batches up to about 5 minutes late, so a spot can only be
             expected within that delay plus one more upload; an older spot no longer
             describes this path. Newest time per (receiver, band, mode) with that spot's rp,
             at most 256 entries, the oldest going first.
             Frequencies the target decodes: spots to the current target from other senders
             (at most 128, forgotten when the target changes), as audio offset = f minus the
             radio's confirmed dial of this band, with the parity of their t_tx (the period of
             the sender's transmission), only for the station's mode and band, at most
             heardWindowSeconds old, inside the free slot range of the mode, newest first and
             distinct per (offset, parity), at most 32. A spot on another band or mode is
             ignored. An unknown dial or band gives none.
             Setting: on by default, because the operator agreed to this read-only
             subscription; it is the master switch beneath PskrUse. pskr.json {schema_version
             2, profile_id, enabled, use} beside profile.json (use: PskrUse; a file of
             schema_version 1 reads with use true and is written as 2 by the next change; a
             foreign or broken file reads as on with use true, naming invalid_pskr). Off
             disconnects and forgets everything the feed said. Each change of the switch ends the
             session of the earlier setting; the status shows connecting while the switch
             is on and the station waits for its next attempt, and off only when no connection
             can be made.
             GET /pskr {v 1, profile_id, boot_id, enabled, use, state off|connecting|connected|error,
             error (code or null), last_spot_utc_s, storage_error}, read once on each
             connection; POST /pskr {v 1, profile_id, boot_id, enabled} (operating access,
             the browser only) saves the switch and POST /pskr/use {v 1, profile_id, boot_id,
             use} saves PskrUse (exact keys and the refusals of POST /pskr each); a display-subscribed peer receives pskr.state
             with the same data on a change, for spots at most once per 30 s, and renders the
             age from station.tick. No polling (WstxStationProtocol::PushedStationState).
             Tests: WSTX_PSKR=off opens no connection; WSTX_PSKR=tcp:<loopback>:<port> speaks
             plain MQTT to a local peer; nothing else can replace the broker. */
    }
    attribute def StrategyWatchdog {
        doc /* In a strategy or contest run (not a pounce, an MCP policy run, a contact the run
             did not select, or manual operation, which keep the stop at N) the Tx watchdog
             never stops the run's own contact (operator decisions 6626745310, 6626799951 on
             #39): the engine sends past the limit for that contact only, and LeaveRule bounds
             it instead. A CQ of the run is no such contact (CqWhenNoTarget,
             WstxContest::ContestRun): the Tx watchdog stops it like any message.
             Slot check (operator 2026-11-07, "Every repetition", replacing the check every N or
             calls_per_station repetitions): at each repetition (LeaveRule) of a target that
             has not answered in this contact and is not known to hear us (no spot, PskrUse
             off, the feed off or unreachable, the band unknown, a call without a
             subscription), Tx takes FreeTxSlot's choice again before the next own period (with Hold
             Tx on Tx alone and Rx stays on the target, with it off Rx and Tx together, D16); a
             target known to hear us (HearingFeed, on this band and mode, with PskrUse on)
             keeps its slot. FreeTxSlot keeps the current slot when it ties for quietest, so
             Tx does not jump between near-equal slots; there is no threshold, this is a tie
             rule only. A target that has answered (a message to my call in this contact) has
             proved the slot: Tx never leaves it in that exchange. A refused move changes
             nothing and is checked again at the next repetition. The Rep goes on over a move:
             the message is the same.
             Unattended (no client for 60 s, or past the run limit, StrategyRun): the stop at
             N is back at once for the run's own contact, so that it ends even when no
             publication arrives; the watchdog's tx_expired stays until a new Auto on.
             The run shows the last check as slot_check {repetitions, hears_us, hz} and the slot
             as tx_slot (FreeTxSlot). WD:n counts down to the repetition at which LeaveRule
             leaves (x, or 2x while the target hears us); "WD:∞" while a contest target in
             situation 1 hears us and nothing more valuable is listed: the contact snapshot's
             watchdog tx_remaining_calls is then null (WstxContact::ContactSnapshot), and a
             number again once the stay ends (e.g. the spot older than 600 s). */
    }
    attribute def StrategySelector {
        doc /* The strategy element in the operating view: a selector with None and the
             names of the built-in and user strategies. A change sends PUT /strategy with the
             new active and nothing else: it asks nothing. With Auto off it only marks
             (ValueView); with Auto on the run of the old selection ends and that of the new
             one starts (AutoToggle); None also turns Auto off. HALT is always on screen. A
             refused start leaves the selector on the strategy with the reason beside it. The
             element shows the run state from GET /automation, read only on an automation.state
             event: "Strategy <name> waiting", "· <call>", "· calling CQ", "· your QSO", a
             waiting reason, the stop reason, or "Strategy <name> · Auto off" while Auto is off.
             No client polling. The line is drawn from the current strategy snapshot and the
             current automation snapshot together at each change of either, so that it never
             keeps the text of an earlier state (#74, CL-074-01): with None, or no strategy
             snapshot yet, and no strategy run it shows the WstxMcp::AutomationIndicator text
             of the automation snapshot ("Automation idle" without a run). A new boot
             (WstxStationProtocol::PushedStationState): when the browser learns a boot_id other
             than that of its held strategy snapshot, the element drops that snapshot and its
             verdicts at once and shows what a freshly loaded page shows before its GET
             /strategy answers (the selector with None only and disabled, Auto disabled with
             "Strategies are loading", "Automation idle", no marks), then the new boot's
             snapshot; nothing of the previous boot is drawn, also not with the new boot's
             automation snapshot. */
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
             the partner is answering is completed, otherwise LeaveRule ends it at x
             repetitions (no doubling, no contest stay) or the stop at N that is back
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
             #24 S2a; a contest strategy: any other than its own, WstxContest::ContestRun); it
             selects nothing until the reason is gone.
             Waiting: on each fresh complete publication the list is the verdicts with a rank,
             not completed in this run on this band and mode, not given up by the operator
             (ManualIntervention) and not in QuietTime, one per call, in ValueOrder (callers
             first with callers_first). The first is selected (select_row {replace false}), Tx
             and Rx take their place by FreeTxSlot (with Hold Tx on Tx stays and Rx is on the
             station, D16) and it is armed (enable_tx). Nothing listed: it
             keeps waiting, or calls CQ (CqWhenNoTarget). A contact the run did not select:
             ManualIntervention.
             In a contact: completion counts and returns to waiting; LeaveRule decides when the
             run leaves the target; no stop. The browser itself never sends enable_tx for a
             strategy. The run snapshot (WstxMcp) carries left (null or {call, reason
             repetitions|caller}), quiet ([{call, band, mode, remaining_s}]), hearing
             (PskrUse) and tx_slot (FreeTxSlot). */
    }
    attribute def AutoToggle {
        doc /* Mode (Q5, Q11, Q12, Q17, Q29). Auto is a toggle above the QSO pane next to CQ
             (WstxOperatingLayout::QsoPane): green on, grey off. It is not part of a strategy
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
             WstxContest::ContestPrompt warning first. A selection change while Auto is on to a
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
    attribute def StartedQso {
        doc /* Courtesy (#81, operator 2026-11-08: "A started QSO should always be finished out
             of courtesy. If we did not answer, then this does not count as a QSO"; "Auto only
             starts"). For every run of WstxMcp::OperatingAutomation: a strategy or contest
             run, a pounce and an MCP policy run.
             Started: the run's contact is a started QSO when its dialogue (the contact
             engine's, WstxContact::ContactSnapshot; never the run's own memory) holds a
             decoded message of the partner to my call and an own transmission to the partner
             that has started (keyed, also one still on the air). No started QSO: a station
             that called my call before our transmission to it started (a reply only armed),
             and a station we called that has sent nothing to my call (a Tx1 to a CQ, also one
             on the air).
             Finishing ends: Auto off; None; another strategy or contest selection (with Auto
             on the new run starts); a contest deselected; an Auto on that ends a pounce or MCP
             policy run; AutomationCommand stop; a policy run's time_limit; and, without
             ending the run, the end of a contest period (the run is manual while the QSO
             finishes, then waits outside_period). At each the run ends (or waits) at once
             as before, with the stop reason it has today, and every end turns Auto off as
             before; a started QSO is not disarmed or cancelled: it stays armed and is
             finished as an ordinary contact. The contact engine sequences it with Auto Seq to
             its end and logs it once (WstxContact::QsoAndLogging). The run's rules for it end
             with the run: no LeaveRule, no QuietTime, no slot check, no WD:n, no target
             subscription (HearingFeed), and no StrategyWatchdog exemption: the Tx watchdog's
             stop at N applies from the next send (WstxContact::TxWatchdog; a message already
             repeated N times under the exemption is not sent again). Tx and Rx stay where
             they are (FreeTxSlot: nothing else moves them in the exchange). Nothing new is
             selected, called or answered for it and its CQ is not called again. A run started
             meanwhile (Auto on, a selection with Auto on) finds it as a contact it did not
             select (ManualIntervention) and resumes when it has ended. The same request again
             (Auto off, None, stop) changes nothing.
             Not started at a finishing end: the contact is disarmed and cancelled at once as
             before; a transmission already on the air (the run's CQ, a Tx1, a reply)
             finishes its period (WstxContact::SetEnableTx) and nothing after it is keyed.
             Still at once (Enable Tx off and the contact cancelled, nothing logged): HALT from
             any source; Abort QSO; an operator's selection of another station (a double-click,
             WstxContact::ChangeContact); the Tx watchdog's stop; the grant revoked or a safety
             edit (authority_lost; a safety edit disarms in the transmit owner itself,
             authorityChanged); a band change or a mode change by the operator; a station
             restart (transmit is disarmed at every start); and the run's leaving while it runs
             (LeaveRule at x, a policy run's no_answer, a pounce's wait again). Unchanged:
             unattended or past the run limit the run itself finishes the QSO in progress
             (StrategyRun).
             Finishing guard: until the finished QSO's contact has ended (completed, cancelled,
             disarmed or replaced) the automation owner keeps, in memory only and in no
             snapshot, its contact id, the station band and mode at the run's end and the
             run's grant; at each station step it disarms and cancels that contact when the
             station band or the mode differs or the grant is no longer current (revoked, or a
             safety edit). It never arms, selects, answers or moves a frequency. A new run, a
             restart or the contact's end drops it. */
    }
    attribute def PskrUse {
        doc /* Use PSK Reporter (Q17, Q29): a toggle next to Auto (WstxOperatingLayout::QsoPane),
             kept across restarts in pskr.json use (HearingFeed), on by default. The Settings
             switch (HearingFeed enabled) stays the master: with it off the toggle is disabled
             (title "PSK Reporter is off in Settings") and counts as off. POST /pskr/use saves
             it; pskr.state pushes it. With it off, runs use no spot: no target subscription, no
             target hears us (LeaveRule does not double x, the contest stays nothing), and
             FreeTxSlot ignores his end.
             While it is on, a strategy or contest run's own contact has a target, the QSO pane
             shows two lines under the header: "Hears us: <age> ago · <rp> dB" from the newest
             spot of my call at the target (age from station.tick: "<n> s" below 120 s, else
             "<n> min" in whole minutes; rp signed as "−12"; "· ? dB" without rp),
             "Hears us: no" when the feed is connected, the call has a subscription and no such
             spot is at most 600 s old, and "Hears us: unknown" otherwise; and "Tx <hz> Hz ·
             open at his end: yes" (no frequency he decodes from my Tx parity lies within 50 Hz
             of the slot), "· no" (the slot was chosen although one does, FreeTxSlot), or
             "· unknown" (he has no such spot). The run snapshot (GET /automation, read on
             automation.state) carries hearing {state heard|no|unknown, spot_utc_s, snr_db} and
             tx_slot {hz, power_db, his_end yes|no|unknown}; a change of either increments the
             run revision. */
    }
    attribute def LeaveRule {
        attribute repetitionsDefault : Integer = 4;
        doc /* Exit (Q6, Q7, Q13-Q16, Q19-Q28), for the target of a strategy or contest run: the
             station it selected (a candidate, a caller answered, also from its CQ). A pounce,
             an MCP policy run and a manual contact do not change.
             Repetition: one fresh complete publication of the target's period parity, after an
             own transmission to it, with no progress. Progress: any decoded message of the
             target to my call, also a repeated one (the #63 fix: a repeated message of the
             target was counted as no progress), except that a target selected as a caller
             repeating the message it was selected on is no answer (#63 b9e7cb3b0); progress
             resets the count to 0. Two situations, counted alike: (1) he repeats, because he
             does not hear us: the target is decoded in that publication without progress (a CQ
             again, a message to another station); (2) we repeat, because we do not hear him,
             although he may hear us: the target is not decoded in it.
             x: repetitions before leaving, the strategy's repetitions (default 4) or the
             contest's (WstxContest::ContestSelection, default 2). Hears us: PskrUse on and
             HearingFeed hears (a spot of my call at the target at most 600 s old on this band
             and mode); it doubles x (2x).
             Strategy: the run leaves at the repetition that brings the count to x, or to 2x
             while the target hears us, in both situations.
             Contest: as a strategy, except in situation 1 at x or more: the run stays, with no
             limit, while the target hears us and no more valuable station is listed in this
             publication (a callable station, eligible, not the target, strictly before it by
             WstxContest::ContestValueOrder); otherwise it leaves.
             No change before an exit criterion (Q7): a more valuable station never ends a stay.
             The one exception: a caller of my call (CallerOfMyCall; in a contest only a caller
             with a rank, so never a dupe) is answered at once while the target has not
             answered in this contact, when callers_first is on (always in a contest), it is
             eligible and not in QuietTime, and the target is not that caller: the stay ends
             and that caller is selected from the same publication.
             Unattended or past the run limit (StrategyRun): x applies, never doubled, there is
             no contest stay and no caller exception.
             Leaving: disarm and cancel the contact, the left station gets its QuietTime, run.left
             = {call, reason repetitions|caller}, and the run waits; reason caller selects the
             caller from that publication at once. The stops of StrategyRun "Ends at once" are
             no leaving. */
    }
    attribute def QuietTime {
        doc /* After every leaving (LeaveRule) the left station gets a quiet time (Q6): the
             strategy's quiet_minutes (default 10) or the contest's (default 10) from the
             leaving, on that band and mode. During it the run does not select it, also not
             when it calls my call, nor answer it from a CQ. It is run memory: a new run starts
             with none. The run snapshot lists it as quiet [{call, band, mode, remaining_s}]
             (whole seconds, rounded up); an entry ends at its time. */
    }
    attribute def CqWhenNoTarget {
        doc /* The strategy option cq_when_no_target (Q35, Q40; off by default; on in Casual
             20 m). It is not a special class. With it on, a waiting run with no waiting reason
             that has seen two consecutive fresh complete publications with nothing listed
             (StrategyRun Waiting) calls CQ as a contest Run does (WstxContest::ContestRun):
             it decides the slot (FreeTxSlot, quiet in my Rx parity; with Hold Tx on the held Tx,
             no decision, D16) and sends enable_tx with
             no partner, which calls the activity's Tx6 (a plain CQ outside a contest
             activity); state calling_cq. On each fresh complete publication the list of
             StrategyRun Waiting is read again: the first listed station is selected (a caller
             with select_row {replace false}, which keeps Enable Tx and answers it from the CQ's
             slot; a candidate the same way), the CQ ends; nothing listed: the CQ goes on. After
             a completion or a leaving the run waits, and calls CQ again after two more
             publications with nothing listed. The Tx watchdog stops the CQ at its limit, and the
             run stops tx_watchdog (StrategyWatchdog). Unattended or past the run limit the CQ
             ends at once (StrategyRun). */
    }
    attribute def FreeTxSlot {
        attribute periodsPerParity : Integer = 4;
        attribute floorLowHz : Integer = 300;
        attribute floorHighHz : Integer = 2700;
        attribute clearanceHz : Integer = 50;
        attribute stepHz : Integer = 10;
        doc /* The Tx slot of a strategy or contest run or a pounce (not a plain MCP policy run,
             not manual operation), operator grill 2026-11-07 Q18, Q30-Q32, Q36, Q39, replacing
             the free slot by decodes; quiet across the passband (#66, D17). The slot is where
             he can answer us: a free slot on my side.
             Parity: every decision (a selection, a slot check, a CQ) judges my Rx periods (his
             Tx parity, the periods I will receive his answer in), never my Tx periods (#66
             round 2: "judge the parity I will receive in"). A CQ's Rx parity is the other of
             the parity it transmits in.
             Counted periods: from the detailed waterfall rows of the live receive (0.2 s rows,
             the native bins of about 2.93 Hz, levels in whole dB), per received period the
             mean level of each bin over the rows of that period; a period I transmitted in is
             not counted. Only recent periods count (#66 "Only if recent"): the counted periods
             among the last periodsPerParity (4) periods of my Rx parity on the clock before the
             period in progress at the decision (FT8 the last 2 minutes, FT4 the last minute);
             a period of them that I transmitted in or did not receive leaves a gap that no
             older period fills; fewer: those there are.
             Floor: per counted period, the WSJT-X passband floor (the baseline of the WSJT-X
             FT8 and FT4 decoders) over the floor bins, the native bins k whose frequency
             k x 12000/4096 Hz lies in [floorLowHz, floorHighHz) = [300, 2700): k = 103..921,
             819 bins. They form ten equal segments of 81 bins from k = 103 (the top 9 bins,
             913..921, in none, as in WSJT-X); in each segment the cutoff is its 8th lowest
             level (WSJT-X's tenth: rank 0.1 x 81 + 0.5 rounded down) and the points are its
             bins at or below the cutoff; a fourth-order polynomial is fitted through all
             points by least squares, plus 0.65 dB. Every segment gives at least 8 points and
             all ten at most 810, so a covered period always has a floor (WSJT-X's minimum of
             5 points and maximum of 1000 are never reached). Coverage: a period counts only
             when its levels reach bin 921 (2698.2 Hz); one whose rows end below it has no
             floor and is not counted (the live detailed rows have 1024 bins, up to 2997 Hz).
             The floor follows a gentle receive-filter roll-off; where a sharp knee leaves
             slots below it, the clamp of the Value makes them free like any slot at the floor,
             never quieter, so the passband edges do not win.
             Value: a slot at f covers the bins in [f, f + width): FT8 50 Hz, FT4 90 Hz. In one
             counted period its level is the mean level of those bins, its floor the mean of
             the floor over the same bins, its rise level minus floor. Its busiest period is
             the one with its largest rise (#66 round 1 Q4; of equal rises the latest period);
             its level and floor are that period's, as measured. The compared value is that
             largest rise clamped at 0 and rounded to whole dB: max(0, rise) (#66, operator
             2026-11-08 "At or under floor = free"; a single fourth-order floor cannot follow a
             sharp receive-filter knee, where slots read below the floor). A slot at or below
             the floor is free (0); stations and the filter knee stay above it. Slots are
             compared with each other across the passband by this value; there is no usual
             level.
             Candidates: f in stepHz (10 Hz) steps and the current Tx, my whole signal inside
             the Tx range (FrequencyControls): FT8 300..2650, FT4 300..2610; never within
             clearanceHz (50 Hz) of the called station's signal nor of my Rx signal (Tx is never
             on the called station, "never to the Rx frequency"). Free of decoded stations
             (#66 round 1 Q2): a candidate whose signal overlaps a station decoded in a counted
             period, its decoded audio frequency d (the lower edge of its signal) with
             |f - d| below the width (FT8 50 Hz, FT4 90 Hz), is left out; when that leaves no
             candidate, all of them are used. Among those left, where known it is free at his
             end: at least 50 Hz from every frequency
             HearingFeed shows him decoding, counting only spots of my Tx parity (PskrUse on);
             when that leaves no candidate, his end is not used and the status says "· no".
             Choice: the lowest value wins; a tie keeps the current Tx when it is among the
             quietest, else goes nearer the current Tx, then lower. There is no threshold. So
             among the free slots (0) the current Tx is kept when it is free, else the free slot
             nearest it, then the lower.
             No power yet (no counted period): Tx keeps the current frequency
             unless it is too near the called station or my Rx (then the nearest candidate away
             from it), power_db null. One counted period is enough to compare.
             Band: a retune keeps the live job, so from a station band change on only periods
             after it count, for the value and the decoded stations; a new live identity counts
             from its first period.
             Hold Tx (WstxContact::FrequencyControls holdTx, read at each decision; D16):
             Hold Tx off: decided once per call, between QSOs, when the run or a pounce has
             selected its station (a caller of my call as well), before a CQ, and at each slot
             check (StrategyWatchdog). Rx = Tx: set_frequency moves rx_hz and tx_hz to the slot
             together, only when either is not on it (the selection has moved Tx to the
             station: it goes back).
             Hold Tx on: a selection (a caller of my call as well, also from the run's CQ) keeps
             Tx and leaves Rx on the station where select_row put it; only when the station's
             signal is within 50 Hz of Tx does Tx go to the nearest candidate clear of it (the
             candidates above with power not used, so also clear of decoded stations while one
             is free, the lower on a tie; round 1 Q2 "Move 50 Hz away"). A CQ goes out on the held Tx with no decision (Q3). At each slot check of a
             target that does not hear us (StrategyWatchdog) Tx alone takes the choice above and
             Rx stays (set_frequency with tx_hz only). A pounce has no slot check, so with
             Hold Tx on it moves Tx only by the 50 Hz rule. A held Tx outside the Tx range above is kept at a
             selection and for a CQ unless it must move by the 50 Hz rule; at the slot check it
             is no candidate and Tx moves into the range (round 3 Q6 "Move into the range"). Status with Hold Tx on: tx_slot names the held Tx with its rise and his
             end.
             Nothing else during the exchange moves it; the
             "may" of the operator's rule (Tx to the partner's frequency once the QSO is
             established) is not taken. A caller of my call is a called station like any
             other. The next decision starts from the Tx the operator may have set meanwhile.
             Status: the run's tx_slot {hz, power_db, his_end yes|no|unknown} (WstxMcp), power_db
             the whole-dB compared value of that slot, its largest rise above the passband floor
             clamped at 0 (null without power). */
    }
    attribute def FreeTxSlots {
        attribute slotsListed : Integer = 5;
        doc /* Free Tx slots (#65, operator 2026-11-08): the best candidates of each slot
             decision of a run, for the operator to compare with the waterfall and to place
             Tx by hand (WstxOperatingLayout::FreeTxSlotMarks). At every decision of
             FreeTxSlot (every rule, also with Hold Tx on where the choice uses no power;
             strategy and contest runs and pounces) and at no other time: no list without a
             run, none between decisions. Candidates and compared value are exactly the
             decision's (FreeTxSlot Candidates with the decoded stations, his end, Value: the
             largest rise above the passband floor in my Rx parity clamped at 0, #66). Ranked by the
             whole-dB value, then nearer the
             current Tx, then lower; walking the ranking a candidate closer than the slot
             width (FT8 50 Hz, FT4 90 Hz) to one already listed is skipped; at most
             slotsListed (5); none without power. Where the decision's rule uses power the
             first listed is the chosen slot. The choice and tx_slot are unchanged. A
             decision is one that sets tx_slot: a repetition whose target has answered or is
             known to hear us is no slot check decision (StrategyWatchdog: it keeps its slot),
             so it lists nothing and the last list stays (#66).
             Value: {run_id, at_utc_ms (station time of the decision), mode ft8|ft4,
             rx_parity even|odd (the judged parity), listening (true at a CQ decision),
             periods {even, odd: {now (the counted periods of the value, at most
             periodsPerParity; null for my Tx parity, which is not judged)}}, slots [{hz,
             rise_db (the compared value, clamped at 0, never negative), level_db, floor_db
             (the level and the floor of the busiest period as measured, not clamped, so
             level_db may lie below floor_db when rise_db is 0)}] in rank order}, each dB
             rounded on its own (#66 replaces usual_db and periods usual). It is GET /automation free_tx_slots
             (WstxMcp::AutomationWire) and the free_tx_slots.state event
             (WstxStationProtocol::PushedStationState). */
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
             human action in the browser is an accepted ContactCommand, a strategy selection
             or an Auto on (AutoToggle) sent by the browser (principal browser, WstxProfiles::RequestPrincipalRule:
             read from the credential at the auth boundary, so an MCP client is never one
             on any route, #58). Only an Enable Tx, a strategy selection or an Auto on from the
             browser ends a watchdog stop. Never operator actions: commands of a run (select_row,
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
    dependency builtinClause from BuiltinStrategies to WstxRequirements::'CL-039-11';
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
    dependency selectorBootClause from StrategySelector to WstxRequirements::'CL-074-01';
    dependency runClause from StrategyRun to WstxRequirements::'CL-039-05';
    dependency freeSlotClause from FreeTxSlot to WstxRequirements::'CL-039-09';
    dependency freeSlotRun from StrategyRun to FreeTxSlot;
    dependency freeSlotPounce from Pounce to FreeTxSlot;
    dependency freeTxSlotsClause from FreeTxSlots to WstxRequirements::'CL-065-01';
    dependency freeTxSlotsChoice from FreeTxSlots to FreeTxSlot;
    dependency watchdogClause from WatchdogFromOperator to WstxRequirements::'CL-039-06';
    dependency hearingClause from HearingFeed to WstxRequirements::'CL-039-20';
    dependency strategyWatchdogClause from StrategyWatchdog to WstxRequirements::'CL-039-21';
    dependency strategyWatchdogHearing from StrategyWatchdog to HearingFeed;
    dependency strategyWatchdogSlot from StrategyWatchdog to FreeTxSlot;
    dependency strategyWatchdogOwner from StrategyWatchdog to WstxContact::TxWatchdog;
    dependency automationPath from StrategyRun to WstxMcp::OperatingAutomation;
    dependency autoClause from AutoToggle to WstxRequirements::'CL-039-22';
    dependency autoFinishClause from AutoToggle to WstxRequirements::'CL-081-01';
    dependency startedQsoClause from StartedQso to WstxRequirements::'CL-081-01';
    dependency startedQsoRun from StrategyRun to StartedQso;
    dependency startedQsoAutomation from StartedQso to WstxMcp::OperatingAutomation;
    dependency startedQsoWatchdog from StartedQso to WstxContact::TxWatchdog;
    dependency pskrUseClause from PskrUse to WstxRequirements::'CL-039-20';
    dependency leaveClause from LeaveRule to WstxRequirements::'CL-039-23';
    dependency quietClause from QuietTime to WstxRequirements::'CL-039-23';
    dependency cqClause from CqWhenNoTarget to WstxRequirements::'CL-039-22';
    dependency distanceClause from StationDistance to WstxRequirements::'CL-039-02';
    dependency leaveHearing from LeaveRule to HearingFeed;
    dependency leaveRun from StrategyRun to LeaveRule;
    dependency cqRun from StrategyRun to CqWhenNoTarget;
    dependency watchdogOwner from WatchdogFromOperator to WstxContact::TxWatchdog;
}
