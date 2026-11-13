package WstxMessageEncode {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-005';
    private import WstxRequirements::AutomationState;
    private import WstxArchitecture::'FR-006';
    private import WstxContact::'CL-011-02';

    enum def MessageFamily { enum standardCalls; enum portableCalls; enum nonstandard; enum freeText; enum telemetry; enum fieldDay; enum rttyRoundup; enum euVhf; }
    enum def PackRefusal {
        enum empty;              // nothing to send after normalization
        enum tooLong;            // message over 37 characters, or free text over 13
        enum invalidText;        // a character no supported family can represent
        enum unsupportedFamily;  // WSJT-X would choose DXpedition or WSPR (EU VHF type 5 is packed since #99)
        enum notExact;           // WSJT-X would transmit an altered rendering (zero-padded telemetry; a Field Day or RTTY Roundup call it would hash)
        enum roundTripMismatch;  // the packed bits do not unpack to the normalized message
    }
    attribute def PackedMessage {
        attribute normalizedText : String;
        attribute payload77 : String;
        attribute i3 : Integer;
        attribute n3 : Integer[0..1];
        attribute family : MessageFamily;
        doc /* normalizedText is the message: ASCII letters folded to upper case,
             NUL treated as blank, blank runs collapsed and leading/trailing blanks
             removed, exactly as WSJT-X pack77_normalized_message. This is the only
             canonicalization; any other difference between input and the receiver's
             rendering is a refusal, never a silently altered message. */
    }
    action def PackMessage {
        in text : String;
        out packed : PackedMessage[0..1];
        out refusal : PackRefusal[0..1];
        doc /* Exactly one of packed/refusal. Family selection follows WSJT-X
             pack77_encode_core order. Messages that do not start with CQ/DE/QRZ are
             first checked for the unsupported DXpedition shape (any ';' except one
             leading "TU;" word), then ARRL Field Day (#24 S2b, CL-024-03,
             pack77_parse_field_day_source): CALL1 CALL2 [R] EXCH SECTION with
             SECTION exactly one of the 86 PACK77_ARRL_SECTIONS, EXCH the transmitter
             count 1-32 (no leading zero) followed by the class A-F, and each call a
             c28 call slot (3-13 characters of A-Z, 0-9 and '/': a standard call, or
             one '/' neither first nor last). A count 1-16 is i3=0 n3=3, 17-32 n3=4
             (bit fields: n28 28, n28 28, R 1, count-1 or count-17 4, class 3, section index 1-86
             7, n3 3, i3 3). Then telemetry
             (one word): exactly 18 hexadecimal digits below 2^71 is i3=0 n3=5;
             a shorter hexadecimal word is notExact (WSJT-X would zero-pad it).
             Then the WSPR shapes (call grid4 digits; slash-call digits) are
             unsupportedFamily. Standard i3=1 (i3=2 when either call carries /P):
             first call CQ, CQ with 3 digits or 1-4 letters, DE, QRZ, a standard
             call, a standard call with /R or /P, or <hashed call>; second call a
             standard call (optionally /R or /P) or <hashed call>; a <hashed call>
             is refused next to any token containing '/' (also inside brackets); tail none, grid4
             AA00..RR99, R grid4, signed report -50..+50, R report, RRR, RR73 or
             73 (CQ takes only none or grid4). A standard call has 3-6 letters/digits,
             its call-area digit at position 2 or 3, a prefix with a letter, at most
             three suffix letters and no leading Q; a <hashed call> slot carries the
             22-bit WSJT-X ihashcall. RTTY Roundup i3=3 (#24 S2b, CL-024-03,
             pack77_parse_type3_source): [TU;] CALL1 CALL2 [R] RST EXCH, RST 5n9 with
             n 2-9, EXCH a four-digit serial 0001-7999 or exactly one of the 171
             PACK77_RTTY_MULTIPLIERS (US states, Canadian provinces, DC, the Dutch
             provinces, X01-X99), the calls c28 call slots as for Field Day (bit fields: TU 1,
             n28 28, n28 28, R 1, n-2 3, serial or 8000 plus multiplier index 13, i3 3).
             In both contest families WSJT-X sends a c28 slot that is not a standard
             call (e.g. PJ4/K1ABC, K1ABC/R) as its 22-bit hash and renders it
             <CALL>, an altered message: such a message is notExact; a slot of more
             than 11 characters is not this family, and an explicit <CALL> token is
             never a contest call slot. Nonstandard i3=4: CQ plus a 5-11 character
             base-38 nonstandard call, or one nonstandard call of at most 11 base-38 characters and one
             <hashed call> (12-bit hash) with optional RRR/RR73/73. EU VHF i3=5 (#99,
             CL-099-01; pack77_parse_type5_source, pack77_5_candidate, encode_pack77_type5,
             tried after i3=4 as WSJT-X does): exactly "<CALL1> <CALL2> [R] EXCH GRID6",
             each call a <hashed call> token of 3-11 characters inside the brackets, R the
             only allowed third word of five, EXCH exactly six digits 5nSSSS with n 2-9
             and the serial SSSS 0001-2047 (520001..592047 and serial >= 1), GRID6 exactly six
             characters AA00AA..RR99XX (bit fields: h12 of CALL1 12, h22 of CALL2 22, R 1,
             n-2 3, serial 11, grid6 index 25, i3 3; the grid6 index as the decoder's
             VhfFields grid). Serial 0000 and above 2047, a report digit 0, 1 or a
             six-digit exchange outside 52..59, a 4-character grid, a missing bracket or a
             word other than R are not this family (WSJT-X rejects them) and fall through.
             The round trip renders <CALL1> and <CALL2> as the input tokens. Free text i3=0
             n3=0: at most 13 characters from " 0-9A-Z+-./?", right-justified base 42.
             Anything else is refused. The packed bits are unpacked again by the
             receive payload decoder and must render the same blank-separated
             tokens (a decoded <...> matches the input <CALL> of at most 11
             characters). A structured candidate that fails this check falls
             through to the next family (WSJT-X take_candidate), so e.g. AB1 W9XYZ
             is free text; roundTripMismatch is returned only when the selected
             free-text or telemetry encoding itself fails it. WSJT-X's truncating free-text
             fallback is deliberately not reproduced. */
    }
    attribute def ChannelFrame {
        attribute payload77 : String;
        attribute codeword174 : String;
        attribute tones : Integer[79];
        doc /* codeword = payload, CRC-14 (polynomial 0x2757 over the payload plus five
             zero bits) and 83 LDPC(174,91) parity bits from the receive generator.
             79 tones: Costas 3140652 at symbols 0, 36 and 72; the 58 data symbols
             take successive bit triples MSB first through Gray map 0,1,3,2,5,6,4,7.
             Bits and tones equal ft8code exactly. */
    }
    attribute def Ft8WaveformContract {
        attribute symbolCount : Integer = 79;
        attribute toneSpacingHz : Real = 6.25;
        attribute gaussianBT : Real = 2.0;
        attribute samplesPerSymbol12k : Integer = 1920;
        attribute samplesPerSymbol48k : Integer = 7680;
        attribute minimumToneZeroHz : Real = 200.0;
        attribute maximumToneZeroHz : Real = 2950.0;
        attribute referenceTolerance : Real = 0.003;
        attribute rateConsistencyTolerance : Real = 0.006;
        assert constraint occupiedBand { minimumToneZeroHz >= 200.0 and maximumToneZeroHz + 8 * toneSpacingHz <= 3000.0 }
        doc /* Real waveform of exactly 79 symbols (151680 samples at 12 kHz, 606720
             at 48 kHz; 48 kHz is the native station playback rate, as WSJT-X), unit
             peak, no lead or tail silence. Math of gen_ft8wave/emit_ft8_waveform: the
             frequency pulse p(t)=(erf(k(t+0.5))-erf(k(t-0.5)))/2, k=pi*sqrt(2/ln2)*BT,
             sampled at t=(i+1-1.5N)/N for i=0..3N-1 (N samples/symbol); per-sample
             phase increments 2*pi*f0/rate plus 2*pi/N times the pulse-weighted tone
             sum, with dummy first/last symbols; sample n = a(n)*sin(phi(n)) where
             phi(0)=0 and the increment applies after each sample; a(n) rises
             (1-cos(pi*n/R))/2 over the first R=N/8 samples and falls
             (1+cos(pi*m/R))/2 over the last R. f0 is tone 0; the whole 50 Hz signal
             lies within 200..3000 Hz, otherwise the request is refused.
             Computation is binary64, output binary32.
             referenceTolerance: maximum absolute difference, as a fraction of full
             scale after both are peak-normalized, between the 12 kHz waveform and a
             zero-noise WSJT-X ft8sim WAV (f0 1500 and 637.5 Hz, signal from sample
             6000). Budget: int16 rounding 1.5e-5 plus ft8sim's 65536-entry phase table
             9.6e-5 plus WSJT-X binary32 phase accumulation drift, measured 2.30e-3 at
             1500 Hz and 7.7e-4 at 637.5 Hz; emulating that binary32 arithmetic leaves
             1.11e-4, so the residual is WSJT-X rounding, not a model difference. A
             one-sample shift or a 0.01 Hz carrier error exceeds the tolerance.
             rateConsistencyTolerance: every fourth 48 kHz sample against the 12 kHz
             waveform; the measured 4.9e-3 rad is the constant pulse-grid
             (rectangle-rule) phase offset between the two native sample grids. */
    }
    attribute def Ft4ChannelFrame {
        attribute payload77 : String;
        attribute codeword174 : String;
        attribute tones : Integer[103];
        doc /* WSJT-X genft4.f90 ft4_tones_from_77bits: the payload XOR the 77-bit
             scrambling vector rvec 0100101001011110100010011011010010110000100010100111
             1001010101011011111000101 is the codeword's first 77 bits, followed by
             CRC-14 over those scrambled bits and the 83 LDPC(174,91) parity bits of
             the same receive generator as FT8. 103 tones: Costas 0132 at tones 0-3,
             1023 at 33-36, 2310 at 66-69, 3201 at 99-102; the 87 data symbols in
             between take successive bit pairs MSB first through Gray map 0,1,3,2.
             The two ramp symbols are not tones; they belong to the waveform. Bits,
             codeword and tones equal the WSJT-X ft4sim printout exactly (no ft4code
             executable ships with 3.3.0-beta5; fixtures/transmit/ft4/ft4sim-vectors.json
             reads the codeword back from the printed tones by the inverse Gray map and
             cross-checks the payload against ft8code). */
    }
    attribute def Ft4WaveformContract {
        attribute channelSymbols : Integer = 103;
        attribute waveformSymbols : Integer = 105;
        attribute toneSpacingHz : Real = 20.833333;
        attribute gaussianBT : Real = 1.0;
        attribute samplesPerSymbol12k : Integer = 576;
        attribute samplesPerSymbol48k : Integer = 2304;
        attribute samples12k : Integer = 60480;
        attribute samples48k : Integer = 241920;
        attribute minimumToneZeroHz : Real = 200.0;
        attribute maximumToneZeroHz : Real = 2916.666667;
        attribute referenceTolerance : Real = 0.001;
        attribute rateConsistencyTolerance : Real = 0.025;
        assert constraint occupiedBand { minimumToneZeroHz >= 200.0 and maximumToneZeroHz + 4 * toneSpacingHz <= 3000.0 }
        assert constraint length { samples12k == waveformSymbols * samplesPerSymbol12k and samples48k == waveformSymbols * samplesPerSymbol48k }
        doc /* Native transmitter convention of gen_ft4wave.f90 as called by
             mainwindow.cpp for FT4 (nsym=103, nsps=4*576, fsample=48000, icmplx=0),
             not the receive decoder's reconstruction (the QEX FT4 waveform).
             Real waveform of (103+2) symbols, unit peak, no lead or tail silence; 48 kHz
             is the native playback rate. Frequency pulse
             p(t)=(erf(k(t+0.5))-erf(k(t-0.5)))/2 with BT 1.0, a three-symbol grid sampled
             at t=(i+1-1.5N)/N for i=0..3N-1; channel tone j (0-based) adds
             2*pi/N*tone*p over samples j*N..j*N+3N-1 of a zero buffer of (103+2)*N
             increments, so the first and last symbol carry only pulse tails (no
             dummy-symbol extension as FT8). Each increment also adds 2*pi*f0/rate.
             Sample n = a(n)*sin(phi(n)) with phi(0)=0 and the increment n applied after
             sample n (sine before phase advance). a(n) = (1-cos(pi*n/N))/2 for n < N,
             (1+cos(pi*m/N))/2 at m = n-104N for the last symbol, else 1; the native
             endpoints are a(0)=0 and a(last) = (1+cos(pi*(N-1)/N))/2 > 0. f0 is tone 0;
             the whole 83.3 Hz tone span lies within 200..3000 Hz, otherwise
             frequencyOutOfRange; a tone above 3 is invalidTone. Binary64 math, binary32
             output.
             referenceTolerance: maximum absolute difference, as a fraction of full
             scale, between the 12 kHz waveform and the in-phase component of a
             zero-noise ft4sim WAV (f0 1500 and 637.5 Hz, ramp-up symbol from sample
             5424). ft4sim writes the real part cos(phi) of the complex form; the test
             takes the imaginary part of its FFT analytic signal (sin(phi)) and the
             analytic magnitude peak as full scale, independent of the implementation.
             Measured 2.8e-4 at 1500 Hz and 2.3e-4 at 637.5 Hz: int16 rounding 1.5e-5,
             WSJT-X binary32 phase accumulation over 60480 samples and the analytic-signal
             edge error. A one-sample shift, a 0.01 Hz carrier error and a ramp one sample
             late (2.7e-3) each exceed it; so do the decoder conventions (phase advanced
             before the sample, mirrored ramp-down endpoint), the FT8 N/8 ramp and an
             output one sample late (source mutations, test evidence).
             rateConsistencyTolerance: every fourth 48 kHz sample against the 12 kHz
             waveform. Each grid samples the pulse one of its own samples early, so the
             frequency trajectories differ by a 3/48000 s shift; the phase difference is
             bounded by 2*pi*3*20.833 Hz*62.5 us = 0.0245 rad (measured 0.0123). */
    }

    requirement 'CL-009-01' {
        doc /* Pack every supported FT8 message family (standard i3=1/2 with CQ forms,
             reports, R/RRR/RR73/73 and /R /P, i3=4 nonstandard calls with WSJT-X
             hashes, free text, telemetry, and since #24 S2b ARRL Field Day i3=0
             n3=3/4 and RTTY Roundup i3=3, CL-024-03) to the WSJT-X 77 bits, CRC-14 and LDPC
             codeword and 79 tones, and generate the FT8 GFSK waveform at 12 kHz and
             48 kHz within the declared WSJT-X reference tolerance. Unsupported,
             invalid or altered messages and out-of-range audio frequencies are
             explicit refusals. Details: WstxMessageEncode::PackMessage, ChannelFrame, Ft8WaveformContract. */
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
    // #11 FT4 transmit preparation (slice A); detailed contract in WstxTransmit.
    requirement 'CL-011-01' {
        doc /* Encode every supported message family for FT4 with the shared FT8 packer
             (same 77 bits and refusals), scramble with the WSJT-X rvec, add CRC-14 and
             LDPC(174,91) parity and map to the 103 genft4 tones; generate the native
             WSJT-X FT4 transmit waveform (gen_ft4wave convention, 105 symbols with
             ramps, 60480 samples at 12 kHz and 241920 at 48 kHz) within the declared
             ft4sim tolerance; plan FT4 starts for named even/odd 7.5 s UTC periods
             with the 300 ms audio delay and the FT8 refusals; a start is stale from
             the earlier of 75 % of the period and the end of the waveform's audio
             (5340 ms), deliberately not WSJT-X's fTR < 0.75 empty-start quirk.
             The mode is explicit per request and FT8 behaviour is unchanged.
             Mode selection and QSO/log rules are CL-011-02..04.
             Details: WstxMessageEncode::Ft4ChannelFrame, Ft4WaveformContract, Ft4Schedule,
             PlanTransmitStart. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/mod.rs; server/src/transmit/waveform.rs; server/src/transmit/schedule.rs";
    }
    dependency CL_011_01_to_FR_005 from 'CL-011-01' to 'FR-005';
    dependency CL_011_01_to_FR_006 from 'CL-011-01' to 'FR-006';
    verification 'TC-006-002' {
        doc /* TC-006-002 — FT4 timing and mode changes
             CL-011-01 (FT4 period timing), CL-011-02 (mid-workflow mode selection)
             Setup: virtual UTC clock values around 7.5 s boundaries, both parities,
             12 kHz and 48 kHz, every clock state, FT8 requests at the same instants;
             for CL-011-02 the actual router with the contact engine and the actual #9
             transmit owner on a hardware double, live FT4/FT8 jobs with hand-authored
             rows.
             Steps: select the next FT4 slot and plan starts before the period, at the
             300 ms delay, late, at the 75 % boundary, after it, for unaligned periods,
             FT4-only boundaries requested as FT8, and unsynchronized/unknown clocks.
             CL-011-02: with an FT4 live job read station.tick and prepare a manual
             entry; request an operating selection with action mode while Tune is on,
             while PTT is keyed before the audio, while the FT4 waveform plays, and after
             Tune ends; stop FT4 receive with an active FT4 contact.
             CL-011-02 oracles (WstxQsoTransmit::StationOperatingMode, ModeChange):
             station.tick period_ms 7500 in FT4 and 15000 in FT8; the manual contact
             uses FT4 (Tx4 RR73); the mode selection while Tune is on, PTT keyed or
             transmitting is 409 busy and nothing changes (operating revision, receive
             mode ft4); after Tune it is not refused busy; after the receive stop the
             period stays 7500 and the FT4 contact stays replying with K1ABC.
             Oracles: WSJT-X values (Modulator.cpp FT4 delay_ms=300 and late-start m_ic,
             TxStartPolicy.hpp 0.75, mainwindow.cpp m_TRperiod=7.5 and t mod 15 s
             parity): exact audio start and skipped samples. Deliberately not WSJT-X's
             fTR < 0.75 empty start: 5339 ms admitted (skip below the waveform's sample
             count), 5340 ms and 5624 ms stale at 12 kHz and 48 kHz, also for the next
             slot; FT8 keeps 15 s periods, 500 ms delay and its 11.25 s limit.
             2 — Isolated automated tests; Windows development PC, no clock, audio or radio. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-011-01';
            verify 'CL-011-02';
        }
        attribute executable : String = "server/tests/transmit_ft4_vectors.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_011_01_verified_by_TC_005_002 from 'CL-011-01' to 'TC-005-002';
    dependency CL_011_01_verified_by_TC_006_002 from 'CL-011-01' to 'TC-006-002';
}
