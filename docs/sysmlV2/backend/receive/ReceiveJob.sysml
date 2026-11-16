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
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The job and its end ----------------------------------------------------------------

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
             its processed_frames is then the length of the recording.
             A live job whose stream does not close keeps its state until the stream is
             closed, and then ends with audio_close_failed unless its end was asked
             for.
             StopLive and CancelJob for a job that has ended are answered with the job
             unchanged.
             An error of the receive stream ends a live job as failed: SourceError
             unsupportedFormat as unsupported_audio, failedClose as
             audio_close_failed, counterExhausted as counter_exhausted, cancelled as
             cancelled, the end of the stream as audio_unavailable, every other one as
             audio_failed; unavailable does not end the job (EpochHandling).
             A replay whose recording is RecordingUnreadable fails with
             recording_unavailable. */
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
             For StartReplay, recording_unavailable: the stored recording is damaged;
             no_recording: none is stored; not_found: the command names another
             recording than the stored one.
             busy: a live job that has ended has not yet given up everything it held,
             or a band or mode selection runs that did not make this start.
             storage_unavailable: the storage of the profile has an error.
             busy: a job has not ended, or an import of a recording has not ended.
             An admitted start clears the state of the job before it: its spectrum rows,
             its records and its views.
             A live start that is admitted and whose stream cannot be started is
             answered with audio_unavailable; its job has failed.
             StopLive is answered with not_found when no live job was admitted or the
             command names another job, and CancelJob when it names another job. */
    }

    verification 'TC-018-003' {
        doc /* The states of a job and the admission of a start.
             Setup: the receive function on a disposable profile folder, with a stored
             recording for (a) and (b) and a scripted receive stream for (c) to (e); no
             sound device and no radio.
             (a) A replay whose work has failed while every sample is processed and
             which still holds its recording: the job reads running and an import is
             refused with busy; after it lets go: failed, not completed.
             (b) A replay of 1200 samples that is held across the moment its row is
             due: completed, and an import is admitted.
             (c) A live job after StopLive while its stream is not closed: cancelling,
             and an import is refused with busy; once the stream is closed: cancelled.
             (d) A StartLive whose stream cannot be started: audio_unavailable and the
             job failed; the next start is admitted with a new job id.
             (e) A live job whose second epoch cannot be given a source id: failed with
             storage_unavailable under the same job id; an import is
             then admitted.
             (f) Planned, no test yet: StartReplay refused with no_recording, not_found
             and recording_unavailable. */
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
                + "live_second_epoch_source_uuid_failure_releases_original_admission";
        }
    }

    // ---- The records of a live job ------------------------------------------------------------

    requirement 'CL-008-03' {
        subject receive : ReceiveService;
        doc /* Receive MUST number the records of a live job without a gap, keep the
             latest of them for reading, and go on under a new job identity after a loss
             in the capture (LiveResults, EpochHandling). */
        @Status { build = ImplementationState::implemented; }
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
             its window, the job fails with decode_limit, and no later frame becomes a
             record.
             A sequence count at its end is refused likewise, with counter_exhausted.
             A window that ends with DecodeError::searchLimited sets
             LiveView::search_limited, and the job fails with decode_limit.
             Receive keeps the latest records, up to keptRecords and keptMiB; when a
             record would exceed one of the two, the oldest leave and
             first_sequence grows.
             The kept records stay readable after the job has ended, until the next
             start is admitted.
             ReadRecords is answered with not_found when it names another source or
             job than the current ones or no live job was admitted, with
             invalid_request in the mode spectrum and for a cursor beyond
             next_sequence, and with CursorExpired for a cursor before
             first_sequence. */
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
             LiveView::last_overrun are cleared.
             The first epoch of a job keeps the job's id.
             Every later epoch gives the job a new id, and its records are numbered
             from 0 again; commands and requests that name the old job or source are
             answered with not_found.
             LiveView::loss_epochs counts the later epochs whose reason is
             EpochReason::captureLoss, and LiveView::last_loss is the trigger of the
             latest of them.
             A gap of known length (a marked block that is not the first of its epoch)
             keeps job and records; the decoder's memory of earlier
             windows and the view last published are cleared.
             A stream that fails with SourceError::unavailable keeps the job running:
             receive forgets the source and, if one was taken up, gives the job a new
             id; the stream goes on with a new epoch.
             A later epoch that cannot be given a source id ends the job as failed,
             with storage_unavailable. */
    }

    verification 'TC-009-004' {
        doc /* The records of a live job, and the job across a loss in the capture.
             Setup: the receive function with a live job, frames published by hand for
             (a) to (d), and a scripted capture for (e) to (g); no sound device and no
             radio.
             (a) 2054 records, one after the other: after record n, next_sequence is n,
             the kept records are the lesser of n and 2048, and first_sequence is the
             greater of n - 2048 and 0.
             (b) Then ReadRecords with cursor 5: CursorExpired with first_sequence 6
             and next_sequence 2054; cursor 7 and limit 1: the record 7, more true;
             cursor 2054: no record, more false; cursor 2055: invalid_request; another
             source: not_found.
             (c) One record kept and the kept bytes at exactly 2 MiB, then one more
             record: the oldest leaves, first_sequence 1 and next_sequence 2.
             (d) A frame whose frequency is not a number: refused, next_sequence
             unchanged; the sequence count at its end: counter_exhausted; a frame of
             another job: no record.
             (e) A first packet without an arrival time: the job keeps its id; the
             first view has the id 1. A flagged packet after a gap of known length:
             the job and the one record stay, the view is gone,
             and the next view has the id 2.
             (f) Then an oversize packet and a good one: a new job id and source id,
             next_sequence 0 and no view; ReadRecords for the old source: not_found;
             StopLive for the old job: not_found; a frame of the old job: no record.
             (g) 300 packets of which every 50th is flagged and continues in time: the
             same job, loss_epochs 0 and no last_loss; then an oversize packet: a new
             job id, loss_epochs 1 and
             last_loss invalidPacket. */
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
                + "live_worker_keeps_its_job_through_engine_glitches_and_reports_loss_epochs";
        }
    }

    // ---- The counters of the decode windows -------------------------------------------------

    requirement 'CL-052-01' {
        subject receive : ReceiveService;
        doc /* Receive MUST keep the counters of its latest decode windows and, while the
             window dump is switched on, write each prompt window of FT8 to a file
             (WindowDiagnostics). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-052-01'; }

    attribute def WindowDiagnostics {
        doc /* What receive records about the windows it gives to the decoder.
             For every such window receive keeps WindowCounters; the marks and counts
             of the capture in them are those audio gives for the span of the window
             (CaptureMarks).
             The window dump is ReceiveConfig::window_dump, taken at station start
             and from every ReceiveConfiguration; a changed switch holds from the next
             window.
             While the dump is on, each prompt window of FT8 is written to the folder
             diagnostic-windows of the profile's folder: its samples as a WAV file,
             mono, 12 kHz, 16 bit, each sample times 32768, rounded and limited to
             the 16-bit range, and beside it a JSON file with v 1, rate_hz 12000,
             sample_format pcm16_mono and the window's WindowCounters.
             The two files are named by the window's origin in 15 digits, a hyphen and
             the UTC of its period start without separators, or unknown without a
             period start.
             A window that cannot be written sets DiagnosticsView::dump_error to
             dump_failed until the next one is written; the decoding goes on
             unchanged. */
        attribute keptWindows : Integer = 20 {
            doc /* DiagnosticsView::windows holds the counters of this many windows. */ }
        attribute dumpKeep : Integer = 20 {
            doc /* The folder holds the files of this many windows, the newest. */ }
        attribute dumpMiB : Integer = 16 {
            doc /* The folder holds at most this much; the oldest windows leave. */ }
        attribute earlyFrames : Integer = 141696 {
            doc /* WindowCounters::early_buffer_zero_samples counts the zeros among this
                 many samples from the period start. */ }
    }

    verification 'TC-052-001' {
        doc /* The counters of a window and the window dump.
             Setup: the diagnostics of the receive function on a disposable profile
             folder, with hand-built windows; no sound device and no radio.
             (a) A window of 20 samples from sample 100 with zeros at its places 2, 3,
             4, 10, 18 and 19 and a period start at sample 104: 6 zeros, the longest run
             3, 4 early ones; without a period start no early count; a period that
             ended before the window: 0 early ones; an empty window: 0, 0 and 0.
             (b) The samples 0, 0.5, -1 and 1 written: a WAV file of 52 bytes, mono,
             12000 Hz, 16 bit, with the values 0, 16384, -32768 and 32767.
             (c) The window dump off, as it is until it is switched on: no window.
             (d) Windows while the dump is off, and a window that is not a prompt
             window of FT8: nothing written. Then a window of origin 3 in the period of
             09:16:00 UTC on 2 November 2026: the files
             000000000000003-20261102T0916000000000Z.wav and .json, the JSON file with
             rate_hz 12000 and the window's counters. After the windows of origin 4 to
             29: the folder holds 20 pairs, from origin 10 on; the view holds 20
             windows, from origin 10 on; dumped_windows is 27; no dump_error.
             (e) Five windows of a third of dumpMiB each: the two newest stay. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-052-01'; }
        @TestedBy { test = "server/src/receive/receive_diagnostics_tests.rs"; }
    }
}
