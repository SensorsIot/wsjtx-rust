package WstxAlert {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import WstxDecodes::ResultRecord;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-042-04' {
        subject ranking : RankingService;
        doc /* Ranking MUST record one alert for each newly decoded station worth calling
             under an active strategy with an alert, once for a call and band within the dedupe
             time, and keep the latest alerts as a history (AlertRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-042-04'; }

    attribute def AlertRule {
        doc /* When an alert is recorded.
             Each ResultRecord of the station's current job is judged once, in the
             order of the records, also while no strategy is active: a record decoded
             before a strategy became active alerts no more. While no strategy is active,
             or the active one has no Strategy::alert, no alert is recorded.
             Under a strategy of class strategy a record alerts when its Verdict has
             the VerdictKind candidate or wanted. Under a strategy of class contest it
             alerts when its Verdict (WstxContestRanking::ContestVerdictRule) has the
             VerdictKind wanted, or the VerdictKind candidate with
             ContestVerdict::newMultiplier true. A caller, an ignored sender and a grey CQ do not
             alert.
             No alert is recorded when one was recorded for the same call on the same
             station band, an unknown band counting as a band of its own, whose
             record's period started less than RankingLimits::alertDedupeMinutes
             before the period of this record. A record without a period start counts
             with the time at which it is judged.
             An alert is one AlertEntry, with the strategy's sound, at the end of
             Alert::history; with RankingLimits::alertHistoryMax alerts kept, one more drops
             the oldest.
             ClearAlerts empties the history. It does not change which call alerted
             when on which band, and the ids go on.
             The history and that memory are held by ranking and are empty at station
             start. */
    }

    verification 'TC-042-006' {
        doc /* Alerts at the station. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-04'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_042_006_alert_records_one_alert_per_call_and_band_and_never_transmits";
        }
    }
}
