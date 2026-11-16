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
    private import WstxModeProcessing::Period;
    private import WstxModeProcessing::ProcessingRequest;
    private import WstxModeProcessing::CallsUpdate;
    private import WstxModeProcessing::DecodeError;
    private import WstxAudioStreams::CaptureTie;
    private import WstxAudioStreams::SampleBlock;
    private import WstxStationTime::StationTime;
    private import WstxStationTime::StationHeard;
    private import WstxStationTime::WindowDone;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelNotes::DiffersFromSource;
    private import ModelNotes::FollowsSource;

    // ---- Decoding the receive stream ----------------------------------------------------------

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
             periods long (Period).
             While the epoch is tied, the windows are those of WindowSchedule.
             A window is given only when it holds at least one whole frame of the
             mode.
             The windows are the same however the stream is cut into blocks.
             Each window is one ProcessingRequest: continuous is true, originFrame is
             the place of its first sample, periodStartFrame the place at which the
             period begins that holds the middle of the window, and context the
             ContactContext last given.
             One window is decoded at a time. When another window comes due
             meanwhile, the one being decoded is given up, LiveView::last_overrun
             names it, its view is published with complete false, and the new window
             is decoded; the late window of WindowSchedule waits instead. When a
             further window comes due while the late window waits, the waiting window
             is given up as well, and last_overrun names the waiting window.
             A window that ends with DecodeError::invalidSamples or decodeLimit ends
             the job as failed with decode_limit.
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
             ResultRecord::dt_seconds is the frame's start against the nominal start
             of that period (Period); it lies between minus and plus half a period.
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
             belongs to: first_sequence and next_sequence span the kept records of
             that period, and are both the next sequence when there is none.
             A window that begins after the nominal start of its period publishes a
             view only when it is the late window of WindowSchedule.
             A view of an earlier period than the one last published is not
             published.
             A window of the period last published whose records begin at the same
             first_sequence publishes that view again under the same id: next_sequence
             grows, complete and transmitted are set and are not cleared.
             Every other view has the next id; an id count at its end is refused with
             counter_exhausted and leaves the view last published in place.
             While the epoch is not tied, the view spans the records from the first
             sequence of its window to the next sequence.
             A job that ends leaves its view as it was. */
    }

    verification 'TC-007-012' {
        doc /* Windows, the timing of records and the view of a period.
             Setup: the window cutting of the receive function with scripted blocks
             for (a) and (b); the receive function with a live job, a tie set by hand
             and frames published by hand for (c) to (i); no sound device and no radio.
             (a) FT8 without a tie, in blocks of 240 samples and in blocks of 239, 1,
             117 and 240: the same four windows, ending at the samples 180000, 360000,
             540000 and 720000, each beginning 360000 before its end and not before 0,
             with every sample at its place. FT4: windows ending at 90000 to 360000,
             each beginning 180000 before its end.
             (b) FT4, blocks up to sample 90000, then a marked block at 170000: no
             window at 180000; the next window ends at 270000 and begins at 170000.
             (c) A tie of sample 0 to 12:00:00 UTC. FT8 frames that start at the
             samples 3600, 6000 and 8400: period 12:00:00 and DT -0.2, 0.0 and +0.2 s.
             FT4 frames at 3024, 5424 and 7824: the same; at 95424: period 12:00:07.5
             and DT 0.0.
             (d) A frame exactly between two periods, FT8 at sample 96000 and FT4 at
             50424: the later period, DT -7.5 and -3.75 s. A tie 0.0001 s later: DT
             0.0001 s. Without a tie: no period and no DT.
             (e) A tie of sample 100000 to 19:23:07.5 UTC: for FT8 the period of the
             samples 100000 and 172000 begins at sample 10000, that of sample 196000
             at 190000; a period that began before sample 0, and no tie: no
             periodStartFrame.
             (f) One record in the period 12:00:00 and 18 in the next, then a window
             of 30 s from sample 0: the view has the id 1, first_sequence 1,
             next_sequence 19, complete true and the period 12:00:15; ReadRecords from
             cursor 1 with limit 16 gives 16 records and that view. A window from
             sample 180000: the view has the id 2, first_sequence and next_sequence
             19, and the period 12:00:30.
             (g) A window of 15 s from sample 0 is being decoded when the next comes
             due: its view has the id 1 and complete false, last_overrun names the
             samples 0 to 180000; the view of the next window has the id 2, complete
             true and the period 12:00:15.
             (h) The id count at its end: the next view is refused with
             counter_exhausted and the view stays; a job that ends cancelled, and one
             that ends failed: the view stays as it was.
             (i) A frame of K1ABC that starts 17.0 s after the tie at 00:00:00, the
             tie moved by 0.5 s and a correction of -2 s: period 00:00:15 and DT 0.0 s;
             without the correction: the same period and DT 2.0 s. In both cases the
             clock is given K1ABC with a DT of 2000 ms. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-01'; }
        @TestedBy {
            test = "server/tests/receive_integration.rs::"
                + "receive_windows_follow_mode_boundaries_independent_of_packet_partition; "
                + "server/tests/receive_integration.rs::"
                + "receive_known_gap_resets_support_preserving_global_positions; "
                + "server/src/recording_tests.rs::"
                + "latest_decode_relative_station_timing_uses_mode_origin_and_source_clock; "
                + "server/src/recording_tests.rs::"
                + "ft8_snr_period_start_follows_the_utc_period_grid; "
                + "server/src/recording_tests.rs::"
                + "latest_decode_replaces_period_atomically_"
                + "including_empty_and_all_retained_rows; "
                + "server/src/recording_tests.rs::"
                + "latest_decode_actual_overrun_stays_partial_then_completes_the_next_period; "
                + "server/src/recording_tests.rs::"
                + "latest_decode_cancel_and_failure_preserve_published_period_"
                + "without_new_identity; "
                + "server/src/recording_tests.rs::"
                + "air_correction_composes_with_capture_drift_and_never_feeds_its_own_estimate";
        }
    }

    // ---- The windows on the periods of station time ---------------------------------------

    requirement 'CL-007-05' {
        subject receive : ReceiveService;
        doc /* Receive MUST end its decode windows at fixed moments of each period of
             station time, and keep one prompt and one late window for every period when
             the tie of the stream or the clock's correction moves (WindowSchedule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-007-05'; }

    attribute def WindowSchedule {
        doc /* The windows of an epoch that is tied to station time.
             Each period has two windows, both one period long (Period): the prompt
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
        doc /* The decode windows on the periods of station time.
             Setup: the schedule and the window cutting of the receive function with
             scripted blocks for (a), (b), (e) and (f); the receive function with a
             live job, a scripted capture and frames published by hand for the others;
             no sound device and no radio.
             (a) A tie of sample 1000 to 19:23:07.5 UTC. FT8: the prompt window ends
             where the sample count leaves 76600 on division by 180000, the late
             window where it leaves 99400, both 180000 samples long. FT4: 79000 and
             5800 on division by 90000, both 90000 long. A tie of sample 179000 to
             19:23:14.0: FT8 176600 and 19400. Without a tie: no schedule.
             (b) The FT8 schedule of (a) with blocks cut in two ways: windows end at
             the samples 256600, 279400, 436600 and 459400, each 180000 long; the two
             ends before them hold less than a frame and give no window.
             (c) The late window comes due while the prompt window is decoded: it
             waits; every view is complete and last_overrun stays absent.
             (d) The prompt window of the period 12:00:15 with one frame: a view with
             first_sequence 0 and next_sequence 1. Its late window without a new
             frame: the state of receive is unchanged. With a frame of DT +1.2 s: the
             same view id, next_sequence 2, and the record has that period and DT
             1.2 s. The same samples as a window that is not the late one: no view.
             (e) The schedule of (b) moved by +0.5 s after the window that ends at
             436600, and by -1 s before 639400: the windows end at 256600, 279400,
             436600, 465400, 622600, 636001, 790600 and 813400, in turn prompt and
             late.
             (f) Station time stepping 0.06 s before a prompt end, by +2 s, by -2 s
             and by +8 s: each time one prompt and then one late window for every
             period, in order; for +2 s they end at 435841, 436081, 592600 and
             615400.
             (g) A PC clock 2 s ahead of the stations and a capture clock 300 ppm slow,
             over 301 s: the correction reaches -2000 ms; 20 prompt windows, one for
             each period; from the second on each ends within 0.1 s of its period
             start + 13.8 s of station time.
             (h) A PC clock 2 s slow with a correction of +2 s: the prompt window of
             the period 12:00:30 has the same period, period_start_frame 360000 and
             window_offset_ms -1200 as with a right clock and no correction.
             (i) A busy recording of FT8 as the capture of two periods 30 s apart,
             through the capture, the windows and the decoder: the view of each period
             holds at least 25 records and is published not later than its period
             start + 15.0 s.
             (j) Planned, no test yet: the prompt and the late end of FT4 through the
             live job, and its views by the period start + 7.5 s. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-05'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "live_window_schedule_follows_the_utc_period_grid; "
                + "server/tests/receive_integration.rs::"
                + "receive_schedule_completes_windows_at_period_residues; "
                + "server/src/recording_tests.rs::"
                + "late_window_waits_for_the_prompt_decode_without_overrun; "
                + "server/src/recording_tests.rs::"
                + "late_window_republishes_its_period_view_with_late_starters; "
                + "server/tests/receive_integration.rs::"
                + "receive_reschedule_moves_completions_without_dropping_or_repeating; "
                + "server/tests/receive_integration.rs::"
                + "receive_clock_steps_keep_each_period_window_once_and_in_order; "
                + "server/src/recording_tests.rs::"
                + "air_correction_composes_with_capture_drift_and_never_feeds_its_own_estimate; "
                + "server/src/recording_tests.rs::"
                + "live_ft8_period_start_and_window_diagnostics_follow_the_air_clock_correction; "
                + "server/src/receive_http_tests.rs::live_native_busy_period_rows_promptly";
        }
    }

    // ---- The periods the station transmits in ------------------------------------------------

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
        doc /* LiveView::rx_level_db, the level of the receive stream.
             It is 10 log10 of the mean of the squared samples, with full scale as
             32768, rounded to a whole number and limited to 0 to maxDb.
             A value is formed from the samples of about one second.
             It is absent while the capture does not run, while the station is on the
             air, and for the rest of a transmit period; the samples of that time do
             not enter a later value. */
        attribute maxDb : Integer = 90;
    }

    verification 'TC-061-005' {
        doc /* Receive in a period the station transmitted in.
             Setup: the receive function with a live FT8 job and a tie of sample 0 to
             12:00:00 UTC; the transmit periods given by hand for (a) and (b), and by
             the transmit function on a scripted radio for (c); no sound device and no
             radio.
             (a) The period 12:00:15 was transmitted in. Its prompt window: a view of
             that period with transmitted true, complete false and first_sequence
             equal to next_sequence; no window was given to the decoder. Its late
             window: the same view. The prompt window of 12:00:30: decoded, complete
             true, not transmitted, and ReadRecords gives that view.
             (b) A level of 60 before. Blocks at 0.9 of full scale in the rest of the
             transmit period, after the station has left the air: no level, and every
             detailed row has tx true. Blocks at 0.01 in the period 12:00:30: rows
             without tx, and after one second a level of 50. On the air again: no
             level at once, and the rows have tx true. The capture reads running and
             loss_epochs 0 throughout.
             (c) The station tunes at 12:00:23: no level at once, and a block of that
             time adds nothing to the next value. After the tuning the one transmit
             period remembered is 12:00:15 in FT8 and 12:00:22.5 in FT4. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-061-04'; }
        @TestedBy { test = "server/src/transmit/recording_tx_tests.rs"; }
    }
}
