package WstxHearingFeed {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-012';
    private import WstxSpotsPart::SpotsService;
    private import WstxHearing::*;
    private import WstxPskReporter::Spot;
    private import WstxPskReporter::FeedError;
    private import WstxPskReporter::FeedSession;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-039-20' {
        subject spots : SpotsService;
        doc /* Spots MUST tell ranking which stations hear the profile's call, and auto, qso
             and the supervisor what the station of the contact in progress hears and
             decodes, from the spots of the PSK Reporter feed, and say unknown where the
             feed cannot tell (HearingFeed). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-039-20'; }

    attribute def HearingFeed {
        doc /* How the HeardByReport and the TargetReport are made from the Spots of the
             feed.
             The target is the station of the contact in progress, made by hand or by
             Auto (FeedContext::target), while that contact is active. Every other time
             there is none. The TargetReport goes to auto, to qso and to the supervisor,
             which shows it.
             A Spot is used when its sender is the profile's call or its receiver is the
             target. Every other Spot is dropped, whatever topic it came on.
             A Spot counts until it is heardWindowSeconds old, measured from the time its
             sender transmitted. A Spot whose time lies ahead of the station's time
             counts as sent on arrival.
             A station hears the profile's call while a Spot from that call received by
             it on the station's band and mode counts (HeardByReport::heardBy).
             The target is heard (HearingState) while such a Spot at the target counts;
             the report carries the time and the reported SNR of the newest one. It is
             no while the feed is connected, the target's call forms a filter
             (FeedSession) and no such Spot counts. It is unknown in every other case.
             The target reports (TargetHearing::reports) while a Spot received by it on
             the station's band and mode counts, from the profile's call or from any
             other sender.
             The frequencies the target decodes (DecodedOffsets) come from the Spots
             the target received from other senders on the station's band and mode
             that count. Each gives the offset of its frequency from the confirmed dial
             and the parity of the period in which its sender transmitted. Only an
             offset inside the range of transmit offsets of the mode is given.
             A Spot of another band or mode tells nothing about this one.
             When the target changes, the Spots the earlier target received are
             forgotten. When the profile's call changes or the feed is switched off,
             every Spot is forgotten.
             While the two switches (FeedSwitches) are not both on, the two reports
             tell nothing (HeardByReport::inUse, TargetReport::inUse). */
        attribute heardWindowSeconds : Integer = 600;
    }

    requirement 'CL-039-26' {
        subject spots : SpotsService;
        doc /* Spots MUST read the feed and let runs use it only as the two switches of
             its configuration say, and report the state of the feed (FeedSwitches,
             FeedStatus). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-039-26'; }

    attribute def FeedSwitches {
        doc /* What the two switches of SpotsConfig do.
             Spots takes them at station start and from every SpotsConfiguration, and
             follows a changed switch at once.
             While enabled is off, spots holds no session with the broker; FeedSession
             says when one begins. Switching enabled off ends the session and forgets
             every Spot and the time of the last one.
             While enabled and use are both on, the two reports tell what the feed
             says, and spots subscribes to the Spots of the target. With one of them
             off they tell nothing (HeardByReport::inUse, TargetReport::inUse) and the
             target is not subscribed. */
    }

    verification 'TC-039-020' {
        doc /* The hearing report from spots written by hand. */
        subject spots : SpotsService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-20'; verify 'CL-039-26'; }
        @TestedBy {
            test = "server/src/operating/qso/pskr_tests.rs::"
                + "parse_spot_reads_the_schema_and_refuses_the_rest; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "hears_us_expires_and_ignores_other_band_and_mode; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "reports_counts_up_to_600_s_and_no_longer; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "decoded_offsets_come_from_the_dial_of_this_band_and_mode; "
                + "server/src/operating/qso/pskr_tests.rs::the_model_is_bounded; "
                + "server/src/operating/qso/pskr_tests.rs::session_against_a_local_peer; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "the_setting_defaults_on_and_survives";
        }
    }

    verification 'TC-039-048' {
        doc /* The reported SNR, the parity of what the target decodes, the second switch and the
             state of the target's hearing. */
        subject spots : SpotsService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-20'; verify 'CL-039-26'; }
        @TestedBy {
            test = "server/src/operating/qso/pskr_tests.rs::"
                + "tc_039_048_rp_is_read_as_the_reported_snr; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "tc_039_048_decoded_offsets_are_kept_per_parity; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "tc_039_048_use_drives_the_target_subscription_and_the_hearing_state; "
                + "server/src/operating/qso/pskr_tests.rs::"
                + "tc_039_048_the_run_reads_the_target_on_the_station_band_honouring_use";
        }
    }
}
