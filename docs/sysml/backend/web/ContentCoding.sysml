package WstxContentCoding {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxWebPart::WebAdapter;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::Status;

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
}
