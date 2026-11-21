package WstxMessagePayload {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-004';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModesPart::ModeFunctions;
    private import WstxModeProcessing::*;

    doc /* The payload function of the modes part: how the 77 bits of a decoded frame
         become a message with its fields, and how a hashed call is shown. The payload
         is the one of the published protocol; this file states the product's choices
         over it. */

    requirement 'CL-007-09' {
        subject modes : ModeFunctions;
        doc /* The payload function MUST give every returned frame exactly the fields of
             a decoded frame, with the fields of its message family (UnpackPayload). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/decoder/payload.rs"; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-007-09'; }

    action def UnpackPayload {
        in payload77 : String;
        out result : ProcessingResult;
        doc /* How a payload becomes a message.
             A payload of the families 0.2, 0.6, 0.7, 6 and 7 has the status unsupported.
             A payload of any other family has the fields of its variant of
             PayloadFields and the status decoded.
             A payload of a supported family whose content is outside the domain of that
             family has the status invalidPayload.
             A standard message whose grid field holds RR73 has the exchange roger RR73.
             The Field Day sections and the RTTY states and provinces are the tables of
             WSJT-X. */
        @FollowsSource {
            reference = "QEX, The FT4 and FT8 Communication Protocols, sections 2 to 5 and "
                + "appendix A; WSJT-X at the behaviour baseline: packjt77, with its tables "
                + "of 86 sections and 171 states and provinces";
        }
    }

    requirement 'CL-024-01' {
        subject modes : ModeFunctions;
        doc /* The payload function MUST show a hashed call as the call itself once the
             station has learned that call, and as <...> until then (HashResolution). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/modes/decoder/hashes.rs"; }
    }
    #derivation connection { end #original ::> 'FR-004'; end #derive ::> 'CL-024-01'; }

    attribute def HashResolution {
        doc /* The calls the station has learned, and how they fill in a hash.
             One table of calls exists for each station process, for as long as the
             process runs and across bands and modes.
             The table learns my call from every CallsUpdate.
             From every frame returned it learns the sending call of a standard message,
             and the full call of a nonstandard message whose hash is the call
             addressed.
             From every AcceptedMessage it learns each call of a standard, Field Day or
             RTTY message (of a standard message without /R or /P), the call of a
             nonstandard CQ, and each call written in angle brackets.
             A call is learned from minCallLength characters upward.
             A hash whose call is known is shown as that call in angle brackets, and the
             call is the text of its CallValue.
             A hash whose call is not known is shown as <...>, and its CallValue has no
             text.
             A frame keeps the text it was returned with when its call is learned
             later.
             Of two calls with the same 10-bit or 12-bit hash, the one learned last is
             shown.
             A hash that equals the hash of my call is shown as my call wherever WSJT-X
             fills my call in, also when maxHash22 other calls were learned since.
             A hash that equals the hash of the DX call of the latest CallsUpdate is
             shown as that DX call wherever WSJT-X applies its DX call. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: packjt77 save_hash_call, "
                + "ihashcall, hashmy10/12/22, hashdx10 and unpack77 with nrx=1";
        }
        @DiffersFromSource {
            what = "WSJT-X learns sent calls from its DX call field; the table learns "
                + "them from the messages transmit accepts.";
        }
        @DiffersFromSource {
            what = "WSJT-X takes the DX call from its DX call field; the table takes it "
                + "from the station's current contact.";
        }
        attribute maxHash22 : Integer = 1000 {
            doc /* The table shows the calls learned last, this many, for a 22-bit
                 hash. For a 10-bit and a 12-bit hash a call stays known for as long as
                 the process runs. */ }
        attribute minCallLength : Integer = 3;
    }

    verification 'TC-004-005' {
        doc /* Payloads and their fields. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-09'; }
        @TestedBy {
            test = "server/tests/decoder_vectors.rs::frozen_payload_channel_tone_vectors; "
                + "server/tests/decoder_vectors.rs::canonical_payload_boundaries; "
                + "server/tests/decoder_signal.rs::"
                + "crc_valid_unsupported_and_invalid_payloads_are_retained; "
                + "server/tests/decoder_vectors.rs::rr73_packed_as_a_grid_square_is_the_roger";
        }
    }

    verification 'TC-024-001' {
        doc /* What the table learns and fills in. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy {
            test = "server/src/modes/decoder/hashes_test.rs; "
                + "server/tests/transmit_service.rs; "
                + "server/src/auth_tests.rs::profile_save_sets_my_call_for_the_hash_table";
        }
    }

    verification 'TC-024-002' {
        doc /* Hashed calls in the frames a station publishes. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy { test = "server/src/recording_tests.rs"; }
    }

    verification 'TC-024-010' {
        doc /* The DX call in a DXpedition message. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy { test = "server/src/modes/decoder/hashes_test.rs"; }
    }
}
