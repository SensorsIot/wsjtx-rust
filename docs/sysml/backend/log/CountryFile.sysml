package WstxCountryFile {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-011';
    private import WstxLogPart::LogService;
    private import WstxLogControl::CallEntity;
    private import WstxLogControl::ReplaceCountryFile;
    private import WstxLogControl::EntityRequest;
    private import WstxLogControl::CountryFile;
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

    verification 'TC-055-001' {
        doc /* Calls resolved against known answers. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-01'; }
        @TestedBy {
            test = "server/src/log/dxcc_tests.rs::"
                + "tc_055_001_effective_prefix_matches_wsjtx_unit_vectors; "
                + "server/src/log/dxcc_tests.rs::tc_055_001_known_answers_from_the_bundled_file; "
                + "server/src/log/dxcc_tests.rs::tc_055_001_overrides_and_refused_files";
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

    verification 'TC-055-008' {
        doc /*
    The country file in use for every lookup and worked set, and the bundled one without it.
        */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-03'; }
        @TestedBy {
            test = "server/src/log/logbook_http_tests.rs::"
                + "cty_upload_replaces_the_country_table_and_refusals_change_nothing; "
                + "server/src/log/dxcc_tests.rs::tc_055_002_worked_set_follows_each_uploaded_table";
        }
    }
}
