package WstxLiveReceive {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-006';
    private import WstxReceivePart::ReceiveService;
    private import WstxReceiveControl::*;
    private import WstxDecodes::ResultRecord;
    private import WstxDecodes::PeriodView;
    private import WstxDisplayData::SpectrumFrame;
    private import WstxDisplayData::DetailedSpectrumFrame;
    private import WstxModeProcessing::Mode;
    private import WstxModeProcessing::ProcessingRequest;
    private import WstxModeProcessing::CallsUpdate;
    private import WstxModeProcessing::DecodeError;
    private import WstxAudioStreams::CaptureTie;
    private import WstxAudioStreams::SampleBlock;
    private import WstxStationTime::StationTime;
    private import WstxStationTime::StationHeard;
    private import WstxStationTime::WindowDone;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::FollowsSource;

    requirement 'CL-007-01' {
        subject receive : ReceiveService;
        doc /* Receive MUST, in a live job of the mode FT4 or FT8, give the receive stream
             to the modes part in windows and publish every decoded frame with its period
             and its DT, and the decodes of each period as one view (LiveWindows,
             RecordTiming, PeriodViews). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-007-01'; }

    attribute def LiveWindows {
        doc /* How the receive stream is cut into windows for the modes part.
             A window is a run of the latest samples that ends at a sample fixed by
             the schedule; it never reaches back over a break in the stream.
             While the epoch is not tied to station time, a window ends at every
             sample whose place is a whole multiple of the period length, and is two
             periods long (Mode).
             While the epoch is tied, the windows are those of WindowSchedule.
             A window is given only when it holds at least one whole frame of the
             mode.
             The windows are the same however the stream is cut into blocks.
             Each window is one ProcessingRequest: continuous is true, originFrame is
             the place of its first sample, periodStartFrame the place at which the
             period begins that holds the middle of the window, and context the
             ContactContext last given.
             One window is decoded at a time. When another window comes due
             meanwhile, the one being decoded is given up, LiveView::lastOverrun
             names it, its view is published with complete false, and the new window
             is decoded; the late window of WindowSchedule waits instead. When a
             further window comes due while the late window waits, the waiting window
             is given up as well, and lastOverrun names the waiting window.
             A window that ends with DecodeError::invalidSamples or decodeLimit ends
             the job as failed with decodeLimit.
             Receive gives the modes part a CallsUpdate at station start and whenever
             the calls of ContactContext change.
             In the mode spectrum no window is cut. */
    }

    attribute def RecordTiming {
        doc /* The period and the DT of a record.
             The station time of a sample is the PC clock time the tie of its epoch
             gives it (CaptureTie), plus the clock's correction (StationTime).
             A frame belongs to the period whose nominal start is nearest to the
             frame's start, and to the later one when two are equally near.
             ResultRecord::dtSeconds is the frame's start against the nominal start
             of that period (Mode); it lies between minus and plus half a period.
             For every record whose message names its sender, receive gives the clock
             a StationHeard: the sender, the SNR, and the DT in milliseconds as it is
             without the clock's correction.
             After every window that was decoded, to its end or until it was given up,
             receive gives the clock a WindowDone with the period length of the
             mode. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: the DT of a decode (xdt)";
        }
    }

    attribute def PeriodViews {
        doc /* When a PeriodView is published and what it holds.
             A view is published after every window that was decoded, for the running
             job only.
             While the epoch is tied, the view is that of the period the window
             belongs to: firstSequence and nextSequence span the kept records of
             that period, and are both the next sequence when there is none.
             A window that begins after the nominal start of its period publishes a
             view only when it is the late window of WindowSchedule.
             A view of an earlier period than the one last published is not
             published.
             A window of the period last published whose records begin at the same
             firstSequence publishes that view again under the same id: nextSequence
             grows, complete and transmitted are set and are not cleared.
             Every other view has the next id; an id count at its end is refused with
             counterExhausted and leaves the view last published in place.
             While the epoch is not tied, the view spans the records from the first
             sequence of its window to the next sequence.
             A job that ends leaves its view as it was. */
    }

    verification 'TC-007-012' {
        doc /* Windows, the timing of records and the view of a period. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-01'; }
        @TestedBy {
            test = "server/tests/receive_integration.rs::"
                + "receive_windows_follow_mode_boundaries_independent_of_packet_partition; "
                + "server/tests/receive_integration.rs::"
                + "receive_known_gap_resets_support_preserving_global_positions; "
                + "server/src/receive/recording_tests.rs::"
                + "latest_decode_relative_station_timing_uses_mode_origin_and_source_clock; "
                + "server/src/receive/recording_tests.rs::"
                + "ft8_snr_period_start_follows_the_utc_period_grid; "
                + "server/src/receive/recording_tests.rs::"
                + "latest_decode_replaces_period_atomically_including_empty_and_all_retained_rows; "
                + "server/src/receive/recording_tests.rs::"
                + "latest_decode_actual_overrun_stays_partial_then_completes_the_next_period; "
                + "server/src/receive/recording_tests.rs::"
            + "latest_decode_cancel_and_failure_preserve_published_period_without_new_identity; "
                + "server/src/receive/recording_tests.rs::"
                + "air_correction_composes_with_capture_drift_and_never_feeds_its_own_estimate; "
                + "server/tests/audio_receive.rs::"
                + "live_provider_known_gap_resets_history_without_renumbering_samples; "
                + "server/src/receive/receive_http_tests.rs::"
                + "live_native_fixture_reaches_real_manager_http_and_browser_callsign; "
                + "server/src/receive/receive_http_tests.rs::"
                + "live_native_ft4_fixture_reaches_real_manager_http_and_browser_callsign; "
                + "tests/receive-integration.test.cjs::"
                + "real native audio reaches Rust manager HTTP and literal browser callsign";
        }
    }

    requirement 'CL-007-05' {
        subject receive : ReceiveService;
        doc /* Receive MUST end its decode windows at fixed moments of each period of
             station time, and keep one prompt and one late window for every period when
             the tie of the stream or the clock's correction moves (WindowSchedule). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-007-05'; }

    attribute def WindowSchedule {
        doc /* The windows of an epoch that is tied to station time.
             Each period has two windows, both one period long (Mode): the prompt
             window, which ends the prompt time after the period start, and the late
             window, which ends the late time after it and so early in the next
             period.
             The prompt window holds the frames of stations that send on time or
             early; the late window adds the frames that start too late for it.
             The late window waits for the decoding of the prompt window of its
             period; its records extend the view of that period (PeriodViews), and
             when it adds none nothing is published.
             The moments are counted in station time. When audio moves the tie
             (CaptureTie) or the clock changes its correction, every window end moves
             by the same amount: one that is moved into the past ends with the next
             sample, one that is moved later waits, and none is left out, repeated or
             moved by a period. */
        attribute ft8PromptEndMs : Integer = 13800;
        attribute ft8LateEndMs : Integer = 15700;
        attribute ft4PromptEndMs : Integer = 6500;
        attribute ft4LateEndMs : Integer = 7900;
        attribute ft8PublishedByMs : Integer = 15000 {
            doc /* Every record of the prompt window of FT8, and the view of its period,
                 is published by this time after the period start. */ }
        attribute ft4PublishedByMs : Integer = 7500 {
            doc /* The same for FT4. */ }
    }

    verification 'TC-004-004' {
        doc /* The decode windows on the periods of station time. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-05'; }
        @TestedBy {
            test = "server/src/receive/recording_tests.rs::"
                + "live_window_schedule_follows_the_utc_period_grid; "
                + "server/tests/receive_integration.rs::"
                + "receive_schedule_completes_windows_at_period_residues; "
                + "server/src/receive/recording_tests.rs::"
                + "late_window_waits_for_the_prompt_decode_without_overrun; "
                + "server/src/receive/recording_tests.rs::"
                + "late_window_republishes_its_period_view_with_late_starters; "
                + "server/tests/receive_integration.rs::"
                + "receive_reschedule_moves_completions_without_dropping_or_repeating; "
                + "server/tests/receive_integration.rs::"
                + "receive_clock_steps_keep_each_period_window_once_and_in_order; "
                + "server/src/receive/recording_tests.rs::"
                + "air_correction_composes_with_capture_drift_and_never_feeds_its_own_estimate; "
                + "server/src/receive/recording_tests.rs::"
                + "live_ft8_period_start_and_window_diagnostics_follow_the_air_clock_correction; "
                + "server/src/receive/receive_http_tests.rs::live_native_busy_period_rows_promptly";
        }
    }

    requirement 'CL-061-04' {
        subject receive : ReceiveService;
        doc /* Receive MUST decode nothing and measure no receive level in a period the
             station transmitted in, and mark the view and the spectrum rows of that
             period as transmitted (TransmitPeriods, RxLevel). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-061-04'; }

    attribute def TransmitPeriods {
        doc /* What receive does with a period the station transmitted in.
             A period is a transmit period when OnAir::onAir was true at a moment of
             it, and when OnAir::lastPeriodStartMs names it; receive remembers the
             latest keptPeriods of them.
             A window of a transmit period, prompt or late, is not given to the modes
             part; its PeriodView is published with transmitted true, complete false
             and no record.
             A SpectrumFrame and a DetailedSpectrumFrame have tx true when their
             middle lies in a transmit period, and when they are finished while the
             station is on the air.
             The receive stream runs on through a transmit period: receive does not
             stop it, and no epoch begins.
             While the epoch is not tied to station time no period is a transmit
             period; windows are decoded, and only the receive level stops while the
             station is on the air. */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline stops its audio input while it "
                + "transmits and draws no waterfall row; the station keeps the stream "
                + "and marks the rows";
        }
        attribute keptPeriods : Integer = 16;
    }

    attribute def RxLevel {
        doc /* LiveView::rxLevelDb, the level of the receive stream.
             It is 10 log10 of the mean of the squared samples, with full scale as
             32768, rounded to a whole number and limited to 0 to maxDb.
             A value is formed from the samples of about one second.
             It is absent while the capture does not run, while the station is on the
             air, and for the rest of a transmit period; the samples of that time do
             not enter a later value. */
        attribute maxDb : Integer = 90;
    }

    verification 'TC-061-005' {
        doc /* Receive in a period the station transmitted in. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-04'; }
        @TestedBy { test = "server/src/transmit/recording_tx_tests.rs"; }
    }
}
