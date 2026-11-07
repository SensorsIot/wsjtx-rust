package WstxContest {
    private import ScalarValues::*;
    doc /* Canonical contract of the contest strategies (issue #63, CL-063-01..06 in
         WstxRequirements; verification TC-063-001..012): the second strategy class beside
         WstxStrategy's award strategies. Nothing here is an execution result.

         Decisions (operator on #63 and #39, 2026-11-04 and 2026-11-06, newest wins):
         D1 One profile per contest from the official rules; S&P and Run; contest strategies do
            call CQ. Two levels: fully automatic and colouring only; colouring only is the
            default and is always available in contest mode. A contest can be operated by hand.
         D2 Choosing an activity never sets a strategy.
         D3 Automation clause: warn and confirm where the rules forbid it, a short note where they
            are silent (never a block).
         D4 RTTY Roundup is dropped (FT8 and FT4 no longer qualify). Usable everywhere in the
            world: a limit that depends on the location or the entry is a note (DX may only work
            W/VE; check-log only). National contests come later as data.
         D5 January VHF is not computed, the period prompt asks; IARU MGM uses standard FT8
            messages with report and 4-character locator; operating-time limits are notes, not
            tracked; a full weekend has Saturday and Sunday both in the month; an unconfirmed
            Cabrillo name stays marked.
         D6 Contest strategies are not saved strategies: the profiles are data, and the choice with
            its period is the selection (ContestSelection), never written to the file. The award
            strategy class on the wire stays award (WstxStrategy::StrategyClass): a saved strategy
            of class contest stays refused.
         D7 The activity stays the operator's (D2 both ways): selecting a contest does not set
            it; the prompt says when it differs. Implementer's default on #63.
         D8 Band Activity lists only what can be called, by value, with a Show all toggle (off),
            and colours only what is interesting: the callable stations and most the new
            multipliers; a dupe or a directed CQ shown by Show all is dimmed, uncoloured.
         D9 Fully automatic stays with the station: the safety of WstxStrategy::StrategyRun
            applies unchanged (HALT, Esc, Tx watchdog, 60 s without a client, 8 hours). Implementer's
            defaults on #63: HALT leaves the contest in force as colouring only; S&P and Run are
            the two automatic operations, chosen at the prompt, not both at once (no band or
            frequency hopping); the Tx watchdog stops a Run on an unanswered CQ like any message.
         D10 Strategydef (#39, operator grill 2026-11-07, WstxStrategy D15): colouring only is
            Auto off (WstxStrategy::AutoToggle, one toggle for strategies and contests); the
            contest keeps its own value (ContestValueOrder); x and the quiet time are set per
            contest, defaults 2 and 10 minutes, more aggressive than strategies; in situation 1
            the run stays while the target hears us and is still the most valuable
            (WstxStrategy::LeaveRule). HALT turns Auto off and leaves the contest selected. */

    enum def DupeRule {
        doc /* band: once per band. band_mode_class: once per band and per Phone, CW or Digital.
             band_grid: once per band from any specific grid. call: one QSO per call in the period. */
        enum band;
        enum band_mode_class;
        enum band_grid;
        enum call;
    }
    enum def PointsRule {
        doc /* one_plus_per_3000_km; one_plus_per_500_km_up; field_day (Phone 1, CW 2, Digital 2);
             vhf_january (50 and 144 MHz 1, 222 and 432 MHz 2, 902 and 1296 MHz 4, 2.3 GHz and up 8);
             vhf_june_september (1, 2, 3, 4); kilometres (one per km truncated plus 1 between large
             square centres at 111.2 km per degree, the same large square 50); one_per_call. */
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
        doc /* A profile has one or more rounds, each a day rule and a start and an exclusive end in
             minutes from 00:00 UTC of that day: the n-th full weekend of a month, the last full
             weekend of a month, the n-th Saturday of a month, the n-th weekday of every month, or
             asked (not computable). A full weekend is a Saturday whose Sunday is in the same month;
             its day is the Saturday. An end stated as "through hh59" is the next minute, exclusive.
             The current or next occurrence is the earliest of all rounds that has not ended at
             that instant. A round may name its one band (FT8 Activity). None when every round is
             asked. Times are UTC. */
    }
    attribute def ContestProfile {
        doc /* Rule facts only, one data entry per contest, no behaviour of its own; wire keys of
             GET /strategy/contests exactly: id, name, cabrillo (null: no Cabrillo log),
             cabrillo_confirmed, activity (WstxContact::SpecialActivity name), bands (ADIF band
             names), modes, exchange, dupes (DupeRule), points (PointsRule), multipliers
             (MultiplierRule), score, automation (AutomationClause), automation_text (the clause
             as the rules word it, or that they do not address it), schedule (the rule in words),
             notes (location and entry limits, operating-time limits), source (the URL) and period
             (null when asked, else {start, end, band}: ScheduleRule at the time of the request,
             "YYYY-MM-DDTHH:MMZ", end exclusive, band null unless the round names one). */
    }
    attribute def ProfileTable {
        doc /* The entries, in selector order, id: name; activity; rules; clause.
             ww_digi: WW Digi; ww_digi; HF six bands, band, one_plus_per_3000_km, field_per_band;
             forbidden (IX.12). Last full weekend of August (unconfirmed: the rules state only the
             dates), Saturday 12:00 to Sunday 12:00.
             arrl_digi: ARRL Digi; arrl_digi; HF six bands and 6 m, band, one_plus_per_500_km_up,
             none; forbidden (OPRG.4). First full weekend of June, Saturday 18:00 to Monday 00:00.
             arrl_field_day: ARRL Field Day; field_day; HF six bands and all from 50 MHz,
             band_mode_class, field_day, none; forbidden (6.4). Fourth full weekend of June, Saturday
             18:00 to Sunday 21:00.
             arrl_vhf_jan: ARRL January VHF; na_vhf; all from 50 MHz, band_grid, vhf_january,
             grid_per_band; forbidden (OPRG.4: contemporaneous direct initiation). Asked.
             arrl_vhf_jun: ARRL June VHF, arrl_vhf_sep: ARRL September VHF; na_vhf; alike with
             vhf_june_september. Second full weekend of June and of September, Saturday 18:00 to
             Monday 03:00.
             iaru_50_mgm: IARU R1 50 MHz MGM (6 m), iaru_70_mgm: IARU R1 70 MHz MGM (4 m); activity
             none; band, kilometres, grid_per_band; silent. Third Saturday of April and of May,
             Saturday 14:00 to Sunday 14:00.
             ft8_activity: FT8 Activity; activity none; 2 m, 70 cm, 23 cm, call, one_per_call,
             grid_per_band; silent. Each month first Wednesday 2 m, second 70 cm, third 23 cm, 17:00
             to 21:00.
             A rule source that does not state something is stated in the entry as unconfirmed.
             The executable table and its hand oracle: server/src/contest.rs, TC-063-001. */
    }
    attribute def ContestHttp {
        doc /* GET /strategy/contests (operating access, no query, empty body; the refusals of GET
             /strategy): {v 1, profile_id, boot_id, profiles: [ContestProfile]}. It changes nothing;
             the browser reads it when the period prompt opens, and once per connection while a
             contest is in force (for its name), never at a plain page load or reconnect (it is several
             kB on the 32 kbit/s link, TC-010-002) and never on a timer. */
    }
    attribute def ContestSelection {
        attribute periodDaysMax : Integer = 31;
        doc /* The optional key contest of WstxStrategy::StrategyConfiguration on PUT /strategy and in
             the GET /strategy snapshot, present only while one is selected: {profile (a profile
             id), start, end (real instants "YYYY-MM-DDTHH:MMZ", end exclusive, start < end, at most
             31 days apart), operation "sp" or "run", repetitions (x of WstxStrategy::LeaveRule,
             1..20, default 2) and quiet_minutes (WstxStrategy::QuietTime, 1..120, default 10)}.
             Exact keys; each refusal names its field (contest, contest.profile, contest.start,
             contest.end, contest.operation, contest.repetitions, contest.quiet_minutes), 400
             invalid_request like any other field; "colouring" and automation_confirmed are
             refused like any other value or extra key (colouring only is Auto off, and the
             confirmation goes with Auto on, WstxStrategy::AutoToggle). null or absent: no contest. Exactly one strategy
             is active or none: active and contest together are refused with field contest. It
             lives in station memory only: the file never holds it and a station restart starts
             without one (as active, WstxStrategy D2). A changed contest is a changed selection
             (WstxStrategy::StrategyRun: any run ends; with Auto on the new one starts, ContestRun).
             HALT turns Auto off and leaves the contest in force: it then transmits nothing. An MCP principal cannot select one (the PUT
             /strategy principal guard). No alert is recorded for a contest
             (WstxStrategy::Alert follows the active award strategy). */
    }
    attribute def ContestLog {
        doc /* The log read for a contest: the contacts whose QSO_DATE and TIME_ON start lies in [start,
             end) only, with a band of the profile and a mode the contest counts: WW Digi FT8 and FT4;
             ARRL Digi digital except RTTY; Field Day and ARRL VHF any mode; IARU MGM and FT8 Activity
             digital. Phone is SSB, USB, LSB, AM, FM, DIGITALVOICE; CW is CW; every other mode is
             digital. In time order; a QSO that is a dupe by the DupeRule counts nothing. Band and
             mode are the record's effective values, the grid its first four characters; a record without
             a band (logged without a confirmed CAT dial, WstxContact::DirectLog) counts for nothing. band_grid
             with no grid: a logged QSO without a grid dupes every grid of that call on the band, a
             decoded message without a grid is a dupe when the call is logged on that band. The
             tally: qsos, multipliers (distinct keys of the MultiplierRule), points (the PointsRule;
             no points where the rule needs a grid that is not known) and score: points x
             multipliers, or the points for a profile without a multiplier rule (Field Day's power
             multiplier and bonus points are not computed). Unreadable: no claim, nothing callable.
             A contest evaluation reads it on a blocking thread, about one read per publication;
             it scans the records without copying those outside the period. */
    }
    attribute def ContestVerdict {
        doc /* WstxStrategy::Verdict with a contest in force, one per decoded record with a resolved
             sender that is standard, or a Field Day exchange (type field_day) to a call, in this
             order of tests: ignored (IgnoreLists, as a strategy); greyed
             (DirectedCqRule); "my own message"; "band unknown"; "band not in the contest"; "log
             unreadable"; "dupe" (DupeRule for the station band, mode class Digital; rank null,
             dupe true, also when it calls my call: operator #63 "non-dupe", the one difference from
             WstxStrategy D5); a caller of my call (CallerOfMyCall, also a grid or Field Day
             exchange to it); else the callsign guard (SaneCall; a /R rover passes where a new grid counts,
             band_grid); else "not a CQ": a CQ or an RR73/73 to someone else counts as calling, in
             every contest. So the callable records have a rank by ContestValueOrder; every other has
             rank null. The reply's verdicts carry dupe, new_multiplier (the record's key is not
             yet in the period, false without a grid) and points (PointsRule; null when not known).
             POST /strategy/evaluate with strategy null and a contest in force returns these, with
             strategy the profile's name and contest the tally {qsos, multipliers, points, score}
             (null when the log is unreadable); explain false lists the ranked, the greyed and the
             dupes. A draft strategy still previews the draft. why: "calls my call", "new
             multiplier", "<n> points" joined by " \· ", or the reason above. */
    }
    attribute def ContestValueOrder {
        doc /* Smaller first: callers of my call before the others (WstxStrategy D5; only callers
             with a rank, never a dupe); then a new multiplier; then more QSO points (unknown 0);
             then the strongest SNR (unknown last); then, for an exact tie only, the lower audio
             frequency, then the call (strategydef Q3, Q9: decode order is never a ranking).
             Replaces WSJT-X's first decoded (operator #63). */
    }
    attribute def ContestPrompt {
        doc /* The Contest button of the strategy element opens a modal dialog with its own HALT (the
             top-bar HALT's action, as WstxStrategy::StrategyEditor); receive keeps running. It reads
             GET /strategy/contests once at opening, so the pre-fill is current. It offers the
             profiles; Start and End (UTC, to the minute): the selection in force when it matches, else
             the profile's period, empty when asked; the schedule in words; the operation S&P or
             Run (S&P the default); "Repetitions before leaving" (default 2) and "Quiet time
             (minutes)" (default 10); the automation text and the notes. Whether it transmits is
             the Auto toggle's (WstxStrategy::AutoToggle): a forbidden clause asks its
             confirmation when Auto is switched on, not at Start. When the profile's
             activity differs from the station's, one line says so. Start with an empty period
             asks for it and sends nothing; else one PUT /strategy with active null and contest. Cancel
             changes nothing. In the selector the contest in force is one more option "<name>
             (contest)"; None or an award strategy sends a PUT without contest (the selector's other
             rule, WstxStrategy::StrategySelector, is unchanged). */
    }
    attribute def ContestView {
        doc /* With a contest in force the browser renders the verdicts as WstxStrategy::ValueView
             does, on the same events (a new publication, a save; never a timer). Band Activity lists
             only the rows with a rank, in rank order under the value sort; rows to my call and the
             partner rows stay (#50); every other row is hidden. Show all (a toggle in the strategy
             element, visible only with a contest, off at each page load, kept in the page only)
             shows them all again without a new request: a dupe and a greyed row dimmed, no colour; a
             row with a new multiplier has its own colour beside the strategy mark
             (WstxOperatingLayout::BandActivityColours: only interesting stations). The colour slots of the
             all-time log (new call, DXCC, zone, grid and LotW) are off while a contest is in force,
             their reasons leave the hover too, and they come back with its end: QSOs outside the
             period do not count (the My call slot stays; the Settings choice is unchanged). The hover names "#n",
             new multiplier and points, or the dupe. The status beside it: "Contest <name> \· <MM-DD
             HH:MM> to <MM-DD HH:MM> UTC \· <S&P or Run> \· Auto <on or off>" (Auto off is colouring only) and, once evaluated, " \· <n> QSOs \· <m>
             mult \· score <s>". Manual operation stays as it is: every row selects as ever, the
             double-click and the directive warning unchanged. */
    }
    attribute def ContestRun {
        attribute repetitionsDefault : Integer = 2;
        attribute quietMinutesDefault : Integer = 10;
        doc /* A contest with Auto on is a WstxStrategy::StrategyRun: one run at a time, through
             the same internal path and the same contact engine, started only by a browser's
             selection with Auto on or Auto on (WstxStrategy::AutoToggle). Unchanged: HALT stops
             every run from any source and turns Auto off (revision + 1, pushed by
             strategy.state; the contest, its operation and period stay); Esc
             changes neither; ManualIntervention (a double-click always, the run resumes after the
             QSO); WatchdogFromOperator; the 8 hour run limit (run_limit) and 60 s without a client
             (no_client), finishing the QSO first, with the contest staying selected, Auto off
             and the reason shown; the grant (authority_lost); WstxStrategy::FreeTxSlot; an
             AutomationCommand start of what it left is refused operator_required. A contact ends
             at once at the end of the period (the run waits outside_period) and when the
             contest is deselected (WstxStrategy::StrategyRun "Ends at once").
             Waiting reasons in a contest (run.reason while state waiting), besides no_receive,
             auto_seq and call: activity (the station's activity is not the profile's), band (the
             station band is not in the profile), outside_period (the station clock is outside
             [start, end)). It selects nothing and calls nothing until the reason is gone.
             sp: on each fresh complete publication the list is ContestVerdict with a rank, one per
             call, not completed in this run on this band and mode nor given up; the first is selected
             as a strategy run selects, not in its QuietTime. Leaving: WstxStrategy::LeaveRule with
             the contest's repetitions and quiet_minutes; no skip (WstxStrategy D6).
             run: while waiting and no reason it decides the slot (FreeTxSlot, no called station) and
             sends enable_tx with no partner, which calls CQ with the activity's Tx6; state
             calling_cq. WstxContact::CallFirst does not answer a CQ started by automation. On each
             fresh complete publication of the partner's parity the callers of my call
             (ContestVerdict kind caller: a dupe has no rank; in ContestValueOrder; not worked in this
             run on this band and mode, not given up, not in QuietTime) are read; the first is selected with
             select_row {replace false}, which keeps Enable Tx, and Tx stays on its slot
             (WstxStrategy::FreeTxSlot with that station). No caller: the CQ goes on. In the contact
             as sp; after completion or a leaving it waits, so the next step calls CQ again.
             In calling_cq: a reason appearing disarms and cancels the CQ and it waits; run_limit
             or no_client disarm and cancel the CQ at once and stop (there is no exchange to
             end); an operator's selection or cancel makes it manual; a disarm stops it with
             the cause (tx_watchdog, transmit_stopped): the Tx watchdog counts a repeated CQ like
             any message, so a Run on a silent band stops at its limit until a new selection (the
             step that sees the disarm stops it tx_watchdog, and an automatic enable_tx after a
             watchdog stop is refused besides, WatchdogFromOperator). Every stop
             and a selection cancel a CQ of the run: none is left to read as the operator's contact.
             Esc on the run's own CQ ends that CQ; the run calls again. A dupe caller has no
             rank: it is never answered and never ends a stay (the #63 fix: the stay check read
             the award evaluator, which counts any caller); every check of a contest run reads
             ContestVerdict.
             The log: ContestLog of the last build on the station step, built at the selection
             first; each step of the run asks for it, so a build behind the log runs on its own
             thread as soon as a QSO is logged, also a manual one, well before the next
             publication; until it is done a QSO is held off by this run's own completed list. Band Activity follows ContestView; the status
             names "calling CQ", "<call>", "your QSO", "waiting · <reason>", "stopped · <reason>"
             or "not started · <reason>" from GET /automation on automation.state only, never a
             timer. The prompt offers S&P and Run; AutomationClause forbidden asks
             WstxOperatingLayout's confirmation with the clause's text when Auto is switched on
             and sends automation_confirmed true with POST /strategy/auto, nothing when
             declined; silent asks nothing, the clause is on the prompt. After a stop only Auto
             on starts it again. No band hopping. */
    }
    attribute def ContestDirective {
        doc /* WstxStrategy::DirectedCqRule in a contest activity: the word of the station's
             current activity (na_vhf and arrl_digi TEST, ww_digi WW, field_day FD, rtty RU) is
             answerable, also with my continent unknown. So it is not greyed, a selection needs no
             directive_confirmed, and a word outside its activity keeps the warning. It depends on
             the activity alone, not on a selected contest strategy (D2). */
    }

    dependency profileClause from ContestProfile to WstxRequirements::'CL-063-01';
    dependency scheduleClause from ScheduleRule to WstxRequirements::'CL-063-01';
    dependency tableClause from ProfileTable to WstxRequirements::'CL-063-01';
    dependency httpClause from ContestHttp to WstxRequirements::'CL-063-01';
    dependency directiveClause from ContestDirective to WstxRequirements::'CL-063-02';
    dependency directiveOwner from ContestDirective to WstxStrategy::DirectedCqRule;
    dependency selectionClause from ContestSelection to WstxRequirements::'CL-063-03';
    dependency promptClause from ContestPrompt to WstxRequirements::'CL-063-03';
    dependency logClause from ContestLog to WstxRequirements::'CL-063-03';
    dependency verdictClause from ContestVerdict to WstxRequirements::'CL-063-04';
    dependency orderClause from ContestValueOrder to WstxRequirements::'CL-063-04';
    dependency viewClause from ContestView to WstxRequirements::'CL-063-04';
    dependency runClause from ContestRun to WstxRequirements::'CL-063-05';
    dependency runSafety from ContestRun to WstxRequirements::'CL-063-06';
    dependency runPath from ContestRun to WstxStrategy::StrategyRun;
}
