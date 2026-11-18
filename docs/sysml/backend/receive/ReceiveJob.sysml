package WstxReceiveJob {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-003';
    private import WstxReceivePart::ReceiveService;
    private import WstxReceiveControl::*;
    private import WstxDecodes::ResultRecord;
    private import WstxModeProcessing::DecodeBand;
    private import WstxModeProcessing::DecodeError;
    private import WstxAudioStreams::EpochProposal;
    private import WstxAudioStreams::EpochAccepted;
    private import WstxAudioStreams::StartCapture;
    private import WstxAudioStreams::StopCapture;
    private import WstxAudioStreams::EpochReason;
    private import WstxAudioStreams::SourceError;
    private import WstxAudioStreams::CaptureMarks;
    private import WstxRecordingTransfer::RecordingUnreadable;
    private import WstxRecordingTransfer::OpenRecording;
    private import WstxModelNotes::Debugging;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::CodeDiffers;

    requirement 'CL-006-02' {
        subject receive : ReceiveService;
        doc /* Receive MUST report the state of its job at every moment and give a job its
             end state only when the job has let go of its source (JobLifecycle). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-006-02'; }

    attribute def JobLifecycle {
        doc /* How a job begins and ends.
             An admitted start makes a job in the state ReceiveState::running, with a new
             id.
             A live job asks audio for the receive stream (StartCapture) and ends it
             when its work stops (StopCapture); a replay asks the profile for the
             recording (OpenRecording).
             StopLive and CancelJob turn a job that has not ended to cancelling; nothing
             more of the job is published from then on.
             A job lets go of its source when its work has stopped: a live job when the
             receive stream is closed, a replay when it has given the recording back.
             A job that has let go of its source gets its end state: cancelled when its
             end was asked for, also when it failed or came to its end meanwhile; else
             failed with its error; else completed.
             Only a replay completes, when it has shown every sample of the recording;
             its processedFrames is then the length of the recording.
             A live job whose stream does not close keeps its state until the stream is
             closed, and then ends with audioCloseFailed unless its end was asked
             for.
             StopLive and CancelJob for a job that has ended are answered with the job
             unchanged.
             An error of the receive stream ends a live job as failed: SourceError
             unsupportedFormat as unsupportedAudio, failedClose as
             audioCloseFailed, counterExhausted as counterExhausted, cancelled as
             cancelled, the end of the stream as audioUnavailable, every other one as
             audioFailed; unavailable does not end the job (EpochHandling).
             A replay whose recording is RecordingUnreadable fails with
             recordingUnavailable. */
    }

    requirement 'CL-006-04' {
        subject receive : ReceiveService;
        doc /* Receive MUST run one job at a time and answer every start it does not admit
             with the reason (Admission). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-006-04'; }

    attribute def Admission {
        doc /* Which start is admitted. A start is refused with the first of these that
             holds, in this order.
             For StartReplay, recordingUnavailable: the stored recording is damaged;
             noRecording: none is stored; notFound: the command names another
             recording than the stored one.
             busy: a live job that has ended has not yet given up everything it held,
             or a band or mode selection runs that did not make this start.
             storageUnavailable: the storage of the profile has an error.
             busy: a job has not ended, or an import of a recording has not ended.
             An admitted start clears the state of the job before it: its spectrum rows,
             its records and its views.
             A live start that is admitted and whose stream cannot be started is
             answered with audioUnavailable; its job has failed.
             StopLive is answered with notFound when no live job was admitted or the
             command names another job, and CancelJob when it names another job. */
    }

    verification 'TC-018-003' {
        doc /* The states of a job and the admission of a start. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-02'; verify 'CL-006-04'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "processing_failure_with_eos_cannot_complete_before_or_after_release; "
                + "server/src/recording_tests.rs::"
                + "crossing_pacing_deadline_completes_and_releases_worker_slot; "
                + "server/src/recording_tests.rs::"
                + "live_terminal_is_unobservable_until_actual_input_drop_releases; "
                + "server/src/recording_tests.rs::"
                + "live_worker_spawn_failure_releases_admission_without_reusing_generation; "
                + "server/src/recording_tests.rs::"
                + "live_second_epoch_source_uuid_failure_releases_original_admission; "
                + "server/src/recording_tests.rs::"
                + "a_replay_start_it_does_not_admit_is_refused_and_changes_nothing; "
                + "tests/recording.test.cjs";
        }
    }

    requirement 'CL-008-03' {
        subject receive : ReceiveService;
        doc /* Receive MUST number the records of a live job without a gap, keep the
             latest of them for reading, and go on under a new job identity after a loss
             in the capture (LiveResults, EpochHandling). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-008-03'; }

    attribute def LiveResults {
        doc /* How the decoded frames of a live job become records.
             Each frame the modes part returns for the running job and its current
             source becomes one ResultRecord with the next sequence.
             A frame is refused when it starts at or after the sample the stream has
             reached, when its frequency is not a number or outside DecodeBand, when
             its SNR is not a number or beyond snrLimitDb either way, and when its
             record is longer than recordMaxBytes; a refused frame ends the decoding of
             its window, the job fails with decodeLimit, and no later frame becomes a
             record.
             A sequence count at its end is refused likewise, with counterExhausted.
             A window that ends with DecodeError::searchLimited sets
             LiveView::searchLimited, and the job fails with decodeLimit.
             Receive keeps the latest records, up to keptRecords and keptMiB; when a
             record would exceed one of the two, the oldest leave and
             firstSequence grows.
             The kept records stay readable after the job has ended, until the next
             start is admitted.
             ReadRecords is answered with notFound when it names another source or
             job than the current ones or no live job was admitted, with
             invalidRequest in the mode spectrum and for a cursor beyond
             nextSequence, and with CursorExpired for a cursor before
             firstSequence. */
        attribute keptRecords : Integer = 2048;
        attribute keptMiB : Integer = 2;
        attribute recordMaxBytes : Integer = 2048;
        attribute snrLimitDb : Integer = 60;
    }

    attribute def EpochHandling {
        doc /* What receive does when audio starts an epoch (EpochProposal).
             Receive takes up every epoch (EpochAccepted) and gives its stream a new
             source id.
             With every epoch the windows, the decoder's memory of earlier windows and
             the spectrum start anew, and the view last published and
             LiveView::lastOverrun are cleared.
             The first epoch of a job keeps the job's id.
             Every later epoch gives the job a new id, and its records are numbered
             from 0 again; commands and requests that name the old job or source are
             answered with notFound.
             LiveView::lossEpochs counts the later epochs whose reason is
             EpochReason::captureLoss, and LiveView::lastLoss is the trigger of the
             latest of them.
             A gap of known length (a marked block that is not the first of its epoch)
             keeps job and records; the decoder's memory of earlier
             windows and the view last published are cleared.
             A stream that fails with SourceError::unavailable keeps the job running:
             receive forgets the source and, if one was taken up, gives the job a new
             id; the stream goes on with a new epoch.
             A later epoch that cannot be given a source id ends the job as failed,
             with storageUnavailable. */
        @CodeDiffers {
            what = "The code refuses a StopLive that names the job of an earlier epoch with "
                + "stateConflict.";
        }
    }

    verification 'TC-009-004' {
        doc /* The records of a live job, and the job across a loss in the capture. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-03'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "live_results_evict_oldest_and_never_restart_sequence; "
                + "server/src/recording_tests.rs::"
                + "live_publication_is_atomic_at_byte_counter_and_context_boundaries; "
                + "server/src/recording_tests.rs::"
                + "live_manager_rotates_unknown_epoch_before_ack_and_rejects_old_stop_results; "
                + "server/src/recording_tests.rs::"
                + "live_worker_keeps_its_job_through_engine_glitches_and_reports_loss_epochs; "
                + "server/src/recording_tests.rs::"
                + "a_frame_outside_its_limits_never_becomes_a_record_and_reads_are_refused";
        }
    }

    requirement 'CL-052-01' {
        subject receive : ReceiveService;
        doc /* Receive MUST keep the counters of its latest decode windows and, while the
             window dump is switched on, write each prompt window of FT8 to a file
             (WindowDiagnostics). */
        @Debugging;
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-052-01'; }

    attribute def WindowDiagnostics {
        doc /* What receive records about the windows it gives to the decoder.
             For every such window receive keeps WindowCounters; the marks and counts
             of the capture in them are those audio gives for the span of the window
             (CaptureMarks).
             The window dump is ReceiveConfig::windowDump, taken at station start
             and from every ReceiveConfiguration; a changed switch holds from the next
             window.
             While the dump is on, each prompt window of FT8 is written to the folder
             diagnostic-windows of the profile's folder: its samples as a WAV file,
             mono, 12 kHz, 16 bit, each sample times 32768, rounded and limited to
             the 16-bit range, and beside it a JSON file with v 1, rateHz 12000,
             sampleFormat pcm16_mono and the window's WindowCounters.
             The two files are named by the window's origin in 15 digits, a hyphen and
             the UTC of its period start without separators, or unknown without a
             period start.
             A window that cannot be written sets DiagnosticsView::dumpError to
             dumpFailed until the next one is written; the decoding goes on
             unchanged. */
        attribute keptWindows : Integer = 20 {
            doc /* DiagnosticsView::windows holds the counters of this many windows. */ }
        attribute dumpKeep : Integer = 20 {
            doc /* The folder holds the files of this many windows, the newest. */ }
        attribute dumpMiB : Integer = 16 {
            doc /* The folder holds at most this much; the oldest windows leave. */ }
        attribute earlyFrames : Integer = 141696 {
            doc /* WindowCounters::earlyBufferZeroSamples counts the zeros among this
                 many samples from the period start. */ }
    }

    verification 'TC-052-001' {
        doc /* The counters of a window and the window dump. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-052-01'; }
        @TestedBy { test = "server/src/receive/receive_diagnostics_tests.rs"; }
    }
}
