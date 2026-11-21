package WstxStationClock {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-006';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxClockPart::ClockService;
    private import WstxStationTime::*;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;

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

    requirement 'CL-009-05' {
        subject clock : ClockService;
        doc /* The clock MUST measure the PC clock against a time server and warn the
             operator when the PC clock is off, when no server answers, or when the
             correction is large although the PC clock is right (TimeServerCheck,
             WarningRule). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/transmit/clock.rs; server/src/transmit/air.rs; "
                + "server/src/main.rs";
        }
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

    verification 'TC-043-001' {
        doc /* The estimate from stations with known DT. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-02'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-092-001' {
        doc /* The correction and the state of station time. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-01'; verify 'CL-043-03'; }
        @TestedBy {
            test = "server/tests/transmit_air_clock.rs; "
                + "server/src/transmit/clock_http_tests.rs::no_clock_source_setting";
        }
    }

    verification 'TC-006-003' {
        doc /* The measurement against a time server. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-05'; }
        @TestedBy { test = "server/tests/transmit/transmit_clock.rs"; }
    }

    verification 'TC-092-003' {
        doc /* The warnings, and station time under every state of the time server. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; verify 'CL-009-05'; }
        @TestedBy {
            test = "server/tests/transmit_air_clock.rs; "
                + "server/src/transmit/clock_http_tests.rs::"
                + "warnings_windows_time_capture_and_revision; "
                + "server/src/transmit/transmit_http_tests.rs::"
                + "transmit_wire_shows_the_sntp_clock_measurement";
        }
    }

    verification 'TC-043-002' {
        doc /* The correction settles and does not swing. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }

    verification 'TC-092-002' {
        doc /* A PC clock that is off does not stop transmitting. */
        subject clock : ClockService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-043-03'; verify 'CL-009-05'; }
        @TestedBy { test = "server/tests/transmit_air_clock.rs"; }
    }
}
