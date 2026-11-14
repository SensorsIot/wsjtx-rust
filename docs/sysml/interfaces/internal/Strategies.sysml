package WstxStrategies {
    private import ScalarValues::*;
    private import WstxRankingControl::Needed;
    private import WstxRankingControl::NewPer;
    private import WstxRankingControl::Continent;
    private import WstxRankingControl::RankingKeys;
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
             contest table (WstxStrategies::ProfileTable), class contest, named by the
             contest's name and holding its id, with the contest defaults: bands null, the three
             lists empty, order [], callers_first true, leave {mode contest, tx_changes 2},
             tx_move_every {heard 0, not_heard 2, no_reports 2}, busy_pause false, cq_when_idle
             true, cq_wait_periods 2, retry_minutes 10. They are offered by the contest prompt
             (WstxStrategies::ContestPrompt) and in the editor's contest group, not as rows of the
             strategy selector.
             The built-ins are not part of the configuration and never written to strategy.json.
             active may name one (exactly as listed; a contest built-in only with its contest
             selection, WstxStrategies::ContestSelection). A PUT cannot edit one: a configuration
             strategy with a built-in's name, also differing in case, is refused 400 invalid_request strategies[i].name, and the key
             builtin is refused like any extra key. In the editor a built-in is shown read-only
             and Duplicate copies it to a user strategy named "<name> copy" (StrategyEditor). A
             saved strategy whose name collides with a built-in's, ignoring case (saved before the
             built-in existed, also a contest added to the table later), reads renamed
             (StrategyConfiguration); it is never dropped. */
    }
    attribute def StrategyConfiguration {
        attribute continent : Continent[0..1];
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
             WstxStrategies::ContestSelection, never persisted). Persisted as strategy.json beside
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
    attribute def StrategyHttp {
        attribute bodyBytesMax : Integer = 32768;

        doc /* GET /strategy (operating access, no query, empty body): {v 1, profile_id,
             boot_id, revision, configuration (or null), configuration_error, the ranking state
             of RankingStateWire, builtin_strategies (BuiltinStrategies) and
             configuration_note ([] or the renames of the upgrade, [{from, to}], until the next
             PUT; the editor shows each once as "Renamed <from> to <to>")}. The body limit stays
             32768 bytes: a configuration whose PUT is larger is refused like any oversized
             body, and the editor says so.
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
             contact.state; the browser then reads GET /strategy. So a HALT's Auto off and
             another browser's selection or toggle are pushed. */
    }
    attribute def ContestProfile {
        doc /* Rule facts only, one data entry per contest, no behaviour of its own; wire keys of
             GET /strategy/contests exactly: id, name, cabrillo (null: no Cabrillo log),
             cabrillo_confirmed, activity (WstxSpecialActivities::SpecialActivity name), bands (ADIF band
             names), modes, exchange, dupes (DupeRule), points (PointsRule), multipliers
             (MultiplierRule), score, automation (AutomationClause), automation_text (the clause
             as the rules word it, or that they do not address it), schedule (the rule in words),
             notes (location and entry limits, operating-time limits), source (the URL) and period
             (null when asked, else {start, end, band}: ScheduleRule at the time of the request,
             "YYYY-MM-DDTHH:MMZ", end exclusive, band null unless the round names one). */
    }
    attribute def ContestHttp {
        doc /* GET /strategy/contests (operating access, no query, empty body; the refusals of GET
             /strategy): {v 1, profile_id, boot_id, profiles: [ContestProfile]}. It changes nothing;
             the browser reads it when the period prompt opens, and once per connection while a
             contest is in force (for its name), never at a plain page load or reconnect (it is several
             kB on the 32 kbit/s link) and never on a timer. */
    }
    attribute def ContestSelection {
        attribute periodDaysMax : Integer = 31;
        doc /* The optional key contest of WstxStrategies::StrategyConfiguration on PUT /strategy and in
             the GET /strategy snapshot, present only while one is selected: {profile (a profile
             id), start, end (real instants "YYYY-MM-DDTHH:MMZ", end exclusive, start < end, at most
             31 days apart)}.
             Exact keys; each refusal names its field (contest, contest.profile, contest.start,
             contest.end), 400 invalid_request like any other field. The keys operation,
             repetitions and quiet_minutes, "colouring" and automation_confirmed are refused like
             any other value or extra key (those settings are the contest strategy's own; colouring
             only is Auto off, and the confirmation goes with Auto on, WstxAutoControl::AutoToggle).
             null or absent: no contest.
             Exactly one strategy is active or none: a contest goes with active naming a
             contest strategy (a contest built-in or a saved strategy of class contest) whose
             contest is profile; active of class contest without it, a contest without such an
             active, or the two naming different contests are refused with field contest. It
             lives in station memory only: the file never holds it and a station restart starts
             without one (as active, WstxStrategy D2). A changed contest is a changed selection.
             HALT turns Auto off and leaves the contest in force: it then transmits nothing. An MCP principal cannot select one (the PUT
             /strategy principal guard). No alert is recorded for a contest
             (WstxAlert::AlertRule follows the active strategy of class strategy). */
    }
    attribute def ContestPrompt {
        doc /* The Contest button of the strategy element opens a modal dialog with its own HALT (the
             top-bar HALT's action, as WstxSettings::StrategyEditor); receive keeps running. It reads
             GET /strategy/contests once at opening, so the pre-fill is current. It offers the
             profiles; Start and End (UTC, to the minute): the selection in force when it matches, else
             the profile's period, empty when asked; the schedule in words; the strategy (D11: the
             profile's contest built-in, first and chosen, and every saved contest strategy of that
             profile, by name; there is no operation choice, the settings are the strategy's own,
             WstxSettings::StrategyEditor); the automation text and the notes. Whether it transmits is
             the Auto toggle's (WstxAutoControl::AutoToggle): a forbidden clause asks its
             confirmation when Auto is switched on, not at Start. When the profile's
             activity differs from the station's, one line says so. Start with an empty period
             asks for it and sends nothing; else one PUT /strategy with active the chosen contest
             strategy and contest. Cancel
             changes nothing. In the selector the contest in force is one more option "<name>
             (contest)"; None or a strategy of class strategy sends a PUT without contest (the selector's other
             rule, WstxOperatingLayout::StrategySelector, is unchanged). */
    }

    enum def StrategyClass {
        doc /* Two classes, wire "strategy" and "contest".
             strategy: Filters and Order from the filter questions; DXCC all and Casual are both of
             this class and differ only in their answers. contest: Filters and Order from a contest
             (WstxContest), with the operator's country, US state and CQ target lists on top; a
             contest strategy is a duplicate of a contest built-in (BuiltinStrategies) and keeps
             its class and contest. Any other class on a PUT is refused. The class is never
             switched in the editor. */
        enum strategy;
        enum contest;
    }
    enum def LeaveMode {
        doc /* The leave modes of LeaveRule: calls (after n calls without an answer, m while he
             hears
             us), until_logged (stay until the QSO is logged; leave when he has not been decoded
             for n minutes), contest (contest style: while he hears us stay as long as he is
             still the
             most valuable, else leave after n Tx changes). */
        enum calls; enum until_logged; enum contest;
    }
    attribute def Strategy {
        attribute name : String;
        attribute strategyClass : StrategyClass;
        attribute ranking : RankingKeys;
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

        assert constraint leaveCallsRange { leaveCalls >= 1 and leaveCalls <= 20 }
        assert constraint leaveCallsHeardRange {
            leaveCallsHeard >= leaveCalls and leaveCallsHeard <= 40
        }
        assert constraint goneRange { goneMinutes >= 1 and goneMinutes <= 60 }
        assert constraint txChangesRange { txChanges >= 1 and txChanges <= 20 }
        assert constraint moveRange {
            moveEveryHeard >= 0 and moveEveryHeard <= 20 and moveEveryNotHeard >= 0 and
            moveEveryNotHeard <= 20 and moveEveryNoReports >= 0 and moveEveryNoReports <= 20
        }
        assert constraint retryRange { retryMinutes >= 1 and retryMinutes <= 120 }
        assert constraint cqWaitRange { cqWaitPeriods >= 1 and cqWaitPeriods <= 20 }
        doc /* Schema 4 of strategy.json (StrategyConfiguration). The same keys for every class,
             in the order of the decisions; the keys bands, filters, order, contest and
             callers_first
             are the features of RankingKeys; wire keys exactly:
             name (1..32 printable ASCII, no leading/trailing space, unique ignoring case, never
             a built-in's name, BuiltinStrategies); class (StrategyClass);
             bands (decision 1, StrategyBands: null for every band);
             filters (decision 2, Candidate): for class strategy exactly {new (1..7 unique
             NewWhat), new_per (NewPer), new_means (Needed), region ({kind all} | {kind dx} |
             {kind
             selected, continents: 1..7 unique Continent codes}), min_snr_db (null or an
             integer -50..49), worked_since ({kind all} | {kind today} | {kind from_to, from,
             to}: WorkedWindow),
             treat_73_as_cq (boolean), countries (CountryList), states (UsStateFilter),
             cq_targets (CqTargetList)}; for contest exactly {countries, states, cq_targets};
             order (decision 3, ValueOrder): 0..16 unique ValueCriterion in the operator's order
             for class strategy, [] for contest (a contest ranks by its own rules);
             contest: null for class strategy, a contest id of the contest table for contest
             (the contest table, WstxStrategies::ProfileTable);
             callers_first (decision 4 "Calling stations are answered", boolean,
             CallerOfMyCall); leave (decision 5, LeaveRule): {mode "calls", calls 1..20,
             calls_heard calls..40} |
             {mode "until_logged", gone_minutes 1..60} | {mode "contest", tx_changes 1..20};
             tx_move_every (decision 6, TxMoveRule): exactly {heard, not_heard, no_reports},
             each
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
             quiet_minutes and cq_when_no_target at the strategy's top level (schema 3, read
             only by the upgrade), calls_per_station, rules, conditions, sort, auto role, switch
             after, skip
             after and callers are refused like any extra key. */
    }
    enum def DupeRule {
        doc /* band: once per band. band_mode_class: once per band and per Phone, CW or Digital.
             band_grid: once per band from any specific grid. call: one QSO per call in
             the period. */
        enum band;
        enum band_mode_class;
        enum band_grid;
        enum call;
    }
    enum def PointsRule {
        doc /* one_plus_per_3000_km; one_plus_per_500_km_up; field_day (Phone 1, CW 2, Digital
             2); vhf_january (50 and 144 MHz 1, 222 and 432 MHz 2, 902 and 1296 MHz 4, 2.3
             GHz and up 8);
             vhf_june_september (1, 2, 3, 4); kilometres (one per km truncated plus 1 between
             large square centres at 111.2 km per degree, the same large square 50);
             one_per_call. */
        enum one_plus_per_3000_km;
        enum one_plus_per_500_km_up;
        enum field_day;
        enum vhf_january;
        enum vhf_june_september;
        enum kilometres;
        enum one_per_call;
    }
    enum def MultiplierRule {
        doc /* none; field_per_band: each 2-character field on each band; grid_per_band: each
             4-character grid on each band. */
        enum none;
        enum field_per_band;
        enum grid_per_band;
    }
    enum def AutomationClause {
        doc /* forbidden: the rules forbid or in effect forbid automatic operation (a warning the
             operator must confirm); silent: the rules do not address it (a short note). No
             contest explicitly permits it. */
        enum forbidden;
        enum silent;
    }
    attribute def ScheduleRule {
        doc /* A profile has one or more rounds, each a day rule and a start and an exclusive
             end in minutes from 00:00 UTC of that day: the n-th full weekend of a month, the last
             full
             weekend of a month, the n-th Saturday of a month, the n-th weekday of every month,
             or asked (not computable). A full weekend is a Saturday whose Sunday is in the same
             month;
             its day is the Saturday. An end stated as "through hh59" is the next minute,
             exclusive. The current or next occurrence is the earliest of all rounds that has
             not ended at
             that instant. A round may name its one band (FT8 Activity). None when every round
             is asked. Times are UTC. */
    }
    attribute def ProfileTable {
        doc /* The entries, in selector order, id: name; activity; rules; clause.
             ww_digi: WW Digi; ww_digi; HF six bands, band, one_plus_per_3000_km,
             field_per_band; forbidden (IX.12). Last full weekend of August (unconfirmed: the
             rules state only the
             dates), Saturday 12:00 to Sunday 12:00.
             arrl_digi: ARRL Digi; arrl_digi; HF six bands and 6 m, band,
             one_plus_per_500_km_up, none; forbidden (OPRG.4). First full weekend of June,
             Saturday 18:00 to Monday 00:00.
             arrl_field_day: ARRL Field Day; field_day; HF six bands and all from 50 MHz,
             band_mode_class, field_day, none; forbidden (6.4). Fourth full weekend of June,
             Saturday
             18:00 to Sunday 21:00.
             arrl_vhf_jan: ARRL January VHF; na_vhf; all from 50 MHz, band_grid, vhf_january,
             grid_per_band; forbidden (OPRG.4: contemporaneous direct initiation). Asked.
             arrl_vhf_jun: ARRL June VHF, arrl_vhf_sep: ARRL September VHF; na_vhf; alike with
             vhf_june_september. Second full weekend of June and of September, Saturday 18:00 to
             Monday 03:00.
             iaru_50_mgm: IARU R1 50 MHz MGM (6 m), iaru_70_mgm: IARU R1 70 MHz MGM (4 m);
             activity none; band, kilometres, grid_per_band; silent. Third Saturday of April and
             of May,
             Saturday 14:00 to Sunday 14:00.
             ft8_activity: FT8 Activity; activity none; 2 m, 70 cm, 23 cm, call, one_per_call,
             grid_per_band; silent. Each month first Wednesday 2 m, second 70 cm, third 23 cm,
             17:00
             to 21:00.
             A rule source that does not state something is stated in the entry as unconfirmed.
             The executable table and its hand oracle: server/src/contest.rs, TC-063-001. */
    }
}
