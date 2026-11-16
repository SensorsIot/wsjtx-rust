package WstxSchedule {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-006';
    private import WstxTransmitPart::TransmitService;
    private import WstxTransmitControl::StartWindow;
    private import WstxTransmitControl::TransmitRefusal;
    private import WstxModeProcessing::Period;
    private import WstxModeProcessing::PeriodParity;
    private import WstxStationTime::StationTime;
    private import WstxStationTime::StationTimeState;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-009-02' {
        subject transmit : TransmitService;
        doc /* Transmit MUST plan the start of a transmission for the period its request
             names from station time, start a late one inside the start window by leaving
             out what has passed, and refuse a start it cannot make in that period
             (StartPlan). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-009-02'; }

    attribute def StartPlan {
        doc /* When the audio of a transmission starts and at which sample of its
             waveform.
             The plan is made from station time (StationTime::utcMs), for the mode and
             the period the request names.
             While StationTime::timeState is not synchronized the start is refused with
             TransmitRefusal::clockNotSynchronized.
             A period start that is not a whole multiple of the period length of the
             mode (Period) is refused with misalignedPeriod.
             Up to the audio delay after the period start the audio starts at the audio
             delay, with the first sample of the waveform.
             After it, while the window is open (StartWindow), the audio starts at once
             and from the sample that would play at that moment had it started on time:
             the time passed since the audio delay, in samples of the waveform's rate,
             rounded down.
             From the moment the window closes the start is refused with stalePeriod; a
             request stays with its period and is not moved to a later one. */
        attribute window : StartWindow;
        attribute period : Period;
    }

    verification 'TC-006-001' {
        doc /* The start plan of FT8.
             Setup: the planning function alone with a given time; no clock, no sound
             device and no radio. The period 12:00:00 UTC of 31 October 2026 is even.
             (a) The next even period at 12:00:00.000, at 12:00:11.249 and at
             11:59:59.999: 12:00:00. At 12:00:11.250: 12:00:30.
             (b) The next odd period at 12:00:00.000 and at 12:00:14.999: 12:00:15. At
             12:00:26.250: 12:00:45.
             (c) The period 12:00:15, planned 3 s before it, 0.499 s and 0.500 s after
             its start: audio at 12:00:15.500 from sample 0.
             (d) Planned 2.750 s after its start for 48 kHz: audio at once from sample
             108000. Planned 11.249 s after it for 12 kHz: at once from sample 128988.
             (e) Planned 11.250 s, 15.001 s and 60 s after its start: stalePeriod.
             (f) A period start 1 ms after 12:00:15: misalignedPeriod.
             (g) Station time not synchronized, 0.1 s after the period start:
             clockNotSynchronized. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-02'; }
        @TestedBy {
            test = "server/tests/transmit_vectors.rs::"
                + "tc_006_001_period_selection_and_parity; "
                + "server/tests/transmit_vectors.rs::"
                + "tc_006_001_start_plan_late_start_and_refusals";
        }
    }

    verification 'TC-006-002' {
        doc /* The start plan of FT4.
             Setup: as for FT8. The FT4 period 12:00:00 UTC of 31 October 2026 is even,
             12:00:07.5 odd and 12:00:15 even; as an FT8 period 12:00:15 is odd.
             (a) The next even period at 12:00:00.000, at 12:00:05.339 and at
             11:59:59.999: 12:00:00. At 12:00:05.340 and at 12:00:05.624: 12:00:15.
             (b) The next odd period at 12:00:00.000 and at 12:00:07.499: 12:00:07.5. At
             12:00:13.125: 12:00:22.5. For FT8 the next odd period at 12:00:07.5 is
             12:00:15.
             (c) The period 12:00:07.5, planned 3 s before it, 0.299 s and 0.300 s after
             its start: audio at 12:00:07.800 from sample 0.
             (d) Planned 0.301 s after its start for 48 kHz: audio at once from sample
             48; 2.750 s after it: from sample 117600; 5.339 s after it: from sample
             241872, and for 12 kHz from sample 60468.
             (e) Planned 5.340 s, 5.341 s, 5.624 s, 5.625 s and 7.501 s after its start,
             for 12 kHz and for 48 kHz: stalePeriod.
             (f) A period start 1 ms after 12:00:07.5: misalignedPeriod. The period
             12:00:07.5 for FT8: misalignedPeriod. The FT8 period 12:00:00 planned at
             12:00:07.5 for 48 kHz: audio at once from sample 336000.
             (g) Station time not synchronized, 0.1 s after the period start:
             clockNotSynchronized. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-02'; }
        @TestedBy {
            test = "server/tests/transmit_ft4_vectors.rs::"
                + "tc_006_002_ft4_period_selection_and_parity; "
                + "server/tests/transmit_ft4_vectors.rs::"
                + "tc_006_002_ft4_start_plan_late_start_and_refusals";
        }
    }
}
