package WstxTransmitSchedule {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-005';
    private import WstxRequirements::'FR-006';
    private import WstxPeriodTiming::ClockState;
    private import WstxTransmitPart::TransmitService;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import RequirementDerivation::*;
    enum def ScheduleRefusal {
        enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod;
    }
    attribute def Ft8Schedule {
        attribute periodMs : Integer = 15000;
        attribute audioDelayMs : Integer = 500;
        attribute latestStartMs : Integer = 11250;
        assert constraint startWindow {
            latestStartMs * 4 == periodMs * 3 and audioDelayMs < latestStartMs
        }
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 Modulator.cpp (FT8 delay_ms=500, late-start m_ic), "
                + "TxStartPolicy.hpp (TxStartLatestPeriodFraction 0.75), mainwindow.cpp "
                + "(Tx even/1st)";
        }
        doc /* A pure function of a virtual UTC clock in integer milliseconds; no timer, device
             or wall clock. */
        doc /* Periods start at UTC multiples of periodMs; a period is even when (start/periodMs)
             is even (WSJT-X Tx even/1st = t mod 30 s < 15 s). */
        doc /* The next slot for a parity is the earliest such period whose start window is still
             open. */
        doc /* Audio of a slot starts audioDelayMs after the period start, independent of the
             configured PTT TxDelay. */
        doc /* A start is admitted while the elapsed time into the requested period is below
             latestStartMs, 75 % of the period. */
        doc /* Before audioDelayMs the plan waits until period start + audioDelayMs with no
             skipped samples; a late start at elapsed e plays immediately from sample
             floor((e - audioDelayMs) * rate / 1000 ms), so the audio stays aligned with the
             period and the elapsed prefix is skipped, never replayed. */
        doc /* A request names its period: from latestStartMs on it is stalePeriod and is never
             moved to a later period; an unaligned period is misalignedPeriod; any clock state
             other than synchronized is clockNotSynchronized. */
    }
    attribute def Ft4Schedule {
        attribute periodMs : Integer = 7500;
        attribute audioDelayMs : Integer = 300;
        attribute latestStartMs : Integer = 5625;
        attribute waveformMs : Integer = 5040;
        attribute audioEndMs : Integer = 5340;
        assert constraint startWindow {
            latestStartMs * 4 == periodMs * 3 and audioDelayMs < latestStartMs
        }
        assert constraint audioEnd {
            audioEndMs == audioDelayMs + waveformMs and audioEndMs < latestStartMs
        }
        @FollowsSource {
            reference = "WSJT-X 3.3.0-beta5 mainwindow.cpp (m_TRperiod=7.5, Tx even/1st), "
                + "Modulator.cpp (FT4 delay_ms=300, late-start m_ic), TxStartPolicy.hpp (0.75)";
        }
        @DiffersFromSource {
            what = "An FT4 start is stale from audioEndMs (5340 ms), the end of the waveform's "
                + "audio; WSJT-X's fTR < 0.75 check would start an empty transmission between "
                + "5340 and 5625 ms.";
        }
        doc /* The Ft8Schedule rules hold with these values: periods start at UTC multiples of
             periodMs, and a period is even when (start/periodMs) is even (Tx even/1st = t mod
             15 s < 7.5 s). */
        doc /* Audio starts audioDelayMs after the period start with the ramp-up symbol, so the
             first channel tone starts 348 ms after it; later starts skip
             floor((e - audioDelayMs) * rate / 1000 ms) samples. */
        doc /* The 105-symbol waveform lasts waveformMs, so its audio ends audioEndMs into the
             period, before latestStartMs: a start is admitted only while the skip is below the
             waveform's sample count at that rate (Ft4WaveformContract samples12k, samples48k),
             that is while the elapsed time is below audioEndMs; from audioEndMs on the request
             is stalePeriod. */
        doc /* The misaligned and clock refusals are those of FT8. */
        doc /* The ft4sim receive placement (channel tones from 0.5 s) is a simulator
             convention, not transmit timing. */
    }
    action def PlanTransmitStart {
        in mode : WstxModeProcessing::Mode;
        in nowUtcMs : Integer;
        in clock : ClockState;
        in periodStartUtcMs : Integer;
        in sampleRateHz : Integer;
        out audioStartUtcMs : Integer[0..1];
        out skippedSamples : Integer[0..1];
        out refusal : ScheduleRefusal[0..1];
        doc /* The mode is explicit in every request and selects Ft8Schedule or Ft4Schedule; a
             period aligned for one mode only is misalignedPeriod for the other. */
        doc /* Selecting the next slot also takes the mode. */
        doc /* For every mode a start is stalePeriod once the elapsed time reaches latestStartMs
             or once the skipped samples would reach the waveform's sample count (audio delay
             plus waveform duration: Ft4Schedule audioEndMs; for FT8 after its latestStartMs),
             so an empty transmission is never admitted; the next slot uses the same window. */
    }

    attribute ft8Schedule : Ft8Schedule;
    attribute ft4Schedule : Ft4Schedule;
    action planTransmitStart : PlanTransmitStart;

    satisfy 'CL-009-02' by ft8Schedule;
    satisfy 'CL-009-02' by planTransmitStart;
    satisfy 'CL-011-05' by ft4Schedule;
    satisfy 'CL-011-05' by planTransmitStart;

    requirement 'CL-009-02' {
        subject transmit : TransmitService;
        doc /* An FT8 transmission start MUST be planned for a named even or odd 15 s UTC period
             from a virtual clock, with the 500 ms audio delay and a late start up to 75 % of
             the period that skips the elapsed prefix. */
        doc /* An unsynchronized or unknown clock, an unaligned period and a stale request MUST
             be refused, and a missed period MUST never be caught up or replayed. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/schedule.rs"; }
    }
    #derivation connection {
        end #original ::> 'FR-006';
        end #derive ::> 'CL-009-02';
    }
    #derivation connection {
        end #original ::> 'FR-005';
        end #derive ::> 'CL-009-02';
    }
    requirement 'CL-011-05' {
        subject transmit : TransmitService;
        doc /* An FT4 start MUST be planned for a named even or odd 7.5 s UTC period with the
             300 ms audio delay and the FT8 refusals; the mode MUST be explicit per request; a
             start MUST be stale from the earlier of 75 % of the period and the end of the
             waveform's audio (5340 ms). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/schedule.rs"; }
    }
    #derivation connection {
        end #original ::> 'FR-006';
        end #derive ::> 'CL-011-05';
    }
    verification 'TC-006-001' {
        doc /* FT8 transmit period scheduling
             Setup: virtual UTC clock values around period boundaries, both parities, 12 kHz
             and 48 kHz, every clock state. The expected values are WSJT-X's (Modulator.cpp
             delay_ms=500 and late-start m_ic, TxStartPolicy.hpp 0.75, mainwindow.cpp even/odd
             t mod 30 s). No clock, audio or radio.
             (a) Select the next slot and plan starts before the period, at the audio delay and
             late: the exact audio start and skipped-sample counts.
             (b) Plan starts at the 75 % boundary and after it: 11249 ms admitted and 11250 ms
             stale.
             (c) Plan starts in the wrong period, for unaligned periods and with unsynchronized
             or unknown clocks: refused; a stale request never moves to a later period. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-009-02';
        }
        @TestedBy { test = "server/tests/transmit_vectors.rs"; }
    }
}
