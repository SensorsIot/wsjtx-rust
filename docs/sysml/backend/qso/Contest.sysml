package WstxContest {
    private import ScalarValues::*;
    private import WstxStrategies::ContestProfile;
    private import WstxStrategies::ContestHttp;
    private import WstxStrategies::ContestSelection;
    private import WstxStrategies::ContestPrompt;
    private import WstxOperatingChain::ContestVerdict;
    private import WstxAutoControl::ContestRun;
    doc /* Canonical contract of the contest strategies (issue #63, CL-063-01..06 in
         WstxRequirements; verification TC-063-001..012): the second strategy class beside
         WstxStrategy's strategies of class strategy. Nothing here is an execution result.

         Decisions (operator on #63 and #39, 2026-11-04 and 2026-11-06, newest wins):
         D1 One profile per contest from the official rules. A contest ranks Band Activity by
            its rules (ContestVerdict, ContestValueOrder); a CQ when nothing callable is listed
            follows the contest strategy's cq_when_idle and CQ wait
            (WstxStrategy::CqWhenNoTarget). Two levels: fully automatic (Auto on) and colouring
            only; colouring only is the default and is always available in contest mode. A
            contest can be operated by hand.
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
         D7 The activity stays the operator's (D2 both ways): selecting a contest does not set
            it; the prompt says when it differs. Implementer's default on #63.
         D8 Band Activity lists only what can be called, by value, with a Show all toggle (off),
            and colours only what is interesting: the callable stations and most the new
            multipliers; a dupe or a directed CQ shown by Show all is dimmed, uncoloured.
         D9 Fully automatic stays with the station: the safety of WstxAutoControl::StrategyRun
            applies unchanged (HALT, Esc, Tx watchdog, 60 s without a client, 8 hours). Implementer's
            defaults on #63: HALT leaves the contest in force as colouring only.
         D10 Strategydef (#39, operator grill 2026-11-07, WstxStrategy D15): colouring only is
            Auto off (WstxAutoControl::AutoToggle, one toggle for strategies and contests); the
            contest keeps its own value (ContestValueOrder). HALT turns Auto off and leaves the
            contest selected.
         D11 Contest strategies (WstxStrategy D19; operator 2026-11-09, Q1 "One per contest"): a
            contest strategy is a strategy of class contest whose Filters and Order come from its
            contest (this package's rules) and whose other settings are its own (WstxStrategy
            D19). Each contest of the table has one read-only contest built-in
            (WstxStrategies::BuiltinStrategies, the contest defaults: leave contest style after 2 Tx
            changes, Tx every 2nd call when he does not hear us or does not report, busy pause
            off, CQ when idle on with the CQ wait 2); the operator duplicates it to a saved
            contest strategy ("ARRL Digi fast"). Contest strategies may be saved; the profiles
            stay data and the period stays the selection (ContestSelection). There is no
            operation choice and no per-contest repetitions or retry pause. */

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
    attribute def ContestLog {
        doc /* The log read for a contest: the contacts whose QSO_DATE and TIME_ON start lies in [start,
             end) only, with a band of the profile and a mode the contest counts: WW Digi FT8 and FT4;
             ARRL Digi digital except RTTY; Field Day and ARRL VHF any mode; IARU MGM and FT8 Activity
             digital. Phone is SSB, USB, LSB, AM, FM, DIGITALVOICE; CW is CW; every other mode is
             digital. In time order; a QSO that is a dupe by the DupeRule counts nothing. Band and
             mode are the record's effective values, the grid its first four characters; a record without
             a band (logged without a confirmed CAT dial, WstxLogbook::DirectLog) counts for nothing. band_grid
             with no grid: a logged QSO without a grid dupes every grid of that call on the band, a
             decoded message without a grid is a dupe when the call is logged on that band. The
             tally: qsos, multipliers (distinct keys of the MultiplierRule), points (the PointsRule;
             no points where the rule needs a grid that is not known) and score: points x
             multipliers, or the points for a profile without a multiplier rule (Field Day's power
             multiplier and bonus points are not computed). Unreadable: no claim, nothing callable.
             A contest evaluation reads it on a blocking thread, about one read per publication;
             it scans the records without copying those outside the period. */
    }
    attribute def ContestValueOrder {
        doc /* Smaller first: callers of my call before the others when the contest strategy's
             Calling stations are answered (callers_first) is on (only callers with a rank, never a
             dupe, and passing the strategy's country and US state lists); with it off a caller
             has no rank (WstxStrategy::CallerOfMyCall); then a new multiplier; then more QSO points (unknown 0);
             then the strongest SNR (unknown last); then, for an exact tie only, the lower audio
             frequency, then the call (strategydef Q3, Q9: decode order is never a ranking).
             Replaces WSJT-X's first decoded (operator #63). */
    }
    attribute def ContestDirective {
        doc /* WstxStrategy::DirectedCqRule in a contest activity: the word of the station's
             current activity (na_vhf, eu_vhf and arrl_digi TEST, ww_digi WW, field_day FD, rtty RU) is
             answerable, also with my continent unknown. So it is not greyed, a selection needs no
             directive_confirmed, and a word outside its activity keeps the warning. It depends on
             the activity alone, not on a selected contest strategy (D2). */
    }

    dependency profileClause from ContestProfile to WstxContact::'CL-063-01';
    dependency scheduleClause from ScheduleRule to WstxContact::'CL-063-01';
    dependency tableClause from ProfileTable to WstxContact::'CL-063-01';
    dependency httpClause from ContestHttp to WstxContact::'CL-063-01';
    dependency directiveClause from ContestDirective to WstxContact::'CL-063-02';
    dependency directiveOwner from ContestDirective to WstxStrategy::DirectedCqRule;
    dependency selectionClause from ContestSelection to WstxContact::'CL-063-03';
    dependency promptClause from ContestPrompt to WstxContact::'CL-063-03';
    dependency logClause from ContestLog to WstxContact::'CL-063-03';
    dependency verdictClause from ContestVerdict to WstxContact::'CL-063-04';
    dependency orderClause from ContestValueOrder to WstxContact::'CL-063-04';
    dependency runClause from ContestRun to WstxContact::'CL-063-05';
    dependency runSafety from ContestRun to WstxContact::'CL-063-06';
    dependency runPath from ContestRun to WstxAutoControl::StrategyRun;
    dependency contestStrategySelection from ContestSelection to WstxContact::'CL-097-07';
    dependency contestStrategyPrompt from ContestPrompt to WstxContact::'CL-097-07';
    dependency contestStrategyRun from ContestRun to WstxContact::'CL-097-07';
}
