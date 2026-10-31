package WstxTransmit {
    private import ScalarValues::*;
    doc /* Canonical FT8 transmit-preparation contract (issue #9, slice A): message
         packing, channel symbols, waveform and pure period scheduling. Nothing here
         opens audio, keys PTT or touches a radio; arming, Halt, PTT and played-audio
         evidence are later #9 clauses. Declared coverage is not a test result.
         CL-009-01/02 and TC-005-001/TC-006-001 are declared in WstxRequirements.
         Behaviour oracle: WSJT-X 3.3.0-beta5 (revision d89fe3) lib/77bit/packjt77.f90,
         packjt77_grammar.f90, lib/ft8/genft8.f90, gen_ft8wave.f90, ft8_waveform.f90,
         Modulator/Modulator.cpp, TxStartPolicy.hpp and widgets/mainwindow.cpp. Its
         ft8code output was checked identical to the pinned beta4 baseline for every
         fixture message (fixtures/transmit/ft8code-vectors.json).
         Encoding reuses the existing receive payload codebook, CRC-14, LDPC(174,91)
         generator, Gray map and Costas arrays of WstxOfflineDecode; it adds no
         second codebook. */

    enum def MessageFamily { enum standardCalls; enum portableCalls; enum nonstandard; enum freeText; enum telemetry; }
    enum def PackRefusal {
        enum empty;              // nothing to send after normalization
        enum tooLong;            // message over 37 characters, or free text over 13
        enum invalidText;        // a character no supported family can represent
        enum unsupportedFamily;  // WSJT-X would choose DXpedition, Field Day, WSPR, RTTY or EU VHF type 5
        enum notExact;           // WSJT-X would transmit an altered rendering (zero-padded telemetry)
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
             first checked for the unsupported DXpedition (any ';') and ARRL Field
             Day (4-5 words ending in an ARRL/RAC section) shapes, then telemetry
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
             22-bit WSJT-X ihashcall. Nonstandard i3=4: CQ plus a 5-11 character
             base-38 nonstandard call, or one nonstandard call of at most 11 base-38 characters and one
             <hashed call> (12-bit hash) with optional RRR/RR73/73. Free text i3=0
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
    enum def ClockState { enum synchronized; enum unsynchronized; enum unknown; }
    enum def PeriodParity { enum even; enum odd; }
    enum def ScheduleRefusal { enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod; }
    attribute def Ft8Schedule {
        attribute periodMs : Integer = 15000;
        attribute audioDelayMs : Integer = 500;
        attribute latestStartMs : Integer = 11250;
        assert constraint startWindow { latestStartMs * 4 == periodMs * 3 and audioDelayMs < latestStartMs }
        doc /* Pure function of a virtual UTC clock in integer milliseconds; no timer,
             device or wall clock. Periods start at UTC multiples of 15 s; even when
             (start/15 s) is even (WSJT-X Tx even/1st = t mod 30 s < 15 s). The next
             slot for a parity is the earliest such period whose start window is
             still open. Audio of a slot starts 500 ms after the period start
             (Modulator.cpp FT8 delay_ms=500, independent of the configured PTT
             TxDelay). A start is admitted while elapsed time into the requested
             period is below 75 % (11.25 s, TxStartPolicy.hpp
             TxStartLatestPeriodFraction). Before 500 ms the plan waits until period
             start + 500 ms with no skipped samples; a late start at elapsed e plays
             immediately from sample floor((e-500 ms)*rate/1000 ms), so the audio stays
             aligned with the period and the elapsed prefix is skipped, never replayed
             (Modulator.cpp late-start m_ic). A request names its period: from 11.25 s
             on it is stalePeriod and is never moved to a later period; an unaligned
             period is misalignedPeriod; any clock state other than synchronized
             is clockNotSynchronized. */
    }
    action def PlanTransmitStart {
        in nowUtcMs : Integer;
        in clock : ClockState;
        in periodStartUtcMs : Integer;
        in sampleRateHz : Integer;
        out audioStartUtcMs : Integer[0..1];
        out skippedSamples : Integer[0..1];
        out refusal : ScheduleRefusal[0..1];
    }
}
