package WstxMessageChoice {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-024';
    private import WstxQsoPart::QsoService;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* What a contact sends: its six messages, the report, the operator's edits and the
         messages with a nonstandard call. */

    requirement 'CL-010-12' {
        subject qso : QsoService;
        doc /* qso MUST give each contact the six messages of MessageSet and let the operator
             set them as MessageSet says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-007'; end #derive ::> 'CL-010-12'; }

    attribute def ReportRange {
        doc /* The signal report: from minimum to maximum dB, written with its sign and two
             digits (-05, +03, +00). The report of a record is its SNR rounded to the
             nearest whole dB, a half away from zero, and brought into the range. */
        attribute minimumDb : Integer = -50;
        attribute maximumDb : Integer = 49;
        attribute startDb : Integer = -15 {
            doc /* The report at station start, for a partner entered by call. */ }
    }

    attribute def MessageSet {
        doc /* The six messages of a contact with the partner DX, from the profile's call MY
             with its locator's first four characters GRID:
             Tx1 "DX MY GRID", Tx2 "DX MY report", Tx3 "DX MY R report", Tx4 "DX MY RRR" or
             "DX MY RR73" (written R-12 for R and -12), Tx5 "DX MY 73", Tx6 "CQ MY GRID",
             with the CQ word of the activity in force after CQ. An activity changes them
             as WstxSpecialActivities says; a nonstandard call as NonstandardRule says. The
             own CQ without a partner has Tx6 only.
             The operator sets: SetReport (ReportRange; outside it invalidReport) renews
             Tx2 and Tx3 and keeps an edited Tx6; SetTx1Skip: with it a selection that
             would give Tx1 gives Tx2, and choosing Tx1 gives Tx2; SetTx4: rrr or rr73
             (FT8 starts with rrr, FT4 has rr73 only); EditMessage: a text of the slot that
             modes packs unaltered (WstxModeProcessing::PackAnswer), in capitals; otherwise
             invalidMessage;
             ChooseNext: the message due (WstxStandardQso::ReopenRule), refused noContact
             without a contact and invalidMessage for a slot without text. A record of
             the current partner keeps the Tx4 form and every text already sent.
             A free-text Tx5 on the own CQ is sent once and ends the CQ as a completed one;
             nothing is handed over. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the standard messages Tx1 to Tx6 "
                + "and their report";
        }
        attribute range : ReportRange;
    }

    requirement 'CL-024-05' {
        subject qso : QsoService;
        doc /* qso MUST run a contact in which one of the two calls is nonstandard or
             compound as NonstandardRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-024'; end #derive ::> 'CL-024-05'; }

    attribute def NonstandardRule {
        doc /* One of the two calls of a contact may be nonstandard or compound; with both,
             the call is refused invalidCall. The nonstandard call is written in full and
             the other in angle brackets where WSJT-X does: a nonstandard partner DX gets
             Tx1 "<DX> MY GRID", Tx2 "<DX> MY report", Tx3 "<DX> MY R report", Tx4 "DX <MY>
             RRR", Tx5 "DX <MY> 73"; a nonstandard own call MY gets Tx1 "<DX> MY", Tx2 "DX
             <MY> report", Tx3 "DX <MY> R report", Tx4 "<DX> MY RRR", Tx5 "<DX> MY 73" and
             Tx6 "CQ MY" without the grid. A hashed call filled from the call hash table is
             read as that call; a record whose sender is an unresolved hash names no
             partner. Call 1st answers no hashed and no nonstandard caller. The contact's
             partner is the DX call of the station's calls for the decoding of hashed
             calls. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: genStdMsgs for compound and "
                + "nonstandard calls";
        }
    }

    verification 'TC-024-003' {
        doc /* Contacts with a nonstandard or compound call. */
        subject qso : QsoService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-05'; }
        @TestedBy {
            test = "server/src/contact_tests.rs::"
                + "a_standard_call_works_a_nonstandard_partner_to_the_log; "
                + "server/src/contact_tests.rs::"
                + "a_nonstandard_own_call_answers_a_standard_caller_to_the_log; "
                + "server/src/contact_tests.rs::"
                + "nonstandard_entries_and_free_text_are_validated; "
                + "server/src/contact_tests.rs::"
                + "call_first_skips_hashed_and_nonstandard_callers; "
                + "server/src/contact_tests.rs::"
                + "a_free_text_tx5_on_an_own_cq_is_sent_once_and_never_logged; "
                + "server/src/contact_http_tests.rs::"
                + "the_contact_step_gives_the_hash_table_the_dx_call";
        }
    }
}
