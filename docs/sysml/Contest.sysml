package WstxContest {
    private import ScalarValues::*;
    doc /* Canonical contract of the contest strategies (issue #63, CL-063-01 and CL-063-02 in
         WstxRequirements; verification TC-063-001..004): the second strategy class beside
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
            Cabrillo name stays marked. */

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
             the browser reads it at (re)connect and when the period prompt opens, never on a
             timer. */
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
}
