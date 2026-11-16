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
        doc /* The ignore list.
             Setup: the evaluator and the list alone, for HB9BLA in EU on 40m with an
             empty logbook and new call; for (c) the station on a throw-away profile on
             40m with decodes written by hand.
             (a) CQ K1ABC FN42 at -12 dB, CQ DL1XYZ JO62 at -3, CQ NA W1AW FN31 and
             HB9BLA VK2ABC QF56. With K1ABC and W1AW on the list: K1ABC has no rank and
             "K1ABC is ignored (ignore list)"; W1AW has no rank, is not grey and has
             "W1AW is ignored (ignore list)"; VK2ABC has rank 0, DL1XYZ 1. With VK2ABC
             on the list it has no rank. The entry K1 does not ignore K1ABC.
             (b) K1ABC and then DL1XYZ put on: the list reads K1ABC, DL1XYZ. K1ABC put
             on again stands after DL1XYZ. Taking off an entry that is not listed
             changes nothing.
             (c) At station start the list is empty. K1ABC put on: listed, and the
             revision of the strategies is 0 still. W1AW put on and K1ABC taken off:
             the list holds W1AW. With DL1XYZ also on the list, CQs of K1ABC, W1AW and
             DL1XYZ: K1ABC has rank 0, W1AW "W1AW is ignored (ignore list)", DL1XYZ
             "DL1XYZ is ignored (ignore list)".
             (d) Planned, no test yet: after the station's band changes to 20m, and to
             and from an unknown band, the list is as before and W1AW and DL1XYZ are
             ignored still; ClearIgnoreList leaves the list empty; after a stop and a
             start of the station the list is empty; with 20 entries listed a 21st is
             refused with ignoreListFull and the list is as before, and one of the 20
             put on again moves to the end. */
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
        doc /* Patterns in the ignore list.
             Setup: as for the ignore list; for (a), (d) and (e) the station on a
             throw-away profile on 40m with decodes written by hand. The star of a
             pattern is written here as "+".
             (a) Put on: "K+1ABC", "+K1ABCDEFGHI+", "BY+", "+/MM" and "K+1A". Refused:
             "+", "++", "+++", "k1+", "k1abc", "K1ABCDEFGHIJK+" of 14 characters and an
             empty entry.
             (b) "+/MM" matches DL1ABC/MM and not DL1ABC/M; "BY+" matches BY1AA and
             BYA1B and not ABY1A; "+K1ABC+" matches K1ABC and K1ABC/P; K1ABC matches
             K1ABC and neither K1ABC/P nor AK1ABC; "K+1ABC" matches K1ABC and KW1ABC
             and not K1ABD; "A+B+C" matches AXBYC and not ACB; "EA8/+" and "+/DL1ABC"
             match EA8/DL1ABC, "DL1+" does not.
             (c) "BY+" on the list: "BY1AA is ignored (ignore list: BY+)". "BY+" and
             BY1AA: "BY1AA is ignored (ignore list)". "BY+" and "JA+": for BY1AA
             "BY1AA is ignored (ignore list: BY+)", for JA1ABC "JA1ABC is ignored
             (ignore list: JA+)".
             (d) "BY+", "+/MM", "K+1A" and "BY+" again put on: the list reads "+/MM",
             "K+1A", "BY+"; with "+/MM" taken off "K+1A", "BY+". With "BY+" and "JA+"
             on the list, CQ BY1AA OM89 at +9 dB, CQ JA1ABC PM95 at +5 and CQ DL1XYZ
             JO62 at -10: DL1XYZ has rank 0; BY1AA has no rank and "BY1AA is ignored
             (ignore list: BY+)"; JA1ABC has "JA1ABC is ignored (ignore list: JA+)".
             (e) Under the built-in of WW Digi with its contest in force and "BY+" on
             the list: CQ WW BY1AA OM89 has no rank and "BY1AA is ignored (ignore
             list: BY+)"; CQ WW JA1XYZ PM95 has rank 0.
             (f) Planned, no test yet: "K1?BC" is put on, matches K1ABC and K1XBC and
             neither K1BC nor K1ABBC, and gives "K1ABC is ignored (ignore list:
             K1?BC)"; "?", "??", "?+", "1+" and "+/1" are refused, as is every entry
             without a letter. */
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
