package WstxAlert {
    private import ScalarValues::*;
    private import WstxRequirements::'FR-026';
    private import WstxRequirements::ImplementationState;
    private import ModelBindings::ImplementedIn;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import RequirementDerivation::*;

    attribute def AlertRule {
        doc /* Without a setting. Each record of the current live job is judged once (a job not
             seen before from its first retained record), also while no strategy is active, so a
             later selection never alerts on older decodes. With an active strategy, each new
             record that is a Candidate of it (Verdict, its window and list) records an alert; a
             caller of my call, an ignored sender and a CQ greyed by DirectedCqRule never alert.
             Dedupe: no alert when the station recorded one for the same call and the same
             station band (station_band at that time; unknown counts as its own band) whose
             period start lies less than 10 minutes before this record's period start (exactly
             10 minutes later alerts again); this memory is kept apart from the history, so
             Clear does not reset it. An alert never transmits, never selects, arms or changes a
             contact, the automation run, the Tx watchdog or the strategy store. */
    }

    attribute alertRule : AlertRule;

    satisfy 'CL-042-04' by alertRule;

    requirement 'CL-042-04' {
        subject ranking : RankingService;
        doc /* Alert has no setting: for each new candidate of the active strategy (an ignored
             sender, a directed CQ not for me and a caller of my call never alert), the station
             records an alert (time, call, message, strategy name, band, mode, SNR, DXCC entity)
             in a history of the last 100 alerts in station memory (kept across page reloads,
             empty after a station restart), at most one per call and band in 10 minutes, and
             announces it to the browser. An alert never transmits or changes a contact or
             automation run. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; server/src/mcp.rs; client/contact.js";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-042-04';
    }
}
