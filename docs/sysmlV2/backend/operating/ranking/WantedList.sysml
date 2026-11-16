package WstxWantedList {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::Status;

    doc /* The wanted list: the calls and patterns the operator wants worked before
         every other station. The entries are ranking's data (WantedEntry); the
         settings function keeps them as one list of the operator's stations
         (WstxProfileAccess::SettingsCollection::wantedList); ranking ranks by them. */

    // ---- A wanted station ranks first -----------------------------------------------------

    requirement 'CL-124-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST rank first, in every ranking it makes, a station that an entry
             of the wanted list names and that has not been worked since the entry was
             added, whenever that station can be called (WantedRule). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-124-02'; }

    attribute def WantedRule {
        doc /* When a record is wanted, when it can be called, and where it stands.
             An entry names a call as an entry of the ignore list does
             (WstxIgnoreLists::IgnoreListsRule): a call, or a pattern with "*" and "?".
             A sender is wanted while an entry of RankingContext::wanted names its call
             and the logbook holds no QSO with that call whose start lies at or after
             the entry's addedUtcMs, on any band and in any mode. A QSO from before the
             entry was added does not count.
             A wanted sender can be called when its record is a CQ, an RR73, an RRR or a
             73 to another call than the profile's, or a message to the profile's call;
             whatever treat73AsCq, callersFirst, the lines of the strategy's filter and,
             under a contest, the contest's verdict say. It cannot be called while it is
             ignored, while the station is off the strategy's bands or the contest's,
             when its call fails the callsign guard of WstxValueOrder::Candidate, and
             for a CQ that WstxValueOrder::DirectedCqRule leaves to others.
             Such a record has a rank with VerdictKind::wanted, and the why "wanted" with
             the entry that names it, "wanted (<entry>)". The wanted records come first
             in the ranked list, ordered among themselves as the strategy orders its
             records (WstxValueOrder::ValueOrder, or under a contest
             WstxContestRanking::ContestValueOrder).
             A wanted entry ranks only while a strategy or a contest is selected. */
    }

    // ---- A worked entry leaves the list ---------------------------------------------------

    requirement 'CL-124-03' {
        subject ranking : RankingService;
        doc /* Ranking MUST report an exact entry of the wanted list once a QSO with its
             call has been logged after the entry was added (WantedRemoval). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-124-03'; }

    attribute def WantedRemoval {
        doc /* Which entries leave the wanted list by themselves.
             An entry without "*" and "?" leaves the list at the first QSO logged with
             its call after its addedUtcMs: ranking gives WantedWorked with the entry,
             and the station service removes it from the list. A pattern stays until the
             operator removes it; a station it names stops being wanted by WantedRule
             once a QSO with that station is logged after the pattern was added. */
    }
}
