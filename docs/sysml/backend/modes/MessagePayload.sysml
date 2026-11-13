package WstxOfflineDecode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-005';
    private import WstxMessageEncode::'CL-011-01';
    private import WstxModemDecode::'CL-007-03';
    private import WstxModemDecode::'TC-004-002';
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import WstxRequirements::'FR-024';
    private import WstxDecodes::ResultRecord;
    doc /* The data the modes part shares with the other parts, and its payload function: how
         a 77-bit payload becomes a record. The payload is the one of the published
         protocol; this package states the product's choices over it. The decode function
         is in WstxModemDecode. */

    attribute def DecodeBand {
        doc /* The audio band of the lowest tone of a decoded frame, both ends inclusive. */
        attribute decodeBandLowHz : Integer = 200;
        attribute decodeBandHighHz : Integer = 3500;
    }

    requirement def HashResolution {
        doc /* The station shows a hashed call as <CALL> once it knows the full call, from one
             table per station instance (profile process), kept for the process lifetime
             across jobs, bands and modes, never shared between profiles and never saved.
             The pure unpack has no table and shows <...>. A call is never guessed from its
             hash. */
        doc /* The table learns my profile callsign at startup and whenever it changes; from
             each published record, the concrete 'from' call of a standard message and the
             full call of a nonstandard message whose hash is the 'to' call; and from each
             transmit request the transmit owner accepts, every concrete call of a
             standard, Field Day or RTTY message, the full call of a nonstandard CQ and
             every bracketed <CALL>. */
        doc /* A slot that is not found stays <...> with null text, and a hashed slot stays
             kind hash. Records published before a call was learned keep their text. The
             filled-in text reaches Band Activity, the QSO pane, MCP reads and the UDP
             Decode message (WstxUdp::OutboundRules) unchanged. Contact selection and
             sequencing read a filled-in hash as its call (WstxStandardQso::SelectDecodedRow);
             the strategy, Call 1st, DXCC and worked-before and Pounce treat it as no call. */
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 packjt77 save_hash_call, ihashcall, unpack77 with "
                + "nrx=1";
        }
        @DiffersFromSource {
            what = "The table learns from the transmit requests the station accepts; WSJT-X "
                + "feeds it the DX call (ft8apset, dxcall13).";
        }
        @DiffersFromSource {
            what = "The DX-call rules of unpack77 use the DX call the station sets from the "
                + "current contact at each contact step.";
        }
    }

    action def UnpackPayload {
        in payload77 : String;
        out record : ResultRecord;
        @ImplementedIn {
            module = "server/src/decoder/payload.rs; server/src/decoder/hashes.rs";
        }
        @FollowsSource {
            reference = "QEX FT4/FT8 sections 2 to 5 and appendix A; WSJT-X 3.3.0-beta5 packjt77";
        }
        doc /* The supported families are 0.0 free text, 0.1 DXpedition, 0.3 and 0.4 Field
             Day, 0.5 telemetry, 1 and 2 standard, 3 RTTY, 4 nonstandard and 5 EU VHF;
             0.2, 0.6, 0.7, 6 and 7 are unsupported. */
        doc /* Structured content outside its domain is invalid_payload and never falls back
             to free text. */
        doc /* A standard exchange packed as the grid square RR73 is the roger RR73; the text
             is unchanged. */
        @FollowsSource { reference = "WSJT-X 3.3.0-beta5 grid_regexp, which excludes RR73"; }
        doc /* Field Day sections are the 86 of
             fixtures/decoder/protocol-data/arrl_rac_sections.json and RTTY exchanges
             8001..8171 those of states_provinces.json there; a section 0 or above 86 and an
             exchange 8000 or above 8171 are invalid. */
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 PACK77_ARRL_SECTIONS and PACK77_RTTY_MULTIPLIERS, "
                + "not the 84 sections of QEX";
        }
    }
    action unpackPayload : UnpackPayload;
    satisfy 'CL-007-09' by unpackPayload;
    dependency payloadOwner from unpackPayload
        to WstxArchitecture::physicalStation::backend::stations::modes;

    requirement 'CL-007-09' {
        doc /* Each record the modem produces MUST carry exactly the fields of ResultRecord,
             with the payload fields of its message family as PayloadFields defines them. */
        @Status { build = ImplementationState::implemented; }
    }
    dependency CL_007_09_to_FR_003 from 'CL-007-09' to 'FR-003';
    dependency CL_007_09_to_FR_004 from 'CL-007-09' to 'FR-004';
    verification 'TC-004-005' {
        doc /* TC-004-005 — Payload vectors
             Setup: the frozen payload, channel and tone vectors in fixtures/decoder/, and
             the payload-boundary cases.
             (a) Every vector unpacks to its text and fields.
             (b) Sections 84 to 86 and exchanges 8065, 8066 and 8171 decode; 87 and 8172
                 are invalid_payload.
             (c) The CRC and parity of every vector match.
             Oracle: the frozen independent vectors.
             2 — Isolated automated tests; Windows PC, offline fixtures. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-007-03';
            verify 'CL-007-09';
            verify 'FR-003';
            verify 'FR-004';
        }
        @TestedBy {
            test = "server/tests/decoder_vectors.rs::frozen_payload_channel_tone_vectors; server/tests/decoder_vectors.rs::canonical_payload_boundaries";
        }
    }
    dependency CL_007_03_verified_by_TC_004_005 from 'CL-007-03' to 'TC-004-005';
    dependency CL_007_09_verified_by_TC_004_002 from 'CL-007-09' to 'TC-004-002';
    dependency CL_007_09_verified_by_TC_004_005 from 'CL-007-09' to 'TC-004-005';
    requirement 'CL-024-01' {
        doc /* #24 S1. The station keeps one session hash table per station instance, fed by every concrete call decoded or sent and by my own call, and shows a hashed call as <CALL> once it resolves, otherwise <...>, as packjt77 does (this reverses the earlier rule of the payload function WstxOfflineDecode::UnpackPayload that a hash is never filled in). It generates and accepts the WSJT-X message sets for exactly one nonstandard or compound call with the bracket rules of genStdMsgs and refuses two nonstandard calls. It accepts free text of at most 13 characters (0.0) in an operator-edited slot. Every transmitted text packs unaltered. Slice S1a: the hash table and fill-in (WstxOfflineDecode::HashResolution); slice S1b: compound/nonstandard QSOs through the contact engine (WstxStandardQso::StandardMessageSet, SelectDecodedRow, EnterDxStation), the nonstandard DX-call fill-in rule, free text in an operator-edited slot with Tx5 editable from the operating screen, and Band Activity marking <MYCALL> rows as to me. The 0.1 DXpedition DX-call rule (hashdx10) is #24 S4a, TC-024-010. Station automation (Auto Call, Auto CQ, Pounce, the strategy) and Call 1st stay standard-only: a run does not start with a nonstandard profile callsign (not_ready call). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/hashes.rs; server/src/decoder/payload.rs; server/src/recording.rs; server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; client/contact.js; client/recording.js";
    }
    dependency CL_024_01_to_FR_024 from 'CL-024-01' to 'FR-024';
    dependency CL_024_01_to_FR_004 from 'CL-024-01' to 'FR-004';
    verification 'TC-024-001' {
        doc /* TC-024-001 — Hash table learning and fill-in, known and unknown calls
             CL-024-01
             Setup: the pure payload codec and the hash table of WstxOfflineDecode::HashResolution; the transmit owner on its recording hardware double (virtual clock; no audio, PTT or radio).
             Steps: unpack "<PJ4/K1ABC> W9XYZ -05" with no table and with an empty table; learn the decodes "CQ PJ4/K1ABC" (i3=4), "CQ K1ABC/R FN42", "CQ K1ABC FN42", "W9XYZ DL1ABC JO62" and "VK9/K1XX <W9XYZ>" (hash 'from'); fill in "<PJ4/K1ABC> W9XYZ -05", "<K1ABC/R> W9XYZ", "<DL1ABC> PA/K1XX", "<W9XYZ> PA/K1XX", "<VK9/K1XX> W9XYZ", "PA/K1XX <DL1ABC> RR73", a DXpedition 0.1 "K1ABC RR73; W9XYZ <KH1/KH7Z> -12" before and after KH1/KH7Z is learned and an EU VHF i3=5 message; set my call HB9BLA and fill in "<HB9BLA> PJ4/K1ABC", "<HB9BLA> K1ABC -05", "PJ4/K1ABC <HB9BLA> RR73" (i3=4, hash 'from') and "<HB9BLA> <K1ABC> R 570001 JN37VL" (EU VHF); learn 1000 more calls; two calls with the same 12-bit hash one after the other; the transmit owner with the table attached accepts "<VP2X/K1JT> HB9BLA" and "CQ YW18FIFA" and refuses (not armed) "<3D2CR/P> HB9BLA".
             Expected: without a table the text is "<...> W9XYZ -05" with to {kind hash, text null, hash_bits 22}; the 'from' calls K1ABC/R, DL1ABC and the nonstandard CQ call are learned, the 'to' call W9XYZ of "W9XYZ DL1ABC JO62" and the nonstandard full 'to' call of a hash-'from' message are not; filled-in texts "<PJ4/K1ABC> W9XYZ -05" with to {kind hash, text PJ4/K1ABC, hash_bits 22, the same hash_value}, "<K1ABC/R> W9XYZ", "<DL1ABC> PA/K1XX", "<...> PA/K1XX", "<...> W9XYZ", "PA/K1XX <DL1ABC> RR73"; the DXpedition hash "<...>" then "<KH1/KH7Z>"; my call fills "<HB9BLA>" in the 'to' slot of standard, nonstandard and EU VHF messages but not the nonstandard hash 'from' slot ("PJ4/K1ABC <...> RR73"), and still after 1000 more calls have pushed it out of the 22-bit list, where the oldest call is then "<...>"; the later of two calls with one 12-bit hash wins; the accepted requests teach VP2X/K1JT and YW18FIFA, the refused one nothing; the pure unpack of every message is unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/decoder/hashes_test.rs; server/tests/transmit_service.rs";
    }
    dependency CL_024_01_verified_by_TC_024_001 from 'CL-024-01' to 'TC-024-001';
    verification 'TC-024-002' {
        doc /* TC-024-002 — The station's live publication fills in hashed calls
             CL-024-01
             Setup: the actual station Recording owner with a fixture live FT8 job and hand-authored decodes; my call HB9BLA set on the Recording; the station fixture with its transmit owner on the recording hardware double; the real profile PUT handler.
             Steps: publish "<VP2X/K1JT> W9XYZ -05", then "CQ VP2X/K1JT", then "<VP2X/K1JT> W9XYZ -05" again, "<HB9BLA> VP2X/K1JT" and "<DL/K1ABC> W9XYZ"; read the published records, their UDP Decode messages and the strategy facts; change my call to HB9BLB and publish "<HB9BLB> VP2X/K1JT"; run the station's startup hash wiring with the profile call hb9bla; save a profile with callsign HB9BLA through PUT /profile.
             Expected: the first record keeps "<...> W9XYZ -05" (no rewriting of history); the later one reads "<VP2X/K1JT> W9XYZ -05" with to {kind hash, text VP2X/K1JT}, "<HB9BLA> VP2X/K1JT" and "<...> W9XYZ" with text null; the UDP Decode messages carry the same texts; the strategy has no facts for a record whose 'from' is hashed and unchanged facts otherwise; after the change "<HB9BLB> VP2X/K1JT"; after the startup wiring the transmit owner holds the Recording's own table and my call is HB9BLA; after the profile save my call is HB9BLA.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/recording_tests.rs; server/src/contact_http_tests.rs; server/src/auth_tests.rs";
    }
    dependency CL_024_01_verified_by_TC_024_002 from 'CL-024-01' to 'TC-024-002';
    verification 'TC-024-003' {
        doc /* TC-024-003 — Compound and nonstandard QSOs through the contact engine
             CL-024-01
             Setup: the contact engine against the actual #9 transmit owner core on a virtual UTC clock with its recording hardware double (no audio, PTT or radio); rows built as the station builds them: packed, unpacked, filled in by a HashTable with my call set, and read by the station's row reader; HB9BLA JN47AA, or DL/HB9BLA.
             Steps: (a) HB9BLA selects "CQ PJ4/K1ABC" (i3=4), Enable Tx; the partner sends "HB9BLA <PJ4/K1ABC> -12", then "<HB9BLA> PJ4/K1ABC RR73"; (b) as DL/HB9BLA, Enable Tx with no partner; the partner sends "<DL/HB9BLA> K1ABC FN42", which is selected, then "<DL/HB9BLA> K1ABC R-07", then "DL/HB9BLA <K1ABC> 73"; (c) enter the DX calls YW18FIFA, PJ4/K1ABC/P, a 12-character call and, as DL/HB9BLA, PA/K1XX, and select "W9XYZ <...> -10" and "PJ4/K9YY <...> RR73" (unresolved 'from') and "<...> W9XYZ RR73" (unresolved 'to', concrete 'from'); (d) edit Tx5 to "tnx 73 gl", and on an own CQ without a partner choose that Tx5 and send it, "TNX FER QSO 73 GL" (17 characters) and "HI, 73" (outside the free-text alphabet); (e) Call 1st on while calling CQ as HB9BLA: "<HB9BLA> PA/K1XX" and "HB9BLA <PJ4/K1ABC> -12" then "HB9BLA W9XYZ -10"; (f) the station's contact step with the manual entry PJ4/K1ABC over POST /contact/command; a table with a 12-bit collision X of HB9BLA in calls12, DX call PJ4/K1ABC, then "<HB9BLA> PJ4/K1ABC" filled in.
             (g) start a station automation run with the profile callsign DL/HB9BLA, then HB9BLA.
             Expected: (a) the message set "<PJ4/K1ABC> HB9BLA JN47", "<PJ4/K1ABC> HB9BLA -NN", "<PJ4/K1ABC> HB9BLA R-NN", "PJ4/K1ABC <HB9BLA> RRR", "PJ4/K1ABC <HB9BLA> 73", "CQ HB9BLA JN47"; the station sends Tx1, Tx3, Tx5, completes and logs PJ4/K1ABC with rcvd -12; (b) Tx6 "CQ DL/HB9BLA", then Tx2 "K1ABC <DL/HB9BLA> -NN", Tx4 "<K1ABC> DL/HB9BLA RRR", completed after the partner's 73, logged K1ABC grid FN42; (c) YW18FIFA and PJ4/K1ABC/P accepted with their nonstandard sets, the 12-character call and PA/K1XX as DL/HB9BLA (two nonstandard calls) invalid_call, the rows from an unresolved hash refused row_not_standard and the one from W9XYZ selected; (d) Tx5 "TNX 73 GL" stored, the long text and a text that would not pack unaltered invalid_message; the own-CQ free text is sent once, the contact completes and nothing is handed to the log; (e) Call 1st skips the nonstandard and the hashed caller and answers W9XYZ; (f) the entry is accepted with Tx1 "<PJ4/K1ABC> HB9BLA JN47" and after the step the station's table holds DX call PJ4/K1ABC; the filled-in 'to' is <HB9BLA>, not <X> (and <X> without the DX call); (g) not_ready call with DL/HB9BLA, then the next readiness check (not_configured strategy) with HB9BLA.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/contact_tests.rs; server/src/contact_http_tests.rs; server/src/decoder/hashes_test.rs; server/src/strategy_tests.rs";
    }
    dependency CL_024_01_verified_by_TC_024_003 from 'CL-024-01' to 'TC-024-003';
    verification 'TC-024-010' {
        doc /* TC-024-010 — The 0.1 DXpedition DX-call rule (hashdx10)
             CL-024-01
             Setup: the pure payload codec and the hash table of WstxOfflineDecode::HashResolution; 0.1 payloads built from their fields (the packer refuses 0.1).
             Steps: resolve "K1ABC RR73; W9XYZ <KH1/KH7Z> -12" with no DX call, with the DX call KH1/KH7Z set, with KH1/KH7Z set while calls10 holds another call of the same 10-bit hash, with the DX call K1ABC (another hash) and with the 2-character DX call KH on a payload built for the DXpedition call KH, so its hash matches; my call HB9BLA in the 0.1 hash slot.
             Expected: "<...>" without a DX call; "<KH1/KH7Z>" with the DX call set, also over the colliding calls10 entry; the calls10 entry (or "<...>") for another DX call and "<...>" for KH although its hash matches (hashdx10 needs at least 3 characters); the received 0.1 hash slot is not filled with my call (unpack77 applies hashmy10 only to nrx=0); the pure unpack is unchanged.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "server/src/decoder/hashes_test.rs";
    }
    dependency CL_024_01_verified_by_TC_024_010 from 'CL-024-01' to 'TC-024-010';
    verification 'TC-024-004' {
        doc /* TC-024-004 — Tx5 free text and <MYCALL> rows in the operating screen
             CL-024-01
             Setup: the browser fixture of the operating screen with the actual isolated station, hand-written live records and a hand-written contact snapshot of an own CQ (no partner, only Tx6), the profile call HB9BLA; contact commands are recorded (the station's validation of the text is TC-024-003).
             Steps: publish rows "<HB9BLA> PJ4/K1ABC" (nonstandard, 'to' filled in), "HB9BLA <PJ4/K1ABC> -12" (standard, 'from' filled in), "<...> PJ4/K1ABC" and "<HB9BLA> K1ABC -12" (standard, 'to' filled in); open the message fold-out and type "tnx 73 gl" into Tx5.
             Then (QsoPane Calling me) the same rows during a QSO with PJ4/K1ABC, Rx 1000 Hz and Tx 1300 Hz.
             Expected: the rows to <HB9BLA> or HB9BLA carry the mycall mark (ba-tome) and sort first as value 1 (calling me, #55 BandActivityValue), the unresolved one does not and follows them; the QSO pane Calling me lists one line per station calling my call, oldest first: PJ4/K1ABC by its newest row "HB9BLA <PJ4/K1ABC> -12" and "<HB9BLA> K1ABC -12", not the unresolved one; during the QSO only "<HB9BLA> K1ABC -12" (the partner PJ4/K1ABC's rows are not callers); Tx5 is enabled without a message while the other empty slots and the Tx5 Next choice are not; edit_message {slot tx5, text "tnx 73 gl"} is sent and nothing transmits; no page errors.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-024-01';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_024_01_verified_by_TC_024_004 from 'CL-024-01' to 'TC-024-004';
}
