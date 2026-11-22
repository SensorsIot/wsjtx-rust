package WstxContentCoding {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxWebPart::WebAdapter;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* How web codes the answers of the link to keep them small on a slow link. */

    requirement 'CL-003-09' {
        subject web : WebAdapter;
        doc /* web MUST code the answers of the link as CodingRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-003-09'; }

    attribute def CodingRule {
        doc /* A successful GET of a view, a read or a file of the client is sent with the
             content coding gzip when the request's Accept-Encoding selects gzip, and
             without a coding otherwise, also when the request accepts no coding at all.
             The coded answer keeps its content type, names Accept-Encoding in Vary and
             carries no length of the uncoded body. Every other answer, an answer that
             already has a coding or a range, the logbook's export and the messages on a
             socket go without a coding. A request's own body is never coded. */
        @FollowsSource {
            reference = "RFC 9110 sections 8.4 and 12.5.3 (content coding, Accept-Encoding); "
                + "RFC 1952 (gzip)";
        }
    }

    verification 'TC-003-003' {
        doc /*
Gzip only when Accept-Encoding selects it, the form of a coded answer, and the answers never coded.
        */
        subject web : WebAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-003-09'; }
        @TestedBy {
            test = "server/src/web/content_coding_tests.rs::"
                + "h1_exact_vary_merge_framing_and_validator_rules; "
                + "server/src/web/content_coding_tests.rs::"
                + "h1_exclusions_preserve_original_before_forbidden_negotiation; "
                + "server/src/web/content_coding_tests.rs::"
                + "static_assets_gzip_when_selected_and_keep_exact_identity_bytes_otherwise; "
                + "tests/radio-selection.test.cjs::"
                + "H1 raw TLS gzip snapshots preserve bounded JSON; "
                + "tests/radio-selection.test.cjs::"
                + "H1 authentication errors mutations static and HEAD bypass negotiation";
        }
    }
}
