package WstxStationClock {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-006';
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import WstxClockPart::ClockService;
    private import WstxStationTime::*;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelNotes::FollowsSource;

    // ---- Station time ---------------------------------------------------------------

    requirement 'CL-043-01' {
        subject clock : ClockService;
        doc /* The clock MUST hold station time as the PC clock plus its own correction
             (TimeBase). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-01'; }

    attribute def TimeBase {
        doc /* How station time is formed.
             Station time is the PC clock plus the correction, for every function alike. */
        attribute startCorrectionMs : Integer = 0 {
            doc /* The correction at station start. */ }
    }

    // ---- The correction from the air --------------------------------------------------

    requirement 'CL-043-02' {
        subject clock : ClockService;
        doc /* The clock MUST estimate how far station time is off from the stations it
             decodes (AirClock). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-02'; }

    attribute def AirClock {
        doc /* The estimate from the stations heard.
             An observation is a StationHeard that receive gives, whose call is not
             the profile's own.
             Each station has one vote: the median of its DT plus the current correction.
             The estimate is the median of all votes; for an even count, the floor of the
             mean of the middle pair. */
        attribute minSnrDb : Integer = -20 {
            doc /* A decode is an observation from this SNR upward. */ }
        attribute maxDtMs : Integer = 3000 {
            doc /* A decode is an observation up to this DT, either way, measured against
                 the uncorrected PC clock. */ }
        attribute windowSeconds : Integer = 120 {
            doc /* The estimate uses the observations of this many seconds. */ }
        attribute sideMarginMs : Integer = 100 {
            doc /* A vote counts as later or earlier when it is beyond this margin. */ }
        attribute minStations : Integer = 4 {
            doc /* The estimate is evidence from this many votes. */ }
        attribute sameSidePct : Integer = 80 {
            doc /* The estimate is evidence when this share of the votes lies on one
                 side. */ }
        attribute maxAgeSeconds : Integer = 60 {
            doc /* An estimate counts up to this age. */ }
        assert constraint sound { minStations >= 2 and sameSidePct > 50 }
    }

    requirement 'CL-043-03' {
        subject clock : ClockService;
        doc /* The clock MUST move its correction toward the middle of the stations heard
             when their estimate is evidence, and keep it otherwise (Correction). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-043-03'; }

    attribute def Correction {
        doc /* How the correction changes.
             Every WindowDone that receive gives makes a new estimate.
             With evidence the correction moves toward the correction minus the
             estimate's median.
             Without evidence (mixed sides, too few votes, no estimate) the correction
             stays as it is. */
        attribute maxSlewPerPeriodMs : Integer = 1000 {
            doc /* The correction changes by at most this much within one period of the
                 current mode. */ }
        attribute txBoundMs : Integer = 1000 {
            doc /* Station time is unsynchronized while a counting estimate is evidence
                 and its median is beyond this bound, and synchronized otherwise. */ }
        attribute maxStepMs : Integer = 100 {
            doc /* A jump of the PC clock beyond this is a step. A step discards the
                 observations and the estimate and is subtracted from a nonzero
                 correction, so station time stays continuous; a correction of 0
                 stays 0. */ }
        attribute maxStepRestartMs : Integer = 3000 {
            doc /* A correction beyond this after a step restarts at 0. */ }
        assert constraint ordered {
            maxSlewPerPeriodMs <= txBoundMs and txBoundMs < maxStepRestartMs
        }
    }

    // ---- The check against a time server ------------------------------------------------

    requirement 'CL-009-05' {
        subject clock : ClockService;
        doc /* The clock MUST measure the PC clock against a time server and warn the
             operator when the PC clock is off, when no server answers, or when the
             correction is large although the PC clock is right (TimeServerCheck,
             WarningRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-009-05'; }

    attribute def TimeServerCheck {
        doc /* The measurement of the PC clock.
             Its result is used for the warnings only.
             A measurement is taken at station start and then repeatedly.
             A server that does not answer validly is skipped.
             A round without a valid answer keeps the previous reading.
             After a step of the PC clock (Correction::maxStepMs) the state is unknown
             until the next reading.
             The latest result is available at once, also while a measurement runs. */
        @FollowsSource { reference = "RFC 4330, SNTP version 4"; }
        attribute servers : String[1..*] ordered {
            doc /* ch.pool.ntp.org, time.windows.com, pool.ntp.org, asked in this order
                 until one answers validly. The environment variable WSTX_SNTP_SERVERS
                 gives another list; an empty value means no server is asked. */ }
        attribute maxOffsetMs : Integer = 500 {
            doc /* The PC clock is synchronized up to this offset and unsynchronized
                 beyond it. */ }
        attribute maxAgeSeconds : Integer = 600 {
            doc /* A reading counts up to this age; without a counting reading the state
                 is unknown. */ }
    }

    attribute def WarningRule {
        doc /* Which ClockWarning holds: the first of these whose condition is met, and
             none otherwise.
             pcClockOff: while the time server state is unsynchronized.
             ntpUnreachable: while a round since start has asked a server and no
             reading counts (TimeServerCheck::maxAgeSeconds).
             stationsOff: while the time server state is synchronized and the correction
             is beyond stationsOffMs. */
        attribute stationsOffMs : Integer = 500;
    }

    // ---- Test cases ---------------------------------------------------------------------

    verification 'TC-043-001' {
        doc /* The estimate from stations with known DT.
             Setup: the clock on explicit clocks with a scripted time server; no receive,
             radio or network. Twelve stations whose true DT has the median 25 ms.
             (a) The PC clock 2 s fast: 12 votes, all later, median +2025 ms.
             (b) The PC clock 1.5 s slow: median -1475 ms.
             (c) One station decoded twenty times: one vote.
             (d) The profile's own call, an SNR of -20.5 dB and a DT of 3001 ms: no
             observation; an SNR of -20 dB and a DT of 3000 ms: an observation.
             (e) Two and three stations at +1850 ms: no evidence; four: evidence.
             (f) Five of nine at +1850 ms (55 %): no evidence.
             (g) An observation 120 s old counts; at 120 s and 1 ms it does not. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-02'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-092-001' {
        doc /* The correction and the state of station time.
             Setup: as TC-043-001; votes given as DT against station time; FT8 periods.
             (a) No station, and three stations at +1500 ms: correction 0, synchronized.
             (b) Four at +1500 ms: correction -1000 ms and unsynchronized, then -1500 ms
             and synchronized.
             (c) 15 of 19 on one side (78.9 %): no change; 16 of 20 (80 %): -600 ms.
             (d) Four at +100 ms: no change; four at +101 ms: -101 ms.
             (e) Four at +600 ms and four at -600 ms: no change.
             (f) Four at +1000 ms: synchronized; four at +1001 ms: unsynchronized.
             (g) Four at +2500 ms for three periods: -1000, -2000, -2500 ms.
             (h) A quiet band for 20 periods after a correction of -1500 ms: -1500 ms kept.
             (i) An estimate 60 s old counts; at 60 s and 1 ms it does not.
             (j) A step of 100 ms: no change; of 101 ms: the observations are discarded.
             (k) With correction -1000 ms a step of 2000 ms leaves -3000 ms; a step of
             2001 ms restarts at 0. With correction 0 a step of +525 ms leaves 0. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-01'; verify 'CL-043-03'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-006-003' {
        doc /* The measurement against a time server.
             Setup: scripted servers on the loopback address and a scripted PC clock; no
             public time server.
             (a) Three replies computed by hand: offset 590 ms with round trip 20 ms,
             -705 ms with 10 ms, 495 ms with 10 ms.
             (b) A short reply, a wrong mode, stratum 0 and 16, a zero transmit timestamp,
             a wrong originate timestamp and a leap alarm: refused; stratum 1 and 15:
             accepted.
             (c) Servers are asked once each in order and none after the first valid
             answer; when none answers there is no reading.
             (d) The PC clock stepping +10 s during the exchange: the offset stays 3 s.
             (e) Offset 500 ms: synchronized; 501 ms: unsynchronized.
             (f) A reading 10 min old counts; at 10 min and 1 ms the state is unknown.
             (g) A step of 100 ms after the reading: no change; of 101 ms: unknown.
             (h) Reading the result while a measurement blocks returns at once. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-05'; }
        @TestedBy { test = "server/tests/transmit/transmit_clock.rs"; }
    }

    verification 'TC-092-003' {
        doc /* The warnings, and station time under every state of the time server.
             Setup: the clock with a scripted time server that records its rounds, votes
             set directly, and a scripted reader of the Windows time service.
             (a) Time server +12 ms and four votes at +1500 ms for two periods: the
             correction still moves to -1000 and -1500 ms; warning stationsOff.
             (b) Correction -500 ms: no warning; -501 ms: stationsOff.
             (c) Time server +500 ms: no warning; +501 ms: pcClockOff, correction and
             state unchanged.
             (d) Time server -1900 ms without evidence: correction 0, synchronized,
             pcClockOff.
             (e) A round asked and no answer: ntpUnreachable.
             (f) A reading 600 s old: no warning; at 600 s and 1 ms:
             ntpUnreachable.
             (g) After a step with a young reading, with an empty server list, and before
             the first round: no warning.
             (h) The service reader answering running, stopped, disabled and failing:
             running, stopped, disabled, unknown.
             (i) Correction -2000 ms while the time server state changes to
             unsynchronized and back: -2000 ms kept. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; verify 'CL-009-05'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-043-002' {
        doc /* The correction settles and does not swing.
             Setup: the clock in a closed loop of 40 FT8 periods: the twelve stations of
             TC-043-001 and one station 1.2 s late, each decoded only while its corrected
             DT lies between -1700 and +2560 ms.
             (a) The PC clock 2 s slow: the correction settles at -2000 ms within two
             periods and stays.
             (b) The PC clock 1.5 s fast: it settles at +1425 ms.
             (c) The PC clock 0.6 s fast: it settles at +550 ms.
             (d) The PC clock right: the correction stays 0.
             (e) The PC clock 2 s and 3 s fast: at most three stations decode; the
             correction stays 0 and station time synchronized.
             (f) On the way the distance to the settled value never grows. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-092-002' {
        doc /* A PC clock that is off does not stop transmitting.
             Setup: the clock with a time server reading of +525 ms; FT4 periods.
             (a) Four stations at -339 ms, one at -50 ms and one at +100 ms (4 of 6):
             correction 0, synchronized, warning pcClockOff; a transmit start is planned.
             (b) Five at -339 ms and one at +100 ms (5 of 6): median -339 ms, correction
             +339 ms, synchronized, pcClockOff; a start is planned.
             (c) Then two stations, and then none: +339 ms kept; a start is planned. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; verify 'CL-009-05'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }
}
