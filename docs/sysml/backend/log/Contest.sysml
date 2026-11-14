package WstxContest {
    private import ScalarValues::*;
    private import WstxStrategies::ContestProfile;
    private import WstxStrategies::ContestHttp;
    private import WstxStrategies::ContestSelection;
    private import WstxStrategies::ContestPrompt;
    private import WstxRankingControl::ContestVerdict;
    private import WstxAutoControl::ContestRun;
    private import WstxStrategies::ProfileTable;
    private import WstxStrategies::ScheduleRule;
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

    dependency profileClause from ContestProfile to WstxContact::'CL-063-01';
    dependency scheduleClause from ScheduleRule to WstxContact::'CL-063-01';
    dependency tableClause from ProfileTable to WstxContact::'CL-063-01';
    dependency httpClause from ContestHttp to WstxContact::'CL-063-01';
    dependency selectionClause from ContestSelection to WstxContact::'CL-063-03';
    dependency promptClause from ContestPrompt to WstxContact::'CL-063-03';
    dependency logClause from ContestLog to WstxContact::'CL-063-03';
    dependency runClause from ContestRun to WstxContact::'CL-063-05';
    dependency runSafety from ContestRun to WstxContact::'CL-063-06';
    dependency runPath from ContestRun to WstxAutoControl::StrategyRun;
    dependency contestStrategySelection from ContestSelection to WstxContact::'CL-097-07';
    dependency contestStrategyPrompt from ContestPrompt to WstxContact::'CL-097-07';
    dependency contestStrategyRun from ContestRun to WstxContact::'CL-097-07';
}
