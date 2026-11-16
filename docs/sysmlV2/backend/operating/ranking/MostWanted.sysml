package WstxMostWanted {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import WstxClubLog::MostWantedQuery;
    private import WstxClubLog::MostWantedDownload;
    private import WstxClubLog::MostWantedRow;
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-039-10' {
        subject ranking : RankingService;
        doc /* Ranking MUST fetch the Most Wanted list of Club Log when the station
             service asks for it, keep the last good list for the profile, and rank an
             entity by it (MostWantedListRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-10'; }

    attribute def MostWantedListRule {
        doc /* How the list is fetched, kept and used.
             An UpdateMostWanted sends one MostWantedQuery. The MostWantedDownload is
             taken as a list when it is what that item says, each MostWantedRow with
             its limits. Everything else is refused with
             RankingRefusal::downloadFailed and a reason: for an answer with another
             status than 200 "status" and that status, for an answer that is no list
             "the reply is not a Most Wanted list". A refused update leaves the list
             in use as it is.
             A list that is taken is written to most_wanted.json in the operator's
             folder, under the file's lock, with the UTC date of the download, and is in use from
             then on. A
             list that cannot be written is refused with
             RankingRefusal::storageUnavailable.
             After a station start the list is read from that file when ranking first
             needs it. Without the file there is no list. With a file that cannot be
             read, is of another profile, or holds no list, there is no list and
             RankingState::mostWantedUnreadable is true.
             The rank of an entity is the rank of the entry with its ADIF number.
             Ranking holds the ADIF number for each name of an entity in the country
             file; an entity that is no DXCC entity of its own carries the number of
             the DXCC entity it belongs to. An entity without a number, or with a
             number that is not on the list, has no rank.
             MostWantedStatus::unmapped counts the entries whose number no name of
             that table carries.
             Without a list no entity has a rank. */
        @FollowsSource {
            reference = "The ADIF specification: the DXCC entity numbers; the country "
                + "file of AD1C: the names of the entities";
        }
    }

    verification 'TC-039-031' {
        doc /* The Most Wanted list: what is a list, the numbers of the entities, the
             update.
             Setup: lists and answers written by hand; the bundled country file; for
             (d) to (f) the station on a throw-away profile with an answer given in
             place of the service. No network.
             (a) The list with the ranks 1, 2 and 3 for "344", the number 123 and
             "9999": 3 entries, 1 unmapped; DPR of Korea has rank 1, Fed. Rep. of
             Germany none. No list: an empty text, a JSON array, an empty object, the
             rank "x", the rank "0", the numbers "x", "0", "10000" and null, one
             number for two ranks, 1001 entries.
             (b) Every entity of the bundled country file has a number, 340 different
             ones in all. Switzerland 287, United States 291, Fed. Rep. of Germany
             230, Japan 339, DPR of Korea 344, Sicily and Italy 248, Shetland Islands
             and Scotland 279, Cape Verde and Cabo Verde 409.
             (c) An answer with the status 200 gives its body; one with 503 the reason
             "status 503"; a text that is no answer "no response".
             (d) Before an update: no list, not unreadable, the attribution. An update
             answered with the ranks 1 and 2 for "150" and "9999": the status has the
             current UTC date, 2 entries and 1 unmapped; the file holds the list and
             the date; read anew as after a station start it gives the same status,
             and Australia has rank 1.
             (e) An update whose fetch fails with "status 503": refused with that
             reason. An answer "<html>": refused with "the reply is not a Most Wanted
             list". The list in use has 2 entries still.
             (f) A file that holds no JSON: no list, unreadable. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-10'; }
        @TestedBy {
            test = "server/src/most_wanted.rs::"
                + "tc_039_031_parser_refuses_all_but_the_exact_list; "
                + "server/src/most_wanted.rs::"
                + "tc_039_031_every_bundled_entity_has_its_adif_number; "
                + "server/src/most_wanted.rs::tc_039_031_response_body; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_031_update_most_wanted_status_failures_and_mcp_refusal";
        }
    }
}
