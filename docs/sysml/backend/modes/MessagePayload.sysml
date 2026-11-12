package WstxOfflineDecode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-005';
    private import WstxRequirements::'CL-011-01';
    doc /* Canonical pure-modem contract used by live receive and internal numerical fixtures.
         Partial Rust FT4/FT8 implementation exists; declared coverage is not test results.
         Package name preserves established identities, not a public offline-decode API.
         Contract: WstxProductScope::ContractIndex 4.4 CR7, 6.4 TC-004-001/002/003, 12.7, 13.6.
         Protocol: https://wsjt.sourceforge.io/FT4_FT8_QEX.pdf sections2-5/AppendixA;
         current source boundaries and fixed vectors use the pinned beta4 reference manifest.
         Pinned GPL-compatible physical routines may be adapted with source provenance/attribution. Independent meaning/readiness
         review is required before production code; semantic parsing is not that review.
         Existing physical station/receive/modem/web/browser usages remain owners. */

    enum def Mode { enum ft4; enum ft8; }
    enum def FrameStatus { enum decoded; enum unsupported; enum invalid_payload; }
    enum def CallKind { enum call; enum token; enum hash; }
    enum def ExchangeKind { enum blank; enum grid; enum report; enum roger; }
    attribute def Settings { attribute mode : Mode; }
    attribute def PayloadCodebook {
        attribute payloadBits : Integer = 77;
        attribute crcInputBits : Integer = 82;
        attribute informationBits : Integer = 91;
        attribute codewordBits : Integer = 174;
        attribute crcPolynomial : Integer = 26455;
        attribute crcInitialState : Integer = 0;
        attribute freeTextRadix : Integer = 42;
        attribute nonstandardCallRadix : Integer = 38;
        attribute cqNumericFirst : Integer = 3;
        attribute cqNumericLast : Integer = 1002;
        attribute cqAlphabeticBase : Integer = 1003;
        attribute callHash22Base : Integer = 2063592;
        attribute standardCallBase : Integer = 6257896;
        attribute gridMaximum : Integer = 32399;
        attribute reservedGridCode : Integer = 32400;
        attribute blankExchange : Integer = 32401;
        attribute rrrExchange : Integer = 32402;
        attribute rr73Exchange : Integer = 32403;
        attribute goodbyeExchange : Integer = 32404;
        attribute maximumExchangeCode : Integer = 32505;
        attribute ft4XorMask : String = "01001010010111101000100110110100101100001000101001111001010101011011111000101";
        attribute generatorTable : String = "fixtures/decoder/protocol-data/generator.dat";
        attribute parityTable : String = "fixtures/decoder/protocol-data/parity.dat";
        attribute sectionTable : String = "fixtures/decoder/protocol-data/arrl_rac_sections.json";
        attribute stateProvinceTable : String = "fixtures/decoder/protocol-data/states_provinces.json";
        attribute protocolReference : String = "https://wsjt.sourceforge.io/FT4_FT8_QEX.pdf";
        doc /* QEX sections2..5/AppendixA plus published data-only tables define normal
             77-bit FT4/FT8. Current source-field boundaries are pinned independently by
             WstxProductScope::BehaviorBaseline's portable codec manifest and fixed official
             vectors. This does not adopt permissive malformed-payload aliases, context guessing
             beyond the a-priori passes of APrioriHypotheses (#56), SuperFox, FT8var, legacy2019FT4 or automatic QSO/TX behaviour.
             Both modes share source families:0.0 free text,0.1 DXpedition,0.3/.4 FieldDay,
             0.5 telemetry,1/2 standard /R or /P,3 RTTY,4 nonstandard,5 extended VHF.
             0.2/.6/.7 and6/7 are unsupported; WSPR packaging0.6 is not an ordinary message.
             Preserve exact77bits even for unsupported/invalid_payload; CRC-invalid never
             publishes. n3 precedes i3 for type0; all fields MSB-first in published order.
             Type1/2 widths28,1,28,1,1,15,3; type3=1,28,28,1,3,13,3;
             type4=12,58,1,2,1,3; currenttype5=12,22,1,3,11,25,3.
             Free-text alphabet is blank,0..9,A..Z,+-./?; trim trailing padding only,
             allblank invalid. Telemetry is71bits,18uppercasehex,firstdigit0..7,zero valid.
             FieldDay0.3 uses1..16 transmitters,0.4 uses17..32,classA..F; one-based86
             sections includeDX (sectionTable: the WSJT-X 3.3.0-beta5 PACK77_ARRL_SECTIONS,
             #24 S2b, which jt9 and ft8code use; it replaces the QEX 2020 84-entry table,
             whose entries 16/25/44 GTA/MAR/NT are GH/NS/TER there and which lacks PE and NB);
             0/>86 invalid. RTTY report529..599 step10, serial0..7999;
            8001..8171 map the stateProvinceTable (WSJT-X 3.3.0-beta5
             PACK77_RTTY_MULTIPLIERS: the QEX 65 states/provinces/DC plus the Dutch provinces
             DR FR GD GR OV ZH ZL and X01..X99); 8000/>8171 invalid. The transmit packer
             reads the same two tables (WstxTransmit::PackMessage).
             DXpedition report is even-30..32; nonstandard fullcall<=11base38characters;
             VHF report52..59,serial0..2047,gridAA00AA..RR99XX.
             Standard c28:DE0/QRZ1/CQ2; numericCQ3..1002=>CQ000..999;
             alphabeticCQ1003+four-positionbase27 blank/A..Z modifier with leading
             blanks removed and no embedded/trailing blank. Reserved holes invalid.
             hash22=2063592+hash; standard mixed-radix call=6257896+call.
             Calls normalize digit into position3; radix37,36,10,27,27,27 alphabets are
             blank/digits/letters; digits/letters; digits; blank/letters three times.
             At least one of first two characters is a letter; nonempty suffix has no
             embedded blank. K1ABC=10214965,W9XYZ=12751800. Grid4 radices18,18,10,10
             with A..R,A..R,0..9,0..9 giveFN42=10342; grid6 adds24,24 lettersA..X.
             Grid/report0..32399 aregrids,32400reserved,32401blank,32402RRR,
            32403RR73,32404'73'. ReportCode below is exact,>32505invalid. Invalid
             structured content never falls back to free text. Hashes keep10/12/22-bit
             numeric identity. The pure unpack has no hash table and displays<...>; only a
             station's live publication fills a hash in, from its HashResolution table of
             calls heard and sent (CL-024-01, #24), never by inverse guessing. A concrete
             type4full call stays concrete; no cross-profile cache.
             CRC14 polynomial0x6757,zero state, operates on payload zero-extended82bits;
             append14CRCbits to77payload bits then published GF(2) parity=>174bits.
             FT4 XORs the exact77-bit mask beforeCRC/FEC and reverses onlyafter validation.
             Gray maps by bit-group value:FT8[0,1,3,2,5,6,4,7],FT4[0,1,3,2].
             FT8=79symbols*1920frames;FT4=105incl2ramps*576frames. Published Costas,
             continuous phase, GaussianBT2/1 and raised-cosine ramps are normative.
             Independent fixtures use separate polynomial division/streaming recurrence,
             published syndrome and fixed tones before audio synthesis; never production
             decoder/reconstruction as sole oracle. Vectors record provenance, fields,
             bits/CRC/codeword/tones,start/frequency/amplitude/noise/seed/parameters/hash.
             Cross-math audio permits1PCM-LSB; retained WAV bytes use exact SHA256. */
    }
    calc def ReportCode {
        in report : Integer;
        return code : Integer = if report < -30 ? 32400 + report + 35 + 101 else 32400 + report + 35;
        assert constraint domain { report >= -50 and report <= 50 }
    }
    calc def StandardCallCode {
        in firstIndex : Integer;
        in secondIndex : Integer;
        in digitIndex : Integer;
        in suffixOne : Integer;
        in suffixTwo : Integer;
        in suffixThree : Integer;
        return code : Integer = 6257896 + (((((firstIndex * 36 + secondIndex) * 10 + digitIndex) * 27 + suffixOne) * 27 + suffixTwo) * 27 + suffixThree);
        assert constraint radixDomains { firstIndex >= 0 and firstIndex < 37 and secondIndex >= 0 and secondIndex < 36 and
            digitIndex >= 0 and digitIndex < 10 and suffixOne >= 0 and suffixOne < 27 and
            suffixTwo >= 0 and suffixTwo < 27 and suffixThree >= 0 and suffixThree < 27 }
        doc /* Indices are from PayloadCodebook's normalized alphabets; caller enforces
             letter-prefix/nonblank-suffix/no-embedded-blank constraints before use. */
    }
    requirement SharedWireMapping {
        doc /* ResultRecord has exact keys sequence,status,payload77,i3,n3,text,fields,
             start_frame,frequency_hz,snr_db, plus a_priori (Integer 1..6, the WSJT-X aN
             type of APrioriHypotheses) present only for an a-priori word, whose status is
             always decoded (#56 slice 5).
             LiveTimedResultRecord adds exactly
             period_start_utc anddt_seconds. Fields null unless decoded; text null unless
             decoded then<=80canonicalASCII; payload77exact77ASCIIbits; i3=0..7,
             n3nullunlessi3=0then0..7. Sequence/start are nonnegative safe integers below
             actual lifetime next_sequence/captured next_frame; finitefrequency200..3500,
             SNRnullorfinite[-60,60]. Record<=2048UTF8bytes, numericalcharge<=1024;
             oversizedpublication=>decode_limit with acceptedpartials. CallValue exactly
             {kind,text,hash_bits,hash_value}; concretecall uppercase1..13(nonstandard<=11),
             tokenCQ/DE/QRZ/modifier bothnullhashfields; hash exactwidth/value with text null,
             or the call without brackets when HashResolution filled it in (the message text
             then shows<CALL>).
             Every supported PayloadFields variant has all its defined keys, no extras:
             free_text/telemetry{type,value};standard{type,to,from,ack,exchange};
             rtty{type,tu,to,from,ack,report,exchange};dxpedition{type,first,second,hashed,report};
             field_day{type,to,from,ack,transmitters,class,section};
             nonstandard{type,full_call,hashed_call,hash_second,cq,roger};
             vhf{type,to,from,ack,report,serial,grid}. Semantic StandardExchange
             serial/state union members map to exact wire{kind,value}, not extra keys.
             A standard exchange packed as the grid square RR73 (32373, as some programs
             send RR73) is the roger {kind roger, value RR73}, never a grid (#55; WSJT-X
             grid_regexp excludes RR73); the text is unchanged. Nonstandard CQ ignores hash for presentation while preserving raw bits/hash.
             i3/n3 disambiguates source family. WstxRadioIO owns live lifecycle/page/error/
             cancellation/retention. No production file-decode route, test-source/raw-path
             command or browser offline-decode action is implied by numerical fixtures. */
    }
    attribute def CallValue {
        attribute kind : CallKind;
        attribute text : String[0..1];
        attribute hash_bits : Integer[0..1];
        attribute hash_value : Integer[0..1];
        doc /* Exact wire keys. call/token have text and null hash fields; hash has
             width10/12/22 and unsigned value below2^width, and text null (displayed<...>)
             or, in a station's live publication, the call HashResolution filled in, without
             brackets (displayed<CALL>; kind stays hash). No inverse guessing; no cache across
             profiles. */
    }
    requirement def HashResolution {
        doc /* CL-024-01 (#24 S1, reversing the earlier "display<...>, no station inverse"
             rule at the operator's approval of 2026-11-03): WSJT-X shows a hashed call as
             <CALL> once the full call is known (packjt77.f90 save_hash_call, hash10/12/22,
             hashmy10/12/22; one session-persistent table shared by receive and transmit),
             and so does the station. One table per station instance (profile process), kept
             for the process lifetime across jobs, bands and modes, never shared between
             profiles, never saved.
             Hash: ihashcall, the top m bits (10/12/22) of the low 64 bits of
             47055833459 * the base-38 value of the call's first 11 characters, blank
             padded (WstxTransmit::PackMessage uses the same function).
             Learning (save_hash_call): a call of at least 3 characters, brackets removed,
             sets calls10[h10] and calls12[h12] unless it is my call, and in the 22-bit list
             of at most 1000 entries replaces the call of an existing h22 entry, else is put
             first (the oldest entry falls out). Calls learned: my profile callsign at
             startup and whenever it changes; from each decoded record as it is published
             (after its own fill-in), the concrete 'from' call of a standard i3=1/2 message
             (with its /R or /P) and the full call of a nonstandard i3=4 message whose hash
             is the 'to' call (including CQ); a 'to' call or other families teach nothing
             (unpack77 nrx=1, not configured); from each transmit request the transmit owner
             accepts, every concrete call of a standard (its base call without /R or /P, as
             pack77_parse_type12_call stages it)/Field Day/RTTY message, the full call of a
             nonstandard CQ and every bracketed <CALL> (pack28/pack77_hash_index).
             Deliberate deviations: WSJT-X packs transmitted texts in its GUI process and
             feeds the decoder's table the DX call instead (ft8apset/dxcall13); the station
             learns from accepted requests. unpack77's DX-call rules (a 0.1 h10 equal to the
             DX call's hash shows the DX call; a nonstandard 'to' h12 equal to my h12 is my
             call when the full call is the DX call, even if calls12 holds another call)
             need the contact's DX call: the station sets the current contact's DX call
             on the table at each contact step (#24 S1b) and applies the nonstandard rule
             and the 0.1 rule (#24 S4a): a received 0.1 h10 equal to the 10-bit hash of that
             DX call (at least 3 characters) shows <DXCALL>, before and instead of the calls10
             entry of that hash (unpack77 n3=1, nrx=1, hashdx10).
             Fill-in (unpack77 nrx=1), per hashed slot: standard/Field Day/RTTY h22 from the
             22-bit list, and a standard 'to' h22 equal to my h22 is my call; nonstandard h12
             from calls12, and when that is empty and the hash is the 'to' call equal to my
             h12, my call (a nonstandard CQ shows no hash); DXpedition h10 from calls10;
             EU VHF 'to' h12 is my call when equal to my h12, else calls12, 'from' h22 from
             the list. A slot not found stays<...> with text null. Records published before
             a call was learned keep their text (no rewriting of history). The filled-in text
             reaches Band Activity, the QSO pane, MCP reads and the UDP Decode message
             (WstxUdp::OutboundRules) unchanged. A hashed slot stays kind hash. Contact
             selection and sequencing read a filled-in hash as its call (WstxContact::
             SelectDecodedRow, #24 S1b); the strategy, Call 1st, DXCC/worked-before and
             Pounce, which need a plain concrete call, keep treating it as no call. */
    }
    attribute def StandardExchange {
        attribute kind : ExchangeKind;
        attribute textValue : String[0..1];
        attribute numericValue : Integer[0..1];
        doc /* Semantic union, wire exactly{kind,value}: blank=>null, grid=>grid4,
             report=>integer-50..50, roger=>RRR/RR73/73. Internal semantic arm names
             are not extra wire fields; SharedWireMapping is the exact canonical JSON mapping. */
    }
    attribute def PayloadFields;
    attribute def FreeTextFields :> PayloadFields {
        attribute 'type' : String = "free_text";
        attribute value : String;
        doc /* type=free_text; 1..13 base42 chars, nonblank, trim trailing padding only. */
    }
    attribute def TelemetryFields :> PayloadFields {
        attribute 'type' : String = "telemetry";
        attribute value : String;
        doc /* type=telemetry; exact18uppercasehex, leading0..7, zero allowed. */
    }
    attribute def StandardFields :> PayloadFields {
        attribute 'type' : String = "standard";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute exchange : StandardExchange;
        doc /* type=standard; i3=1/R or2/P. Exact c28/grid/report canonical maps are PayloadCodebook and ReportCode;
             codes32400 and>32505 invalid, not fallback text. */
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
        doc /* type=rtty; exact wire exchange{kind,value} chooses serial0..7999 or
             exchanges8001..8171 (stateProvinceTable), reserved8000 invalid. report529..599 step10. Semantic
             union arm names are not extra JSON fields. */
    }
    attribute def DxpeditionFields :> PayloadFields {
        attribute 'type' : String = "dxpedition";
        attribute 'first' : CallValue;
        attribute 'second' : CallValue;
        attribute hashed : CallValue;
        attribute report : Integer;
        doc /* type=dxpedition,0.1; h10 exact, even report-30..32; firstRR73;secondhashreport. */
    }
    attribute def FieldDayFields :> PayloadFields {
        attribute 'type' : String = "field_day";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute transmitters : Integer;
        attribute 'class' : String;
        attribute section : String;
        doc /* type=field_day,0.3=>1..16,0.4=>17..32; classA..F, section1..86 inclusiveDX
             (sectionTable). S7=75WCF,76WI,84DX,85PE,86NB; 0/>86 invalid. */
    }
    attribute def NonstandardFields :> PayloadFields {
        attribute 'type' : String = "nonstandard";
        attribute full_call : CallValue;
        attribute hashed_call : CallValue;
        attribute hash_second : Boolean;
        attribute cq : Boolean;
        attribute roger : String[0..1];
        doc /* type=nonstandard,i3=4; full call<=11base38 chars, h12 exact; r2blank/RRR/RR73/73.
             CQ ignores hash for display, preserves typed bits; empty/out-of-domain call invalid. */
    }
    attribute def VhfFields :> PayloadFields {
        attribute 'type' : String = "vhf";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute serial : Integer;
        attribute grid : String;
        doc /* type=vhf,currenti3=5; hash12to/hash22from, report52..59, serial0..2047,
             mixed18,18,10,10,24,24 grid0..18662399=>AA00AA..RR99XX. */
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
            sequence >= 0 and sequence <= (900719925 * 10000000 + 4740991) and i3 >= 0 and i3 <= 7 and
            start_frame >= 0 and start_frame <= (900719925 * 10000000 + 4740991) and
            frequency_hz >= 200.0 and frequency_hz <= 3500.0
        }
        doc /* Exact shared live wire keys,<=2048UTF8bytes. payload77 exactly77binarychars; n3 only
             ifi3=0; text<=80ASCII and matching fields only when decoded, otherwise null.
             Supported0.0/.1/.3/.4/.5,1/2/3/4/5;0.2/.6/.7,6/7 unsupported. BadCRC never
             published. start indexes canonical12k first ramp/sync, never native orUTC.
             SNR null orfinite[-60,60], bounds labeled; full identity is page envelope. */
    }
    // #9 transmit preparation; detailed contract in WstxTransmit.
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
