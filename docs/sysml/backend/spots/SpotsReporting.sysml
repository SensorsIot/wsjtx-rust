package WstxSpotsReporting {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-027';
    private import WstxSpotsPart::SpotsService;
    private import WstxHearing::SpotsConfig;
    private import WstxHearing::FeedContext;
    private import WstxDecodes::ResultRecord;
    private import WstxPskReporter::ReceptionReport;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::Status;
    private import WstxModelNotes::FollowsSource;

    requirement 'CL-039-28' {
        subject spots : SpotsService;
        doc /* Spots MUST report the stations the live receive job decodes to the PSK
             Reporter collector while reporting is on (ReceptionReports). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-027'; end #derive ::> 'CL-039-28'; }

    attribute def ReceptionReports {
        doc /* What spots reports, and when.
             Spots reports while SpotsConfig::report is on and FeedContext gives the
             profile's call and locator and a confirmed dial.
             A ResultRecord of the live receive job is reported when it is decoded, its
             message is a CQ or names the sender's grid, and its sender is not the
             profile's call. A played recording is no live job.
             The report of a record names the sender's call and grid as the message
             names them, the dial plus the record's audio offset, the mode, the SNR and
             the start of its period.
             A call that was reported is not reported again within repeatSeconds,
             except on a frequency above 49 MHz, where every such record is reported.
             The reports wait and are sent together every sendSeconds, in one
             ReceptionReport to SpotsConfig::reportCollector, which names the profile's
             call and locator and WSTX-Rust with its version. With more than pendingMax
             waiting, the oldest is given up.
             When reporting is switched off, or the station stops, what waits is sent
             once more. A changed collector takes the next sending. Nothing comes back
             from the collector, and a sending that fails is not repeated. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Network/PSKReporter.cpp "
                + "(MIN_SEND_INTERVAL, CACHE_TIMEOUT, MAX_PENDING_SPOTS) and "
                + "widgets/mainwindow.cpp pskPost";
        }
        attribute repeatSeconds : Integer = 300;
        attribute sendSeconds : Integer = 120;
        attribute pendingMax : Integer = 2048;
    }
}
