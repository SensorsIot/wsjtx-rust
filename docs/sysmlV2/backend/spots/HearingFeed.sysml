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

    // ---- Who hears the station ----------------------------------------------------------

    requirement 'CL-039-20' {
        subject spots : SpotsService;
        doc /* Spots MUST tell ranking which stations hear the profile's call and auto what
             the station being called hears and decodes, from the spots of the PSK
             Reporter feed, and say unknown where the feed cannot tell (HearingFeed). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-012'; end #derive ::> 'CL-039-20'; }

    attribute def HearingFeed {
        doc /* How the HeardByReport and the TargetReport are made from the Spots of the
             feed.
             The target is the station called by the own contact of a strategy run or a
             contest run, while that contact is active. Every other time there is none.
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

    // ---- The operator's switches and the state of the feed ------------------------------

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

    // ---- Test cases ---------------------------------------------------------------------

    verification 'TC-039-020' {
        doc /* The hearing report from spots written by hand.
             Setup: payloads written by hand in the form of the feed, given to spots
             directly or through a peer on the loopback address; explicit times; no
             network.
             (a) The payload f 7075512, md FT8, rp -5, t 1000, t_tx 990, sc HB9BLA,
             rc K1ABC, b 40m: a Spot from HB9BLA at K1ABC, FT8, 40m, 7075512 Hz, time
             990, SNR -5. Without t_tx: time 1000. An empty payload, one that is no
             object, one without md, a negative f, an empty sc and an sc of 17
             characters: no Spot.
             (b) A Spot of HB9BLA at K1ABC at time 1000 on 40m FT8: K1ABC hears at 1000
             and at 1600 and not at 1601; not on 20m, not on FT4; W1AW does not hear.
             (c) A Spot that is 601 s old on arrival does not count. A Spot whose time
             lies ahead counts from its arrival at 1000 and not at 1601.
             (d) A Spot of DL1XYZ at the target K1ABC: K1ABC does not hear, and it
             reports at 1600 and not at 1601.
             (e) Dial 7074000 Hz, Spots at the target from another sender at 7075200,
             7074800 and again 7075200 Hz at the times 1000, 1001 and 1002, range 300 to
             2650 Hz: the offsets 1200 and 800 in this order; at 1602 only 1200. Spots
             at 7074100, 7077500 and 7073000 Hz, on 20m, on FT4, received by W1AW and
             sent by the profile's call give no offset. After a change of target: none.
             (f) 178 Spots at the target at different frequencies: 32 offsets, the
             newest first. Three Spots of the profile's call at one station: the newest
             time is kept.
             (g) Over a session, on the topic of HB9BLA at W1AW with the target W1AW:
             a text that is no payload and a Spot of DL1XYZ at F5AAA are dropped; a Spot
             of HB9BLA at W1AW makes W1AW hear; a Spot of DL1XYZ at W1AW at 7075512 Hz
             gives the offset 1512 at the dial 7074000 Hz; the time of the last Spot is
             present. Switched off: W1AW does not hear and there is no offset.
             (h) A configuration that was never set: enabled on, and the state off
             where no connection is allowed.
             (i) Planned, no test yet: a report is given at once while the feed waits on
             the network. */
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
        doc /* The reported SNR, the parity of what the target decodes, the second
             switch and the state of the target's hearing.
             Setup: as the hearing report from spots written by hand; for (d) a peer on
             the loopback address that answers as a broker; for (e) the station on a
             throw-away profile.
             (a) rp -5, -99 and 99: kept. rp absent, 100, -100, "x", 2.5 and null:
             no SNR, and the Spot counts. A Spot at time 1000 with -12 and then one at
             time 990 with 3: the report carries 1000 and -12.
             (b) Four senders at 14075200 Hz at the target, two in an odd and two in an
             even FT8 period, dial 14074000 Hz: the offset 1200 once for each parity,
             the newest first. One Spot of an odd period: 1200 for odd, nothing for
             even. With use off: nothing.
             (d) Target K1ABC before the connection: unknown. Connected and subscribed
             without a Spot: no. A Spot of HB9BLA at K1ABC on 20m, 60 s old, with -12:
             heard, with its time and -12; on 40m: no; W1AW, which is not the target:
             unknown. Target K1ABC/P: the subscription is removed and the state is
             unknown. Use off: the subscription is removed and the state is unknown.
             Use on: subscribed again and heard.
             (e) Without a feed, and with one and no band: unknown, and the offsets
             unknown. On 20m: heard, with the time and -12; without a target: unknown.
             Without a confirmed dial the offsets are unknown; with the dial 14074000
             Hz: 1200 for odd and an empty list for even. Use off: unknown, and the
             offsets unknown. Enabled off counts as use off. */
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
