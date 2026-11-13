package WstxTransmitSchedule {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::'FR-005';
    private import WstxRequirements::AutomationState;
    private import WstxTransmit::'TC-006-003';
    private import WstxTransmit::ClockState;
    requirement 'CL-009-02' {
        doc /* Plan an FT8 transmission start for a named even/odd 15 s UTC period from a
             virtual clock: 500 ms audio delay, late start up to 75 % of the period by
             skipping the elapsed prefix, refusal for an unsynchronized/unknown clock,
             an unaligned period or a stale request, and no catch-up or replay of a
             missed period. Details: WstxTransmitSchedule::Ft8Schedule, PlanTransmitStart. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/schedule.rs";
    }
    dependency CL_009_02_to_FR_006 from 'CL-009-02' to 'FR-006';
    dependency CL_009_02_to_FR_005 from 'CL-009-02' to 'FR-005';
    verification 'TC-006-001' {
        doc /* TC-006-001 — FT8 transmit period scheduling
             CL-009-02
             Setup: virtual UTC clock values around period boundaries, both parities,
             12 kHz and 48 kHz, every clock state.
             Steps: select the next slot and plan starts before the period, at the audio
             delay, late, at the 75 % boundary, after it, in the wrong period, for
             unaligned periods and unsynchronized/unknown clocks.
             Oracles: WSJT-X values (Modulator.cpp delay_ms=500 and late-start m_ic,
             TxStartPolicy.hpp 0.75, mainwindow.cpp even/odd t mod 30 s): exact audio
             start and skipped-sample counts; 11249 ms admitted and 11250 ms stale;
             stale requests never move to a later period.
             2 — Isolated automated tests; Windows development PC, no clock, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-02';
        }
        attribute executable : String = "server/tests/transmit_vectors.rs";
    }
    dependency CL_009_02_verified_by_TC_006_003 from 'CL-009-02' to 'TC-006-003';
    dependency CL_009_02_verified_by_TC_006_001 from 'CL-009-02' to 'TC-006-001';
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
