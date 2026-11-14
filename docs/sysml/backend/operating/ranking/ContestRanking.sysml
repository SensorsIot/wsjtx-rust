package WstxContestRanking {
    private import ScalarValues::*;
    private import ModelNotes::DiffersFromSource;
    private import WstxRequirements::'FR-024';
    private import WstxRequirements::'FR-026';
    private import WstxRequirements::ImplementationState;
    private import ModelBindings::ImplementedIn;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import RequirementDerivation::*;

    attribute def ContestValueOrder {
        @DiffersFromSource {
            what = "WSJT-X takes the first decoded station of a contest; this order ranks the "
                + "callable stations instead.";
        }
        doc /* Smaller first: callers of my call before the others when the contest strategy's
             Calling stations are answered (callers_first) is on (only callers with a rank, never a
             dupe, and passing the strategy's country and US state lists); with it off a caller
             has no rank (WstxValueOrder::CallerOfMyCall); then a new multiplier; then more QSO
             points (unknown 0);
             then the strongest SNR (unknown last); then, for an exact tie only, the lower audio
             frequency, then the call (decode order is never a ranking). */
    }
    attribute def ContestDirective {
        doc /* WstxValueOrder::DirectedCqRule in a contest activity: the word of the station's
             current activity (ActivityWord) is answerable, also with my continent unknown. So it is
             not greyed. It depends on the activity alone, not on a selected contest strategy. */
    }

    attribute def ContestVerdictRule {
        doc /* Verdict with a contest in force, one per decoded record with a resolved sender
             that is standard, or a Field Day exchange (type field_day) to a call, in this order
             of tests: ignored (IgnoreLists, as a strategy); greyed (DirectedCqRule); "my own
             message"; "band unknown"; "band not in the contest"; "log unreadable"; "dupe"
             (DupeRule for the station band, mode class Digital; rank null, dupe true, also when
             it calls my call: "non-dupe", CallerOfMyCall); a caller of my call (CallerOfMyCall,
             also a grid or Field Day exchange to it); else the callsign guard (SaneCall; a /R
             rover passes where a new grid counts, band_grid); else "not a CQ": a CQ or an
             RR73/73 to someone else counts as calling, in every contest. So the callable
             records have a rank by ContestValueOrder; every other has rank null. The reply's
             verdicts carry dupe, new_multiplier (the record's key is not yet in the period,
             false without a grid) and points (PointsRule; null when not known). */
    }

    attribute contestValueOrder : ContestValueOrder;
    attribute contestDirective : ContestDirective;
    attribute contestVerdictRule : ContestVerdictRule;

    satisfy 'CL-063-02' by contestDirective;
    satisfy 'CL-063-04' by contestVerdictRule;
    satisfy 'CL-063-04' by contestValueOrder;

    requirement 'CL-063-02' {
        subject ranking : RankingService;
        doc /* In a contest activity a CQ with the activity's own word (na_vhf, eu_vhf and
             arrl_digi CQ TEST, ww_digi CQ WW, field_day CQ FD, rtty CQ RU) is answerable: it is
             no longer greyed. Outside the matching activity it stays not answerable. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/contact_http.rs; server/src/contact.rs";
        }
    }
    requirement 'CL-063-04' {
        subject ranking : RankingService;
        doc /* With a contest in force the stations that can be called (non-dupe in the period,
             directive allows it, a CQ or an RR73/73, on a band of the contest) are ordered by
             callers of my call, new multiplier, QSO points, SNR, with the partner on top. The
             station evaluates. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/contest.rs; server/src/strategy.rs; client/contact.js; client/recording.css";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-063-02';
    }
    #derivation connection {
        end #original ::> 'FR-024';
        end #derive ::> 'CL-063-02';
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-063-04';
    }
    #derivation connection {
        end #original ::> 'FR-024';
        end #derive ::> 'CL-063-04';
    }
}
