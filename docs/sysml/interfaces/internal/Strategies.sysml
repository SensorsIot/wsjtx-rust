package WstxStrategies {
    private import ScalarValues::*;
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
             (WstxRankingControl::Alert follows the active strategy of class strategy). */
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
}
