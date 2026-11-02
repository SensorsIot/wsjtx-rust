package WstxTransmit {
    private import ScalarValues::*;
    doc /* Canonical FT8 and FT4 transmit contract. Slice A (issue #9, FT4 issue #11
         slice A): message packing, channel symbols, waveform and pure period
         scheduling, none of which opens audio, keys PTT or touches a radio. Slice B
         (issue #9, CL-009-03/04): the station's transmit owner (arming under the
         explicit TransmitAuthority, TransmitRequest admission and replacement, CI-V
         PTT with readback, 48 kHz output, priority Halt, Tune, Tx watchdog, failure and
         restart handling, TransmitWire); WstxContact (#10) consumes it. Physical RF
         acceptance is TC-008-002 and is not claimed by automated tests. Declared
         coverage is not a test result.
         CL-009-01/02, CL-011-01 and TC-005-001/002, TC-006-001/002 are declared in
         WstxRequirements. FT4 reuses PackMessage unchanged (FT4 and FT8 share pack77).
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
             not the receive decoder's reconstruction (WstxOfflineDecode quadratures).
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
    enum def ClockState { enum synchronized; enum unsynchronized; enum unknown; }
    enum def PeriodParity { enum even; enum odd; }
    enum def ScheduleRefusal { enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod; }
    attribute def Ft4Schedule {
        attribute periodMs : Integer = 7500;
        attribute audioDelayMs : Integer = 300;
        attribute latestStartMs : Integer = 5625;
        attribute waveformMs : Integer = 5040;
        attribute audioEndMs : Integer = 5340;
        assert constraint startWindow { latestStartMs * 4 == periodMs * 3 and audioDelayMs < latestStartMs }
        assert constraint audioEnd { audioEndMs == audioDelayMs + waveformMs and audioEndMs < latestStartMs }
        doc /* Ft8Schedule rules with FT4 values: periods start at UTC multiples of
             7.5 s (mainwindow.cpp m_TRperiod=7.5); even when (start/7.5 s) is even
             (Tx even/1st = t mod 15 s < 7.5 s); audio starts 300 ms after the period
             start (Modulator.cpp FT4 delay_ms=300) with the ramp-up symbol, so the
             first channel tone starts 348 ms after it; later starts skip
             floor((e-300 ms)*rate/1000 ms) samples. The 105-symbol waveform lasts
             5040 ms, so its audio ends 5340 ms into the period, before the 75 % limit
             (5.625 s, TxStartPolicy.hpp): a start is admitted only while the skip is
             below the waveform's sample count at that rate (60480 at 12 kHz, 241920 at
             48 kHz), i.e. elapsed below 5340 ms; from 5340 ms the request is
             stalePeriod. This deliberately differs from WSJT-X, whose fTR < 0.75 check
             would start an empty transmission between 5340 and 5625 ms. Misaligned and
             clock refusals as FT8. The ft4sim receive
             placement (channel tones from 0.5 s) is a simulator convention, not
             transmit timing. */
    }
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
    // ------------------------------------------------------------------
    // #9 slice B transmit owner (delivered; consumer contract of WstxContact #10,
    // supervisor decision 2026-10-31 on #10). Implementation:
    // server/src/transmit/service.rs (owner), server/src/radio_control/actor.rs and
    // executor.rs (PttControl), server/src/playback.rs (AudioPlayback),
    // server/src/transmit_http.rs (station hardware, TransmitWire).
    enum def ArmState { enum disarmed; enum armed; }
    enum def DisarmCause {
        enum operator; enum halt; enum contactCompleted; enum contactCancelled;
        enum txWatchdog; enum refused; enum failed; enum deviceLost; enum startup;
        enum authorityChanged;
    }
    enum def TransmitRefusal {
        enum transmitUnsupported; enum notArmed; enum audioStarted; enum duplicateSequence;
        enum staleRequest; enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod;
        enum packRefused; enum frequencyOutOfRange; enum busy; enum notAuthorized;
        enum radioUnavailable;
    }
    enum def TransmitFailure {
        enum pttTimeout; enum pttRejected; enum pttReadbackMismatch; enum pttIndeterminate;
        enum radioLost; enum audioUnavailable; enum audioDeviceLost; enum audioStalled;
        enum authorityChanged; enum ownerFault;
    }
    enum def TransmitCapability { enum unsupported; enum unavailable; enum available; }
    enum def PttState { enum released; enum keyed; enum indeterminate; }
    enum def HaltState { enum idle; enum pending; enum stopped; }
    attribute def TransmitAuthority {
        attribute armedOnStartup : Boolean = false;
        attribute persisted : Boolean = false;
        doc /* The station's explicit transmit authority (WstxArchitecture::RadioAuthority),
             evaluated at Arm, at every request admission, at keying and on every
             owner step. Capability: unsupported unless the saved profile has
             control.mode cat, control.ptt cat and an exact audio.output_device (a
             receive-only profile, ptt disabled, is never transmit capability);
             unavailable while the CL-022-03 automatic CAT gate is not eligible (no
             current grant, commissioning missing or invalidated) or its actor is not
             ready; otherwise available. Authority: an explicit operator Arm request
             carrying the current CL-022 safety revision of the selected radio scope,
             sent by a request with a current CL-022 grant (a plaintext profile has no
             grant and never arms). CL-022 receive-only commissioning is a precondition
             of CAT but is not transmit authority. The authority is per boot, never
             persisted or restored: every process start is disarmed (startup), and any
             safety revision change (control/profile edit, recommissioning) disarms
             (authorityChanged); loss of the radio or capability disarms (deviceLost).
             MCP and the browser use the same operation; neither can widen it. */
    }
    attribute def TransmitTiming {
        attribute haltMs : Integer = 250;
        attribute pttExchangeMs : Integer = 1000;
        attribute keyLeadMs : Integer = 0;
        attribute playbackScale : Real = 0.5;
        attribute sampleRateHz : Integer = 48000;
        attribute releaseMarginMs : Integer = 500;
        attribute renderStallMs : Integer = 500;
        doc /* Keying: the output device is opened first, then PTT is keyed at the period
             start (keyLeadMs after it; for an admitted late start at once), so the
             audio delay of Ft8Schedule/Ft4Schedule (500/300 ms) separates the confirmed
             key from the first sample. Audio starts only after the key readback, at
             the first owner step at or after period start + audio delay, and plays
             from the sample PlanTransmitStart gives for that instant (late start skips,
             never replays). PTT is released with readback after the device reports the
             last sample played, and at the latest at the device-independent release
             deadline audio start + remaining waveform duration + releaseMarginMs
             whatever the device reports (audioStalled); disarm never unbounds a keyed
             transmission. haltMs: from HaltTransmit receipt, audio output stops
             without waiting for the owner lock and PTT is released and read back
             within 250 ms while CAT answers; a release exchange that fails or times
             out (pttExchangeMs per exchange, RadioIO 1 s) leaves PttState
             indeterminate, closes that CAT connection and is reported, never hidden.
             Halt priority: the halt flag is checked immediately before keying and
             aborts the output open and the wait for the CAT owner; a halt received
             during the open never keys, one received during the key exchange releases
             at once after it; halt_state stopped only after the confirmed release,
             otherwise pending with the true PttState. Owner fault: a panic of the
             transmit owner thread fails closed (audio stopped, one release attempt,
             requests failed ownerFault, disarmed failed, Arm refused for the boot)
             and halt keeps answering. ExitRelease: Ctrl+C, console close, logoff,
             shutdown and any process panic stop output and, only when the CI-V switch
             may be keyed, send one off-only release bounded to 500 ms.
             playbackScale: the unit-peak waveform is played at -6.02 dBFS, fixed for
             now (supervisor decision); drive level is set at the radio (IC-7300 USB MOD
             level), no attenuation setting is offered in this slice. */
    }
    attribute def TransmitClock {
        attribute maxOffsetMs : Integer = 500;
        attribute maxAgeS : Integer = 600;
        attribute intervalS : Integer = 60;
        attribute serverTimeoutMs : Integer = 1500;
        attribute maxStepMs : Integer = 100;
        assert constraint freshness { intervalS < maxAgeS and serverTimeoutMs < intervalS * 1000 }
        doc /* ClockState of the station's system UTC clock from the station's own SNTP
             measurement (RFC 4330 client, operator decision 2026-10-31 on #9; a
             third-party tool that steps the clock, e.g. Dimension 4, is never reported
             by Windows as discipline, so Windows discipline is not used). A dedicated
             thread measures at start and then every intervalS, never the transmit
             owner, audio or HTTP thread; those only read the latest measurement. One
             measurement asks the servers ch.pool.ntp.org, time.windows.com,
             pool.ntp.org in that order (UDP port 123) and takes the first valid
             answer; a server that does not answer validly within serverTimeoutMs is
             skipped. The environment variable WSTX_SNTP_SERVERS, when set, replaces
             the order with its comma-separated host or host:port entries; empty means
             no measurement (unknown), which isolated tests use so that they never
             contact a public server. A valid reply is at least 48 bytes, leap indicator not 3, mode 4,
             stratum 1..15, nonzero transmit timestamp and an originate timestamp equal
             to the request's transmit timestamp; anything else is ignored.
             offset = ((T2-T1)+(T3-T4))/2 and round trip (T4-T1)-(T3-T2) (not below 0),
             in milliseconds to the nearest, NTP timestamps compared modulo the era;
             T4 is T1 plus the monotonic time to the reply, so a clock step during the
             exchange cannot distort it. A round without an answer keeps the previous
             measurement. Each measurement keeps the monotonic instant of its reply and
             the system time its offset describes (the send time plus the monotonic
             time to the reply); step = system time elapsed since then minus monotonic
             time elapsed. A |step| above maxStepMs means the system clock was stepped
             during or after the exchange (e.g. by a third-party tool), so the offset
             no longer describes it. synchronized: the latest measurement is at most
             maxAgeS old, |step| <= maxStepMs and |offset| <= maxOffsetMs;
             unsynchronized: at most maxAgeS old, |step| <= maxStepMs and
             |offset| > maxOffsetMs; unknown: no measurement, an older one or a larger
             step (until the next measurement). The
             offset is reported, never applied: the station does not set the system
             clock. WstxRadioIO receive clock external accuracy stays unknown.
             PlanTransmitStart refuses anything but synchronized; the state it receives
             is the station clock's (AirClock: by the profile's clock source, #43). */
    }
    attribute def AirClock {
        attribute minSnrDb : Integer = -20;
        attribute maxDtMs : Integer = 3000;
        attribute windowS : Integer = 120;
        attribute minHeard : Integer = 3;
        attribute trimMs : Integer = 400;
        attribute minStations : Integer = 4;
        attribute minConfidencePct : Integer = 60;
        attribute hysteresisMs : Integer = 50;
        attribute maxSlewMs : Integer = 1000;
        attribute huntWindows : Integer = 4;
        attribute huntMs : Integer = 1000;
        attribute maxAgeS : Integer = 60;
        attribute maxResidualMs : Integer = 500;
        attribute maxDisagreementMs : Integer = 200;
        assert constraint robust { minHeard < minStations and hysteresisMs < maxResidualMs and maxDisagreementMs < maxResidualMs }
        doc /* #43 the clock from the air (WstxRequirements CL-043-01..03, defaults chosen
             on the CR): the station clock combines TransmitClock (SNTP) with an estimate
             of its offset from the DT of decoded stations by the profile's clock source
             ntp|air|both (clock.json). Observations: decodes with a concrete sending call
             other than the profile's own, SNR >= minSnrDb and |raw DT| <= maxDtMs, raw DT
             against the uncorrected system clock; the last windowS; one median vote per
             station, none below minHeard stations, votes beyond trimMs of the median
             trimmed; offset = -median of the rest; confident with minStations and
             minConfidencePct. Each completed decode window re-estimates and moves the
             applied correction toward a confident estimate beyond hysteresisMs by at
             most maxSlewMs; until the first confident estimate, every huntWindows windows
             without one alternate it between 0 and +huntMs (acquisition of a slow clock).
             A system clock step is subtracted from it (station UTC continuous).
             synchronized: confident, at most maxAgeS old, unstepped,
             |estimate - applied| <= maxResidualMs. The applied correction is added to
             station UTC on the air basis (air, or both while SNTP is not synchronized)
             for receive windows, period/DT, transmit planning and audio start; the
             system clock is never set. Estimating from raw DT keeps the correction out
             of its own input, so it cannot oscillate with the receive windows or the
             capture drift tracker (WstxRadioIO, #47). */
    }
    action def PttControl {
        in enable : Boolean;
        doc /* Typed CI-V transmit switch through the one WstxRadioIO CAT owner:
             FE FE radio controller 1C 00 01|00 FD, ACK FB required (NG FA is
             pttRejected), then the 1C 00 query must read back the requested state.
             Compiled code, not an Operation: catalogue data, POST /radio/operation and
             the automatic CL-022 lifecycle cannot reach it, and the lifecycle emits
             no PTT. Keying takes the actor's transmit hold, which waits for a running
             poll or operation and then excludes every ordinary operation, receive
             transition and poll until a release is confirmed, so a release is the
             next exchange. Closing a connection that may be keyed first sends one
             off-only release. After an indeterminate release the owner retries
             off-only releases (never a key) and refuses Arm until one is confirmed. */
    }
    action def AudioPlayback {
        doc /* WASAPI shared event-driven render on exactly the profile's
             audio.output_device endpoint ID (no default fallback), 48 kHz mix format
             only (float32 or PCM16/24/32, any channel count, the mono program on every
             channel); otherwise audioUnavailable before PTT is keyed. The device opens
             streaming silence before keying, plays one program (waveform from its
             planned sample or the Tune tone), and stops and closes within 250 ms from
             any thread. Drain: after the program's last frame nothing more is written,
             so the device padding drains and the end is reported only when every
             program frame was consumed. Render watchdog: while playing, no device
             consumption for renderStallMs, or an ended render thread, is
             audioDeviceLost. A render error or invalidated device during audio is
             audioDeviceLost: PTT is released and the station disarms. Capture never
             opens it; it never touches CAT. */
    }
    enum def StartupRelease { enum pending; enum notNeeded; enum released; enum failed; }
    action def StartupSafetyRelease {
        doc /* Safety release after a station boot (supervisor decision 2026-10-31 on #9):
             a crash while keyed can leave the radio transmitting (a CI-V TX switch
             latches). On the first fresh confirmed 1C 00 readback of the boot (whoever
             queried it, normally the CL-022 automatic poll), if it shows TX and this
             boot has never keyed, the transmit owner sends exactly one off-only release
             1C 00 00 with readback through PttControl (released, or failed if not
             confirmed); otherwise notNeeded. Once per boot, never a key, never
             anything else, regardless of the profile's PTT configuration; a later TX
             (for example the operator's microphone) is not ended. failed keeps Arm
             refused for the boot. This is the single permitted exception to "the
             automatic CAT lifecycle never sends a setter/PTT" (CL-022-03). Reported as
             GET /transmit startup_release pending|not_needed|released|failed. */
    }
    attribute def TransmitArming {
        attribute armState : ArmState = ArmState::disarmed;
        attribute lastDisarmCause : DisarmCause = DisarmCause::startup;
        doc /* One armed state per station, owned by WstxArchitecture::TransmitService;
             disarmed at startup and after every DisarmCause. Arm/Disarm are requests
             from QsoAndLogging (Enable Tx) through the qso-to-transmit connection, or
             TransmitWire. Arming requires TransmitAuthority: unsupported capability
             is refused transmitUnsupported, unavailable radioUnavailable, a missing
             grant or a different safety revision notAuthorized. Disarm sends no new
             request and cancels requests that are not keyed; a transmission already
             keyed or playing finishes unless halted. */
    }
    attribute def TransmitRequest {
        attribute contactId : String[0..1];
        attribute requestSequence : Integer;
        attribute mode : WstxOfflineDecode::Mode;
        attribute periodStartUtcMs : Integer;
        attribute messageText : String;
        attribute txOffsetHz : Integer;
        doc /* At most one pending (not audio-started) request per station. Admitted only
             while armed under TransmitAuthority; the service packs messageText
             (PackMessage), plans the start (PlanTransmitStart), encodes the 48 kHz
             waveform, keys PTT and plays (TransmitTiming). requestSequence is a
             strictly increasing safe integer per boot: a lower or equal sequence is
             duplicateSequence, never transmits twice and changes nothing (a retry does
             not disarm). A new admitted request REPLACES the pending one (replaced)
             while its audio has not started; a keyed pending request is replaced only
             by one for the same period (else busy). From audio start a request for the
             same period is refused audioStarted (no disarm) and one for another period
             becomes the next pending request, started after the current one completes.
             Clock, alignment and lateness refusals (clockNotSynchronized,
             misalignedPeriod, stalePeriod) and packRefused or frequencyOutOfRange are
             checked at admission; the start is planned again at keying and at audio
             start, so a request that became stale is refused, never replayed. A
             request of another boot is refused at the wire (state_conflict). */
    }
    enum def TransmitOutcomeKind { enum accepted; enum replaced; enum started; enum completed; enum halted; enum refused; enum failed; }
    attribute def TransmitOutcome {
        attribute outcomeSequence : Integer;
        attribute requestSequence : Integer;
        attribute kind : TransmitOutcomeKind;
        attribute refusal : TransmitRefusal[0..1];
        attribute failure : TransmitFailure[0..1];
        attribute audioStartUtcMs : Integer[0..1];
        doc /* started is reported at audio start, completed after the last sample and the
             confirmed PTT release, halted after HaltTransmit. refused (except
             duplicateSequence and audioStarted) and failed disarm (DisarmCause refused,
             failed, deviceLost or authorityChanged). outcomeSequence orders all outcomes
             of a boot; the consumer reads those after its cursor; the last 32 are
             retained. No outcome is inferred from a client timeout or a lost response. */
    }
    action def HaltTransmit {
        doc /* Immediate priority stop of a transmission or Tune: stops audio without the
             owner lock, releases PTT with readback (TransmitTiming haltMs), cancels the
             pending and next requests (halted) and disarms (DisarmCause halt). Always
             admitted for the selected profile (no boot or revision check), idempotent,
             independent of decode, receive or display congestion
             (ProcessingAndHaltOwnership). Wire: POST /transmit/halt exactly
             {v,profile_id,boot_id,command_id}, 202 {v:1,command_id,halt_state} with
             halt_state stopped (confirmed within 250 ms), pending (not yet confirmed;
             GET /transmit shows the result) or idle (nothing was keyed); a repeated
             command_id returns the same receipt (last 16). */
    }
    action def SetTune {
        in enable : Boolean;
        doc /* Unmodulated tone at the given Tx offset (200..2950 Hz) under the same
             authority, armed and with nothing pending; stopped by SetTune(false),
             HaltTransmit or the tune limit (WstxContact::TuneWatchdog, default 90 s,
             1..300 s) with PTT release. */
    }
    attribute def TransmitWatchdog {
        doc /* WstxContact::TxWatchdog enforced by the owner: limit 1..99 minutes (default
             6 at each start), counted only while armed, reset at Arm, on accepted
             operating activity (every accepted transmit command; the contact consumer
             reports its own) and at the start of a transmission whose text differs from
             the last one. At expiry the owner halts and disarms (txWatchdog) and
             reports tx_expired until the next Arm. */
    }
    attribute def TransmitWire {
        doc /* Selected-profile routes, existing authentication, exact Origin on mutations,
             JSON media rules, 1024-byte bodies and error envelope; identity-coded (not
             in the compressed GET allowlist); no WebSocket or StatusReply change.
             GET /transmit: exactly {v:1,profile_id,boot_id,transmit,ptt,transmitting,
             clock,clock_measurement,clock_source,clock_warning,watchdog,outcomes,startup_release} with transmit exactly the WstxContact read view
             without its safety_revision: {capability,arm_state,last_disarm_cause,tune,pending_sequence,last_text,
             last_period_utc,halt_state,refusal}, ptt released|keyed|indeterminate,
             clock synchronized|unsynchronized|unknown (the station clock: TransmitClock
             and AirClock by clock_source ntp|air|both), clock_warning null or
             ntp_air_disagree (AirClock),
             clock_measurement null before the first answer, else exactly the latest
             measurement {server,offset_ms,round_trip_ms,age_ms} (server as configured,
             age at the read), watchdog exactly {tx_minutes,
             tx_remaining_minutes,tx_expired,tune_seconds,tune_remaining_seconds} and
             outcomes the last 8 {outcome_sequence,request_sequence,kind,refusal,failure,
             audio_start_utc_ms} and startup_release the StartupSafetyRelease state;
             enum values snake_case.
             POST /transmit/command: exactly {v,profile_id,boot_id,command_id,action}
             plus the action's parameters: arm {safety_revision}; disarm {};
             request {request_sequence,mode ft8|ft4,period_start_utc_ms,message_text,
             tx_offset_hz}; tune {enabled} or {enabled true,tx_offset_hz};
             set_watchdogs {tx_minutes,tune_seconds}. 200 {v:1,profile_id,boot_id,
             command_id,result}: result is the TransmitOutcome of a request, otherwise
             {accepted,refusal}. A retained command_id (last 16) with the identical body
             returns the same reply without effect, a different body is state_conflict;
             another boot is state_conflict. POST /transmit/halt: HaltTransmit. */
    }
    dependency armingPromise from TransmitArming to WstxRequirements::'FR-008';
    dependency pttPromise from PttControl to WstxRequirements::'FR-009';
    dependency authorityPromise from TransmitAuthority to WstxRequirements::'CL-009-03';
    dependency haltClausePromise from HaltTransmit to WstxRequirements::'CL-009-04';

    attribute def StationModeGate {
        attribute stationMode : WstxOfflineDecode::Mode[0..1];
        doc /* #11 CL-011-04 (review repair 2026-11-01). The transmit owner holds the
             station's operating mode (WstxContact::StationOperatingMode), set by the
             station at every change of that mode (live job start, admitted operating
             selection, owner start) and refreshed by every contact step. A request
             whose mode differs is refused staleRequest at admission (disarming as any
             admission refusal) and, if the mode changes after admission, refused
             staleRequest when its period starts, before PTT is keyed or audio starts
             (a request keyed before audio is released); it is never keyed or played.
             A transmission whose audio already started finishes, as with any disarm,
             and a mode selection is refused busy meanwhile (WstxContact::ModeChange).
             The gate does not depend on the 50 ms contact step. Absent stationMode
             (an owner not yet told) gates nothing. */
    }
    action def PlanTransmitStart {
        in mode : WstxOfflineDecode::Mode;
        in nowUtcMs : Integer;
        in clock : ClockState;
        in periodStartUtcMs : Integer;
        in sampleRateHz : Integer;
        out audioStartUtcMs : Integer[0..1];
        out skippedSamples : Integer[0..1];
        out refusal : ScheduleRefusal[0..1];
        doc /* The mode is explicit in every request and selects Ft8Schedule or
             Ft4Schedule; a period aligned for one mode only is misalignedPeriod for
             the other. Selecting the next slot also takes the mode. For every mode a
             start is stalePeriod once elapsed time reaches the 75 % limit or once the
             skipped samples would reach the waveform's sample count (audio delay plus
             waveform duration: FT4 5340 ms; FT8 13140 ms, after its 11.25 s limit), so
             an empty transmission is never admitted; the next slot uses the same
             window. */
    }
}
