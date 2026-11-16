package WstxMessagePayload {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-004';
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import WstxModesPart::ModeFunctions;
    private import WstxModeProcessing::*;

    doc /* The payload function of the modes part: how the 77 bits of a decoded frame
         become a message with its fields, and how a hashed call is shown. The payload
         is the one of the published protocol; this file states the product's choices
         over it. */

    // ---- From payload to fields -----------------------------------------------------------

    requirement 'CL-007-09' {
        subject modes : ModeFunctions;
        doc /* The payload function MUST give every returned frame exactly the fields of
             a decoded frame, with the fields of its message family (UnpackPayload). */
        @Status { build = ImplementationState::implemented; }
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
             family has the status invalid_payload.
             A standard message whose grid field holds RR73 has the exchange roger RR73.
             The Field Day sections and the RTTY states and provinces are the tables of
             WSJT-X. */
        @ImplementedIn { module = "server/src/decoder/payload.rs"; }
        @FollowsSource {
            reference = "QEX, The FT4 and FT8 Communication Protocols, sections 2 to 5 and "
                + "appendix A; WSJT-X at the behaviour baseline: packjt77, with its tables "
                + "of 86 sections and 171 states and provinces";
        }
    }

    // ---- Hashed calls ---------------------------------------------------------------------

    requirement 'CL-024-01' {
        subject modes : ModeFunctions;
        doc /* The payload function MUST show a hashed call as the call itself once the
             station has learned that call, and as <...> until then (HashResolution). */
        @Status { build = ImplementationState::implemented; }
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
        @ImplementedIn { module = "server/src/modes/decoder/hashes.rs"; }
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

    // ---- Test cases -----------------------------------------------------------------------

    verification 'TC-004-005' {
        doc /* Payloads and their fields.
             Setup: the payload function alone, on payloads with known text and fields
             and on payloads built at the borders of each field.
             (a) Every payload of the vector set unpacks to its text and fields.
             (b) A standard message with grid value 32399 decodes as grid RR99; with
             32400 it is invalid_payload.
             (c) A CQ with modifier value 1002 decodes as "CQ 999"; with 1003 it is
             invalid_payload.
             (d) A free text of blanks only, and one outside the 42 characters of free
             text, is invalid_payload.
             (e) A frame with a payload that is unsupported or invalid_payload is
             returned with that status, its exact 77 bits, and no text and no
             fields. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-09'; }
        @TestedBy {
            test = "server/tests/decoder_vectors.rs::frozen_payload_channel_tone_vectors; "
                + "server/tests/decoder_vectors.rs::canonical_payload_boundaries; "
                + "server/tests/decoder_signal.rs::"
                + "crc_valid_unsupported_and_invalid_payloads_are_retained";
        }
    }

    verification 'TC-024-001' {
        doc /* What the table learns and fills in.
             Setup: the payload function with one table; transmit on a double of the
             radio for (g).
             (a) Without a known call "<PJ4/K1ABC> W9XYZ -05" reads "<...> W9XYZ -05";
             its addressed call has the kind hash, 22 bits and no text.
             (b) After "CQ PJ4/K1ABC", "CQ K1ABC/R FN42" and "W9XYZ DL1ABC JO62" were
             returned, the messages read "<PJ4/K1ABC> W9XYZ -05", "<K1ABC/R> W9XYZ" and
             "<DL1ABC> PA/K1XX".
             (c) W9XYZ, only addressed in "W9XYZ DL1ABC JO62", is not learned:
             "<...> PA/K1XX".
             (d) With my call HB9BLA: "<HB9BLA> PJ4/K1ABC" and "<HB9BLA> K1ABC -05";
             the sending hash of a nonstandard message stays "PJ4/K1ABC <...> RR73".
             (e) After 1000 more calls my call is still filled in, and the call learned
             first reads "<...>".
             (f) Of two calls with the same 12-bit hash the later one is shown.
             (g) The accepted messages "<VP2X/K1JT> HB9BLA" and "CQ YW18FIFA" teach
             VP2X/K1JT and YW18FIFA; a refused message teaches nothing. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy {
            test = "server/src/modes/decoder/hashes_test.rs; "
                + "server/tests/transmit_service.rs";
        }
    }

    verification 'TC-024-002' {
        doc /* Hashed calls in the frames a station publishes.
             Setup: receive with a live FT8 job and frames given by hand; my call
             HB9BLA.
             (a) "<VP2X/K1JT> W9XYZ -05" published before the call is known reads
             "<...> W9XYZ -05" and keeps that text.
             (b) After "CQ VP2X/K1JT" the same message reads "<VP2X/K1JT> W9XYZ -05",
             and its addressed call has the kind hash and the text VP2X/K1JT.
             (c) "<HB9BLA> VP2X/K1JT" shows my call; "<DL/K1ABC> W9XYZ" reads
             "<...> W9XYZ" with no text.
             (d) After my call changes to HB9BLB: "<HB9BLB> VP2X/K1JT". */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy { test = "server/src/recording_tests.rs"; }
    }

    verification 'TC-024-010' {
        doc /* The DX call in a DXpedition message.
             Setup: the payload function with one table, on the message
             "K1ABC RR73; W9XYZ <KH1/KH7Z> -12".
             (a) Without a DX call the hash reads "<...>".
             (b) With the DX call KH1/KH7Z it reads "<KH1/KH7Z>", also when another call
             with the same 10-bit hash was learned.
             (c) With the DX call K1ABC it reads the learned call of that hash, or
             "<...>" when none was learned.
             (d) A DX call of two characters whose hash matches is not filled in.
             (e) My call HB9BLA is not filled into the hash of a received DXpedition
             message. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-024-01'; }
        @TestedBy { test = "server/src/modes/decoder/hashes_test.rs"; }
    }
}
