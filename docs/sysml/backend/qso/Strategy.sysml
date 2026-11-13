package WstxStrategy {
    private import ScalarValues::*;
    doc /* Canonical contract of the strategy engine (issue #39, CL-039-01..11 and CL-039-20..23 in
         WstxRequirements; verification TC-039-001..010, TC-039-020..022, TC-039-030..033 and
         the strategydef cases TC-039-040..048, the holdtx cases TC-039-049..051, the quiet
         slots of issue #66 TC-066-001..003; the ignore
         lists of issue #42, CL-042-02 and TC-042-002..003; Pounce, CL-042-03 and
         TC-042-004..005; Alert, CL-042-04 and TC-042-006..007; the strategy settings and ranking
         of issue #97, CL-097-01..08 and TC-097-001..019, D19): the two classes of strategy
         (strategy and contest) and their settings, the directed-CQ rule, the ranking of Band
         Activity, the strategy editor popup, and the run elements that apply the settings
         (StrategyRun with LeaveRule, TxMoveRule, BusyPause, CqWhenNoTarget and QuietTime).
         Nothing here is an execution result.

         Decisions (operator decisions on #39, 2026-11-04 to 2026-11-06, comments
         6626205191, 6626483800, 6626497059, 6626745310, 6626929588, 6626981068,
         6627875105, and the implementing CR's defaults, listed on #39):
         D1 One evaluator: the station evaluates every strategy (Verdict). The browser
            renders the verdicts (POST /strategy/evaluate) and never evaluates anything
            itself; automatic operation uses the same verdicts.
         D2 What a strategy is: exactly one strategy is active, or none (manual operation).
            A strategy is of one of two classes (StrategyClass) and holds the nine settings of
            D19 (Strategy). Selecting a strategy only ranks Band Activity by it (Verdict);
            transmitting is Auto's (AutoToggle). The browser sends only the selection and the
            toggles.
         D3 Treat 73 as CQ: an RR73 or 73 that ends another station's QSO counts as calling.
         D15 Strategydef (operator grill 2026-11-07, Q1-Q42, #39 comment 6705641422, the
            operator's "yes, go ahead", and the answers of 2026-11-07 relayed on #39): filter
            and order apart (Candidate, ValueOrder), SNR and distance as order criteria, the
            Auto and Use PSK Reporter toggles and the quietest Tx slot (FreeTxSlot). Out of
            scope: a combined weighted score, the station changing band or mode, calling several
            targets at once.
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
         D18 Open slots all the time (#82, operator 2026-11-09: "open slots are shown all the
            time as a part of the waterfall"; "we want to signal the other station a free
            frequency on our side when he will be transmitting"; "we just want to mark open
            slots, nothing else on screen. auto mode could use a quality ranking for its
            decision which of them to select"; round 1 Q1-Q4 (a): also without a run, built at
            each period start for the next period, pushed to Detailed and Thin every period).
            The station marks every open slot, with or without a run, a QSO or Auto
            (FreeTxSlots); Auto's choice keeps its own ranking (FreeTxSlot), not shown. It
            replaces #65's five best of each run decision, its run_id match, "no list without a
            run" and the "Show free Tx slots" checkbox.
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
         D13 Grids are a known-unknown: only 6,729 of the operator's 26,902 Log4OM QSOs carry
            a grid, so a missing grid is unknown, never new (NewNeeded grid).
         D19 Strategy settings and ranking (operator grill 2026-11-09, mockups "DXCC all" and
            "ARRL Digi fast"; operator 2026-11-12). The operator chooses a strategy; every
            strategy holds the same settings with its own values, each editable per strategy,
            in this order: 1 Band (StrategyBands), 2 Filters (Candidate, CountryList,
            UsStateFilter, CqTargetList), 3 Order (ValueOrder), 4 Calling stations are answered
            (CallerOfMyCall), 5 Leaving a station (LeaveRule), 6 Tx frequency (TxMoveRule,
            FreeTxSlot), 7 Busy pause (BusyPause, WstxContact::BusyPartner), 8 CQ when idle with
            the CQ wait (CqWhenNoTarget), 9 Retry pause (QuietTime). Filters and Order come from
            one of two sources: the filter questions (class strategy) or a contest (class
            contest: the contest's rules, WstxContest, with the operator's country, US state and
            CQ target lists on top). A new strategy is made only by duplicating one
            (StrategyEditor); the built-ins are BuiltinStrategies. A strategy defines values and
            ranks Band Activity; it never selects, calls, answers, arms or transmits. The
            settings of decisions 5 to 9 take effect only through Auto (AutoToggle), the part
            that starts QSOs. */

    enum def StrategyClass {
        doc /* D19, two classes (operator grill Q12 2026-11-09; wire "strategy" and "contest").
             strategy: Filters and Order from the filter questions; DXCC all and Casual are both of
             this class and differ only in their answers. contest: Filters and Order from a contest
             (WstxContest), with the operator's country, US state and CQ target lists on top; a
             contest strategy is a duplicate of a contest built-in (BuiltinStrategies) and keeps
             its class and contest. Any other class on a PUT is refused. The class is never
             switched in the editor. */
        enum strategy;
        enum contest;
    }
    enum def NewWhat {
        doc /* "What must be new?" (#97 decision 2), wire names exactly, multiple choice: dxcc (the
             DXCC entity), call, grid (the 4-character grid), cq_zone (WAZ), itu_zone, continent
             (WAC), prefix (WPX, WpxPrefix). */
        enum dxcc; enum call; enum grid; enum cq_zone; enum itu_zone; enum continent; enum prefix;
    }
    enum def NewPer {
        doc /* "New per" (#97 decision 2): ever (any band and mode), band (the station band, any
             mode), band_mode (the station band and the operating mode, ADIF MODE, an MFSK record by
             its SUBMODE). One choice for every NewWhat of the strategy. */
        enum ever; enum band; enum band_mode;
    }
    enum def ValueCriterion {
        doc /* The criteria of ValueOrder (Q2, Q3, Q8; decision 3), wire names exactly. */
        enum most_wanted; enum new_dxcc; enum new_dxcc_band; enum new_dxcc_band_mode;
        enum new_call; enum new_call_band; enum new_grid; enum new_grid_band;
        enum new_cq_zone; enum new_itu_zone; enum new_continent; enum new_prefix;
        enum snr_bucket; enum snr; enum distance; enum hears_us;
    }
    enum def Needed {
        doc /* "New means" (#97 decision 2): not_worked; not_confirmed (not worked, or worked and
             not confirmed: LoTW, QSL or eQSL received, dxcc::Standing). */
        enum not_worked; enum not_confirmed;
    }
    enum def RegionKind { enum 'all'; enum dx; enum selected; }
    enum def WindowKind { enum 'all'; enum today; enum from_to; }
    enum def LeaveMode {
        doc /* #97 decision 5 (LeaveRule): calls (after n calls without an answer, m while he hears
             us), until_logged (stay until the QSO is logged; leave when he has not been decoded for
             n minutes), contest (contest style: while he hears us stay as long as he is still the
             most valuable, else leave after n Tx changes). */
        enum calls; enum until_logged; enum contest;
    }
    enum def PskCase {
        doc /* #97 decision 6 (#94), the PSK Reporter case of a called station (TxMoveRule): heard
             (he reports and hears us), not_heard (he reports and does not hear us), no_reports (he
             does not report, or it is not known). */
        enum heard; enum not_heard; enum no_reports;
    }
    attribute def Strategy {
        attribute name : String;
        attribute strategyClass : StrategyClass;
        attribute bands : String[0..*];
        attribute contest : String[0..1];
        attribute newPer : NewPer;
        attribute needed : Needed;
        attribute minSnrDb : Integer[0..1];
        attribute treat73AsCq : Boolean = true;
        attribute callersFirst : Boolean = true;
        attribute leaveMode : LeaveMode;
        attribute leaveCalls : Integer = 4;
        attribute leaveCallsHeard : Integer = 8;
        attribute goneMinutes : Integer = 10;
        attribute txChanges : Integer = 2;
        attribute moveEveryHeard : Integer = 0;
        attribute moveEveryNotHeard : Integer = 1;
        attribute moveEveryNoReports : Integer = 2;
        attribute busyPause : Boolean = true;
        attribute cqWhenIdle : Boolean = false;
        attribute cqWaitPeriods : Integer = 2;
        attribute retryMinutes : Integer = 10;
        attribute orderCriteriaMax : Integer = 16;
        attribute listEntriesMax : Integer = 64;
        assert constraint leaveCallsRange { leaveCalls >= 1 and leaveCalls <= 20 }
        assert constraint leaveCallsHeardRange { leaveCallsHeard >= leaveCalls and leaveCallsHeard <= 40 }
        assert constraint goneRange { goneMinutes >= 1 and goneMinutes <= 60 }
        assert constraint txChangesRange { txChanges >= 1 and txChanges <= 20 }
        assert constraint moveRange { moveEveryHeard >= 0 and moveEveryHeard <= 20 and moveEveryNotHeard >= 0 and moveEveryNotHeard <= 20 and moveEveryNoReports >= 0 and moveEveryNoReports <= 20 }
        assert constraint retryRange { retryMinutes >= 1 and retryMinutes <= 120 }
        assert constraint cqWaitRange { cqWaitPeriods >= 1 and cqWaitPeriods <= 20 }
        doc /* D19 (schema 4 of strategy.json, StrategyConfiguration). The same keys for every
             class, in the order of the decisions; wire keys exactly:
             name (1..32 printable ASCII, no leading/trailing space, unique ignoring case, never a
             built-in's name, BuiltinStrategies); class (StrategyClass);
             bands (decision 1, StrategyBands: null for every band, else 1..32 unique ADIF band
             names of the ADIF band enumeration in lower case, "20m", "6m", "2m", "70cm");
             filters (decision 2, Candidate): for class strategy exactly {new (1..7 unique
             NewWhat), new_per (NewPer), new_means (Needed), region ({kind all} | {kind dx} | {kind
             selected, continents: 1..7 unique of AF AN AS EU NA OC SA}), min_snr_db (null or an
             integer -50..49), worked_since ({kind all} | {kind today} | {kind from_to, from, to}:
             real calendar dates "YYYY-MM-DD" between 1930-01-01 and 2099-12-31 with from <= to),
             treat_73_as_cq (boolean), countries (CountryList), states (UsStateFilter), cq_targets
             (CqTargetList)}; for contest exactly {countries, states, cq_targets};
             order (decision 3, ValueOrder): 0..16 unique ValueCriterion in the operator's order
             for class strategy, [] for contest (a contest ranks by its own rules);
             contest: null for class strategy, a contest id of the contest table for contest
             (the contest table, WstxContest::ProfileTable);
             callers_first (decision 4 "Calling stations are answered", boolean, CallerOfMyCall);
             leave (decision 5, LeaveRule): {mode "calls", calls 1..20, calls_heard calls..40} |
             {mode "until_logged", gone_minutes 1..60} | {mode "contest", tx_changes 1..20};
             tx_move_every (decision 6, TxMoveRule): exactly {heard, not_heard, no_reports}, each
             an integer 0..20: 0 stay, 1 move every call, n move every n-th call;
             busy_pause (decision 7, boolean, BusyPause);
             cq_when_idle (decision 8, boolean, CqWhenNoTarget);
             cq_wait_periods (decision 8, the CQ wait, an integer 1..20, CqWhenNoTarget; refused
             also when missing, at strategies[i].cq_wait_periods);
             retry_minutes (decision 9, 1..120, QuietTime).
             Each refusal is 400 invalid_request naming its field path
             (strategies[0].filters.worked_since.to, strategies[0].order[1],
             strategies[0].leave.calls_heard, strategies[0].filters.countries.include[2].value).
             A strategy is new only as a duplicate (StrategyEditor): there is no blank strategy.
             Nothing else exists: goals, needed, value, window, region, min_snr_db, repetitions,
             quiet_minutes and cq_when_no_target at the strategy's top level (schema 3, read only by
             the upgrade), calls_per_station, rules, conditions, sort, auto role, switch after, skip
             after and callers are refused like any extra key. */
    }
    attribute def StrategyBands {
        doc /* #97 decision 1. A strategy with bands null works on every band; with a list it works
             only while the station band (CAT dial band, else the operating selection band) is one
             of them, and an unknown station band is none of them. It never switches bands (D8).
             Off its bands: every verdict has rank null with why "band not in the strategy" ("band
             unknown" when unknown), so nothing is marked, alerted or called. A contest strategy
             works only on the bands both of its list and of the contest
             (WstxContest::ContestVerdict "band not in the contest"). */
    }
    attribute def CountryList {
        attribute entriesMax : Integer = 64;
        doc /* #97 decision 2 "Prefix/country include/exclude (optionally per band, + Country
             names)". filters.countries = {include, exclude}, each 0..64 entries {kind, value,
             bands}: kind "prefix" with value 1..13 of A-Z 0-9 / (upper case), matching when the
             decoded call begins with it; or kind "country" with value a full entity name of the
             country table (WstxCountryFile::EntityOfCall, a WAE entity by its own name), matching the
             sender's entity, compared ignoring case; a name the current table does not hold is
             refused at the PUT (an entry read from the file whose name a replaced cty.dat no
             longer holds matches nothing); bands null (every band) or 1..32 unique ADIF band
             names, the entry counting only while the station band is one of them. The line
             holds when no exclude entry matches and, with a non-empty include list, at least one
             include entry matches; a sender without an entity matches no country entry. Editor:
             one line per entry, with a country picker that lists the table's names. */
    }
    attribute def UsStateFilter {
        doc /* #97 decision 2 "US state include/exclude". filters.states = {include, exclude}, each
             0..51 unique two-letter codes of the 50 US states and DC (ADIF Primary Administrative
             Subdivision of the entities 291, 6 and 110). The sender's state (UsStateOf): with a
             non-empty include list the line holds only when the state is known and listed (an
             unknown state, also every station outside those entities, fails it); with an exclude
             list it fails only when the state is known and listed. */
    }
    calc def UsStateOf {
        in sender : String;
        return stateCode : String[0..1];
        doc /* The state of a sender of the entities 291, 6 or 110 (WstxCountryFile::EntityOfCall),
             the first source that knows it: (1) the decoded message, when its exchange carries a
             US state (the RTTY Roundup family; an ARRL or RAC section once #98's section table maps
             it to a state); (2) the log: the ADIF STATE of the newest record of that call that has
             one, a confirmed record (dxcc::Standing) before an unconfirmed one. The FCC/ISED
             licence data and the grid, the further sources of the operator's decision, are a
             separate issue, #101 (operator 2026-11-09, #97 Q6 "separate issue"); until it is
             delivered they give nothing.
             None: unknown. */
    }
    attribute def CqTargetList {
        attribute entriesMax : Integer = 32;
        doc /* #97 decision 2 "CQ target include/exclude (POTA, SOTA, EU, DX ...)".
             filters.cq_targets = {include, exclude}, each 0..32 unique words of 1..8 A-Z 0-9: the
             directive of a CQ (the word after CQ: "CQ POTA K1ABC FN42" has POTA, "CQ DX ..." DX; a
             plain CQ and an RR73/73 counted as calling have none). Exclude: a CQ whose directive is
             listed fails. Include (non-empty): only a CQ whose directive is listed passes; a plain
             CQ and an RR73/73 counted as calling fail. A caller of my call is no CQ and is not
             judged by this line. A word on the
             include list that DirectedCqRule does not answer (POTA, SOTA, a number) is answerable
             for this strategy, never for the operator's own selection, whose warning stays.
             Verdict: such a CQ is not grey for that strategy (grey false, ranked by its filters
             and order), so Band Activity marks it and does not strike it through, and Alert
             records it like any candidate. A continent directive and DX keep DirectedCqRule
             (operator 2026-11-09, #97 Q2: "we could define a pota/sota strategy"; the built-in
             POTA/SOTA, BuiltinStrategies). */
    }
    attribute def BuiltinStrategies {
        doc /* D19 (operator grill 2026-11-09). The read-only presets, one table in the
             station in this order, listed in the GET /strategy snapshot as builtin_strategies,
             each a Strategy with builtin true:
             | name | class | filters new, new_per, new_means | order | leave | cq_when_idle |
             DXCC all | strategy | [dxcc], band_mode, not_confirmed | [most_wanted, snr] |
             until_logged, gone_minutes 10 | false;
             New DXCC on band | strategy | [dxcc], band, not_confirmed | [most_wanted, snr] |
             until_logged, gone_minutes 10 | false;
             New DXCC | strategy | [dxcc], ever, not_confirmed | [most_wanted, snr] | until_logged,
             gone_minutes 10 | false;
             Casual | strategy | [call], band, not_worked | [snr_bucket, distance] | calls, calls 4,
             calls_heard 8 | true;
             POTA/SOTA | strategy | [call], band, not_worked, with worked_since today and
             cq_targets {include [POTA, SOTA], exclude []} | [snr_bucket, distance] | calls, calls 4,
             calls_heard 8 | false.
             The five differ only in their answers, not in their class. POTA/SOTA (operator
             2026-11-09, #97 Q2 "we could define a pota/sota strategy"; its values are the
             definer's defaults, listed on #97): it ranks only CQ POTA and CQ SOTA (CqTargetList
             makes them answerable for it), each activator not yet worked on this band today (a
             new park or summit is usually a new day), the strongest bucket first and then the
             farthest; its cq_when_idle is false.
             All five, unless stated in the table: bands null (all), region all, min_snr_db null,
             worked_since all, treat_73_as_cq true, countries, states and cq_targets empty, contest
             null, callers_first true, tx_move_every {heard 0, not_heard 1, no_reports 2} (stay,
             every call, every 2nd call), busy_pause true, cq_wait_periods 2, retry_minutes 10.
             "DXCC all" is first in the selector and in the editor; active stays None at a station
             start (StrategyConfiguration; operator 2026-11-09, Q8 "first in the list, not
             selected at start"). No built-in is named or marked as a default.
             Contest built-ins (operator 2026-11-09, Q1 "One per contest"): one per contest of the
             contest table (WstxContest::ProfileTable), class contest, named by the
             contest's name and holding its id, with the contest defaults: bands null, the three
             lists empty, order [], callers_first true, leave {mode contest, tx_changes 2},
             tx_move_every {heard 0, not_heard 2, no_reports 2}, busy_pause false, cq_when_idle
             true, cq_wait_periods 2, retry_minutes 10. They are offered by the contest prompt
             (WstxContest::ContestPrompt) and in the editor's contest group, not as rows of the
             strategy selector.
             The built-ins are not part of the configuration and never written to strategy.json.
             active may name one (exactly as listed; a contest built-in only with its contest
             selection, WstxContest::ContestSelection). A PUT cannot edit one: a configuration
             strategy with a built-in's name, also differing in case, is refused 400 invalid_request strategies[i].name, and the key
             builtin is refused like any extra key. In the editor a built-in is shown read-only
             and Duplicate copies it to a user strategy named "<name> copy" (StrategyEditor). A
             saved strategy whose name collides with a built-in's, ignoring case (saved before the
             built-in existed, also a contest added to the table later), reads renamed
             (StrategyConfiguration); it is never dropped. */
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
             profile.json: {schema_version 4, profile_id, revision, configuration} (#97), written
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
             of it that is otherwise malformed makes the file malformed. Each then reads on as a
             schema 3 file.
             Upgrade of schema 3 (#97, every strategy of class award) at its revision, each
             strategy mapped key by key: class strategy; bands null; filters.new and new_per from
             goals (dxcc: dxcc ever; dxcc_band: dxcc band; dxcc_slot: dxcc band_mode; waz: cq_zone
             ever; wpx: prefix ever; grid: grid ever; new_call: call ever; new_call_band: call
             band), the whats in goal order without repeats, and when the goals' pers differ the
             most specific of them (band_mode before band before ever), so that every station the
             strategy needed before is still needed; new_means = needed; region, min_snr_db and
             treat_73_as_cq kept; worked_since = window; countries, states and cq_targets {include
             [], exclude []}; order = value with new_dxcc_slot renamed new_dxcc_band_mode; contest
             null; callers_first kept; leave {mode calls, calls = repetitions, calls_heard = 2 x
             repetitions} (the doubling of the old LeaveRule); tx_move_every {heard 0, not_heard 1,
             no_reports 2} (#94, the built-ins' values); busy_pause true; cq_when_idle =
             cq_when_no_target; cq_wait_periods 2; retry_minutes = quiet_minutes. A schema 3
             strategy that is otherwise malformed makes the file malformed.
             A schema 4 file whose strategy has no cq_wait_periods (written before the key
             existed) reads it as 2; a PUT must carry it, as every key.
             Names: in every schema, a saved strategy whose name equals a built-in's ignoring case
             reads renamed "<name> copy", else "<name> copy 2", "<name> copy 3" and so on, the
             first name that is free and at most 32 characters (the name cut so that the suffix
             fits); its configuration_note lists each rename {from, to} until the next PUT (GET
             /strategy, StrategyHttp). Every older file is written as schema 4 by the next PUT. */
    }
    calc def ContinentOfCall {
        in call : String;
        return continent : String[0..1];
        doc /* #55: the continent of WstxCountryFile::EntityOfCall for the call (with a {cont}
             override of the matching cty.dat entry applied); none when the call has no
             entity (/MM, /AM, unknown prefix). It replaces the earlier locator-rectangle
             approximation: the message grid no longer decides a station's continent.
             The snapshot's derived_continent is ContinentOfCall of my callsign. */
    }
    calc def NewNeeded {
        in strategy : Strategy;
        in what : NewWhat;
        in per : NewPer;
        in needed : Needed;
        in sender : String;
        return isNew : Boolean;
        doc /* Whether one NewWhat is new for a
             decoded sender, per NewPer, against WorkedWindow of the strategy (worked_since):
             not_worked: no logged QSO with the same key; not_confirmed: none, or none confirmed
             (dxcc::Standing). The key: dxcc the sender's entity (WstxCountryFile::EntityOfCall, WAE
             entities by their own full name); call the call; grid the 4-character grid square in
             the decoded message, with the rule of D13 (no grid in the message is not new; a sender
             with a logged QSO without a grid in the window has an unknown grid status and is not
             new); cq_zone and itu_zone the zones of the sender's entity with the cty.dat entry's
             overrides; continent ContinentOfCall; prefix WpxPrefix of the call. per: ever any
             logged QSO; band one on the station band, any mode; band_mode one on the station band
             in the operating mode (ADIF MODE, an MFSK record by its SUBMODE). False without an
             entity (dxcc, cq_zone, itu_zone, continent; /MM, /AM, unknown prefix), without a
             known station band (band, band_mode) and when the log is unreadable (no claim of new).
             A logged call without an entity counts for nothing for those keys; a logged contact
             without a band counts only for ever. The schema 3 goals are exactly: dxcc ever,
             dxcc band, dxcc band_mode, cq_zone ever (waz), prefix ever (wpx), grid ever, call ever,
             call band. */
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
             than the sender's RR73/73, whose sender is not ignored (IgnoreLists). Decision 2
             (operator 2026-11-09): a caller of my call has a rank only when it passes the filters
             too: every line of Candidate except "a CQ" (and the CQ target line, which judges only
             CQs); for a contest strategy the contest's verdict (a dupe never has a rank,
             WstxContest::ContestVerdict) and the country and US state lists. A caller that fails
             gets rank null with the failing line as why ("calls my call · not new", "calls my
             call · region"). Decision 4, Calling stations are answered (callers_first): on, the
             callers that pass come first (ValueOrder); off, a caller that passes has rank null
             too, why "calls my call · not answered" (CL-097-03). Off follows WSJT-X, where the
             CQ response None (widgets/mainwindow.cpp 1564-1568, default None in
             mainwindow_settings.cpp 313) answers no caller of my CQ automatically (mainwindow.cpp
             7481-7496) and "Calling CQ forces Call 1st" is off by default (Configuration.cpp
             3884). A started QSO is always finished (StartedQso, #81): a target that answers our
             call is progress, never a caller judged again. */
    }
    attribute def Candidate {
        doc /* The filter, yes or no (Q2, Q10; #97 decision 2, the filter questions): every line
             must hold. A decoded standard message with a resolved sender, not mine, passing
             SaneCall, not ignored (IgnoreLists), the station band one of the strategy's
             (StrategyBands), not greyed (DirectedCqRule, except a word of the include list of
             CqTargetList), a CQ, or with treat_73_as_cq an RR73/73 addressed to someone else;
             region holds (all; dx: my continent and the sender's are known and differ; selected:
             the sender's continent is listed); min_snr_db null or the SNR known and >= it;
             NewNeeded true for at least one NewWhat of filters.new, with the strategy's new_per,
             new_means and worked_since (any chosen what counts); CountryList, UsStateFilter and
             CqTargetList hold. Each failing line names itself as why ("band not in the strategy",
             "region", "below min SNR", "not new", "country list", "state list", "CQ target").
             A contest strategy: ContestVerdict decides its callable records (the contest's rules
             first) and CountryList, UsStateFilter and CqTargetList apply on top; none of the
             other lines. The filter and the order may use the same field. */
    }
    attribute def ValueOrder {
        doc /* The ranking (Q2, Q3, Q8, Q9; #97 decision 3). The strategy's order is a list of
             ValueCriterion, shown as dropdown rows: the first decides and the next breaks a tie.
             Each criterion, better first:
             most_wanted: on the Most Wanted list by its rank ascending, then the stations without
             a rank (MostWantedList).
             new_dxcc, new_dxcc_band, new_dxcc_band_mode: NewNeeded dxcc per ever, band,
             band_mode; new_call, new_call_band: NewNeeded call per ever, band; new_grid,
             new_grid_band: NewNeeded grid per ever, band (D13: no grid, an unknown grid status or
             an unknown band is not new); new_cq_zone, new_itu_zone, new_continent, new_prefix:
             NewNeeded cq_zone, itu_zone, continent, prefix per ever; each with the strategy's
             new_means and worked_since; new before not new.
             snr_bucket: the SNR in three buckets, above 0 dB (snr > 0) first, -10..0 dB (-10 <=
             snr <= 0) next, below -10 dB (snr < -10) last, unknown after them; equal inside a
             bucket.
             snr: stronger first, unknown last.
             distance: StationDistance, farther first, unknown last.
             hears_us: the stations that hear us (PskrUse on and HearingFeed has a spot of my call
             at that station at most 600 s old on the station band and mode) first, then the rest;
             equal with PskrUse off or no feed.
             Then always, hidden (Q3, Q9): SNR stronger first (unknown last); then, for an
             exact tie only, the lower audio frequency, then the call in character order.
             Decode order is never a ranking.
             Order of a strategy's list: with Calling stations are answered on (callers_first,
             decision 4) the callers of my call that pass the filters (CallerOfMyCall) come first,
             ranked among themselves by the same criteria, then the candidates; with it off a
             caller has no rank (CallerOfMyCall) and the list holds the candidates only. Band
             Activity: the partner (#50, on top by the browser's partner rows), then that list,
             then the rest. A contest strategy has no order (order []): it ranks by the contest's
             own rules (WstxContest::ContestValueOrder), under the same rule for callers. */
    }
    calc def StationDistance {
        in sender : String;
        in grid : String[0..1];
        return km : Integer[0..1];
        doc /* The distance for the value criterion distance: the great-circle distance from
             the centre of the profile locator to the centre of the 4-character grid in the
             message; otherwise to the sender's entity centre from cty.dat (the approximate
             entity distance of WstxCountryFile::DecodedEntity). Unknown without a profile locator
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
             of WstxCountryFile::EntityOfCall, null without an entity)}; revision counts every
             alert recorded and every clear since the station started.
             Routes (the StrategyHttp rules for Origin, authorization, media and size): GET
             /strategy/alerts (operating access, no query, empty body) -> {v 1,
             profile_id, boot_id, revision, alerts (oldest first)}. POST
             /strategy/alerts/clear {v, profile_id, boot_id}: exact keys, the refusals of
             POST /strategy/ignore (400 invalid_request with the field,
             unsupported_version, 403 wrong_profile, 409 state_conflict boot_id); it
             empties the history, revision + 1, and returns the alerts snapshot. No MCP
             tool dispatches to the clear (an MCP principal is refused, #58); wstx_read
             view alerts reads GET /strategy/alerts (WstxMcpEndpoint::ToolCatalog).
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
             special activity (WstxSpecialActivities::SpecialActivity: na_vhf, eu_vhf and arrl_digi TEST, ww_digi WW,
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
             refused directive_not_answerable also with directive_confirmed. The one exception
             (#97, CqTargetList): a strategy run's own select_row of a CQ whose directive word is on
             its active strategy's CQ target include list passes, and that strategy's verdict of it
             is not grey. */
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
             DirectedCqRule (not grey when its directive word is on the strategy's CQ target
             include list, CqTargetList); a Candidate, and a caller (CallerOfMyCall) while Calling
             stations are answered is on, have rank = the position (0-based) in ValueOrder among
             the evaluated records; with it off a caller has rank null, why "calls my call · not
             answered" (CL-097-03); every other record rank null.
             why (explain only): "calls my call", "new: dxcc, grid" (the new whats, with
             " on <band>" or " on <band> <MODE>" per new_per), with " · Most Wanted
             #n" when ranked by the list, "not new", "not a CQ", "region", "below min SNR",
             "band not in the strategy", "band unknown", "country list", "state list", "CQ
             target", "calls my call · <failing line>" (CallerOfMyCall),
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
             up}), the MostWantedList status, builtin_strategies (BuiltinStrategies) and
             configuration_note ([] or the renames of the upgrade, [{from, to}], until the next
             PUT; the editor shows each once as "Renamed <from> to <to>")}. The body limit stays
             32768 bytes: a configuration whose PUT is larger is refused like any oversized body,
             and the editor says so.
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
             action and enabled state; receive keeps running): choose, duplicate and delete
             strategies (a new strategy is only a duplicate, "<name> copy", of a built-in or
             user strategy, keeping its class and contest; there is no blank "Add"); the list
             grouped Strategy, Contest (the two classes). Exactly the settings of Strategy, as the nine
             numbered decisions in order (D19, mockups of 2026-11-09):
             name and class (strategy or contest, shown, never switchable: a duplicate keeps it);
             1 Band: "All bands" or band checkboxes;
             2 Filters, as questions with answers: "What must be new?" (DXCC entity, Call, Grid,
             CQ zone (WAZ), ITU zone, Continent (WAC), Prefix (WPX) checkboxes); "New per" (Ever,
             Band, Band and mode); "New means" (Not worked, Not confirmed (QSL/LoTW)); "Region"
             (All, Other continents than mine, Selected continents with checkboxes); "Minimum SNR"
             (empty: none); "Worked since" (Any time, Today UTC, From/to UTC dates); "Treat 73 as
             CQ"; "Prefix/country" include and exclude lists (an entry: a prefix or a country name
             typed as free text, checked by the station on Save with a refusal shown at the entry;
             no picker, optional bands); "US state" include and exclude
             (state codes); "CQ target" include and exclude (words); the line "Callers of my call
             must pass these filters too". A contest strategy shows its contest (read-only) and
             only the three lists, under "Contest rules first, then:".
             3 Order: dropdown rows, one criterion each (add a row from the ValueCriterion names
             not yet listed, remove one, move one up or down; "the first decides, the next breaks
             a tie"; the line "then SNR" under the rows, not removable); a contest strategy shows
             "Ranked by the contest's rules" instead.
             4 "Calling stations are answered" (a checkbox, callers_first).
             5 "Leaving a station": After <n> calls without answer, <m> if he hears us | Until
             logged, leave when not decoded for <n> min | Contest style: while he hears us stay as
             long as he is the most valuable, else leave after <n> Tx changes.
             6 "Tx frequency": for each PSK case (He reports and hears us · He reports, does not
             hear us · He does not report) Stay | Move every call | Move every <n>-th call; the line
             "a move goes to a quiet slot, never onto a frequency he reports busy, never below 500
             Hz".
             7 "Busy pause: while he is in a QSO with another station keep calling on a split
             frequency and do not count".
             8 "CQ when idle, after <n> periods with nothing callable" (a checkbox, cq_when_idle,
             and a number 1..20, cq_wait_periods).
             9 "Retry pause (minutes)" before a left station is called again.
             Labels of the criteria: Most wanted (Club Log rank), New DXCC, New DXCC on band, New
             DXCC on band and mode, New call, New call on band, New grid, New grid on band, New CQ
             zone, New ITU zone, New continent, New prefix, SNR bucket (above 0, -10..0, below
             -10), SNR (stronger first), Distance (farthest first), Hears us first (PSK
             Reporter). A refused field is shown at its control with the station's reason. The
             live preview evaluates the
             unsaved draft against the latest period (POST /strategy/evaluate with explain,
             400 ms after an edit, one request per edit, no timer otherwise) and shows each
             decode's rank and why. Save sends one PUT /strategy, applies at once (also to the
             active strategy) and never selects a strategy. A built-in strategy is listed read-only with
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
             He reports (#97, #94 "reports its stations"): at least one spot whose receiver is the
             current target, from any sender (my call included), on the station's band and mode,
             at most heardWindowSeconds old, whatever its offset (the 32-offset bound and the slot
             range do not apply to this test). A spot of my call at him (he hears us) is one. With
             no target subscription yet, or one younger than a spot's upload delay, he reports only
             when such a spot has arrived: until then the PSK case is no_reports (TxMoveRule).
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
             Tx moves: at each repetition (LeaveRule) of a target that has not answered in this
             contact, Tx follows TxMoveRule (decision 6). A target that has answered (a message to my call in this
             contact) has proved the slot: Tx never leaves it in that exchange. The Rep goes on
             over a move: the message is the same.
             Unattended (no client for 60 s, or past the run limit, StrategyRun): the stop at
             N is back at once for the run's own contact, so that it ends even when no
             publication arrives; the watchdog's tx_expired stays until a new Auto on.
             The run shows the last repetition's decision as slot_check {repetitions, case
             (PskCase), hears_us (case heard), moved (boolean), hz} and the slot as tx_slot
             (FreeTxSlot).
             Display (LeaveCountLabel): WD:n is the Tx watchdog only. While the Tx
             watchdog does not bound the run's own contact (attended), the contact snapshot's
             watchdog tx_remaining_calls is null and no WD is shown; the leave count is the run's
             leave (LeaveCountLabel) with its own label. Unattended the stop at N is back and
             WD:n shows it. */
    }
    attribute def TxMoveRule {
        doc /* #97 decision 6 (operator #94, 2026-11-09: "when we call a station and it reports its
             stations and it does not hear us, we change TX frequency to another quiet slot. never
             to a occupied frequency (reported from the other station)"; "it hears us, we stay";
             "it does not report its stations ... we change TX frequency every second trial to
             another quiet slot"; #90). For the target of a strategy or contest run while it has
             not answered in this contact.
             PSK case at each repetition: heard (PskrUse on and HearingFeed hears: a spot of my
             call at him at most 600 s old on this band and mode); not_heard (not heard, and he
             reports, HearingFeed "He reports"); no_reports (every other: no spot by him, PskrUse
             off, the feed off or unreachable, the band unknown, a call without a subscription).
             The strategy's tx_move_every of that case, k: 0 stay (Tx never moves for this case);
             k >= 1: the run counts the repetitions since the selection or the last move (a call
             paused by BusyPause is not counted); when the count reaches k Tx moves before the next
             own period and the count restarts at 0. So 1 moves at every call and 2 at every second.
             A case change between repetitions applies the new case's k to the same count.
             A move takes FreeTxSlot's choice with two exclusions of its own: never the current
             slot (no candidate whose signal overlaps the current Tx signal, |f - tx| below the
             width: "another quiet slot"), and never within 50 Hz of a frequency he decodes in my
             Tx parity (HearingFeed; "never to an occupied frequency": no fallback to his end
             ignored). With no candidate left Tx stays, slot_check moved false, and the count is
             kept, so the next repetition tries again. Hold Tx on: Tx alone moves and Rx stays on
             the target; Hold Tx off: Rx and Tx together (D16). A refused move changes nothing and
             is tried again at the next repetition. Contest-style leaving counts these moves
             (LeaveRule). Unattended (StrategyRun) moves go on as above. */
    }
    attribute def BusyPause {
        doc /* #97 decision 7 (operator #93, 2026-11-09: "Keep calling, don't count"; "if the called
             station is in contact with another station, we pause counting (while still
             transmitting on a split frequency) till the called station finishes its other qso.
             reason: he cannot call us, but he sees us on his dashboard and knows that we want a
             contact"; "check if we are not on his transmit frequency").
             Busy: WstxContact::BusyPartner (from his message to another call until he ends that
             QSO, however long he is not decoded). A repetition (LeaveRule) while the target is busy
             is a paused call, when the strategy's busy_pause is on, the run is attended and the
             bound below is not reached. Unattended, or past the bound, the calls count, while the
             split move of BusyPartner still keeps Tx clear of his signal (busy_pause on).
             A paused call counts for nothing of the run: not toward leaving (the calls of mode
             calls, the change points of mode contest), not toward TxMoveRule's count; until_logged
             is not affected (it counts minutes without his decode, not calls; busy or not, its
             gone timer runs only while he is not decoded). Tx keeps calling: the split move of
             WstxContact::BusyPartner keeps Tx clear of his signal; no TxMoveRule move is made while
             he is busy.
             Bound (operator 2026-11-09, #97 Q5): at most N paused calls per message, N the
             Tx watchdog limit (WstxQsoTransmit::TxWatchdog); the (N+1)-th call while he is busy counts
             as any call. A new message (the exchange advanced) or a new contact restarts it; the
             target's being busy never does.
             busy_pause off: a busy target's repetitions count as today, and WstxContact's
             partnerWorksOther stop applies to the run's contact as today.
             The run snapshot's leave carries busy (LeaveCountLabel). */
    }
    attribute def LeaveCountLabel {
        doc /* The run snapshot (WstxMcp::AutomationWire) carries leave: null, or while the run's own contact
             has a target, {mode (LeaveMode), remaining, busy (boolean, BusyPause), paused (paused
             calls of the message due next), staying (boolean, contest stay)}: mode calls,
             remaining = calls left before leaving (n, or m while he hears us, minus the counted
             calls); until_logged, remaining = whole minutes left until he counts as gone (rounded
             up), null while he is decoded in the latest publication of his parity; contest,
             remaining = Tx changes left (tx_changes minus the changes made), null while staying.
             The browser shows it where WD:n stood for the run (the QSO pane's watchdog line and the
             station bar's transmit state), as: "Leave in <n> calls", "Until logged · leave if gone
             <n> min" ("Until logged" while he is decoded), "Leave in <n> Tx changes", "Stay · most
             valuable"; while busy " · <call> busy with <other>, not counted (<k>/<N>)" is appended (the text of
             WstxContact::BusyPartner). WD:n is never
             used for it. A manual contact, a pounce and an MCP run have leave null. */
    }
    attribute def StrategySelector {
        doc /* The strategy element in the operating view: a selector with None and the
             names of the built-in and user strategies (grouped Strategy, Contest, "DXCC
             all" first; the contest group lists the user's contest strategies and the contest in
             force, "<name> (contest)"; the contest built-ins are chosen in the contest prompt,
             WstxContest::ContestPrompt). Choosing a saved contest strategy: with a contest of its
             profile in force it sends one PUT with that active and the same contest key; with no
             contest or another contest in force it sends nothing and opens the contest prompt on
             its contest with that strategy chosen and the contest's period pre-filled, whose Start
             sends active and the contest (Cancel keeps the earlier selection, and the selector shows
             it again). Every other change sends PUT /strategy with the
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
             the partner is answering is completed, otherwise LeaveRule ends it (its unattended
             rule: no m, no contest stay, no busy pause) or the stop at N that is back
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
             #24 S2a; a contest strategy: any other than its own, WstxContest::ContestRun), band
             (the station band is not one of the strategy's, StrategyBands; a contact the run
             armed on a band it then left ends at once as a band change does); it
             selects nothing until the reason is gone.
             Waiting: on each fresh complete publication the list is the verdicts with a rank,
             not completed in this run on this band and mode, not given up by the operator
             (ManualIntervention) and not in QuietTime, one per call, in ValueOrder (callers
             first with callers_first). The first is selected (select_row {replace false}), Tx
             and Rx take their place by FreeTxSlot (with Hold Tx on Tx stays and Rx is on the
             station, D16) and it is armed (enable_tx). Nothing listed: it
             keeps waiting, or calls CQ (CqWhenNoTarget). A contact the run did not select:
             ManualIntervention.
             Decision timing (#89, operator 2026-11-09: "decision always fastest when needed
             info is available. this is a general rule for the auto mode"): every decision of an
             Auto run (a selection, a slot, a slot check, a CQ, a leaving) is taken at the
             earliest moment the information it needs is available, never later: on the
             publication that brings it at once, and, where that information can be missing,
             at the latest at the moment its own rule names, then with what is there. A
             decision whose information is all there is taken at once, without waiting. The
             waiting cases are named where the decision is defined (FreeTxSlot "Waiting for
             the newest period").
             In a contact: completion counts and returns to waiting; LeaveRule decides when the
             run leaves the target; no stop. The browser itself never sends enable_tx for a
             strategy. The run snapshot (WstxMcp) carries left (null or {call, reason
             repetitions|gone|tx_changes|caller}, #97 LeaveRule), quiet ([{call,
             band, mode, remaining_s}], the retry pause), hearing (PskrUse), tx_slot (FreeTxSlot),
             slot_check (StrategyWatchdog) and leave (LeaveCountLabel). */
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
             engine's, WstxQsoWire::ContactSnapshot; never the run's own memory) holds a
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
             stop at N applies from the next send (WstxQsoTransmit::TxWatchdog; a message already
             repeated N times under the exemption is not sent again). Tx and Rx stay where
             they are (FreeTxSlot: nothing else moves them in the exchange). Nothing new is
             selected, called or answered for it and its CQ is not called again. A run started
             meanwhile (Auto on, a selection with Auto on) finds it as a contact it did not
             select (ManualIntervention) and resumes when it has ended. The same request again
             (Auto off, None, stop) changes nothing.
             Not started at a finishing end: the contact is disarmed and cancelled at once as
             before; a transmission already on the air (the run's CQ, a Tx1, a reply)
             finishes its period (WstxQsoTransmit::SetEnableTx) and nothing after it is keyed.
             Still at once (Enable Tx off and the contact cancelled, nothing logged): HALT from
             any source; Abort QSO; an operator's selection of another station (a double-click,
             WstxStandardQso::ChangeContact); the Tx watchdog's stop; the grant revoked or a safety
             edit (authority_lost; a safety edit disarms in the transmit owner itself,
             authorityChanged); a band change or a mode change by the operator; a station
             restart (transmit is disarmed at every start); and the run's leaving while it runs
             (LeaveRule at x, a policy run's no_answer, a pounce's wait again). Unchanged:
             unattended or past the run limit the run itself finishes the QSO in progress
             (StrategyRun).
             Finishing guard: while the finished QSO's contact is still active and not
             replaced, the automation owner keeps, in memory only and in no snapshot, its
             contact id, the station band and mode at the run's end, the run's grant and the
             HALT count; at each station step it disarms and cancels that contact when the
             station band or the mode differs, the grant is no longer current (revoked, or a
             safety edit) or the HALT count has grown. It never arms, selects, answers or
             moves a frequency. The guard ends when the contact is no longer active or is
             replaced, when a new run starts, or on a restart. */
    }
    attribute def PskrUse {
        doc /* Use PSK Reporter (Q17, Q29): a toggle next to Auto (WstxOperatingLayout::QsoPane),
             kept across restarts in pskr.json use (HearingFeed), on by default. The Settings
             switch (HearingFeed enabled) stays the master: with it off the toggle is disabled
             (title "PSK Reporter is off in Settings") and counts as off. POST /pskr/use saves
             it; pskr.state pushes it. With it off, runs use no spot: no target subscription, no
             target hears us or reports (LeaveRule uses n, never m, the contest stays nothing,
             TxMoveRule's case is no_reports, ValueOrder hears_us ties), and FreeTxSlot ignores his
             end.
             While it is on, a strategy or contest run's own contact has a target, the QSO pane
             shows two lines under the header: "Hears us: <age> ago · <rp> dB" from the newest
             spot of my call at the target (age from station.tick: "<n> s" below 120 s, else
             "<n> min" in whole minutes; rp signed as "−12"; "· ? dB" without rp),
             "Hears us: no" when the feed is connected, the call has a subscription and no such
             spot is at most 600 s old, and "Hears us: unknown" otherwise; and "Tx <hz> Hz ·
             open at his end: yes" (no frequency he decodes from my Tx parity lies within 50 Hz
             of the slot), "· no" (the slot was chosen although one does, FreeTxSlot), or
             "· unknown" (he has no such spot). The run snapshot (GET /automation, read on
             automation.state) carries hearing {state heard|no|unknown, reports (he reports,
             HearingFeed; false also when unknown), spot_utc_s, snr_db} and
             tx_slot {hz, power_db, his_end yes|no|unknown}; a change of either increments the
             run revision. The QSO pane's PSK line itself is #95's. */
    }
    attribute def LeaveRule {
        attribute leaveMode : LeaveMode;
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
             although he may hear us: the target is not decoded in it. A call paused by BusyPause
             is no repetition for leaving.
             Hears us: PskrUse on and HearingFeed hears (a spot of my call at the target at most
             600 s old on this band and mode).
             The strategy's leave (decision 5):
             calls {calls n, calls_heard m}: the run leaves at the repetition that brings the count
             to n, or to m while the target hears us, in both situations (reason repetitions).
             until_logged {gone_minutes g}: no count; the run stays until the QSO is completed (and
             logged, WstxLogbook::DirectLog) and leaves at the first fresh complete publication of
             the target's parity at whose period start the newest decoded message of the target
             (any message, to anyone, on this band and mode; at the selection the message it was
             selected on) has a period start g minutes or more earlier (reason gone): exactly g
             minutes leaves, g minutes less one period does not.
             contest {tx_changes c} (contest style): in situation 1 while the target hears us and
             no more valuable station is listed in this publication (a callable station, eligible,
             not the target, strictly before it by the strategy's order, for a contest strategy
             WstxContest::ContestValueOrder) the run stays, with no count (staying). Otherwise it
             counts Tx changes (operator 2026-11-09, #97 Q4 "6 calls on 3 slots"): a change point is a
             repetition at which TxMoveRule's case would move (k >= 1 and its count reaching k), and
             with k = 0 (stay) every repetition; at a change point with fewer than c changes made
             the change counts and Tx moves by TxMoveRule when the case's k >= 1 (also counted when
             no candidate is left and Tx stays); with k = 0 Tx never moves (stay means stay, #94 "it
             hears us, we stay"), also off a heard target that is no longer the most valuable; at a
             change point with c changes made the run leaves (reason tx_changes). So c 2 with every
             2nd call leaves after 6 calls on three slots, and c 2 with k 0 after 3 calls on one
             slot.
             Progress resets every count of the contact to 0 (calls, change points, changes made).
             No change before an exit criterion (Q7): a more valuable station never ends a stay
             except as the contest mode says.
             The one exception: a caller of my call that passes the filters (CallerOfMyCall; in a
             contest strategy only a caller with a rank, so never a dupe) is answered at once while
             the target has not answered in this contact, when callers_first is on, it is
             eligible and not in QuietTime, and the target is not that caller: the stay ends
             and that caller is selected from the same publication.
             Unattended or past the run limit (StrategyRun): calls uses n, never m; until_logged
             and contest leave at the stop at N that is back (StrategyWatchdog), with no contest
             stay; there is no busy pause and no caller exception.
             Leaving: disarm and cancel the contact, the left station gets its retry pause
             (QuietTime), run.left = {call, reason repetitions|gone|tx_changes|caller}, and the run
             waits; reason caller selects the caller from that publication at once. The stops of
             StrategyRun "Ends at once" are no leaving. */
    }
    attribute def QuietTime {
        doc /* The retry pause (decision 9, Q6). After every leaving
             (LeaveRule) the left station gets the strategy's retry_minutes (default 10) from the
             leaving, on that band and mode. During it the run does not select it, also not
             when it calls my call, nor answer it from a CQ. It is run memory: a new run starts
             with none. The run snapshot lists it as quiet [{call, band, mode, remaining_s}]
             (whole seconds, rounded up); an entry ends at its time. */
    }
    attribute def CqWhenNoTarget {
        doc /* CQ when idle (decision 8, CL-097-08): the strategy option cq_when_idle (Q35, Q40;
             off in DXCC all, New DXCC on band, New DXCC and POTA/SOTA, on in Casual and in the
             contest built-ins, WstxContest D11) with its CQ wait cq_wait_periods (1..20, 2 in every
             built-in). It is not a special class. With it on, a waiting run with no waiting reason
             that has seen cq_wait_periods consecutive fresh complete publications with nothing
             listed (StrategyRun Waiting; every period counts, both parities: 2 is 30 s in FT8 and
             15 s in FT4) calls CQ (WstxContest::ContestRun). The count starts at 0 at Auto on
             (a new run), after a QSO ends and after a leaving, and a publication with a listed
             station ends the wait (it is selected). With cq_when_idle off the CQ wait has no
             effect and is kept. The CQ:
             it decides the slot (FreeTxSlot, quiet in my Rx parity; with Hold Tx on the held Tx,
             no decision, D16) and sends enable_tx with
             no partner, which calls the activity's Tx6 (a plain CQ outside a contest
             activity); state calling_cq. On each fresh complete publication the list of
             StrategyRun Waiting is read again: the first listed station is selected (a caller
             with select_row {replace false}, which keeps Enable Tx and answers it from the CQ's
             slot; a candidate the same way), the CQ ends; nothing listed: the CQ goes on. After
             a completion or a leaving the run waits, and calls CQ again after cq_wait_periods
             more publications with nothing listed. The Tx watchdog stops the CQ at its limit, and the
             run stops tx_watchdog (StrategyWatchdog). Unattended or past the run limit the CQ
             ends at once (StrategyRun). */
    }
    attribute def FreeTxSlot {
        attribute periodsPerParity : Integer = 4;
        attribute floorLowHz : Integer = 300;
        attribute floorHighHz : Integer = 2700;
        attribute clearanceHz : Integer = 50;
        attribute stepHz : Integer = 10;
        attribute candidateLowHz : Integer = 500;
        attribute upperEdgeHz : Integer = 2400;
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
             among the last periodsPerParity (4) periods of my Rx parity that are due at the
             decision (FT8 about the last 2 minutes, FT4 the last minute); a period of them that
             I transmitted in or did not receive leaves a gap that no older period fills; fewer:
             those there are.
             Due (#89, operator 2026-11-09 "Count once decoded"): a period is due once it has
             ended on the station clock, or earlier, while it is in progress, once the complete
             publication of its decodes has been published (the decoder publishes a period before
             it ends, about 0.9 s before the next period start in FT8). A period that has not
             started on the station clock is never due, also when a publication names it. So a decision taken on the publication of my
             newest Rx period, still in progress on the clock (a selection, a slot check, a
             pounce, a CQ after CqWhenNoTarget's publications), counts that period, and the
             oldest of the four drops out. Such a period counts with its decodes of that
             publication and its levels over the detailed rows received up to the decision; once
             it has ended, a later decision takes all its rows. A partial publication (not
             complete) makes no period due; a period in progress without its complete
             publication is not counted. A period that has ended without its decodes published
             counts by its levels, and its decodes count from their publication on (unchanged).
             No decision already taken is taken again because a period becomes due.
             Waiting for the newest period (#89 round 1 Q1, StrategyRun Decision timing): every
             CQ of a contest Run (WstxContest::ContestRun) decided in waiting without a fresh
             publication (at Auto on, when a waiting reason ends, when a manual contact ends or
             Esc gives a caller up, after a completion or a leaving) while the newest period of
             its Rx parity (in progress or ended) has no complete publication waits for that
             publication and is taken at once when it arrives, at the latest when the period in
             progress ends (then with what is due then), never later; when that period's complete
             publication is already there it is taken at once. The CQ (enable_tx) is sent only
             after the decision. With
             Hold Tx on the CQ takes no decision (D16) and does not wait. A run that stops, gets a
             waiting reason or is made manual meanwhile takes no decision and sends nothing; a
             repeated Auto on during the wait starts no second wait or decision.
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
             the Tx range (FrequencyControls) from candidateLowHz: FT8 500..2650, FT4 500..2610
             (#97, #90, operator 2026-11-09 "Avoid the lower edge below 500": Auto never chooses a
             slot below 500 Hz; a held Tx below 500 is kept where Hold Tx keeps it, and is no
             candidate; the open-slot marks, FreeTxSlots, keep 300); never within
             clearanceHz (50 Hz) of the called station's signal nor of my Rx signal (Tx is never
             on the called station, "never to the Rx frequency"). Free of decoded stations
             (#66 round 1 Q2): a candidate whose signal overlaps a station decoded in a counted
             period, its decoded audio frequency d (the lower edge of its signal) with
             |f - d| below the width (FT8 50 Hz, FT4 90 Hz), is left out; when that leaves no
             candidate, all of them are used. Among those left, where known it is free at his
             end: at least 50 Hz from every frequency
             HearingFeed shows him decoding, counting only spots of my Tx parity (PskrUse on);
             when that leaves no candidate, his end is not used and the status says "· no" (not for
             a move of TxMoveRule, which never uses that fallback).
             Choice: the lowest value wins; a tie prefers a slot off the upper edge (#97, #90 "The
             upper edge is acceptable but not preferred"; operator 2026-11-09, #97 Q3 "above 2400 Hz, tie-break only": a
             slot whose signal reaches above upperEdgeHz, f + width > 2400 Hz, loses every tie and
             wins only when strictly quieter), then keeps the current Tx when it is among the
             quietest, else goes nearer the current Tx, then lower. There is no threshold. So
             among the free slots (0) a free slot off the upper edge wins, the current Tx when it
             is one, else the one nearest it, then the lower.
             No power yet (no counted period): Tx keeps the current frequency
             unless it is too near the called station or my Rx (then the nearest candidate away
             from it), power_db null. One counted period is enough to compare.
             Band: a retune keeps the live job, so from a station band change on only periods
             after it count, for the value and the decoded stations; a new live identity counts
             from its first period.
             Hold Tx (WstxContact::FrequencyControls holdTx, read at each decision; D16):
             Hold Tx off: decided once per call, between QSOs, when the run or a pounce has
             selected its station (a caller of my call as well), before a CQ, and at each move of
             TxMoveRule. Rx = Tx: set_frequency moves rx_hz and tx_hz to the slot
             together, only when either is not on it (the selection has moved Tx to the
             station: it goes back).
             Hold Tx on: a selection (a caller of my call as well, also from the run's CQ) keeps
             Tx and leaves Rx on the station where select_row put it; only when the station's
             signal is within 50 Hz of Tx does Tx go to the nearest candidate clear of it (the
             candidates above with power not used, so also clear of decoded stations while one
             is free, the lower on a tie; round 1 Q2 "Move 50 Hz away"). A CQ goes out on the held Tx with no decision (Q3). At each move of
             TxMoveRule Tx alone takes the choice above and
             Rx stays (set_frequency with tx_hz only). A pounce has no TxMoveRule, so with
             Hold Tx on it moves Tx only by the 50 Hz rule. A held Tx outside the candidate range above is kept at a
             selection and for a CQ unless it must move by the 50 Hz rule; at a move it
             is no candidate and Tx moves into the range (round 3 Q6 "Move into the range"). Status with Hold Tx on: tx_slot names the held Tx with its rise and his
             end.
             Busy (WstxContact::BusyPartner): when he sends to another call and Tx is not clear of
             his signal (FT8 100 Hz, FT4 140 Hz between the lower edges), Tx alone moves to the
             nearest candidate clear of it and Rx stays on him, with Hold Tx on and off alike.
             Nothing else during the exchange moves it; the
             "may" of the operator's rule (Tx to the partner's frequency once the QSO is
             established) is not taken. A caller of my call is a called station like any
             other. The next decision starts from the Tx the operator may have set meanwhile.
             Status: the run's tx_slot {hz, power_db, his_end yes|no|unknown} (WstxMcp), power_db
             the whole-dB compared value of that slot, its largest rise above the passband floor
             clamped at 0 (null without power). */
    }
    attribute def FreeTxSlots {
        attribute eventBytesMax : Integer = 1024;
        attribute rangesMaxFt8 : Integer = 48;
        attribute rangesMaxFt4 : Integer = 26;
        doc /* Open Tx slots (#65, replaced by #82, D18): every free frequency on my side at
             the time the other station will be transmitting, for the operator to see on the
             waterfall and to place Tx by hand (WstxOperatingLayout::FreeTxSlotMarks). The
             station's own value, built with or without an automation run, a QSO or Auto (no
             run_id, no ranking, no limit; #65's five best of each run decision go).
             Judged parity (round 2 Q1, "when he will be transmitting"): my Rx parity, the
             periods the other station transmits in (#66). In a QSO (Enable Tx on, my own CQ
             included, or a contact in progress, replying..signoff; by a run or by hand) the
             contact's Rx parity, the other of its Tx parity, so the value stays on that one
             parity. Otherwise (only listening: no run, a run waiting, Tune alone) the next
             period I could transmit in is the one after the period P in progress, and its Rx
             parity is P's own (round 1 Q3): the parity alternates every period.
             Counted periods, floor and value: FreeTxSlot's, unchanged (the last
             periodsPerParity periods of that parity that are due, ended on the clock or in
             progress with their complete publication published, #89; a period I transmitted in or did not
             receive leaving a gap; the WSJT-X
             passband floor; a slot's largest rise above it in those periods, clamped at 0 in
             whole dB). They are taken from the station's live job in the station's operating
             mode (WstxQsoTransmit::StationOperatingMode), from the last station band change on
             and from a new live identity's first period (FreeTxSlot Band, kept by the station,
             not by a run).
             Open (round 2 Q2): a Tx frequency f of FreeTxSlot's candidate grid (stepHz 10 Hz
             steps with my whole signal inside the Tx range, FT8 300..2650, FT4 300..2610) is
             open when its compared value is 0 (at or under the floor) and its signal
             [f, f + width) (FT8 50 Hz, FT4 90 Hz) overlaps no station decoded in a counted
             period (|f - d| below the width, d the decoded audio frequency). Nothing else
             applies: no clearance of a called station or of my Rx, no his end, no fallback
             when none is open, no ranking. The partner and every other decoded station of the
             counted periods close their own slots.
             Open ranges: the union of the signals [f, f + width) of the open f, as half-open
             intervals; overlapping intervals join, touching ones stay separate. Each range is
             [lo_hz, hi_hz) with lo an open f and hi an open f + width, at least one width
             long, ascending and disjoint. So at most rangesMaxFt8 (48, 2400 / 50) in FT8 and
             rangesMaxFt4 (26, floor of 2400 / 90) in FT4.
             Built: at each period start on the station clock; when the decodes of a counted
             period are published (operator 2026-11-09, Rebuild on decodes), also the complete
             publication of the period in progress of the judged parity, which makes it due and
             counted from that build on (#89; while only listening the judged parity is that
             period's own, so the last build before the next period start counts it); at once when a QSO starts or ends (the judged parity may change); at once when the live job, its mode or the
             station band changes. Without a live receive (no live job) the value is null; with
             no counted period open is [].
             Value: null or {at_utc_ms (station time of the build), mode ft8|ft4, rx_parity
             even|odd (the judged parity), qso (true in a QSO), periods (the number of counted
             periods, 0..periodsPerParity), open [[lo_hz, hi_hz], ...]}, integers in Hz, no
             per-slot numbers. It is GET /automation free_tx_slots (WstxMcp::AutomationWire)
             and the free_tx_slots.state event (WstxStationProtocol::PushedStationState), at
             most eventBytesMax (1024) bytes with the most ranges at their longest numbers.
             Auto's choice is FreeTxSlot's, unchanged: its own candidates (clear of the called
             station and with Hold Tx on of my Rx, his end where known), its own ranking (the
             lowest value, then the current Tx, nearer it, lower) and tx_slot in the run status.
             That ranking is not on screen. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    attribute def WatchdogFromOperator {
        doc /* The Tx watchdog limits the repetitions of one message
             (WstxQsoTransmit::TxWatchdog, operator rule 2026-11-06) and is never paused by
             automation; a new message or station restarts the repetition count, so it
             bounds a run per message, not in total (max_run_minutes bounds a policy run; a
             strategy run is bounded by its 8 hour run limit and its grant). A
             human action in the browser is an accepted ContactCommand, a strategy selection
             or an Auto on (AutoToggle) sent by the browser (principal browser, WstxStationProtocol::RequestPrincipalRule:
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

    dependency storeClause from StrategyConfiguration to WstxContact::'CL-039-01';
    dependency evaluateClause from Verdict to WstxContact::'CL-039-02';
    dependency goalClause from NewNeeded to WstxContact::'CL-039-02';
    dependency strategyRedesignClause from Strategy to WstxContact::'CL-097-01';
    dependency strategyClassClause from StrategyClass to WstxContact::'CL-097-01';
    dependency builtinRedesignClause from BuiltinStrategies to WstxContact::'CL-097-01';
    dependency storeRedesignClause from StrategyConfiguration to WstxContact::'CL-097-01';
    dependency editorRedesignClause from StrategyEditor to WstxContact::'CL-097-01';
    dependency bandsClause from StrategyBands to WstxContact::'CL-097-02';
    dependency filterClause from Candidate to WstxContact::'CL-097-02';
    dependency newNeededClause from NewNeeded to WstxContact::'CL-097-02';
    dependency callerFilterClause from CallerOfMyCall to WstxContact::'CL-097-02';
    dependency countryClause from CountryList to WstxContact::'CL-097-02';
    dependency stateClause from UsStateFilter to WstxContact::'CL-097-02';
    dependency stateOfClause from UsStateOf to WstxContact::'CL-097-02';
    dependency cqTargetClause from CqTargetList to WstxContact::'CL-097-02';
    dependency orderClause from ValueOrder to WstxContact::'CL-097-03';
    dependency leaveRedesignClause from LeaveRule to WstxContact::'CL-097-04';
    dependency retryClause from QuietTime to WstxContact::'CL-097-04';
    dependency leaveLabelClause from LeaveCountLabel to WstxContact::'CL-097-04';
    dependency watchdogLabelClause from StrategyWatchdog to WstxContact::'CL-097-04';
    dependency txMoveClause from TxMoveRule to WstxContact::'CL-097-05';
    dependency txMoveSlot from TxMoveRule to FreeTxSlot;
    dependency txMoveHearing from TxMoveRule to HearingFeed;
    dependency slotEdgeClause from FreeTxSlot to WstxContact::'CL-097-05';
    dependency busyPauseClause from BusyPause to WstxContact::'CL-097-06';
    dependency busyPausePartner from BusyPause to WstxContact::BusyPartner;
    dependency cqIdleClause from CqWhenNoTarget to WstxContact::'CL-097-01';
    dependency contestClassClause from StrategyClass to WstxContact::'CL-097-07';
    dependency valueClause from ValueOrder to WstxContact::'CL-039-02';
    dependency builtinClause from BuiltinStrategies to WstxContact::'CL-039-11';
    dependency mostWantedClause from MostWantedList to WstxContact::'CL-039-10';
    dependency ignoreClause from IgnoreLists to WstxContact::'CL-042-02';
    dependency pounceClause from Pounce to WstxContact::'CL-042-03';
    dependency pouncePath from Pounce to WstxMcp::OperatingAutomation;
    dependency alertClause from Alert to WstxContact::'CL-042-04';
    dependency directedClause from DirectedCqRule to WstxContact::'CL-039-03';
    dependency myContinentClause from MyContinent to WstxContact::'CL-039-03';
    dependency manualClause from ManualIntervention to WstxContact::'CL-039-05';
    dependency valueViewClause from ValueView to WstxRequirements::'CL-039-04';
    dependency editorClause from StrategyEditor to WstxRequirements::'CL-039-04';
    dependency selectorClause from StrategySelector to WstxRequirements::'CL-039-04';
    dependency selectorBootClause from StrategySelector to WstxRequirements::'CL-074-01';
    dependency runClause from StrategyRun to WstxContact::'CL-039-05';
    dependency freeSlotClause from FreeTxSlot to WstxContact::'CL-039-09';
    dependency freeSlotRun from StrategyRun to FreeTxSlot;
    dependency freeSlotPounce from Pounce to FreeTxSlot;
    dependency freeTxSlotsClause from FreeTxSlots to WstxContact::'CL-065-01';
    dependency freeTxSlotsChoice from FreeTxSlots to FreeTxSlot;
    dependency watchdogClause from WatchdogFromOperator to WstxTransmit::'CL-039-06';
    dependency hearingClause from HearingFeed to WstxContact::'CL-039-20';
    dependency strategyWatchdogClause from StrategyWatchdog to WstxContact::'CL-039-21';
    dependency strategyWatchdogHearing from StrategyWatchdog to HearingFeed;
    dependency strategyWatchdogSlot from StrategyWatchdog to FreeTxSlot;
    dependency strategyWatchdogOwner from StrategyWatchdog to WstxQsoTransmit::TxWatchdog;
    dependency automationPath from StrategyRun to WstxMcp::OperatingAutomation;
    dependency autoClause from AutoToggle to WstxContact::'CL-039-22';
    dependency autoFinishClause from AutoToggle to WstxContact::'CL-081-01';
    dependency startedQsoClause from StartedQso to WstxContact::'CL-081-01';
    dependency startedQsoRun from StrategyRun to StartedQso;
    dependency startedQsoAutomation from StartedQso to WstxMcp::OperatingAutomation;
    dependency startedQsoWatchdog from StartedQso to WstxQsoTransmit::TxWatchdog;
    dependency pskrUseClause from PskrUse to WstxContact::'CL-039-20';
    dependency leaveClause from LeaveRule to WstxContact::'CL-039-23';
    dependency quietClause from QuietTime to WstxContact::'CL-039-23';
    dependency cqClause from CqWhenNoTarget to WstxContact::'CL-039-22';
    dependency distanceClause from StationDistance to WstxContact::'CL-039-02';
    dependency leaveHearing from LeaveRule to HearingFeed;
    dependency leaveRun from StrategyRun to LeaveRule;
    dependency cqRun from StrategyRun to CqWhenNoTarget;
    dependency watchdogOwner from WatchdogFromOperator to WstxQsoTransmit::TxWatchdog;
}
