package WstxMostWanted {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-039-10' {
        subject ranking : RankingService;
        doc /* Ranking MUST rank an entity by the Most Wanted list the settings function
             keeps (MostWantedListRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-10'; }

    attribute def MostWantedListRule {
        doc /* How the list is used. The list is RankingContext::mostWanted; it is in use
             from the moment the context brings it. The rank of an entity is the rank of
             the entry with its ADIF number. Ranking holds the ADIF number for each name
             of an entity in the country file; an entity that is no DXCC entity of its
             own carries the number of the DXCC entity it belongs to. An entity without a
             number, or with a number that is not on the list, has no rank.
             MostWantedStatus gives the list's date, its entries, and in unmapped the
             entries whose number no name of that table carries.
             Without a list no entity has a rank. */
        @FollowsSource {
            reference = "The ADIF specification: the DXCC entity numbers; the country "
                + "file of AD1C: the names of the entities";
        }
    }

    verification 'TC-039-031' {
        doc /* The numbers of the entities. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-10'; }
        @TestedBy {
            test = "server/src/most_wanted_tests.rs::"
                + "tc_039_031_every_bundled_entity_has_its_adif_number";
        }
    }
}
