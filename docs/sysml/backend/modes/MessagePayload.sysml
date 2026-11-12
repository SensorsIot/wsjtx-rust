package WstxOfflineDecode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-005';
    private import WstxRequirements::'CL-011-01';
    private import WstxModemDecode::'CL-007-03';
    private import WstxModemDecode::'TC-004-002';
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    doc /* The data the modes part shares with the other parts, and its payload function: how
         a 77-bit payload becomes a record. The payload is the one of the published
         protocol; this package states the product's choices over it. The decode function
         is in WstxModemDecode. */

    enum def Mode { enum ft4; enum ft8; }
    enum def FrameStatus {
        doc /* decoded: a payload of a supported family with valid content. unsupported: a
             CRC-valid payload of a family the product does not unpack. invalid_payload: a
             CRC-valid payload of a supported family whose content is outside its domain. */
        enum decoded;
        enum unsupported;
        enum invalid_payload;
    }
    enum def CallKind { enum call; enum token; enum hash; }
    enum def ExchangeKind { enum blank; enum grid; enum report; enum roger; }
    attribute def Settings { attribute mode : Mode; }

    attribute def DecodeBand {
        doc /* The audio band of the lowest tone of a decoded frame, both ends inclusive. */
        attribute decodeBandLowHz : Integer = 200;
        attribute decodeBandHighHz : Integer = 3500;
    }

    attribute def CallValue {
        attribute kind : CallKind;
        attribute text : String[0..1];
        attribute hash_bits : Integer[0..1];
        attribute hash_value : Integer[0..1];
        doc /* A call or a token (CQ, DE, QRZ, a CQ modifier) has its text and null hash
             fields; a concrete call is 1 to 13 upper-case characters, 11 at most in a
             nonstandard message. A hash has its width (10, 12 or 22 bits) and its value,
             and null text, or, in a station's live publication, the call HashResolution
             filled in, without brackets; its kind stays hash. */
    }
    attribute def StandardExchange {
        attribute kind : ExchangeKind;
        attribute textValue : String[0..1];
        attribute numericValue : Integer[0..1];
        doc /* On the wire exactly {kind, value}: blank null, grid a 4-character grid, report
             an integer -50..50, roger RRR, RR73 or 73. */
    }
    attribute def PayloadFields {
        doc /* The fields of a decoded payload: one variant per message family, each with all
             its keys and no others. */
    }
    attribute def FreeTextFields :> PayloadFields {
        attribute 'type' : String = "free_text";
        attribute value : String;
        doc /* Family 0.0: 1 to 13 characters, trailing padding trimmed; all blank is invalid. */
    }
    attribute def TelemetryFields :> PayloadFields {
        attribute 'type' : String = "telemetry";
        attribute value : String;
        doc /* Family 0.5: 18 upper-case hex digits, the first 0 to 7. */
    }
    attribute def StandardFields :> PayloadFields {
        attribute 'type' : String = "standard";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute exchange : StandardExchange;
        doc /* Families 1 (/R) and 2 (/P). */
    }
    attribute def RttyFields :> PayloadFields {
        attribute 'type' : String = "rtty";
        attribute tu : Boolean;
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute exchangeKind : String;
        attribute serial : Integer[0..1];
        attribute stateToken : String[0..1];
        doc /* Family 3: on the wire the exchange is {kind, value}, a serial 0..7999 or a
             state or province 8001..8171. */
    }
    attribute def DxpeditionFields :> PayloadFields {
        attribute 'type' : String = "dxpedition";
        attribute 'first' : CallValue;
        attribute 'second' : CallValue;
        attribute hashed : CallValue;
        attribute report : Integer;
        doc /* Family 0.1. */
    }
    attribute def FieldDayFields :> PayloadFields {
        attribute 'type' : String = "field_day";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute transmitters : Integer;
        attribute 'class' : String;
        attribute section : String;
        doc /* Families 0.3 (1 to 16 transmitters) and 0.4 (17 to 32). */
    }
    attribute def NonstandardFields :> PayloadFields {
        attribute 'type' : String = "nonstandard";
        attribute full_call : CallValue;
        attribute hashed_call : CallValue;
        attribute hash_second : Boolean;
        attribute cq : Boolean;
        attribute roger : String[0..1];
        doc /* Family 4. A nonstandard CQ shows no hash and keeps its bits. */
    }
    attribute def VhfFields :> PayloadFields {
        attribute 'type' : String = "vhf";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute serial : Integer;
        attribute grid : String;
        doc /* Family 5, the EU VHF contest message. */
    }

    item def ResultRecord :> WstxArchitecture::ProcessingResult {
        attribute sequence : Integer;
        attribute status : FrameStatus;
        attribute payload77 : String;
        attribute i3 : Integer;
        attribute n3 : Integer[0..1];
        attribute text : String[0..1];
        attribute fields : PayloadFields[0..1];
        attribute start_frame : Integer;
        attribute frequency_hz : Real;
        attribute snr_db : Real[0..1];
        attribute a_priori : Integer[0..1];
        assert constraint boundedRecord {
            sequence >= 0 and sequence <= (900719925 * 10000000 + 4740991) and
            i3 >= 0 and i3 <= 7 and
            start_frame >= 0 and start_frame <= (900719925 * 10000000 + 4740991)
        }
        doc /* One decoded frame, with exactly these keys; a_priori is present only for an
             a-priori word. payload77 is the exact 77 payload bits as 0 and 1 characters,
             also for an unsupported or invalid payload. n3 is null unless i3 is 0. text
             (at most 80 ASCII characters) and fields are present only when the status is
             decoded, otherwise null. frequency_hz lies within DecodeBand; snr_db is null or
             as WstxModemDecode::MeasureFrame states it; start_frame indexes the canonical
             12 kHz stream. */
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
             sequencing read a filled-in hash as its call (WstxContact::SelectDecodedRow);
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

    requirement 'CL-009-01' {
        doc /* Pack every supported FT8 message family (standard i3=1/2 with CQ forms,
             reports, R/RRR/RR73/73 and /R /P, i3=4 nonstandard calls with WSJT-X
             hashes, free text, telemetry, and since #24 S2b ARRL Field Day i3=0
             n3=3/4 and RTTY Roundup i3=3, CL-024-03) to the WSJT-X 77 bits, CRC-14 and LDPC
             codeword and 79 tones, and generate the FT8 GFSK waveform at 12 kHz and
             48 kHz within the declared WSJT-X reference tolerance. Unsupported,
             invalid or altered messages and out-of-range audio frequencies are
             explicit refusals. Details: WstxTransmit::PackMessage, ChannelFrame, Ft8WaveformContract. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/mod.rs; server/src/transmit/pack.rs; server/src/transmit/waveform.rs";
    }
    dependency CL_009_01_to_FR_005 from 'CL-009-01' to 'FR-005';

    verification 'TC-005-001' {
        doc /* TC-005-001 — FT8 message, symbol and waveform encoding
             CL-009-01
             Setup: fixtures/transmit/ft8code-vectors.json generated by
             fixtures/transmit/generate.py with WSJT-X 3.3.0-beta5 ft8code.exe
             (ft8code "<message>", tool hashes recorded, beta4 output identical) for 119
             messages covering every supported family and refusal shape, plus two
             zero-noise ft8sim WAVs (ft8sim "<message>" f0 0.0 0 0 1 99).
             Steps: pack and encode each message; generate 12 kHz and 48 kHz waveforms;
             compare to the ft8sim WAVs; decode the waveforms with the receive decoder;
             apply out-of-range frequencies, invalid tones and malformed messages.
             Oracles: ft8code bits, CRC, parity and tones match exactly for every message
             WSJT-X encodes unaltered in a supported family; every other fixture is
             refused; ft8sim within referenceTolerance with the one-sample and 0.01 Hz
             negative controls failing; 48 kHz decimated within rateConsistencyTolerance;
             the receive decoder returns the same payload; refusals are explicit.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-01';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs";
    }
    dependency CL_009_01_verified_by_TC_005_001 from 'CL-009-01' to 'TC-005-001';
    verification 'TC-005-002' {
        doc /* TC-005-002 — FT4 message, symbol and waveform encoding
             CL-011-01
             Setup: fixtures/transmit/ft4/ft4sim-vectors.json generated by
             fixtures/transmit/generate.py --ft4sim with the WSJT-X 3.3.0-beta5 utilities
             ft4sim.exe (ft4sim "<message>" 1500.0 0.0 0 0 1 99, hash recorded) for 122
             messages (the FT8 fixture messages plus an FT4 exchange): payload bits,
             codeword read back from the printed tones, 103 tones; payload bits
             identical to ft8code for every shared unaltered message; two zero-noise
             ft4sim WAVs (f0 1500 and 637.5 Hz).
             Steps: encode each message for FT4; generate 12 kHz and 48 kHz waveforms;
             compare with the in-phase (analytic-signal) component of the ft4sim WAVs;
             decode the waveforms with the receive FT4 decoder; apply out-of-range
             frequencies and invalid tones.
             Oracles: bits, codeword and tones match exactly for every message ft4sim
             encodes unaltered in a supported family, every other fixture is refused;
             waveform within Ft4WaveformContract::referenceTolerance with the one-sample
             shift, 0.01 Hz and one-sample-late ramp controls failing; 241920 samples at
             48 kHz, decimated within rateConsistencyTolerance; the receive decoder
             returns the same payload at the placed frequency and start.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or WSJT-X installation at test time. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-011-01';
        }
        attribute executable : String = "server/tests/transmit_ft4_vectors.rs";
    }
}
