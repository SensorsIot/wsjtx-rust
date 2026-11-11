package WstxOfflineDecode {
    private import ScalarValues::*;
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
    attribute def ModemPublicationKey {
        attribute payload77 : String;
        attribute startFrame : Integer;
        attribute frequencyHz : Real;
        attribute reservedBytes : Integer;
    }
    item def ModemHistoryState {
        attribute mode : Mode;
        attribute liveHistory : Boolean;
        attribute lastWindowOrigin : Integer[0..1];
        attribute keys : ModemPublicationKey[0..2048];
        attribute retainedBytes : Integer;
        assert constraint boundedBytes { retainedBytes >= 0 and retainedBytes <= 2097152 }
        doc /* Puremodemcontext,nosource/jobidentity/result-ring/wiresequenceauthority.
             DecodeState::new(mode)=finite numericaltestutility,lifetimekey/bytecaps.
             DecodeState::new_live(mode)=continuousreceive,boundedactivehistory.
             Mode/policyimmutable; available_count()=retainedkeys,encoded_bytes()=storedcharges.
             Livegettersnevermanagerwirecount/cursor. SharedwindowAPI/result/errortypesunchanged.
             EachkeyretainsitsoriginalcompactNumberedJSONcharge; livechargeuses
             sequence9007199254740991(16digits),finiteutilityusespublicationordinal.
             Record<=1024bytes,keys<=2048,totalcharges<=2MiB; managerownsactualsafesequence
             andindependent2048/2MiBpublicring. Callernewcontextonjob/source/gap/historyreset. */
    }
    action def PrepareModemWindow {
        in history : ModemHistoryState;
        in sourceWindowOrigin : Integer;
        out preparedHistory : ModemHistoryState;
        doc /* UpdatesSAMEcaller-ownedinstance,noadditionalcache/worker/source.
             Afterwindowinputvalidation, liveorigin<lastacceptedorigin=>InvalidSamples
             withoutstatechange; equaloriginallowed. Otherwise STRICTLYretirekey.startFrame
             <max(0,sourceWindowOrigin-symbolFrames/2),subtractexactstoredreservedBytes,
             thenrecordlastWindowOrigin. Retainboundarykeysforhalf-symboloverlapdedupe/SIC.
             Finiteutilityperformsnoretirementandkeepslifetime2048/2MiBbehavior.
             Allhistoryinsideexisting64MiB; callbackpartialsretainedonlaterDecodeLimit. */
    }
    attribute def Limits {
        attribute rateHz : Integer = 12000;
        attribute historyFrames : Integer = 360000;
        attribute sourceBlocks : Integer = 2;
        attribute windowFrames : Integer = 360000;
        attribute advanceFrames : Integer = 180000;
        attribute workerBytes : Integer = 67108864;
        attribute processDeltaBytes : Integer = 100663296;
        attribute workersPerStation : Integer = 1;
        attribute pendingJobs : Integer = 0;
        attribute records : Integer = 2048;
        attribute encodedRecordStoreBytes : Integer = 2097152;
        attribute recordBytes : Integer = 1024;
        attribute pageBytes : Integer = 1536;
        attribute pageRecords : Integer = 1;
        attribute pollMs : Integer = 2000;
        attribute quantumMs : Integer = 50;
        attribute cancelReleaseMs : Integer = 250;
        attribute statusDisplayMs : Integer = 2000;
        attribute candidateCap : Integer = 256;
        attribute rawMaximumBound : Integer = 661758;
        attribute complexTransformBound : Integer = 838992;
        attribute recoveryInformationRank : Integer = 91;
        attribute fecIterations : Integer = 30;
        attribute recoverySums : Integer = 2;
        attribute subtractionPasses : Integer = 3;
        attribute subtractions : Integer = 200;
        attribute minFrequencyHz : Real = 200.0;
        attribute maxFrequencyHz : Real = 3500.0;
        attribute costasThreshold : Real = 2.0;
        attribute maxHardDisagreements : Integer = 36;
        attribute ft8PadBeforeFrames : Integer = 24000;
        attribute ft8PadAfterFrames : Integer = 7680;
        attribute weakSnrDb : Real = -25.0;
        attribute weakSnrMaxCostasHits : Integer = 10;
        attribute duplicateSubtractionSeparationHz : Real = 50.0;
        attribute dataPointSteps : Integer = 2;
        attribute dataPointTweakHz : Real = 0.5;
        attribute retrySeparationHz : Real = 50.0;
        doc /* maxHardDisagreements applies to FT8 only (ft8b); FT4 (ft4_decode) has none.
             #56 slice 3: costasThreshold 2.0 (was 2.7; jt9 sync8 syncmin 1.3 relative to its
             40th-percentile baseline admits these frames), subtractions 200 per window (was 32;
             jt9 subtracts every decode, MAX_EARLY 200). ft8Pad*, weakSnr* and
             duplicateSubtractionSeparationHz: see Ft8PaddedResidual and the aggregate.
             #56 slice 4: dataPoint* see Ft8DataPoint; retrySeparationHz see the aggregate
             (Ft8RetryOverlapped). */
    }
    attribute def ModeParameters {
        attribute mode : Mode;
        attribute symbolFrames : Integer;
        attribute hopFrames : Integer;
        attribute symbolCount : Integer;
        attribute syncCount : Integer;
        attribute gaussianBT : Integer;
        attribute timeToleranceFrames : Integer;
        attribute frequencyToleranceHz : Real;
        assert constraint exactParameters {
            (mode == Mode::ft8 and symbolFrames == 1920 and hopFrames == 480 and
             symbolCount == 79 and syncCount == 21 and gaussianBT == 2 and
             timeToleranceFrames == 240 and frequencyToleranceHz == 1.0) or
            (mode == Mode::ft4 and symbolFrames == 576 and hopFrames == 144 and
             symbolCount == 105 and syncCount == 16 and gaussianBT == 1 and
             timeToleranceFrames == 144 and frequencyToleranceHz == 3.0)
        }
    }
    attribute def Settings { attribute mode : Mode; }
    item def DecodeJob :> WstxRecordingReceive::ReceiveJob {
        attribute :>> kind = WstxRecordingReceive::ReceiveKind::live;
        attribute settings : Settings;
        attribute available_count : Integer;
        attribute search_limited : Boolean;
        assert constraint boundedProgress {
            processed_frames >= 0 and processed_frames <= (900719925 * 10000000 + 4740991) and
            available_count >= 0 and available_count <= 2048
        }
        doc /* Existing station receive-job authority, kind=live with immutable mode.
             One import OR recorded spectrum OR continuous receive; no queue.
             Source-relative FT8/FT4 windows, reliable live ring and epoch rules12.8.
             Numerical recorded fixtures have no production receive operation. */
    }
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
             (WstxUdp::Decode) unchanged. A hashed slot stays kind hash. Contact
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
    item def LiveTimedResultRecord :> ResultRecord {
        attribute period_start_utc : String[0..1];
        attribute dt_seconds : Real[0..1];
        doc /* Live-only manager extension4.7.4/12.8, native Decode unchanged.
             Both null without correlated source timing; otherwise nearest nominal
             period and signed relative seconds via WstxRadioIO::RelativeDecodeTiming.
             Existing2048-byte live record cap and stricter1024-byte modem cap remain. */
    }
    item def ResultPage {
        attribute v : Integer = 1;
        attribute correlation : WstxRecordingReceive::Correlation;
        attribute mode : Mode;
        attribute 'state' : WstxRecordingReceive::ReceiveState;
        attribute error : WstxRecordingReceive::ErrorCode[0..1];
        attribute search_limited : Boolean;
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute available_count : Integer;
        attribute 'next' : Integer;
        attribute more : Boolean;
        item records : LiveTimedResultRecord[0..16];
        attribute latest_decode : WstxRadioIO::LatestDecodePeriod[0..1];
        assert constraint pageCursor { first_sequence >= 0 and next_sequence >= first_sequence and next_sequence <= (900719925 * 10000000 + 4740991) and available_count == next_sequence - first_sequence and available_count <= 2048 and 'next' >= first_sequence and 'next' <= next_sequence }
        doc /* Exact12.8 live envelope<=16384bytes,record<=2048bytes; Thinlimit1/page3072.
             Each record sequence<next_sequence,start_frame<actually captured next_frame.
             cursor<first=>410cursor_expired,cursor>next=>400,cursor==next=>empty.
             No file decode operation/snapshot/page endpoint. */
    }
    attribute def Ft8CarrierSearchPolicy {
        attribute minimumCarrierHz : Real = 200.0;
        attribute maximumCarrierHz : Real = 3500.0;
        attribute internalToneSpacingHz : Real = 6.25;
        attribute requiresKnownCarrier : Boolean = false;
        attribute requiresKnownStartTime : Boolean = false;
        attribute requiresCarrierOnToneGrid : Boolean = false;
        attribute retainsPerCandidateFrequencyAndTiming : Boolean = true;
        attribute refinementHalfRangeHz : Real = 2.5;
        attribute refinementStepHz : Real = 0.5;
        doc /* Search each station independently within the inclusive carrier band.
             The internal6.25Hz tone spacing does not fix a station's lowest-tone
             offset to multiples of6.25Hz or a shared transmitter-frequency grid.
             Finite receiver search steps approximate arbitrary carrier offsets;
             existing selection bounds and1Hz/240-frame FT8 tolerances remain.
             Ft8FineSynchronization defines finer carrier/time search;
             SymbolTransformGrid defines the coarse search. */
    }
    calc def CostasRatio {
        in tones : Integer;
        in expectedPower : Real;
        in otherPower : Real;
        return ratio : Real = (tones - 1) * expectedPower / otherPower;
        doc /* Call onlywhenotherPower>0; bothzero rejects, positive/zero outranksfinite.
             Require>=costasThreshold (2.0); zero-basedFT8sync0..6/36..42/72..78,FT4sync1..4/34..37/67..70/100..103.
             Localmaxhalf-symbol/half-tone, ties scoredesc/freqasc/timeasc. */
    }
    attribute def ComplexCoefficient {
        attribute re : Real;
        attribute im : Real;
        doc /* Runtime complex-f32, eight bytes, shared Fourier convention. */
    }
    item def SymbolTransformGrid {
        attribute coefficients : ComplexCoefficient[0..838992];
        doc /* Same1920/576 transforms and two shifted frequency grids retain complex values.
             Complete30swindow:747*1080FT8 or2497*336FT4 coefficients. Raw start/frequency
             grid <=435*1057FT8 or2081*318FT4=661758.
             ThisgridisFT8coarse/rectangularSNR; FT4detectioninsteadusesFt4FrequencyCandidates
             andone4162*9timinggrid/frequency. ItsrectangulargridisSNR-only. Priority heap and suppression bitmap,
             checkpoint visits; no quadratic all-pairs suppression. All storage inside64MiB. */
    }

    item def ModemSampleWindow {
        attribute mode : Mode;
        attribute sourceWindowOriginFrame : Integer;
        attribute samples : Real[0..360000];
        attribute subtractionPass : Integer;
        assert constraint windowPosition { sourceWindowOriginFrame >= 0 and sourceWindowOriginFrame <= (900719925 * 10000000 + 4740991) }
        assert constraint passRange { subtractionPass >= 0 and subtractionPass <= 2 }
        doc /* PRIVATEboundedcanonicalf32window,NOTa4096-framecaptureSampleBlock/newsource.
             Sharedreceiveowneraccumulatesvalidatedcanonicalblocksandprovidesthiswindow;
             origin/modepreserved,source/job/boot/generationauthorityremainoutsidepuremodem.
             Originalwindowimmutable; worker-ownedresidualcopyhasSAMEorigin/mode/length.
             L=samplescount. LiveFT8<=360000frames/FT4<=180000;finiteutility<=360000.
             No gaps fabricated; the only padding is Ft8PaddedResidual's private zeros (#56).
             Allhistory/windows/residuals/FFTs inside64MiB. */
    }
    action def Ft8PaddedResidual {
        in source : ModemSampleWindow;
        out residual : Real[0..360000];
        doc /* #56 slice 3, after jt9 sync8 (lags -62..+62, DT -2.5..+2.5 s) and ft8b, which
             read symbols outside the buffer as zero. When L+24000+7680<=360000 the FT8
             worker-owned residual is 24000 zero frames (2.0 s), the L window frames, then
             7680 zero frames (0.64 s); otherwise no padding. Search, band limit, fine
             synchronization, metrics, channel decode, known-word fit and subtraction run on
             these padded coordinates exactly as on an unpadded window, so a frame that runs
             past either window edge (its missing symbols zero) is found, verified and
             subtracted like any other. It is published only when it starts no earlier than
             half a symbol (960 frames) before the window and ends no later than half a symbol
             after it; its reported canonical start is window origin + padded start - 24000,
             floored at 0, and its SNR is measured on the window frames at max(start, window
             start). A frame outside that tolerance is subtraction-only: never published,
             never a record. The padding is reset to zero after each pass's subtractions, so
             it never carries residual energy; the original window stays immutable. FT4 has
             no padding. */
    }
    attribute def Ft8PhysicalLimits {
        attribute inputRate : Integer = 12000;
        attribute maxInputFrames : Integer = 360000;
        attribute longFftUnit : Integer = 192000;
        attribute longFftMax : Integer = 384000;
        attribute downsample : Integer = 60;
        attribute shortFftMax : Integer = 6400;
        attribute basebandRate : Integer = 200;
        attribute samplesPerSymbol : Integer = 32;
        attribute firstTimePoints : Integer = 21;
        attribute firstTimeRadius : Integer = 10;
        attribute frequencyPoints : Integer = 11;
        attribute frequencyStepHz : Real = 0.5;
        attribute finalTimePoints : Integer = 9;
        attribute finalTimeRadius : Integer = 4;
        attribute requiredCostasHits : Integer = 9;
        attribute totalCostasSymbols : Integer = 21;
        attribute metricFamilies : Integer = 5;
        attribute metricScale : Real = 2.83;
        attribute channelIterationsPerFamily : Integer = 30;
        attribute recoverySumsPerFamily : Integer = 2;
        attribute hardDisagreementMax : Integer = 36;
        attribute filterRadius : Integer = 2000;
        attribute filterTaps : Integer = 4001;
    }
    item def ComplexBasebandCoefficient { attribute realPart : Real; attribute imaginaryPart : Real; }
    enum def PhysicalMetricFamily { enum single; enum pair; enum triple; enum normalizedSingle; enum strongest; enum quadruple; }
    item def PhysicalLlrFamily { attribute family : PhysicalMetricFamily; attribute llrZeroPositive : Real[174]; }
    item def PhysicalFinePoint {
        attribute sourceStartFrame : Integer;
        attribute carrierHz : Real;
        attribute syncPower : Real;
        attribute hardCostasHits : Integer;
    }
    calc def Ft8MetricDifference {
        in maxBitOne : Real;
        in maxBitZero : Real;
        return raw : Real = maxBitOne - maxBitZero;
    }
    calc def Ft8ChannelPolarity {
        in raw : Real;
        in populationSigma : Real;
        return llrZeroPositive : Real = -2.83 * raw / populationSigma;
        doc /* Sigma strictlypositive/finite. Perfamily m=sumraw/174,q=sumrawSquared/174;
             sigma=sqrt(q-m*m) ifpositive,else sqrt(q). NOmean subtraction.
             Zerowidth/nonfinitefamily suppliesnoword; no duplicateFEC afterfamily5. */
    }
    action def Ft8BandLimit {
        in source : ModemSampleWindow;
        in currentPass : Integer;
        in carrierHz : Real;
        out baseband : ComplexBasebandCoefficient[0..6400];
        out centerBinHz : Real;
        doc /* Pinned0f7d592 ft8_downsample adaptation. L=currentpassframes;
             N1=192000*ceil(L/180000)<=384000,N2=N1/60,df=12000/N1.
             i0=round(f0/df),ib=max(1,round((f0-9.375)/df)),it=min(N1/2,round((f0+53.125)/df)).
             Sharedcachednegative-signunnormalizedlongFFT rebuiltwhenresidualchanges.
             Maporiginalbin i to(i-i0)modN2. T=round(6.25/df),K=it-ib+1,j=i-ib.
             Lowtaperj0..T:.5*(1+cos(pi*(T-j)/T));hightaperjK-1-T..K-1:
             .5*(1+cos(pi*(j-(K-1-T))/T));interior1.
             UnnormalizedpositiveinverseFFT,scale1/sqrt(N1*N2),200complexsamples/s.
             Actualmixedcenter=i0*df; everytrial/reportaccountsforit. L is the
             Ft8PaddedResidual length; frames may extend into its zero padding (#56), never
             beyond it. Sharedplanned/scalarRustFFT6.4.1,
             sameconventions/cacheowner; real/complex64transform/metric/convolutionsums
             overcanonicalfloat32input, finalLLRfloat32; allstoragewithin64MiB. */
    }
    action def Ft8FineSynchronization {
        in source : ModemSampleWindow;
        in coarseStartFrame : Integer;
        in coarseCarrierHz : Real;
        out fine : PhysicalFinePoint[0..1];
        doc /* CoarseCostasratio>=costasThreshold (2.0)/currentgrid/suppression/order unchanged.
             UseFt8BandLimit; P(b,d)=sumover21Costassymbolsabs(sumj0..31
             z[b+32*s+j]*exp(-i2pi*(tone_s/32+d/200)*j))Squared.
             Independentsymbolphases. Firstb=round(coarseStart/60)+[-10..10],d0;
             thenfrequencytweaks[-2.5..2.5]step.5atbestb; rebuildatbestcarrier;
             finalb=bestb+[-4..4],d0. Descendingpower,tiesascendingfrequency/start.
             Everypointcomplete151680framesinsidethe Ft8PaddedResidual/carrier200..3500inclusive.
             Outputcanonicalstart60*b includesramp,notGUI DT/UTC.
             FFT32eachsymbol,hardtone=largestabsbin0..7,tieslower;>=9/21Costashits.
             QualifyBEFORE256cap,257th=>searchLimited. Post-refinementcanonicalstarts:
             b=floor(s/60+.5),nonnegativehalftiesUP;clamp0..floor((L-151680)/60).
             RechecktoneevidenceatnearestCOMPLETEbasebandorigin/finalcarrier (zeros of Ft8PaddedResidual count as evidence of no tone).
             PRESERVEreportedcanonicalstart s; mappingonlyphysicalguardbeforepublication/SIC.
             NOcrosssymbol/blockfractiongateforFT8. */
    }
    action def Ft8DataPoint {
        in source : ModemSampleWindow;
        in fine : PhysicalFinePoint;
        out alternative : PhysicalFinePoint[0..1];
        doc /* #56 slice 4. Used only when no metric family (unassisted or CQ a-priori) of
             the fine point yields an accepted word. Over carriers fine+{-0.5,0,+0.5} Hz
             (dataPointTweakHz) and baseband origins b=fine/60+[-2..2] (dataPointSteps, 5 ms),
             each point complete inside the Ft8PaddedResidual and carrier 200..3500: Ft8BandLimit
             rows as for the metric families; energy = sum over the 79 symbols of the Costas
             symbol's known-tone power, or the data symbol's largest tone power. The highest
             energy wins; ties keep the first point in carrier-then-origin order. If it differs
             from the fine point, Ft8ObserveMetricFamilies runs once more there, physical gate
             included, and an accepted word continues from that point (known-word refinement,
             physical check, SNR, subtraction) exactly as a word of the fine point would.
             Rationale: the Costas-only sync power sees 21 of 79 symbols; next to an
             interferer it can settle just outside the region where the word decodes. ft8b
             has no such step; it only adds words, each under every later check. */
    }
    action def Ft8ObserveMetricFamilies {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        out families : PhysicalLlrFamily[5];
        doc /* Pinnedft8b unassistedimetric1. C[k,t]=FFT32symbol[k][t]/1000,t0..7.
             Gray[0,1,3,2,5,6,4,7],MSBfirst. Each29datahalfstarts7/43(zerobased).
             n1/2/3,k0,n,2n..<29; v0..8^n-1 selectsnGraytones; S=abs(sumCselected).
             EndgroupsKEEPactualfollowingsynccoefficient. Bitindexhalf*87+3*k+bit,
             storeonlyindex<174; secondhalfoverwritesitsownpositions.
             A/B/C=Ft8MetricDifferenceperbitforsingle/pair/triple. D=A/max8S,zeroifmax0.
             E=largestabsoluteRAW A/B/Cperbit,tiesA/B/C. FormEbeforeanynormalization.
             Normalizeeach174elementfamilyasFt8ChannelPolarity,NOmean subtraction.
             No callsign/contact/semanticprior here; the only a-priori bits are the
             APrioriHypotheses passes. No currentFT4neighborlikelihoodapplies. */
    }
    item def APrioriContext {
        attribute myCall : Integer[0..29];
        attribute dxCall : Integer[0..29];
        attribute qsoProgress : Integer;
        attribute rxHz : Real;
        attribute txHz : Real;
        attribute cqOnly : Boolean;
        attribute apWidthHz : Real = 50.0;
        attribute lowConfidenceQuality : Real = 0.17;
        attribute cqOnlyAfterSeconds : Integer = 300;
        doc /* #56 slice 5. The station's a-priori context of one live decode window, set on
             the modem state before the window like its period start, so the decode set
             depends only on the window and this context (CL-057-02 in-order replay holds).
             myCall = payload bits 0..28 (c28 and /R flag) and dxCall = bits 29..57 of the
             standard message "MyCall DxCall RRR" packed from the selected profile callsign
             and the current contact's dx_call (WSJT-X ft8apset: i3=1 and an exact round
             trip required, else neither; without a DxCall the dummy KA1ABC packs MyCall and
             dxCall is absent). Deliberate departure: a nonstandard (compound) MyCall that
             ft8apset would pack hashed as <MyCall> gives no myCall here (types 1 only). qsoProgress = WSJT-X nQSOProgress from the contact state:
             calling/idle/cancelled 0, replying 1, report 2, roger_report 3, rogers 4,
             signoff/completed 5. rxHz/txHz = the contact Rx/Tx audio frequencies.
             cqOnly (lapcqonly) = for the last 300 s no contact tick saw the station
             transmitting, tuning or with Enable Tx on (WSJT-X m_dateTimeLastTX, refreshed
             while m_transmitting, m_auto or m_tune); true from start until then. A file decode has no
             myCall/dxCall (CQ hypothesis only). */
    }
    action def APrioriHypotheses {
        in context : APrioriContext;
        in families : PhysicalLlrFamily[0..5];
        in carrierHz : Real;
        out hypotheses : PhysicalLlrFamily[0..8];
        doc /* #56 slice 5, WSJT-X 3.3.0-beta5 ft8b/ft4_decode, ncontest=0. Tried only after
             every unassisted family of a candidate failed. Types: 1 CQ ??? ???, 2 MyCall ??? ???,
             3 MyCall DxCall ???, 4/5/6 MyCall DxCall RRR/73/RR73 (tails ir=0, grid 32402/
             32404/32403, i3=1). Types per qsoProgress (naptypes): FT8 0:[1,2] 1,2:[2,3]
             3,4:[3,4,5,6] 5:[3,1,2]; FT4 0:[1,2] 1,2:[2,3] 3,4:[3,6] 5:[3,1,2]; cqOnly:[1].
             Skipped: type>=2 without myCall; type>=3 without dxCall or when the carrier is
             more than apWidthHz from rxHz and (FT8 only) from txHz. Fixed bits: type1 bits
             0..28 = CQ token (c28=2, ipa=0); type2 0..28 = myCall; type3 0..57 = myCall,
             dxCall; types 4..6 all 77. FT8 types 1..3 also fix 74..76 to i3=1; FT4's do
             not, and FT4 fixed bits are scrambled with ft4XorMask. FT8: each type on the
             single then the triple family, fixed at 1.1 times that family's largest |LLR|;
             FT4: each type once on the quadruple family, fixed at 1.1 times the single
             family's largest |LLR|. Each through Ft8ChannelDecode with those bits fixed;
             first accepted wins. Acceptance: not all-zero, hard disagreements<=36 (both
             modes), a payload that unpacks with status decoded (WSJT-X drops an a-priori word
             that does not unpack and tries the next pass), and, for every type except FT8
             type 1, WSJT-X's confidence
             qual = 1-(nharderrors+dmin)/60 >= lowConfidenceQuality, dmin = sum of |LLR|
             over the bits the word disagrees with. Deliberate departure: WSJT-X publishes a
             low-confidence a-priori word marked '?' (and FT4 any hard-error count); the
             station acts on decoded rows, so it does not publish one. FT8 type 1 keeps the
             slice-2 acceptance (hard disagreements<=36). The published record carries the
             type as a_priori (WSJT-X aN); an unassisted word has no a_priori key. */
    }
    action def Ft8DecodeMetricFamilies {
        in families : PhysicalLlrFamily[5];
        out accepted : Boolean;
        out channelWord : Integer[174];
        out payload77 : Integer[77];
        doc /* Fiveorderedfamilies, each through Ft8ChannelDecode. Accept a word with
             hard disagreements (nharderrors)<=36 that is not the all-zero codeword (ft8b,
             #56); publishedH+CRCmandatory. Avalidwordfailingacceptance
             DOESNOTstoplaterfamilies. Firstacceptedwordwins. Only when all five fail, two
             the APrioriHypotheses passes of the window's APrioriContext run (#56 slices 2 and 5);
             no further fallback decode. An a-priori word's record carries a_priori (1..6);
             a low-confidence a-priori word is never published (hence WstxUdp::Decode
             lowConfidence).
             Unsupported/invalidsourceinterpretationremainstypedobservation,notdropfilter.
             Sameworker,cancel/servicecheckpoints<=50ms,terminalrelease<=250ms. */
    }
    action def Ft8ChannelDecode {
        in llrZeroPositive : Real[174];
        out channelWord : Integer[174];
        out hardDisagreements : Integer;
        doc /* Adapted WSJT-X decode174_91 (maxosd=2, norder=2) and osd174_91 (Keff=91,
             ndeep=2), shared by FT8 and FT4 (#56). Sum-product belief propagation, flooding
             schedule: check message 2*platanh(product of tanh(extrinsic/2)), WSJT-X
             piecewise-linear platanh saturating at 7. Iterations 0..30; a word whose syndrome and CRC are zero ends it;
             stop early after iteration>=10 when unsatisfied checks>15 did not decrease for 5
             iterations. Keep the cumulative bit sums of iterations 1 and 2. On BP failure
             run ordered statistics on each kept sum in turn: order the 174 bits by
             decreasing |sum| (ties in reverse index order), Gaussian-eliminate the systematic
             (174,91) generator with whole-row operations (CRC bits free; the pivot of
             position id is searched in positions id..110, i.e. within the first k+20), re-encode the hard decisions of
             the 91 most reliable bits, then try every single (pair) flip of them whose
             re-encoded first 40 parity bits differ from the hard decisions in at most 9 (8)
             places; keep the candidate of least reliability-weighted distance. The result
             must pass H and CRC. hardDisagreements counts bits that disagree with the
             channel LLR signs (BP word) or with the kept sum's hard decisions (OSD word).
             Deliberate deviations: tanh by a rational approximant within 1e-4; an OSD word
             with zero disagreements is accepted (decode174_91 requires >0); every word
             must pass H and CRC (WSJT-X checks CRC only).
             A-priori (fixed) bits keep their channel LLR in BP and are never flipped.
             Cancellation is checked every BP iteration and every OSD flip position. */
    }
    action def Ft8SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[151680];
        out residual : ModemSampleWindow;
        doc /* Adaptedsubtractft8, boundedCENTEREDzerobasedproductdefinition:
             c[k]=x[start+k]*conj(reference[k]),zerooutsideframe;
             h[j]=cos(pi*j/4000)^2/sum[a=-2000..2000]cos(pi*a/4000)^2,j=-2000..2000.
             y[k]=sumj h[j]*c[k-j], exact linear (zero outside frame): with
             h~(1+cos(pi*j/2000))/2, y = constant plus two cosine-modulated window
             sums of exact prefix sums, O(frame) per subtraction, no FFT padding (#47).
             One sweep keeps the prefix sums 2000+1 frames ahead in a ring of at least
             2*2000+2 entries; every window sum uses the same exact prefix values (#57).
             Atedge-distancea0..2000 dividebyavailableweight sumj[-2000..a]h[j].
             Subtract2*Re(reference[k]*y[k])ONLYwithinframe; originalsourceimmutable.
             <=3passes/200verifiedsubtractions, invalidatepassFFTafterresidualchanges.
             Directscalarconvolution/edgesareindependentoracle; no circularwrap.
             No additionalowner/provider/job/source orTXauthority. */
    }

    attribute def Ft4PhysicalLimits {
        attribute longFftUnit : Integer = 72576;
        attribute longFftMax : Integer = 435456;
        attribute downsample : Integer = 18;
        attribute basebandMax : Integer = 24192;
        attribute samplesPerSymbol : Integer = 32;
        attribute shapedSymbols : Integer = 105;
        attribute observedSymbols : Integer = 103;
        attribute firstFrequencyPoints : Integer = 9;
        attribute firstFrequencyStepHz : Integer = 3;
        attribute firstTimePoints : Integer = 4162;
        attribute firstTimeStep : Integer = 4;
        attribute frequencyFft : Integer = 2304;
        attribute frequencyHop : Integer = 576;
        attribute smoothBins : Integer = 15;
        attribute baselineSegments : Integer = 10;
        attribute baselinePercentile : Integer = 10;
        attribute baselineDegree : Integer = 4;
        attribute baselineLiftDb : Real = 0.65;
        attribute minFrequencyContrast : Real = 1.18;
        attribute finalFrequencyPoints : Integer = 9;
        attribute finalTimePoints : Integer = 11;
        attribute requiredToneHits : Integer = 8;
        attribute requiredSyncBits : Integer = 20;
        attribute minSyncMagnitude : Real = 1.2;
        attribute metricFamilies : Integer = 3;
        attribute rawBits : Integer = 206;
        attribute filterTaps : Integer = 1401;
    }
    item def PhysicalFrequencyPeak { attribute carrierHz : Real; attribute contrast : Real; }
    action def Ft4FrequencyCandidates {
        in source : ModemSampleWindow;
        out frequencies : PhysicalFrequencyPeak[0..1152];
        doc /* Pinnedgetcandidates4/ft4_baseline/nuttal_window/pctile/polyfit adaptation.
             FFT2304/hop576overEVERYcompleteORIGINALwindow,inputx*window/300.
             Periodicwindowj0..2303:.3635819-.4891775cos(2pi*j/2304)
             +.1365995cos(4pi*j/2304)-.0106411cos(6pi*j/2304).
             Averagepositive-binLINEARpowers, smooth15bins; retainedlinearbeforedbfit.
             df12000/2304,ia=round(200/df),ib=round((3500+31.25)/df).
             10integerfloorsegments,remainderexcludedfromfit. Percentile1basedindex
             clamp(floor(.10*segmentLength+.5),1,n),includealltiedvalues<=cutoff.
             BaselineinputUNSMOOTHEDaveragedpowers; <=1000lower-envelopepoints,
             equalweightquarticleastsquares,finitefullrank5;
             affinexscalingallowedasSAMEpolynomialspace. Baseline=10^((fitdb+.65)/10).
             Allzero/insufficient/singular/nonfinite/nonpositivebaseline=>nofrequencies.
             Individualzerobinsuseminpositivedb-120forfitonly; positivepowersneverfloored.
             ratio=original15-binmean/baseline;interiorlocalmaxratio>=1.18.
             delta=.5*(left-right)/(left-2center+right),0ifden0;
             carrier=(bin+delta)*df-31.25,contrast=center-.25*(left-right)*delta.
             Retain200..3500inclusive. Endpointe200/3500:u=(e+31.25)/df,j=flooru,a=u-j;
             interpolateAFTERdivision rEnd=ratio[j]+a*(ratio[j+1]-ratio[j]);a0=>ratio[j]only.
             Exactendpointtrialiff rEnd>=1.18; no polynomial/rawpowerinterpolation.
             Ordercontrastdesc/carrierasc; noQSO/semanticpriority. Nocandidatemadefrompadding.
             Sharedworker/FFTdependency/scratch,<=50msquantum/64MiB. */
    }
    action def Ft4BandLimitAndFineSync {
        in source : ModemSampleWindow;
        in coarseCarrierHz : Real;
        in priorFine : PhysicalFinePoint[0..256];
        out fine : PhysicalFinePoint[0..256];
        out searchLimited : Boolean;
        doc /* The outputfinecontainsADDITIONALpoints only. DedupagainstpriorFineAND
             currentfinebeforecounting; size(priorFine)+size(fine)<=256 globally.
             Nextdistinctqualifiedpointwouldexceedcap=>searchLimited,notperfrequencyreset.
             Multipletemporalframesare retained inthispluraloutput.
             Pinned0f7d592 ft4_downsample/sync4d/driver boundedlocaladaptation.
             N1=72576*ceil(L/72576)<=435456,N2=N1/18,df=12000/N1,baud=12000/576.
             T=floor(.5baud/df),F=floor(4baud/df),S=floor(baud/df),i0=round(f0/df).
             PeriodicW[j]:j0..<T .5*(1+cos(pi*(T-1-j)/T));jT..<T+F 1;
             jT+F..<2T+F .5*(1+cos(pi*(j-T-F)/T));else0.
             Signedbinb mapspositiveoriginali0+b if0..N1/2,weightW[(b+S)modN2]/N2.
             Positiveunnormalizedinverse,normalizewindowbypositivefiniteRMS.
             Actualcenteri0*df explicitlyaccounted;666.666...Hz/32samplespersymbol.
             Ft4FrequencyCandidates suppliesONLYcarrierconfidence,notcoarsetimeprior.
             FirstCostasoriginb=32..floor((L-60480)/18)+32 step4,includeoffgridlastendpoint.
             Scorefourblocksatb+{0,33,66,99}*32;each64EVERYSECOND FILTEREDsamples
             correlatesrectangularCostas4tonepattern/frequencytweak,sum4magnitudes/64,
             independentblockphases. Firstd[-12..12]step3 atALLcompleteoriginpositions.
             Visit3x3localmaxima>=1.2descendingpower,tiesfrequency/time,suppresshalfsymbol
             ANDhalftoneforRAWgridpoints. ThenbestD+[-4..4]step1,bestB+[-5..5]step1.
             AFTERrefinementANDphysical8tone/20bitqualification,suppresscompeting
             completewaveforms iff abs(startDifference)<60480 ANDabs(carrierDifference)<=12000/576/2.
             Halfopensupports:exactlyadjacent60480remaineligible. Firstqualifiedpoint
             inexistingfrequencycontrast/carrierthenpower/carrier/startvisitorderwins.
             FailedphysicalqualificationcreatesNOexclusion;comparepriorFine+currentfine
             acrossALLfrequencycandidatesbeforeglobalcount. FEC/payloaddoesnotinfluence
             selection; retainedpointkeepssupporteveniflaterFECfails. Resetallthese
             exclusionsatnewresidualpass. Explicitblind-windowstrongest-timingadaptation,
             notUTC/source-originpartitions,notliteralupstream3fixedsegments.
             Atmost4162time*9frequencycells/frequencycandidate,releasedbeforenext;
             precomputedtemplates/boundedservicecheckpoints. NoUTC/slot/time-powerprior.
             CompleteORIGINAL60480frames/carrier200..3500; outputstart18*(b-32)inclramp.
             FFT32at103symbolsstartinground(start/18)+32:>=8/16hardtonehits and>=20/32
             Grayhardbits,max1-max0,ties1. Physicalqualificationbefore256cap/257=>limited,
             andatfinalfullrateknown-wordmeasurementbeforepublication/subtraction:
             firstCostasb=floor(s/18+.5)+32,nonnegativehalftiesUP,preservereporteds;
             guardspansinsideORIGINALsupport. NOcross-block/groupfractiongate, no duplicateworker/cache/provider. */
    }
    action def Ft4ObserveMetricFamilies {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        out families : PhysicalLlrFamily[3];
        doc /* Pinnedget_ft4_bitmetrics,103complexFFT32symbols,fourtones,Gray[0,1,3,2].
             Families=single/pair/quadruple; n1/2/4,k0,n,2n...<=103-n;
             enumerate4^n coherentmagnitudes;max1-max0
             MSB-first2bits/tone,206rawbits/family. Pairbits204..205=single;
             fourbits200..203=pair,204..205=single (zerobased).
             NormalizeFULL206populationasFT8(no meansubtraction),thenextractinclusive
             ranges8..65/74..131/140..197=>174data,scale2.83/negateONCE.
             Threeorderedfamilies, each through Ft8ChannelDecode; accept any word that is
             not the all-zero codeword (ft4_decode has no hard-disagreement cap), H+CRC.
             Failedwordcontinues;
             no4thfallback except the APrioriHypotheses passes (#56 slice 5).
             Sourceunsupported/invalidstatusretained, no semanticprior. */
    }
    action def Ft4SubtractVerifiedFrame {
        in source : ModemSampleWindow;
        in point : PhysicalFinePoint;
        in reference : ComplexBasebandCoefficient[60480];
        out residual : ModemSampleWindow;
        doc /* Sameboundedcomplex-envelopeoperationasFt8SubtractVerifiedFrame,
             h[j]=cos(pi*j/1400)^2/sum[-700..700]cos(pi*j/1400)^2,j[-700..700],1401taps.
             Centeredlinearconvolution (same exact prefix-sum window sums, R700),
             NOedgeavailabilitycorrection.
             Referenceincludesramp,alreadycanonicalorigin,NOsecond-576frameadjustment.
             Originalsamplesimmutable,3passes/200verifiedsubtractions,passFFTinvalidated.
             Sharedpurewaveform/measurement/FFT/cancelownership,within64MiB. */
    }
    action def AdmitDecode {
        in source : WstxRecordingReceive::SourceDescriptor[0..1];
        in settings : Settings;
        out job : DecodeJob;
        doc /* Production12.8 live start only; selected-profile auth/Origin/schema,
             boot/generation/profile-revision and shared receive admission precede capture.
             Mode immutable. Source absent during opening before first provider ACK;
             no publication until acknowledged full tuple. Initialstart freshjob/gen,
             firstsourceACK samejob/gen;
             subsequent unknownepoch freshsource/job/gen beforeproviderACK and ring reset.
             Recorded waveforms are internal numerical/integration fixtures, no file API. */
    }
    doc /* Coarse search explicitly includes both200 and3500Hz even when off the uniform
         half-tone FFT grid. Evaluate exact off-grid endpoint power by direct quadrature;
         refine clipped to inclusive bounds. FT4mustnotround3500awayorrelax3Hzoracle. */
    action def AdvanceDecode {
        in block : WstxRecordingReceive::SampleBlock;
        in job : DecodeJob;
        out records : ResultRecord[0..2048];
        doc /* SharedreceiveownerassemblesModemSampleWindowfromcanonicalSampleBlocks;
             physicalalgorithmsconsumeTHATprivatewindow,notone4096-framecaptureblock.
             Purecanonical12kconsumer,noWAV/device/network/UTCaccess. LiveFT8<=30s/15sadvance,
             FT4<=15s/7.5sadvance;finiteinternaltestutilitywindow/historyunchanged.
             Live window schedule (#47, CL-007-05): with a correlated source UTC anchor the
             shared receive owner completes two windows per period at fixed source-counter
             residues of the advance: FT8 prompt +13.8 s/15 s of audio (DT -1.7..+0.66 s)
             and late +15.7 s/15 s (DT +0.2..+2.56 s); FT4 prompt +6.5 s/7.5 s (DT
             -1.5..+0.96 s) and late +7.9 s/7.5 s (DT -0.1..+2.36 s). Overlapping frames are
             deduplicated by the modem history. The late window arriving during the prompt
             decode waits in one slot until that decode completes; any other window arriving
             during a decode abandons it as an overrun (last_overrun names the newest skipped
             support). The residues come from the epoch's UTC anchor plus the measured
             capture-clock offset (CL-007-05): when it moved by more than 50 ms the residues
             are recomputed and each scheduled window's next completion moves by the signed
             correction of any size, staying the completion of the same UTC period (no
             wrap by a period). One moved into the past completes now; coinciding ones
             complete one after the other in schedule order (prompt, then late); each then
             returns to its grid, so none is dropped or repeated. A scheduled late window
             extends its period's view under the same id.
             Without a correlated anchor the counter grid (30 s/15 s, 15 s/7.5 s) applies.
             The modem reads no UTC.
             FT8coarseN1920/hop480/half-tone200..3500inclusive/endpoints;FT4N576/hop144
             noisegridseparatefromFt4FrequencyCandidates/Ft4BandLimitAndFineSync.
             FT8BandLimit/FineSynchronization/ObserveMetricFamilies/DecodeMetricFamilies;
             FT4BandLimitAndFineSync/ObserveMetricFamilies. Qualifiedcap256,257=>limited.
             FiveFT8orthreeFT4families; each Ft8ChannelDecode (BP<=30 + OSD ndeep2 on
             2 sums, rank91). FT8 hard disagreements<=36; never all-zero; H+CRC mandatory.
             APrioriHypotheses passes only (CQ, MyCall/DxCall per QSO state), no other hints/semanticdrop; physicalsyncguardsatfinalreportedcoordinates.
             Sharedfullrateknownword3gridmeasurement,mode-specificcomplexenvelopeSIC,
             <=3passes/200verifiedsubtractions; originalsimmutable/no weakrelativeenergystop.
             The last pass's verified frames are not subtracted: no later pass reads that
             residual (#57).
             SharedFFT/bandlimit/finesync/bitmetrics/channel/convolutionboundary,modeparameters;
             onecurrentmode/windowplan/scratchcache andcurrentpassFFT,droponepochreset;
             no globalmutablecommonblocks; residualchangeinvalidatesFFT.
             SharedRustFFT6.4.1planned/scalar/oneworker(itsparallelstagethreads:CL-057-02)/noqueue/source/cancelquanta<=50ms,
             serviceconversion/spectrum betweenquanta,release<=250ms. Allplans/grids/scratch
             within64MiB. Onepurewaveformowner7/futurereuse9,noTXauthority.
             Displayfixed0..3000Hzindependentofdecode200..3500; no sharedmodem/displayFFTplan.
             Dedupmode/payload/startwithinhalfsymbol,retainlaterrepeatedtransmissions.
             Within a window (#56 slice 3) a verified word whose payload and start (within half
             a symbol) repeat an earlier word of the window is skipped when its carrier is
             within 50 Hz of that word's; on a carrier more than 50 Hz away it is subtracted
             like ft8b (which subtracts before ft8_decode drops the duplicate message) but
             publication still follows the history dedup above, so it is not published twice.
             ft8b weak-word guard (nsync<=10 and xsnr<-25): an FT8 word whose final point has
             at most 10 of 21 hard Costas hits and whose unfloored MeasureFrame SNR is below
             -25 dB is rejected before the window's duplicate record, publication and
             subtraction. Deliberate deviation: ft8b subtracts such a word before rejecting
             it; the station does not. The guard needs a measured SNR, so it does not apply
             to a subtraction-only partial frame or a word without an SNR (carrier outside
             the baseline band, no baseline). FT8 frames run on Ft8PaddedResidual coordinates.
             Ft8RetryOverlapped (#56 slice 4): an FT8 candidate of a pass whose verification
             yields no word (Ft8DataPoint included) and which a frame subtracted in that pass
             overlaps (carriers within retrySeparationHz 50 Hz, starts less than one frame
             apart) is qualified again (Ft8FineSynchronization from its fine point) on the next
             pass's residual and, if it qualifies and no candidate of that pass lies within
             1 Hz and 120 frames of it, appended in order after the pass's own candidates; the
             256 cap counts it. Requalification runs in parallel and is replayed in order, so
             the decode set stays independent of the thread count (CL-057-02).
             Schema/history/source/job/epoch/resultauthorityunchanged; modelisnottestverdict. */
    }
    action def ReconstructGfskReference {
        in mode : Mode;
        in tones : Integer[79..105];
        in carrierHz : Real;
        out reference : ComplexBasebandCoefficient[60480..151680];
        doc /* Sharedpureprimitive:N1920/576,BT2/1,F=N*symbols,spacing12000/N.
             p(t)=(erf(c*(t+.5))-erf(c*(t-.5)))/2,c=pi*BT*sqrt(2/ln2),p0outsideabs(t)<2.
             offset[k]=sum_s tone_s*spacing*p((k+.5-(s+.5)*N)/N),exteriortones0.
             phi[k]=sum_m0..k 2pi*(carrier+offset[m])/12000,ADVANCEbeforeemission.
             R240/576,amp[k]=(1-cos(pi*k/R))/2 forfirstR,mirrorF-1-kforlastR,else1.
             Referenceamp*(cosphi+i*sinphi),samefitting/SICkernel,independentwaveformoracle.
             No TXauthority/extra encoderdependency/semanticprior. */
    }
    action def MeasureFrame {
        in block : ModemSampleWindow;
        out record : ResultRecord;
        doc /* Start canonicalframe nearest first ramp/sync. Frequency lowesttoneaudioHz.
             SNR on the WSJT-X 2500 Hz scale (#52), whole dB (round half away from zero).
             FT8 = ft8b xsnr2 as WSJT-X first reports it, from its early period buffer: the
             frame's period starts at the UTC period start when the receive clock
             establishes it (finite decodes: frame 0 + k*180000), else 0.5 s before the
             frame on a 0.5 s window grid; only that period's first 41*3456 frames are
             seen, later ones as zero. One baseline per period and pass serves its frames.
             xsig = sum over the 79 symbols of |1920-frame DFT at the decoded tone|^2/60
             (ft8_downsample's 32-point power); xbase = 1e-4 * the sync8 baseline at bin
             round(f/3.125 Hz): sum of the 92 Nuttall 3840-frame power spectra stepped 1920
             (window scaled to sum 12.8), in dB, quartic fit to the 10th-percentile lower
             envelope of 10 segments over 200..4000 Hz, +0.65 dB. SNR = 10log10(a)-27 with
             a = xsig/xbase/3e6-1 when > 0.1, else 0.001; floor -25.
             FT4 = ft4_decode: the pass's getcandidates4 contrast c (15-bin mean of the
             average spectrum over its ft4_baseline) at the largest of the 3 bins nearest
             decoded frequency+31.25 Hz, parabola-interpolated when a local maximum;
             10log10(c-1)-14.8, -21 when c <= 1, floor -21.
             No baseline or nonfinite => null; ceiling +60.
             Error<=240frames/1HzFT8,144frames/3HzFT4,<=3dBisolatedAWGN>=-15/-10.
             Known-codeword fit3fixedgrids:df1=6000/waveformFrames; stage1time+-N/4stepN/16,
             freq+-spacing/2stepdf1 includingoffgridendpoints; stage2time+-N/16stepmax(1,floor(N/128)),
             freq+-df1/2stepdf1/8; stage3time+-max(1,floor(N/128))step1,frequencyfixed.
             Complete/in-band only,EVERYsamptrimN/2ends. Actualfullratereal/quadratureGramG,
             b=[u.x,w.x],maximizeb^T*inverse(G)*b,tiesfreq/time. Rejectnonfiniteorrelative
             determinant<=1e-12; noquadratureorthogonalityassumption. Nounfilteredsubsampling:
              unrelatedcarriersmustnotaliasintocandidatequadratures. Samegridcoordinates/order
              andcandidate/pass/subtraction/FECcaps.
             Grid pruning (#47): each stage ranks its grid points by the decimated
             correlation with the current-pass candidate baseband (the band-limited
             transform of physical sync: carriers outside the band are filtered, never
             aliased), and scores only the 6/3/2 best-ranked points of stages 1/2/3 with
             the full-rate Gram above; the result is the full-rate maximum among them under
             the same tie rule. Without a candidate band every grid point is scored.
             finalamplitude/subtractionallsamples. No whole-frame phase rejection,
             ordinary+-2Hz/min drift andarbitraryinitialphase remaineligible.
             No dBFS/noiseless/crowded reference-SNR inference. */
    }
    action def PublishResults {
        in job : DecodeJob;
        in records : ResultRecord[0..2048];
        out page : ResultPage;
        doc /* Stationauthority rechecks fullidentity/generation beforeappend. Cancelinvalid
             beforeack; terminalonlyafterrelease<=250ms; retain marked partials onstop/failure.
             Newjob/source/restart invalidates oldpages/callbacks. Reliable2048/2MiB live ring;
             evictionadvancesfirst_sequence, lifetime safecountersneverreset within an epoch.
             SearchLimited=>failed/decode_limit+search_limited=true,acceptedpartialsretained;
             accepted cancellation has priority. No invented calls/exception strings.
             Browser onependingpage,Thinlimit1/starts>=4sbehindexplicitstatus; optional
             spectrum<=1/2s; two32kbitclients<=3000accountedB/s/direction,status<=2s.
             No automaticmutationreplay or browsermodem/clockauthority. */
    }
    action admitDecode : AdmitDecode;
    action advanceDecode : AdvanceDecode;
    action measureFrame : MeasureFrame;
    action publishResults : PublishResults;
    satisfy WstxRequirements::'CL-007-01' by admitDecode;
    satisfy WstxRequirements::'CL-007-02' by publishResults;
    satisfy WstxRequirements::'CL-007-03' by measureFrame;
    satisfy WstxRequirements::'CL-007-04' by advanceDecode;
    satisfy WstxRequirements::'CL-007-05' by advanceDecode;
    dependency admissionOwner from admitDecode to WstxArchitecture::physicalStation::backend::stations::receive;
    dependency calculationOwner from advanceDecode to WstxArchitecture::physicalStation::backend::stations::modes;
    dependency measurementOwner from measureFrame to WstxArchitecture::physicalStation::backend::stations::modes;
    dependency publicationOwner from publishResults to WstxArchitecture::physicalStation::backend::stations::web;
    dependency viewerOwner from publishResults to WstxArchitecture::physicalStation::frontend::browsers;
    package IndependentVerification {
        doc /* Verification intent; executable coverage is declared in WstxRequirements metadata. Cost2
             offlineWindowsPC, actualcandidate
             Rust/server/browser and independent fixtures/directmath/recordings/link model.
             No hardware/live service. Source and source_message are not decoded inversehashes.
             Missing/empty manifests fail. WstxRequirements retains the independent case expectations.
             Corpus2286:2000noise+160AWGN+80overlap+40offset+6silence/mismatch/CRCnegative;
             fieldboundary and supportedfamily vectors additional. Actual execution not claimed. */
        verification ft4 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* FT4exactpayload/CRC/H/105tones/GFSKallfamilies+boundaries; strong36/40@-10,
                 weak20/40@-13; overlapsboth18/20at2spacings,strong18/weak10at1spacing6dB;
                 official>=16/19matches notexhaustivetruth. Error144frames/3Hz,3dBstrongAWGN.
                 Continuoushistorybothmodes:>2048lifetimeverifiedcallbackswithadvancingorigins,
                 exacthalf-symbolboundarydedupe,strictolderretirement/exactstoredcharges,
                 equaloriginsallowed,backwardsrejectunchanged,newcontextgapreset;
                 privatekeys/bytesboundedandmanagerwirecursorsindependent.
                 Finitetestutilityunchangedlifetimecaps/partials.
                 SeparateCRCrecurrence/publishedtables/fixedvectors/independentsynthesis.
                 FullrateGramoracle:60480frames,k288..60191EVERYsample;
                 phase=2pi*f*(k+1)/12000+.4sin(2pi*((k+1)/12000)/.048),x=.6u-.8w.
                 f1499/1499.9/1500/1500.1/1501/2999/3000/3001Hz; independentf64Gram
                 yieldscoefficients.6/-.8,explained=sumx*x; candidatef32relativeerror<=5e-7.
                 Unrelatedcarrieroracle:same60480frames/trimmedsupport,f400/1000Hz,
                 t=(k+1)/12000,psi=.4sin(2pi*t/.048),u=cos(2pi*f*t+psi),w=sin(2pi*f*t+psi).
                 x=cos(2pi*(3000-f)*t-psi+.7),repeatwithx+.25u-.5w; float32storage.
                 Independentfullratescalar2x2Gramenergy; candidateerror<=5e-7*totalxenergy.
                 Unrelatedonlyfullratefraction<.001,stride4diagnostic>.999; latterMUSTNOT
                 determinegridordering. Mixedcoefficients/energyfollowindependentfullrateoracle.
                 Unfilteredstride4scoringnegativecontrolmustfail; unchangedgrids/caps/2286/14/recording/runtime/
                 cancellation/64MiBthresholds. Sameoracleappliestobothmodes' sharedfitkernel.
                 Rust/decoderfixture bindings are declared in WstxRequirements; no production encoder oracle. */
        }
        dependency ft4Case from ft4 to WstxRequirements::'TC-004-001';
        verification ft8 {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* FT8exactpayload/CRC/H/79tones/GFSKallfamilies+boundaries; strong36/40@-15,
                 weak20/40@-18; sameoverlapcounts; official>=12/14matches,22inheritedtexts
                 supplementaryonly. The shared known-wordfitkernel uses the SAME eight-frequency
                 FullrateGramoracle defined by ft4 above, with identical60480-frame phase/x formulas,
                 expectedcoefficients.6/-.8 andexplained=sumx*x within5e-7f32relativeerror.
                 Error240frames/1Hz,3dBstrongAWGN. Valid/RandTUvectors
                 retainedpositivesdespitereferencenondetection; no qualityscopeweakening. */
        }
        dependency ft8Case from ft8 to WstxRequirements::'TC-004-002';
        verification rejectionLifecycleResources {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-02'; verify WstxRequirements::'CL-007-04'; }
            doc /* 1000noise/modefourRMSplusinvalid/wrongmode/silence/goodFECbadCRC require
                 zeropublishedframes. Unsupported/invalidonlyinjectedvalidCRCframes, nopanic.
                 Repeatpayloadmultiset,time<=1frame,freq<=.2HzFT8/.5HzFT4. Cancelallphases,
                 stale/restart/busy/limits/strictHTTP/realbrowser/twopeer<=2sstatus (no 32 kbit/s link, #80).
                 OneCPUworker(onedecodethread;defaultthreadcount:CL-057-02):15sFT8<=5s,7.5sFT4<=3s,120s<=40s,cold+<=2s; tenruns+warmup,
                 actualreferencePC HB9BLA(AMDRyzen9 3900X,32GB,Windows11)
                 OS/build/power/hash/workload/min/median/p95/max/memory;
                 fourprofiles<=2xruntime,64MiBworker/96MiBprocessdelta,<=250msrelease.
                 Futurejoint48kcapture+FFT+decode provesfairness, notlargerringassumption.
                 Rust/fixture/HTTP/browser/link bindings are declared in WstxRequirements; no execution verdict. */
        }
        verification phaseLikelihoodAndScale {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* Independent additional recipes:phase.7/pi/2,drift+-1/30Hz/s,canonicalgains1e-4/8,
                 secondstation80dBbelowstronger with sub-PCM16-quantumamplitude andfloatrepeat;
                 retainbothmessages. Quantizationresiduals afterindependent best-fit subtraction:
                 q=round(x*32767)/32768,unitreal/90degreeu,w,fullsupport2x2Gramfit[a,b],
                 r=q-a*u-b*w beforegain/floatstorage. Innerproducts<=128epsilon64*sqrt(max(u.u,w.w)*q.q)
                 beforestorage,<=4epsilon32*sqrt(max(u.u,w.w)*rStored.rStored)afterward.
                 Finitecaserequireszeropublications,no search_limited,neverproductionhelpers.
                 All2286originalcases/thresholds/256cap remain. Verifyrecipe/composer/audiohashes,
                 FT4bandlimitedblocksync/threemetrics andFT8bandlimitedsymbolsync/fivemetrics;
                 physicalhits/complexenvelopeSIC/rank91/64MiB.
                 No externaldecoder oracle or skipped case pass. */
        }
        dependency phaseLikelihoodCase from phaseLikelihoodAndScale to WstxRequirements::'TC-004-003';
        dependency rejectionCase from rejectionLifecycleResources to WstxRequirements::'TC-004-003';
    }
    verification ft8ArbitraryCarrierOffsets {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-01'; verify WstxRequirements::'CL-007-04'; }
        doc /* TC-004-002 uses the existing twenty independent frequency/start
             combinations, including lowest-tone carriers200.5/1000.3/3499Hz.
             These offsets need not be multiples of6.25Hz. Exact injected payloads
             and starts are the oracle; carrier error<=1Hz,start error<=240frames.
             No operator-supplied station frequency/start or new fixture is required.
             Executable trace:server/tests/decoder_signal.rs quality_corpus and
             fixtures/decoder/quality-cases.json Ft8/offset cases. No test verdict
             follows from this model or its semantic validation. */
    }
    dependency ft8ArbitraryCarrierCase from ft8ArbitraryCarrierOffsets
        to WstxRequirements::'TC-004-002';
    verification ft8PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
        doc /* Cost2WindowsPC, independentdirectDFTselectedbins,15/30sFFTdimensions,
             bandedges/centerbin/scaling/400Hzcandidate+2600Hzunrelatedcarrier.
             DFTerror<=1e-9*max(1,sumabsinput); basebandsample<=1e-8*max(1,inputRMS).
             Enumerate8/64/512tonechoicesusingindependentDecimal80coefficienttables,
             completeendgroups/sync/halfboundaries/GrayMSB; allfivefamilies/ties.
             Metric/normalizationerror<=1e-9*max(1,absexpected),finalf32LLR<=1ULP
             fromindependentlyroundedvalues. Zero/constant/nonfinitesigma/polaritycases.
             Directscalar4001tapconvolution/impulses/edges,selectedf32residualerror
             <=1e-7*max(1,sourcePeak); no circularwrap/outsideframewrites.
             HardCostas8/9,qualified256/257,failed-earlierword=>latermetric,atmost5FEC.
             Finalstarts29/30/31/89/90/91=>0/1/1/1/2/2basebandorigins,supportallowing;
             L=151680+31,s31=>clampedb0,no paddingclaim/canonicalstartstill31.
             All2286/38/14inputs/thresholdsunchanged; unsupportedtypedchannelvalidframes
             preserved. OfficialFT8>=12/14, no inventedgoldens. ActualFortranreference
             comparedwithfixedPCM/sourceSHA/settings/APprofile, everyextra/missingreported.
             No localFortrancompiler; source-builtreferenceartifactcomesfromGitHubActions.
             Thisverificationdefinitionisnotanexecutionverdict. */
    }
    dependency ft8PhysicalCase from ft8PhysicalOracles to WstxRequirements::'TC-004-002';
    dependency ft8PhysicalRejectionCase from ft8PhysicalOracles to WstxRequirements::'TC-004-003';

    verification ft4PhysicalOracles {
        subject decoder : AdvanceDecode;
        objective { verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
        doc /* Cost2WindowsPC: independentdirectDFT/asymmetrictaper/bincenter/RMS,
             all4/16/256sequenceenumerations,206normalization/174extraction/Gray/polarity,
             last-familybitcopies; hardtone7/8 andhardsync19/20; first-ramp0/1/incomplete;Nuttall/scalarDFT/knownquartic/constant/zero/singular
             baselines/percentilehalfties/endpointslinear-after-division1.18andneighborbounds;
             TWOcompleteframespersamefrequencyreturnedthroughpluralfineinterface;
             qualifiedsupportoverlap60479/60480/60481,half-toneinclusiveedge,
             failedphysicalpointcannotexclude,strongerFECinvalidqualifiedpointstillholds
             exclusion,perpassreset,duplicatefinepoints,andfixedFT8asFT4wrongmode;
             trueframesmustnotdependontime-powermaxima;
             finalstarts8/9/10=>firstCostas32/33/33,reportedstartunchanged.
             SameexplicitFT8DFT/metric/f32tolerances; direct1401tapconvolution/no wrap/no
             secondrampoffset. Unchanged2286/38/14inputs andoriginalFT4quality/performance/
             falsepublication/cancel/typedpayloadthresholds. SourcebuiltFortrancomparison
             separatewithPCM/settings/depth/APidentity. No candidate-generatedgoldens. */
    }
    dependency ft4PhysicalCase from ft4PhysicalOracles to WstxRequirements::'TC-004-001';
    dependency ft4PhysicalRejectionCase from ft4PhysicalOracles to WstxRequirements::'TC-004-003';

    package SimulatedReferenceFixtures {
        attribute def SimulatorFixture {
            attribute identity : String;
            attribute finalWavFilename : String;
            attribute mode : String;
            attribute scenario : String;
            attribute messageText : String;
            attribute carrierHz : Real;
            attribute nominalDtSeconds : Real = 0.125;
            attribute sampleRateHz : Integer = 12000;
            attribute channels : Integer = 1;
            attribute pcmBits : Integer = 16;
            attribute frames : Integer;
            attribute snrArgumentDb2500 : Real;
            attribute fadingSpreadHz : Real;
            attribute pathDelayMs : Real;
            attribute exposesSeedControl : Boolean = false;
            attribute freezesGeneratedBytes : Boolean = true;
        }
        attribute sim18_ft8_clean : SimulatorFixture {
            :>> identity = "SIM18-FT8-CLEAN";
            :>> finalWavFilename = "SIM18-FT8-CLEAN.wav";
            :>> mode = "ft8";
            :>> scenario = "clean";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft8_weak : SimulatorFixture {
            :>> identity = "SIM18-FT8-WEAK";
            :>> finalWavFilename = "SIM18-FT8-WEAK.wav";
            :>> mode = "ft8";
            :>> scenario = "weak";
            :>> messageText = "CQ W1AW FN31";
            :>> carrierHz = 1499.7;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = -15.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft8_fading : SimulatorFixture {
            :>> identity = "SIM18-FT8-FADING";
            :>> finalWavFilename = "SIM18-FT8-FADING.wav";
            :>> mode = "ft8";
            :>> scenario = "fading";
            :>> messageText = "K1ABC W9XYZ -10";
            :>> carrierHz = 1800.5;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = -10.0;
            :>> fadingSpreadHz = 0.5;
            :>> pathDelayMs = 1.0;
        }
        attribute sim18_ft8_overlap : SimulatorFixture {
            :>> identity = "SIM18-FT8-OVERLAP";
            :>> finalWavFilename = "SIM18-FT8-OVERLAP.wav";
            :>> mode = "ft8";
            :>> scenario = "overlap";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 180000;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
            attribute overlapDetails : ControlledOverlap {
                :>> secondCarrierHz = 1006.55;
            }
        }
        attribute sim18_ft4_clean : SimulatorFixture {
            :>> identity = "SIM18-FT4-CLEAN";
            :>> finalWavFilename = "SIM18-FT4-CLEAN.wav";
            :>> mode = "ft4";
            :>> scenario = "clean";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft4_weak : SimulatorFixture {
            :>> identity = "SIM18-FT4-WEAK";
            :>> finalWavFilename = "SIM18-FT4-WEAK.wav";
            :>> mode = "ft4";
            :>> scenario = "weak";
            :>> messageText = "CQ W1AW FN31";
            :>> carrierHz = 1499.7;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = -10.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
        }
        attribute sim18_ft4_fading : SimulatorFixture {
            :>> identity = "SIM18-FT4-FADING";
            :>> finalWavFilename = "SIM18-FT4-FADING.wav";
            :>> mode = "ft4";
            :>> scenario = "fading";
            :>> messageText = "K1ABC W9XYZ -10";
            :>> carrierHz = 1800.5;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = -5.0;
            :>> fadingSpreadHz = 0.5;
            :>> pathDelayMs = 1.0;
        }
        attribute sim18_ft4_overlap : SimulatorFixture {
            :>> identity = "SIM18-FT4-OVERLAP";
            :>> finalWavFilename = "SIM18-FT4-OVERLAP.wav";
            :>> mode = "ft4";
            :>> scenario = "overlap";
            :>> messageText = "CQ K1ABC FN42";
            :>> carrierHz = 1000.3;
            :>> frames = 72576;
            :>> snrArgumentDb2500 = 99.0;
            :>> fadingSpreadHz = 0.0;
            :>> pathDelayMs = 0.0;
            attribute overlapDetails : ControlledOverlap {
                :>> secondCarrierHz = 1021.1333333333333;
            }
        }
        attribute def ControlledOverlap {
            attribute secondCarrierHz : Real;
            attribute secondMessage : String = "CQ W1AW FN31";
            attribute strongGain : Real = 0.25;
            attribute weakGain : Real = 0.12529680840681806;
            attribute gainDifferenceDb : Real = 6.0;
            attribute rejectsClipping : Boolean = true;
            attribute saturates : Boolean = false;
            doc /* Mix two emitted noise-free PCM16 components in float64 after
                 division by32768, y=.25*x1+weakGain*x2, then
                 q=round_ties_even(32768*y). Rejectq outside[-32768,32767]; write
                 admittedq as signedlittle-endianPCM16. Retain component
                 and final hashes. Strong/weak labels describe selected gain ratio,
                 not a measured RF SNR. Preserve complete original supports. */
        }
        action def AdmitFinalWavFilename {
            in declaredFixture : SimulatorFixture;
            in suppliedFilename : String;
            out admitted : Boolean;
            assert constraint exactDeclaredFilename {
                admitted == (suppliedFilename == declaredFixture.finalWavFilename)
            }
            doc /* CL-007-03; TC-004-003. declaredFixture is selected only after
                 immutable mode declaration identity/settings validation. Each fixed
                 finalWavFilename is identity followed by literal .wav. Compare the
                 supplied string literally before reading the final WAV; do not
                 resolve or normalize an alternate spelling into admission. False
                 yields ValueError and no final-WAV read. Absolute and ../ names
                 remain false even when their target PCM/hash/metadata is valid.
                 Manifest/declaration/oracle reads are distinct from final-WAV reads.
                 Historical command/cwd provenance never authorizes another input. */
        }
        verification simulatorFixtureIntegrity {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-03'; }
            doc /* Existing TC-004-001/002 simulator subcases: eight admitted
                 12k mono PCM16 files, exact lengths/hashes, declared-vs-emitted
                 message/canonical77bits/79or103tones independently checked. Retain
                 FT4 legacy emitted scrambled77 separately; canonical77 is obtained
                 with the pinned FT4 XOR mask, not relabeled as emitted. Unknown PRNG
                 seed stays unknown; immutable bytes define each retained realization.
                 DT argument is NOT raw ramp origin or GUI DT. Inspect circular-shift
                 boundary artifacts and reject clipping; do not trim/pad/normalize.
                 Clean single-station messages recover exactly; weak/fading/overlap
                 misses and extras remain observations, never replacement goldens.
                 APoff FT8 and FT4 Fast reference, search200..3500, exact same PCM.
                 Cost2 Windows PC, no radio; hosted simulator build only if needed. */
        }
        verification simulatorFixtureRefusals {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-03'; verify WstxRequirements::'CL-007-04'; }
            doc /* TC-004-003: independently malformed/hash-mismatched/truncated
                 metadata, invalid format/length, nonfinite mixture and clipping
                 are refused. In a disposable valid copied mode dataset, keep all
                 metadata/hash/bytes fixed and change only one final-WAV filename:
                 the declared SIM18-FT8-CLEAN.wav or SIM18-FT4-CLEAN.wav is admitted;
                 an absolute path to the valid WAV and ../ plus that basename with
                 a byte-identical parent file both yield ValueError before any
                 final-WAV reader call. A reader spy distinguishes refusal from
                 missing-file/hash/format failure. Expected results come from the
                 literal filename contract, never decoder output. Automated cost 2
                 on Windows PC, no radio; clean only disposable test copies. Wrong expected content is not repaired from Rust
                 output. Existing quality/noise/runtime/cancel limits are unchanged. */
        }
        verification simulatorFixtureProvenance {
            subject decoder : AdvanceDecode;
            objective { verify WstxRequirements::'CL-007-03'; }
            doc /* TC-004-002 provenance subcase, cost 2 offline artifact review on
                 Windows PC. Compare supplied package inventory with provenance:
                 FT8 includes build-ft8sim.log, cmake-version.txt,
                 gfortran-version.txt, source-revision.txt, COPYING and AUTHORS.
                 Do not claim absent header/source/CMake source files accompany
                 the FT8 directory. Pinned corresponding-source URLs remain links,
                 not evidence that bytes are bundled. Repair wording only; preserve
                 generation inputs, frozen PCM, manifest truth and comparisons. */
        }
        dependency simulatorProvenanceCase from simulatorFixtureProvenance to WstxRequirements::'TC-004-002';
        dependency ft4SimulatorCases from simulatorFixtureIntegrity to WstxRequirements::'TC-004-001';
        dependency ft8SimulatorCases from simulatorFixtureIntegrity to WstxRequirements::'TC-004-002';
        dependency simulatorRefusalCases from simulatorFixtureRefusals to WstxRequirements::'TC-004-003';
    }

    doc /* contract 4.7.5/12.8.1 coordinated operating selection is modeled by
         WstxOperatingReceive. This companion retains the unchanged legacy strict
         receive/radio/result shapes and owner/cancellation/source contracts.
         New selection uses the same authority, explicit actual release before
         setters/new capture and a fresh context, not a second pipeline or actor. */
}
