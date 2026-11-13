package WstxTransmitClock {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-006';
    private import WstxArchitecture::'FR-004';
    private import WstxTransmit::'TC-043-004';
    private import WstxTransmit::'CL-009-05';
    private import WstxTransmit::'CL-043-03';
    private import WstxRequirements::AutomationState;
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
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/air.rs; server/src/recording.rs; server/src/transmit_http.rs";
    }
    dependency CL_043_02_to_FR_006 from 'CL-043-02' to 'FR-006';
    dependency CL_043_02_to_FR_004 from 'CL-043-02' to 'FR-004';
    dependency CL_043_02_verified_by_TC_043_001 from 'CL-043-02' to 'TC-043-001';
    dependency CL_043_02_verified_by_TC_043_004 from 'CL-043-02' to 'TC-043-004';
    dependency CL_043_02_verified_by_TC_092_001 from 'CL-043-02' to 'TC-092-001';
    verification 'TC-043-001' {
        doc /* TC-043-001 — Clock from the air: estimates of known DT distributions
             CL-043-02, CL-043-03, CL-009-05
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
             2 — Isolated automated tests; Windows development PC, no audio, radio or
             network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs";
    }
    // #92 Time synchronization in three situations: the station clock is always known.
    verification 'TC-092-001' {
        doc /* TC-092-001 — Evidence rule of the clock from the air
             CL-043-02, CL-043-03
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
             2 — Isolated automated tests; Windows development PC, no audio, radio or
             network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-02';
            verify 'CL-043-03';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs";
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
}
