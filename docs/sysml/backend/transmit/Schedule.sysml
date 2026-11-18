package WstxSchedule {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-006';
    private import WstxTransmitPart::TransmitService;
    private import WstxTransmitControl::StartWindow;
    private import WstxTransmitControl::TransmitRefusal;
    private import WstxModeProcessing::Mode;
    private import WstxModeProcessing::PeriodParity;
    private import WstxStationTime::StationTime;
    private import WstxStationTime::StationTimeState;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

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
             mode (Mode) is refused with misalignedPeriod.
             Up to the audio delay after the period start the audio starts at the audio
             delay, with the first sample of the waveform.
             After it, while the window is open (StartWindow), the audio starts at once
             and from the sample that would play at that moment had it started on time:
             the time passed since the audio delay, in samples of the waveform's rate,
             rounded down.
             From the moment the window closes the start is refused with stalePeriod; a
             request stays with its period and is not moved to a later one. */
        attribute window : StartWindow;
        attribute mode : Mode;
    }

    verification 'TC-006-001' {
        doc /* The start plan of FT8. */
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
        doc /* The start plan of FT4. */
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
