package WstxContestRanking {
    private import ScalarValues::*;
    private import WstxRankingControl::ContestVerdict;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-024';
    private import WstxRequirements::ImplementationState;
    private import WstxContact::'TC-063-004';
    private import WstxContact::'TC-063-006';
    private import WstxContact::'TC-063-007';
    private import WstxContact::'TC-063-008';

    attribute def ContestValueOrder {
        doc /* Smaller first: callers of my call before the others when the contest strategy's
             Calling stations are answered (callers_first) is on (only callers with a rank, never a
             dupe, and passing the strategy's country and US state lists); with it off a caller
             has no rank (WstxValueOrder::CallerOfMyCall); then a new multiplier; then more QSO points (unknown 0);
             then the strongest SNR (unknown last); then, for an exact tie only, the lower audio
             frequency, then the call (strategydef Q3, Q9: decode order is never a ranking).
             Replaces WSJT-X's first decoded (operator #63). */
    }
    attribute def ContestDirective {
        doc /* WstxValueOrder::DirectedCqRule in a contest activity: the word of the station's
             current activity (na_vhf, eu_vhf and arrl_digi TEST, ww_digi WW, field_day FD, rtty RU) is
             answerable, also with my continent unknown. So it is not greyed, a selection needs no
             directive_confirmed, and a word outside its activity keeps the warning. It depends on
             the activity alone, not on a selected contest strategy (D2). */
    }

    dependency directiveClause from ContestDirective to WstxContestRanking::'CL-063-02';
    dependency directiveOwner from ContestDirective to WstxValueOrder::DirectedCqRule;
    dependency verdictClause from ContestVerdict to WstxContestRanking::'CL-063-04';
    dependency orderClause from ContestValueOrder to WstxContestRanking::'CL-063-04';

    requirement 'CL-063-02' {
        doc /* In a contest activity a CQ with the activity's own word (na_vhf, eu_vhf (#99) and arrl_digi CQ TEST, ww_digi CQ WW, field_day CQ FD, rtty CQ RU) is answerable: it is no longer greyed and an operator's selection needs no confirmation. Outside the matching activity it stays not answerable, with the warning of CL-039-03. Details: WstxContestRanking::ContestDirective, WstxValueOrder::DirectedCqRule. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/contact.rs";
    }
    requirement 'CL-063-04' {
        doc /* With a contest in force Band Activity lists only the stations that can be called (non-dupe in the period, directive allows it, a CQ or an RR73/73, on a band of the contest), ordered by callers of my call, new multiplier, QSO points, SNR, with the partner on top; a Show all toggle (off) shows the rest. Colour only for the callable, a new multiplier apart; a dupe and a directed CQ dimmed. The station evaluates, the browser renders after a publication, never on a timer. A contest also works by hand: every row stays selectable with Show all. Details: WstxRankingControl::ContestVerdict, ContestValueOrder, ContestView. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/contest.rs; server/src/strategy.rs; client/contact.js; client/recording.css";
    }
    dependency CL_063_02_to_FR_024 from 'CL-063-02' to 'FR-024';
    dependency CL_063_02_to_FR_007 from 'CL-063-02' to 'FR-007';
    dependency CL_063_02_verified_by_TC_063_004 from 'CL-063-02' to 'TC-063-004';
    dependency CL_063_04_to_FR_024 from 'CL-063-04' to 'FR-024';
    dependency CL_063_04_to_FR_010 from 'CL-063-04' to 'FR-010';
    dependency CL_063_04_verified_by_TC_063_006 from 'CL-063-04' to 'TC-063-006';
    dependency CL_063_04_verified_by_TC_063_007 from 'CL-063-04' to 'TC-063-007';
    dependency CL_063_04_verified_by_TC_063_008 from 'CL-063-04' to 'TC-063-008';
}
