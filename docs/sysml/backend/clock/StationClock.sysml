package WstxTransmitClock {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-005';
    private import WstxRequirements::'FR-016';
    private import WstxTransmitSchedule::'CL-009-02';
    private import WstxLiveReceive::'CL-007-05';
    private import WstxOperatingLayout::'CL-037-02';
    private import WstxRequirements::AutomationState;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    requirement 'CL-043-02' {
        doc /* The station estimates its clock offset from the decodes of its live receive
             (WstxTransmitClock::AirClock): every published decode whose message names a
             concrete sending call (the from call of the standard, field day, RTTY and VHF
             families, the full call of a nonstandard CQ) with a known SNR of at least
             -20 dB and |raw DT| at most 3000 ms is an observation; raw DT is the DT
             against the uncorrected system clock (the capture drift of CL-007-05
             included, the station clock correction of CL-043-03 not). Decodes of the
             profile's own call (any case: the station's own echo) never count. The
             observations of the last 120 s of system time form the estimate (#92,
             operator 2026-11-09: "Our station should always be in the middle"): one
             vote per distinct station, the median of its raw DT plus the current
             correction (its DT against station UTC); no estimate without a vote;
             stations = the votes, median_dt_ms = the median of all votes (no trimming),
             plus = the votes above +100 ms, minus = the votes below -100 ms. The
             estimate is evidence when stations is at least 4 and plus or minus is at
             least 80 % of stations (5 x count >= 4 x stations): the stations differ in
             one direction. Medians of an even count are the floor of the mean of the
             middle pair. A system clock step of more than 100 ms between observations
             (system time elapsed minus monotonic time elapsed) discards all observations
             and the estimate and is subtracted from a nonzero correction, so station UTC
             stays continuous (a step that corrected the system clock leaves 0); a
             correction beyond 3000 ms after that restarts at 0; a correction of 0 stays
             0 (the accepted time is the system clock). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/air.rs; server/src/recording.rs; server/src/transmit_http.rs"; }
    }
    dependency CL_043_02_to_FR_006 from 'CL-043-02' to 'FR-006';
    dependency CL_043_02_to_FR_004 from 'CL-043-02' to 'FR-004';
    verification 'TC-043-001' {
        doc /* Clock from the air: estimates of known DT distributions
             Setup: hand-written raw DT sets around a twelve-station crowd with true DT
             -250, -150, -100, -50, 0, 0, 50, 100, 150, 200, 300, 400 ms (median 25 ms);
             the pure AirClock and StationClock on explicit or real clocks with a fake
             SNTP monitor; no receive, radio or network.
             Steps (#92 rule): run periods for the crowd with a station clock 2 s ahead
             (raw DT +1750 to +2400) and 1.5 s behind (raw DT -1750 to -1100); the 2 s
             ahead crowd plus a station with a bad clock at raw DT +800; one station
             decoded twenty times; two and three stations at +1850; four at +1850; five
             at +1850 among nine scattered around 0; a crowd split at -500 and +500;
             observe the own call (any case), SNR -20.5/None/NaN, |DT| 3001 and 3000; a
             quiet band after a correction; the estimate of the 2 s ahead crowd (median
             +2025 ms) with no further window, read 60 s and 60 s + 1 ms later; a 100/101
             ms system clock step with correction -2000; the 2 s fast system clock stepped
             back to UTC; a +5 s step; the 2 s ahead crowd with SNTP +12 ms, with SNTP
             -1900 ms and without SNTP.
             Oracles (hand-computed; #92): 2 s ahead: 12 votes all plus, median +2025,
             correction -1000 (unsynchronized, median then +1025) and -2000 in the next
             period, then votes median +25 with 4 plus and 2 minus (mixed) and the
             correction kept at -2000, synchronized; 1.5 s behind: median -1475, +1000
             (unsynchronized), then median -475 with 11 of 12 minus (evidence) +1475,
             then 4 plus and 3 minus (mixed) kept at +1475; with the bad clock 13 votes
             all plus, median +2000, -1000 then -2000, then 4 plus and 3 minus kept; the
             chatty station one vote; two and three stations no evidence; four at +1850
             evidence, -1000 then -1850; five of nine (55 %) no evidence; the split crowd
             mixed (50 %); only the two in-range observations admitted; the quiet band
             keeps the last correction, synchronized; that estimate (median +2025 ms)
             is unsynchronized at 60 s and synchronized at 60 s + 1 ms, the correction
             -1000 ms both times; the 100 ms step changes
             nothing, the 101 ms step clears the window and makes the correction -2101
             (forward step); stepping back to UTC leaves correction 0; the +5 s step
             restarts at 0; only synchronized plans a transmit start; correction and state
             equal with SNTP +12, -1900 and none (SNTP never applied), warning
             stations_off with SNTP +12 and correction -2000, pc_clock_off with -1900.
             no audio, radio or
             network. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }
    // #92 Time synchronization in three situations: the station clock is always known.
    verification 'TC-092-001' {
        doc /* Evidence rule of the clock from the air
             Setup: the pure AirClock and StationClock on explicit clocks with a fake SNTP
             monitor; hand-written votes, one per station, given as DT against station
             UTC (raw DT plus the correction), FT8 periods; no receive, radio or network.
             Steps (#92 rule, operator 2026-11-09): from start (correction 0) periods
             with no station; three stations at +1500 ms; four at +1500; 15 at +600 and 4
             at -600 (15 of 19); 16 at +600 and 4 at -600 (16 of 20); four at +100; four
             at +101; four at -100; four at -101; four at +600 and four at -600; four at
             +1000; four at +1001; four at +2500 for three periods, with two windows in
             the first; a quiet band for 20 periods after a correction of -1500 ms;
             from start four votes at +1500 ms in one window and then no further window,
             read 60 s and 60 s + 1 ms later; observations 120 s and 120 s + 1 ms old;
             a 100 ms and a 101 ms system clock step; with correction -1000 ms forward
             steps of 2000 ms and, from the same start, 2001 ms; with correction 0 a
             +525 ms step.
             Expected (hand-computed medians; independent oracle: CL-043-02/03 and the
             operator's rule of 2026-11-09): no station and three stations: no evidence,
             correction 0, synchronized; four at +1500: evidence, -1000 (unsynchronized:
             median 1500 above 1000), then votes +500 all plus: -1500, synchronized; 15
             of 19 (78.9 %): no change; 16 of 20 (80 %): evidence, median +600, -600; four
             at +100 and at -100: no change (not beyond the 0.1 s margin); four at +101
             and at -101: -101 and +101; +600/-600 mixed: no change; four at +1000:
             synchronized, -1000; four at +1001: unsynchronized until the next estimate,
             -1000, then votes +1 (no evidence) synchronized with -1000 kept; four at
             +2500: -1000 in the first period (the second window of that period adds
             nothing), -2000 in the second (unsynchronized, median +1500), -2500 in the
             third (median +500, synchronized); the quiet band keeps -1500, synchronized
             (no reset, no alternation); the estimate of four votes at +1500 ms with no
             further window: unsynchronized at 60 s, synchronized at 60 s + 1 ms, the
             correction -1000 ms both times; observations count at 120 s and not at 120 s + 1 ms; the
             100 ms step changes nothing, the 101 ms step clears the window; the 2000 ms
             step leaves -3000 ms, the 2001 ms step restarts at 0; the +525 ms step leaves
             0; the state is never unknown.
             no audio, radio or
             network. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-02';
            verify 'CL-043-03';
        }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
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
             is the station clock's (AirClock, #43), which is never unknown and does not
             depend on this SNTP state (#92). The
             monitor records whether any round since start asked a server, for the
             warning ntp_unreachable (#92). #92 situation 1: the station never sets the
             Windows clock and never starts or configures a service (it runs without
             administrator rights); it reads the Windows Time service state (running,
             stopped, disabled; unknown when the query fails) without administrator
             rights, for the remedy of the warning pc_clock_off (CL-043-03). */
    }
    attribute def AirClock {
        attribute minSnrDb : Integer = -20;
        attribute maxDtMs : Integer = 3000;
        attribute windowS : Integer = 120;
        attribute minStations : Integer = 4;
        attribute sameSidePct : Integer = 80;
        attribute sideMarginMs : Integer = 100;
        attribute maxSlewPerPeriodMs : Integer = 1000;
        attribute maxAgeS : Integer = 60;
        attribute txBoundMs : Integer = 1000;
        attribute maxStepRestartMs : Integer = 3000;
        assert constraint robust { minStations >= 2 and sideMarginMs < txBoundMs and maxSlewPerPeriodMs <= txBoundMs and txBoundMs < maxStepRestartMs }
        doc /* #43 the clock from the air (WstxRequirements CL-043-01..03); #92 the
             air is the reference (operator 2026-11-09: "accept the OTA time as the
             reference"; "Our station should always be in the middle"): station UTC is
             always the system clock plus this correction, without a source setting or
             basis; TransmitClock (SNTP) only measures the system clock for warnings.
             Observations: decodes with a concrete sending call other than the profile's
             own, SNR >= minSnrDb and |raw DT| <= maxDtMs, raw DT against the uncorrected
             system clock; the last windowS; one vote per station, the median of its raw
             DT plus the current correction; median of all votes (no trimming); plus and
             minus the votes beyond +sideMarginMs and -sideMarginMs. Evidence: at least
             minStations votes and plus or minus at least sameSidePct of them. Each
             completed decode window re-estimates; an estimate counts while at most
             maxAgeS old and unstepped; evidence moves the correction toward the middle
             (correction minus the median) by at most maxSlewPerPeriodMs in total within
             one period; without evidence (mixed sides, fewer stations, no estimate) the
             last correction is kept; it starts at 0; no search. A system clock step
             above 100 ms is subtracted from a nonzero correction (station UTC
             continuous), a correction of 0 stays 0, and a correction beyond
             maxStepRestartMs after a step restarts at 0. unsynchronized: a counting
             evidence estimate with |median| > txBoundMs; synchronized otherwise; never
             unknown; the SNTP state never changes it. The correction is added to station
             UTC for receive windows, period/DT, transmit planning and audio start; the
             SNTP offset is never applied and the system clock is never set. Warnings
             pc_clock_off, ntp_unreachable and stations_off as CL-043-03. Taking each
             vote from raw DT keeps the estimate independent of the windows it aligns,
             so the correction converges to the middle without oscillating with the
             receive windows or the capture drift tracker (WstxRadioIO, #47). */
    }
    requirement 'CL-009-05' {
        doc /* Determine the station clock state for transmit from the station's own SNTP
             measurement, off the transmit and audio threads, at start and every 60 s
             with the servers ch.pool.ntp.org, time.windows.com, pool.ntp.org in that
             order (the next when one does not answer validly within 1.5 s):
             synchronized when the latest measurement is at most 10 min old and its
             |offset| is at most 500 ms, unsynchronized when outside, unknown without a
             recent measurement or when the system clock stepped by more than 100 ms
             since it; report the offset, server and age on GET /transmit and with the
             transmit state in the browser. #43, #92 (operator 2026-11-09: "we always
             know the time. It just might be wrong ... never an unknown time"; "accept
             the OTA time as the reference"): transmit is admitted by the station clock
             state of CL-043-03, which is never unknown and does not depend on this SNTP
             state: unsynchronized only while the stations heard show the station clock
             more than 1 s off to one side, otherwise synchronized. This SNTP state only
             gives the warnings pc_clock_off and ntp_unreachable (CL-043-03); it never
             refuses transmit and its offset is never applied.
             GET /transmit also reports clock_warning. Details:
             WstxTransmitClock::TransmitClock, AirClock, TransmitWire. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/clock.rs; server/src/transmit/air.rs; server/src/transmit_http.rs; server/src/main.rs; client/recording.js"; }
    }
    dependency CL_009_05_to_FR_006 from 'CL-009-05' to 'FR-006';
    verification 'TC-006-003' {
        doc /* Station SNTP clock measurement
             Setup: hand-computed NTP timestamps; fake SNTP responders on 127.0.0.1
             (silent, kiss-of-death stratum 0, answering a fixed offset ahead of the
             request) with a fake station clock; a scripted blocking measurement
             source; the actual station router with an injected clock monitor.
             Steps: compute offsets and round trips including an NTP era boundary;
             present short, wrong-mode, stratum 0/16, zero-transmit, wrong-origin and
             leap-alarm replies; measure over silent, refusing, answering and later
             servers; a fake station clock stepping +10 s during the exchange; derive
             states at |offset| 500/501 ms, ages 10 min / 10 min + 1 ms and system
             clock steps of +-100/+-101/+-2000 ms after the measurement; plan FT8 and
             FT4 starts with each derived state; read the state while a measurement
             blocks; GET /transmit before and after measurements; the browser transmit
             status with a transmit.state fixture.
             Oracles: RFC 4330/5905 arithmetic by hand (590/20 ms, -705/10 ms, 495/10
             ms); every invalid reply refused, stratum 1 and 15 accepted; servers asked
             once each in order, none after the first valid answer, none answering
             gives no measurement; a step during the exchange leaves the offset at
             3 s (not -2 s); 500 ms synchronized, 501 ms unsynchronized, older than
             10 min unknown, a step above 100 ms unknown; only synchronized admitted (else
             clockNotSynchronized); reading never waits for a measurement; exact
             clock_measurement keys {server,offset_ms,round_trip_ms,age_ms}, null and
             unknown before the first answer; the status reads "clock synchronized
             +12 ms ch.pool.ntp.org 34 s ago".
             loopback UDP only, no
             public time server, audio or radio; the actual server and Chromium for the
             status line. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-009-05';
            verify 'CL-009-02';
        }
        @TestedBy { test = "server/tests/transmit/transmit_clock.rs; server/src/transmit/transmit_http_tests.rs; tests/ui-operating.test.cjs"; }
    }

    // #43 Optional clock from the air (defaults chosen on the CR, recorded in AirClock).
    requirement 'CL-043-01' {
        doc /* (#43; #92 operator 2026-11-09: the three situations of CL-043-03 are fixed
             behaviour; "accept the OTA time as the reference") The station clock has no
             source setting and no basis: station UTC is always the system clock plus
             the correction from the air (CL-043-02/03); NTP only measures the system
             clock. clock.json (#43) is no longer read or written; a file left by #43 is
             ignored and left in place. POST /clock no longer exists (the router's answer
             for an unknown route), and GET /transmit has no clock_source. GET /clock
             (operating access, no query, empty body) returns exactly {v 1, profile_id,
             boot_id, state synchronized|unsynchronized (never unknown), correction_ms,
             ntp {state, measurement null | {server, offset_ms, round_trip_ms, age_ms},
             windows_time running | stopped | disabled | unknown}, air {estimate null |
             {median_dt_ms, stations, plus, minus, age_ms}}, warning null | pc_clock_off
             | ntp_unreachable | stations_off, capture_warning null | uncorrelated |
             drift_high, clock_revision}. Pushed state (#92 operator 2026-11-09
             "Everywhere"; WstxStationLink::PushedStationState): a WebSocket event
             exactly {v:1, type:"clock.state", data:{profile_id, boot_id,
             clock_revision, clock:{state, correction_ms, warning, ntp_offset_ms,
             capture_warning}}}, at most 512 bytes, for every profile (receive-only
             too), sent to each peer with a display subscription once after its first
             subscription and then when a field of clock changes, coalesced to at most
             one per second per peer and sent within 1 s of the change; clock_revision is
             a station-wide safe integer increasing at each change of those fields (GET
             /clock carries the same value); ntp_offset_ms is the SNTP offset while
             warning is pc_clock_off, else null, so a healthy clock sends no event per
             SNTP round. The browser holds the clock state from these events (no GET
             /clock and no timer for it). The operator view is Settings > General >
             Clock: a status line with state, correction, the median DT of the stations
             heard, how many are heard and how many are above +0.1 s and below -0.1 s,
             its age, the SNTP offset, the warning text and remedy of CL-043-03; for
             these details the browser reads GET /clock only when the
             Settings drawer opens (at most every 10 s) or the General tab is chosen,
             never on a timer, so the thin link carries no clock polling. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/clock_http.rs; server/src/main.rs; server/src/recording.rs; server/src/transmit_http.rs; client/contact.js; client/recording.js"; }
    }
    dependency CL_043_01_to_FR_006 from 'CL-043-01' to 'FR-006';
    dependency CL_043_01_to_FR_016 from 'CL-043-01' to 'FR-016';
    requirement 'CL-043-03' {
        doc /* (#43; #92 operator 2026-11-09: "we always know the time. It just might be
             wrong ... never an unknown time"; "computer time not NTP time --> try to fix
             and if not possible, warning; WSJTX time not computer time --> try to fix
             and if not possible, warning"; "I think we should accept the OTA time as the
             reference because this is what counts. If other stations report differences
             in one direction, then for sure our station is wrong. And we have to do
             something against it."; "Our station should always be in the middle ... If
             the other stations show plus and minus, then we do not have to react"; the
             200 ms NTP/air disagreement warning: "Drop it") Three situations, each fixed
             where the station can and otherwise warned.
             (1) PC clock against NTP: the SNTP state of CL-009-05. The station never
             sets the Windows clock and never starts or configures a service (it runs
             without administrator rights); it reads the Windows Time service state
             (running, stopped or disabled; unknown when the query fails) without
             administrator rights and names the remedy. Warning pc_clock_off while the
             SNTP state is unsynchronized; else ntp_unreachable while at least one SNTP
             round since start has asked a server and no valid measurement is at most
             600 s old (not in the gap after a detected step, before the first round
             ends or with an empty server list).
             (2) Station time against the PC clock: the capture clock is re-anchored to
             the PC's UTC by CL-007-05 (#47), which is the fix; the applied correction
             of (3) is a deliberate difference, shown in the status line, never warned.
             capture_warning (the station, only while live receive runs; operator
             2026-11-09 "Also on large drift"): uncorrelated while a capture epoch exists
             and its clock is not correlated to UTC (no re-anchoring possible; null while
             no epoch exists yet, so a receive start or restart is no entry, CL-037-02),
             else drift_high while
             |capture_drift_ppm| (CL-007-05, known after the first 60 s) is above 1000 ppm
             (at 1000 ppm the audio frequency error reaches a quarter of the FT8 tone
             spacing at 1500 Hz, 1.5 of 6.25 Hz, and the drift within one FT8 period
             15 ms; a sound card crystal is normally within 100 ppm), else null.
             (3) Out of step with the stations heard, the reference on every SNTP state:
             each completed live decode window (prompt and late) re-estimates
             (CL-043-02); the latest estimate counts while at most 60 s old and
             unstepped. When it is evidence (at least 4 stations, at least 80 % of them
             on one side by more than 100 ms) the correction moves toward the middle,
             correction minus median_dt_ms, by at most 1000 ms in total within one period
             of the current mode; with mixed sides, fewer than 4 stations or no estimate
             it does not change: the last correction is kept. The correction starts at 0
             at station start; a system clock step is handled as CL-043-02; there is no
             search (no change without evidence). The SNTP offset is never applied and
             the Windows clock is never set. Station UTC is always the system clock plus
             the correction, used alike for live receive window alignment,
             period_start_utc and DT of results (in addition to the capture drift, #47),
             transmit planning and audio start (CL-009-02), the contact engine and UDP
             times. The station clock is never unknown: unsynchronized while the latest
             counting estimate is evidence with |median_dt_ms| above 1000 ms (FT8 still
             decodes within about +-1 s), else synchronized, whatever the SNTP state.
             Transmit is refused for the clock (clock_not_synchronized) only while the
             station clock is unsynchronized, never for a smaller one-sided offset while
             the correction catches up. Because each vote is taken from raw DT plus the
             current correction, the correction converges to the middle without
             oscillating; with the live window coverage of corrected DT (-1.7 s to
             +2.56 s) it finds system clock errors of about -2.5 s to +1.7 s; outside
             them too few stations decode, there is no evidence and the time is
             accepted. stations_off (#92 operator 2026-11-09 "Note above 500 ms"):
             while the SNTP state is synchronized and |correction| is above 500 ms, the
             cause lies outside the PC clock (for example audio latency).
             GET /clock warning and GET /transmit clock_warning carry the same value, the
             first that holds of pc_clock_off, ntp_unreachable, stations_off. Error field
             entries (CL-037-02), from clock.state (CL-043-01): while transmit is
             configured "Clock off · Tx blocked" (error) while the station clock is
             unsynchronized; for every profile (operator 2026-11-09 "Everywhere") one warn
             entry per warning and capture_warning, also while transmit works:
             pc_clock_off "PC clock <n> ms slow vs
             NTP · see Settings" ("fast" for a negative offset, n = |SNTP offset_ms|),
             ntp_unreachable "NTP not reachable · check the network", stations_off
             "Clock corrected <c> ms from the air · PC clock matches NTP, check audio
             latency" (c = correction_ms with sign); uncorrelated "Audio timing not tied to the
             PC clock · DT may be off"; drift_high "Sound card clock drifts over
             1000 ppm · check the audio device". The clock entries open Settings >
             General > Clock, the audio entries the receive details (which read GET
             /receive/clock on demand); each disappears when its condition clears. The Settings clock status
             line appends the warning text and for pc_clock_off the remedy by
             windows_time: stopped "Windows Time service is stopped: start it and set it
             to Automatic (services.msc, as administrator)"; disabled "Windows Time
             service is disabled: set it to Automatic and start it (services.msc, as
             administrator)"; running "Windows Time runs but the clock is off: Settings >
             Time & language > Date & time > Sync now"; unknown "Check the Windows Time
             service and sync the clock". GET /transmit clock_warning keeps carrying the
             warning value for other clients. Without evidence and with correction 0 the status line reads
             "Clock accepted (stations heard are not off to one side)" instead of the
             synchronized wording. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/air.rs; server/src/transmit/clock.rs; server/src/transmit/windows_time.rs; server/src/transmit/clock_http.rs; server/src/recording.rs; server/src/transmit_http.rs; server/src/main.rs; client/contact.js; client/recording.js"; }
    }
    dependency CL_043_03_to_FR_006 from 'CL-043-03' to 'FR-006';
    dependency CL_043_03_to_FR_005 from 'CL-043-03' to 'FR-005';
    verification 'TC-043-002' {
        doc /* Clock from the air: stable feedback with the receive windows
             Setup: (a) the AirClock in a closed receive loop of 40 FT8 periods: the crowd
             of TC-043-001 plus a +1.2 s bad clock, decodable only while their corrected DT
             lies in the live window coverage -1.7 s to +2.56 s, both windows completing
             each period; (b) the actual live worker, window buffer and ClockTracker with
             a scripted capture clock 300 ppm slow (actual Recording, no SNTP measurement).
             Steps: (a) station clock errors -2 s, +1.5 s, +0.6 s, 0, +2 s and +3 s; the negative
             control replaces the correction in full by an estimate from corrected DT;
             (b) 301 s of capture, the air correction becoming -2000 ms at 150 s; then
             publish one CQ K1ABC decode 17.0 s after the anchor with 0.5 s drift at
             correction -2000 ms and 0; (c) the live worker analyzes the FT8 prompt window
             of a period-aligned CQ K1ABC with the system clock 2 s slow and correction
             +2000 ms.
             Oracles (#92): (a) for -2 s, +1.5 s and +0.6 s the applied correction
             settles within 50 ms of error - 25 ms within two periods, never moves again
             and approaches monotonically; 0 keeps correction 0 (mixed sides: 5 of 13
             votes above +100 ms); +2 s and +3 s keep correction 0 and stay synchronized over 20
             periods (no evidence, the time accepted, no alternation); the negative
             control alternates
             -2025, 0, -2025, ...; (b) 20 prompt windows (none lost or repeated), each after
             the first completing within 100 ms of +13.8 s of corrected UTC across the
             drift and the correction; the decode at period 00:00:15 with DT 0.0 s at
             -2000 ms and 2.0 s uncorrected, the estimator receiving raw DT 2000 ms both
             times; (c) the record, the FT8 SNR period start and the window diagnostics
             (period start frame and UTC, window offset -1200 ms) equal those of a correct
             clock, the SNR that of the file decode of the same period.
             no audio device, radio
             or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-043-03';
            verify 'CL-007-05';
        }
        @TestedBy { test = "server/tests/transmit_air_clock.rs; server/src/recording_tests.rs"; }
    }
    verification 'TC-043-003' {
        doc /* Clock view, wire and display
             Setup: the actual station router on a disposable profile directory with the
             station clock as main wires it (SNTP monitor that never measures); the actual
             transmit owner; the actual server and Chromium with routed clock.state events
             (as TC-092-005; the error-field clock entries come from clock.state, not
             transmit.state), a transmit-configured profile and GET /clock fixtures where
             stated.
             Steps (#92): open with clock.json missing and with a #43 file {schema_version
             1, profile_id, source ntp}; GET /clock; GET /transmit; hear twelve stations at
             raw DT +1555 ms over two periods; POST /clock; on the transmit owner hear two
             then six stations at raw DT +2000 ms for three periods, read its clock and
             UTC. In the browser: requests before Settings opens; open Settings >
             General; an estimate fixture (correction -1980 ms, 14 stations, 2 above
             +0.1 s, 3 below -0.1 s, median DT +20 ms, 3 s old, SNTP +12 ms); clock.state
             events with clock synchronized and correction 0, synchronized and -1980,
             unsynchronized (warning and capture_warning null).
             Oracles: the same behaviour with and without the file, the file unchanged;
             exact view keys of CL-043-01 (no source, basis, disagreement_ms or
             storage_error), state synchronized, correction 0; GET /transmit without
             clock_source, clock_warning null, clock synchronized; estimate median +1555
             ms, 12 stations all plus, correction -1000 then -1555 ms, synchronized;
             POST /clock answered as an unknown route; the owner synchronized with
             correction 0 with two stations (no evidence), with six -1000 (unsynchronized:
             median +2000) then -2000, synchronized, station UTC 2000 ms (+-10 ms) behind
             the system clock. Browser: no /clock request before Settings opens; no
             source select; the status line exactly "Clock synchronized, correction
             -1980 ms · stations heard: 14, 2 above +0.1 s, 3 below -0.1 s, median DT
             +0.02 s, 3 s ago · NTP +12 ms"; chips exactly none, none, Clock off · Tx
             blocked; the Clock line names the correction.
             loopback only, no
             public time server, audio or radio. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        @TestedBy { test = "server/src/transmit/clock_http_tests.rs; tests/ui-operating.test.cjs"; }
    }
    verification 'TC-043-004' {
        doc /* Live clock from the air on HB9BLA
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3, USB Audio
             CODEC, FT8 receive on a band with at least ten stations heard; for the transmit steps, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). Steps (1)-(4)
             keep the PC clock disciplined by NTP and need no administrator rights (agents
             have none); step (5), the issue's offset-clock check, is performed by the
             operator with administrator rights.
             Steps (#92): (1) read GET /clock and GET /transmit for three periods (SNTP
             offset, air estimate); read Band Activity DT. (2)-(3) none (no source
             setting). (4) with the operator's consent for transmit, arm and send one CQ;
             check PSK Reporter spots of HB9BLA and a partner's DT. (5) operator,
             administrator: stop Windows Time (w32time) and any clock tool, set the PC
             clock 1.5 s fast, wait four FT8 periods and one SNTP round, read GET /clock,
             GET /transmit and Band Activity DT; repeat with the PC clock 1.5 s slow and
             2.0 s slow; restore the clock and its service.
             Expected: (1) state synchronized with |SNTP offset| at most 500 ms; the
             correction either unchanged (mixed sides) or moved to the stations' middle
             (the crowd's own DT bias, typically +0.1 to +0.2 s, and the correction are
             recorded); Band Activity median DT within +-0.1 s of 0 after a correction;
             warning null while |correction| is at most 500 ms; GET /transmit clock
             synchronized; no clock chip; (4) the
             transmission is admitted, starts at the period start + 0.5 s of station UTC,
             and PSK Reporter spots and the partner's DT (within +-0.5 s) confirm the
             transmitted timing; (5) warning pc_clock_off with windows_time stopped;
             within four periods state synchronized with correction_ms
             within 200 ms of -1500 and +1500 ms respectively, Band Activity median DT
             within +-0.5 s; at 2.0 s slow (the edge of the found range) correction_ms
             either within 200 ms of +2000 ms (enough edge stations decode) or 0 (the time
             accepted), state synchronized either way; each time GET /transmit clock
             synchronized (transmit admitted); a
             transmission under step (4)'s consent is spotted on time.
             Steps (1) and (5) without transmit are receive-only, cost 4; transmit
             steps are cost 5.
             explicit operator consent;
             HB9BLA. Not run by the automated gate. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-043-01';
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
    }
    verification 'TC-092-002' {
        doc /* Replay of the 10 m FT4 refusals of 2026-11-09
             Setup: StationClock with a fake SNTP monitor holding a current
             measurement +525 ms (unsynchronized); FT4 votes (DT against station UTC) of
             6 stations: four at -339 ms, one at -50 and one at +100; PlanTransmitStart
             on the station clock.
             Steps: complete windows with these six; then with five at -339 and one at
             +100; then with 2 stations; then with none for 3 minutes; plan a transmit
             start in each window.
             Expected (independent oracle: the operator's rule of 2026-11-09 and the
             observed 2026-11-09 values): the first crowd 4 of 6 below -0.1 s (66 %): no
             change, correction 0; then 5 of 6 (83 %): median -339, correction +339;
             then kept +339 with 2 and with no stations; the station clock synchronized
             in every window; every start planned (no clock_not_synchronized); warning
             pc_clock_off throughout. Red on the parent, which falls to unknown and
             refuses.
             no audio, radio or
             network. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }
    verification 'TC-092-003' {
        doc /* The three situations: correction, state and warnings
             Setup: StationClock with a fake SNTP monitor that records rounds (asked a
             server or not, answer or none), votes set directly (DT against station UTC)
             and a fake Windows Time service reader; explicit clocks.
             Steps: SNTP +12 ms (synchronized) with four votes at +1500 ms for two
             periods; corrections -500 and -501 ms with SNTP +12; SNTP +500 and +501 ms
             without votes; SNTP -1900 ms with no evidence; one round asked with no
             answer and no measurement; a measurement 600 s and 600 s + 1 ms old after
             failed rounds; a 101 ms step with a young measurement; an empty server list
             (no round asks); no round yet; the service reader answering running,
             stopped, disabled and failing; with live receive a correlated clock at
             capture drift 1000.0, -1000.0 and 1000.1 ppm, a rate not yet known, receive
             running before its first capture epoch, an uncorrelated epoch, then receive
             stopped with 1500 ppm; system clock steps of +300 and -300 ms with
             correction 0; the 2026-11-09 recovery: SNTP +525 ms, the mixed crowd of
             TC-092-002 (correction 0), Windows Time steps the system clock +525 ms, the
             SNTP step gap (unknown), the next round +3 ms; correction -2000 ms with SNTP
             changing from synchronized to unsynchronized and back. GET /clock and GET
             /transmit after each.
             Expected (TransmitClock 500 ms / 600 s / 100 ms, CL-043-03): with SNTP
             synchronized the votes still move the correction (-1000, then -1500,
             synchronized) and give stations_off; stations_off null at -500 and set at
             -501 with SNTP synchronized; SNTP +500 null and +501 pc_clock_off with the
             correction and state unchanged; SNTP -1900 without evidence correction 0,
             synchronized, pc_clock_off (the SNTP offset is never applied);
             ntp_unreachable; null at 600 s and ntp_unreachable at 600 s + 1 ms; null
             after the step, with the empty list and before the first round, the station
             clock synchronized in each; windows_time running, stopped, disabled,
             unknown; capture_warning null at 1000.0 and -1000.0 ppm, drift_high at
             1000.1 ppm, null without a known rate, null before the first epoch,
             uncorrelated for the uncorrelated epoch, null with receive stopped; the
             steps leave correction 0 and station UTC equal to the system clock; the
             recovery gives correction 0 and station UTC equal to the system clock at
             every step, pc_clock_off until the +525 ms step, null in the SNTP step gap
             (SNTP unknown with a young measurement: neither warning applies) and after
             the +3 ms round, no
             clock_not_synchronized; the -2000 ms correction is kept through every SNTP
             change (SNTP never resets it); GET /clock warning equals GET /transmit
             clock_warning; no clock_source key; clock_revision increases at each change of
             a clock.state field and only then.
             no public time server,
             audio or radio. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        @TestedBy { test = "server/tests/transmit_air_clock.rs; server/src/transmit/clock_http_tests.rs; server/src/transmit/transmit_http_tests.rs"; }
    }
    verification 'TC-092-004' {
        doc /* No clock source setting
             Setup: the actual station router on a disposable profile directory, SNTP
             monitor that never measures, twelve stations heard at a clock 2 s fast.
             Steps: open with clock.json missing, then with #43 files {source ntp},
             {source air} and malformed JSON; GET /clock and GET /transmit each time;
             POST /clock {v 1, profile_id, boot_id, source ntp}.
             Expected (CL-043-01): in every case the same view: exactly the keys of
             CL-043-01 (no source, basis, disagreement_ms or storage_error), correction
             -2000 ms after two periods, synchronized; GET /transmit without
             clock_source; each file byte for byte unchanged; POST /clock answered as an
             unknown route.
             loopback only, no
             public time server, audio or radio. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-01';
        }
        @TestedBy { test = "server/src/transmit/clock_http_tests.rs"; }
    }
    verification 'TC-092-005' {
        doc /* Clock entries in the error field and the clock status line
             Setup: the actual server and Chromium at 1366x768 with routed transmit.state,
             receive state and GET /clock fixtures; a transmit-configured and a
             receive-only profile.
             Steps: routed clock.state events (no GET /clock outside Settings): transmit
             configured, clock synchronized, with warning pc_clock_off and ntp_offset_ms
             +525, then -620; ntp_unreachable; stations_off; null; clock unsynchronized
             with pc_clock_off; the receive-only profile with pc_clock_off, ntp_unreachable
             and stations_off; capture_warning uncorrelated, drift_high, then null on both
             profiles; count the /clock requests; click each entry; open Settings >
             General > Clock with GET /clock warning pc_clock_off and windows_time
             stopped, disabled, running and unknown, and with a view without evidence;
             stations_off with correction_ms -1980.
             Expected (CL-043-03 texts, CL-037-02): exactly one warn entry "PC clock
             525 ms slow vs NTP · see Settings" and no clock entry; "PC clock 620 ms fast
             vs NTP · see Settings"; "NTP not reachable · check the network"; "Clock
             corrected -1980 ms from the air · PC clock matches NTP, check audio latency";
             "No problems"; the two entries
             "Clock off · Tx blocked" (error) and the PC clock entry (warn); the same three
             warn entries on the receive-only profile and never "Clock off" there; "Audio
             timing not tied to the PC clock · DT may be off" and "Sound card clock drifts
             over 1000 ppm · check the audio device" (warn) on both profiles, gone at
             null; no /clock request before Settings opens; the clock entries open
             Settings clock, the audio entry the receive details; the status line remedy
             texts of CL-043-03 for each windows_time value, and without evidence and with correction 0 it
             begins "Clock accepted (stations heard are not off to one side)"; no source
             select; no view
             shows "Clock unknown" or "NTP and air clock disagree".
             no radio or
             RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-03';
            verify 'CL-037-02';
        }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-092-006' {
        doc /* Live clock state on HB9BLA after the deploy
             Setup: the deployed candidate on HB9BLA, receive running.
             Steps: read GET /clock and GET /transmit for three periods; look at the error
             field.
             Expected: no source key; state synchronized or unsynchronized, never
             unknown; ntp.windows_time as Windows reports it; the correction and the
             estimate (median DT, stations, plus, minus) recorded; warning null while
             |SNTP offset| and |correction| are at most 500 ms, else the CL-043-03 value,
             the same in both reads; the error field matches it; capture_drift_ppm from
             GET /receive/clock recorded.
             Not run by the automated gate. */
        @TestLevel { cost = 3; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
        }
    }
    verification 'TC-092-007' {
        doc /* Live PC clock offset
             Setup: HB9BLA, FT8 receive on a band with at least ten stations heard; the
             operator with administrator rights stops Windows Time (w32time) and any
             clock tool.
             Steps: set the PC clock 1.5 s fast, wait four FT8 periods and one SNTP round,
             read GET /clock, GET /transmit, the error field and Settings clock; set it
             0.4 s fast and repeat; restore the clock and its service and wait 60 s.
             Expected: at 1.5 s correction_ms within 200 ms of -1500 (Band Activity
             median DT within +-0.1 s), state synchronized, the warn entry "PC clock n ms
             fast vs NTP · see Settings" with n 1300 to 1700, Settings naming the stopped
             Windows Time service and its remedy, no Clock off; at 0.4 s correction_ms
             within 200 ms of -400, synchronized, no PC clock entry (SNTP within
             500 ms); after the restore a step that leaves station UTC continuous, the
             correction then moving back toward the stations' middle, and the entry gone
             within 60 s.
             operator with administrator rights. Not run by the
             automated gate. */
        @TestLevel { cost = 4; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-043-03';
        }
    }
    verification 'TC-092-008' {
        doc /* Live call on a sparse band with NTP not correct
             Setup: HB9BLA, IC-7300, 10 m FT4 with few stations; the operator's consent
             for transmit; NTP unsynchronized or unreachable (the operator's choice how).
             Steps: call stations or CQ for ten own periods; read GET /transmit and the
             error field.
             Expected (the reported failure of 2026-11-09): no clock_not_synchronized
             refusal over the ten periods; the yellow PC clock or NTP entry shown; PSK Reporter spots
             or a partner's DT within +-1 s.
             explicit operator consent;
             HB9BLA. Not run by the automated gate. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
    }
    verification 'TC-092-009' {
        doc /* clock.state pushed to every profile
             Setup: the actual server with a receive-only and a transmit-configured
             profile, a fake SNTP monitor and capture drift source, two WebSocket peers
             subscribed Detailed and Thin; loopback only.
             Steps: subscribe; wait 10 s with nothing changing; let the SNTP offset move
             from +12 to +40 ms (synchronized); set it to +525 ms; then +530 ms; three
             changes within 300 ms; set capture drift 1500 ppm; restore all; compare each
             event with GET /clock.
             Expected (CL-043-01): one event per peer after subscribing, exactly
             {v:1,type:"clock.state",data:{profile_id,boot_id,clock_revision,clock:{state,
             correction_ms,warning,ntp_offset_ms,capture_warning}}}, at most 512
             bytes; no event while nothing changes and none for +12 to +40 ms
             (ntp_offset_ms null); one event within 1 s with warning pc_clock_off and
             ntp_offset_ms 525, one with 530; the three quick changes coalesced into at
             most one event per second per peer, the last state delivered; capture_warning
             drift_high, then null; clock_revision increasing, equal to GET /clock's; the
             same on both profiles.
             loopback only, no
             public time server, audio or radio. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
        }
        @TestedBy { test = "server/src/transmit/clock_http_tests.rs"; }
    }
}
