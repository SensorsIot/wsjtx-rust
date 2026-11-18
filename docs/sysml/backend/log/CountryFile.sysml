package WstxCountryFile {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-011';
    private import WstxLogPart::LogService;
    private import WstxLogControl::CallEntity;
    private import WstxLogControl::ReplaceCountryFile;
    private import WstxLogControl::EntityRequest;
    private import WstxOperatingChain::WorkedSet;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-055-01' {
        subject log : LogService;
        doc /* Log MUST resolve a call to its DXCC entity, with the continent, the zones
             and the position the country file gives for it, as WSJT-X does
             (EntityOfCall, CountryFile). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-055-01'; }

    action def EntityOfCall {
        in call : String;
        out entity : CallEntity[0..1];
        doc /* How an EntityRequest is answered from the country file in use.
             The call is read in upper case. An empty call, a call with a character
             outside ASCII and a call that ends in /MM or /AM have no entity.
             The effective prefix: endings after a "/" are taken off from the right
             while they are a digit, A, M, P, Q, R, QRP, FD, FF, AM, MM, LH, LT or LGT;
             of a call that then still has a "/", the shorter side is the prefix, and
             the left side when both are equally long.
             When the effective prefix is not the whole call, an exact entry of the
             file for the whole call decides.
             Otherwise the longest entry that begins the effective prefix decides; an
             exact entry counts only when it is as long as the whole call.
             A call that begins with KG4 and has neither three nor five characters is
             of the entity whose primary prefix is K.
             The answer is the entity with what the deciding entry says in its place
             for the CQ zone, the ITU zone, the continent and the position; the
             longitude is turned to positive east.
             The shown name is the name shortened as WSJT-X shortens it, with an entity
             that only the WAE list knows shown as its DXCC entity; the name itself
             stays the one of the file. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: AD1CCty lookup and "
                + "abbreviated_entity_name, Radio effective_prefix, and the display of "
                + "entities with the extra WAE entities off";
        }
    }

    attribute def CountryFile {
        doc /* The country file and how it is read.
             The file bundled with the station is cty.dat as WSJT-X at the behaviour
             baseline ships it.
             A line with fewer than seven ":" is skipped. Each other line begins an
             entity, whose entries follow up to a ";".
             An entry given a second time keeps the entity of its first place.
             An exact entry VER followed by eight digits is the version of the file.
             A file is refused, with the line of the entity counted from 1, for a
             number that cannot be read, a CQ zone above 40 or an ITU zone above 90,
             also in an entry, a continent that is none of Continent, a shown name that
             is not 1 to 40 printable ASCII characters, an entity without a primary
             prefix, and entries that do not end with ";". A file without an entity
             is refused with line 1. */
        @FollowsSource {
            reference = "AD1C cty.dat, the format of the country files of "
                + "country-files.com; WSJT-X at the behaviour baseline: AD1CCty load_cty";
        }
    }

    verification 'TC-055-001' {
        doc /* Calls resolved against known answers. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-01'; }
        @TestedBy {
            test = "server/src/dxcc_tests.rs::"
                + "tc_055_001_effective_prefix_matches_wsjtx_unit_vectors; "
                + "server/src/dxcc_tests.rs::tc_055_001_known_answers_from_the_bundled_file; "
                + "server/src/dxcc_tests.rs::tc_055_001_overrides_and_refused_files";
        }
    }

    requirement 'CL-055-03' {
        subject log : LogService;
        doc /* Log MUST use the country file the settings function keeps in the place of
             the bundled one (ProfileCountryFile). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-055-03'; }

    attribute def ProfileCountryFile {
        doc /* Which file is in use. A ReplaceCountryFile with a text puts that file in use,
             read as CountryFile, from then on for every EntityRequest and every WorkedSet
             made afterwards; without a text the bundled file is in use. The settings
             function fetches and checks the file (WstxProfileDocument::CountryFileFetch). */
    }
}
