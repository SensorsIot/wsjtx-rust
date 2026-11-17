package WstxIgnoreLists {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-042-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST give no rank, in every ranking it makes, to a station whose
             call an entry of the ignore list matches, and hold that list for the session
             as the operator puts entries on it and takes them off (IgnoreListsRule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-042-02'; }

    attribute def IgnoreListsRule {
        doc /* The ignore list and what it does.
             An entry is a call or a pattern, of the form of IgnoreCommand::call. It
             matches a call when it matches the whole call: "*" stands for any run of
             characters, also for none, wherever and as often as it occurs; "?" stands
             for exactly one character; every other character stands for itself. An
             entry with "*" or "?" is a pattern.
             The list is held by ranking for the session: it is not stored, it is empty
             at station start, and it holds on every band. An IgnoreCommand puts its
             entry at the end; an entry that is listed is taken off first. With
             RankingLimits::ignoreListMax entries listed, an IgnoreCommand for an entry
             that is not among them is refused with RankingRefusal::ignoreListFull. An
             IgnoreCommand with ignore false takes its entry off; one that is not listed
             changes nothing. ClearIgnoreList takes every entry off. An entry stays on
             the list until one of these two commands takes it off; a change of the
             station's band leaves the list as it is.
             A sender that an entry matches is ignored in every ranking ranking makes,
             whatever strategy or contest it ranks by and whatever the filter and the
             order of that strategy say: its Verdict has no rank and is not grey, also
             when it calls the profile's call, and it stands among the verdicts without
             a rank. Without a rank it is not answered by Auto; a reply the operator
             starts by hand is not refused.
             Its why is "<call> is ignored (ignore list)", and for a pattern "<call> is
             ignored (ignore list: <entry>)". The entry that is the call itself is
             named before a pattern, and of several patterns the first in the order of
             their characters. */
    }

    verification 'TC-042-002' {
        doc /* The ignore list. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_042_002_ignored_senders_never_match; "
                + "server/src/strategy_tests.rs::"
                + "tc_042_002_session_list_expiry_renewal_capacity_and_band_change; "
                + "server/src/strategy_tests.rs::"
                + "tc_042_002_ignore_route_store_and_band_change";
        }
    }

    verification 'TC-125-001' {
        doc /* Patterns in the ignore list. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_125_001_entries_match_the_whole_call; "
                + "server/src/strategy_tests.rs::"
                + "tc_125_001_session_patterns_and_the_station_skip_matches; "
                + "server/src/strategy_tests.rs::"
                + "tc_125_001_a_contest_strategy_skips_a_sender_matched_by_a_pattern";
        }
    }
}
