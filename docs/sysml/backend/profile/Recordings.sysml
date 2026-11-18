package WstxRecordings {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-018';
    private import WstxProfilePart::PersistedProfile;
    private import WstxRecordingTransfer::*;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::Debugging;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-006-01' {
        subject profile : PersistedProfile;
        doc /* Profile MUST take in only a recording whose file is a WAV file of the one
             form and within the limits, keep that file byte for byte, and give receive
             its samples from it (WavForm, StoredRecording). */
        @Debugging;
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/recording.rs"; }
    }
    #derivation connection { end #original ::> 'FR-018'; end #derive ::> 'CL-006-01'; }

    attribute def WavForm {
        doc /* Which file is a recording. The file is read in this order, and the first
             fault found decides.
             A file over RecordingLimits::fileBytes: recordingLimit.
             The file begins with RIFF, a length and WAVE, and that length plus 8 is
             the length of the file; otherwise invalidRecording.
             Chunks follow to the end of the file, each with its name and its length;
             a chunk of odd length is followed by one byte that is not counted in it.
             Fewer than 8 bytes left for a chunk, and a chunk that reaches beyond the
             end of the file: invalidRecording. More chunks than
             RecordingLimits::importMaxRiffChunks: recordingLimit.
             There is one fmt chunk, before the data chunk; a second one, and one after
             the data chunk: invalidRecording. Its length is 16 or 18; otherwise
             unsupportedAudio.
             The fmt chunk names PCM (format 1), one channel, RecordingLimits::rateHz
             and 16 bits for a sample. A file that names another of these is of another
             form: unsupportedAudio, unless a fault of the build of the file is found
             as well, which decides.
             A fmt chunk of this form names 2 bytes for a sample frame and 24000 bytes
             for a second, and its two further bytes, when its length is 18, are 0;
             otherwise invalidRecording.
             There is one data chunk, after the fmt chunk, with an even length above
             0; a file without one, with two, with an empty one or one of odd length:
             invalidRecording. Two of its bytes are one sample, the low byte first.
             A chunk of another name is passed over unread; it is kept with the file.
             More samples than RecordingLimits::importMaxFrames: recordingLimit.
             A file that ends where a part of it is expected: invalidRecording. A file
             that cannot be read for another reason: storageUnavailable. */
        @FollowsSource {
            reference = "Multimedia Programming Interface and Data Specifications 1.0 "
                + "(IBM and Microsoft): RIFF, the WAVE form and its PCM format";
        }
    }

    attribute def StoredRecording {
        doc /* The one recording a profile holds, and how receive gets it.
             The recording lies in the folder recordings of the profile's folder as
             three files: the file of the import as it came, named by the id of the
             recording and .wav; its description, named by the id and .json, with
             schemaVersion 1, recordingId, fileBytes, frames and rateHz; and
             current.json with schemaVersion 1 and the recordingId of the stored
             recording.
             A profile holds one recording or none. The recording is the one
             current.json names.
             At station start the profile reads current.json, the description and the
             file. The recording is stored when current.json names a UUID, the
             description is that recording's, and the file reads as WavForm with the
             length and the count of samples the description says.
             Without current.json and without a file of the folder that is named by a
             UUID and .wav or .json, no recording is stored.
             In every other case the stored recording cannot be read:
             RecordingStatus::sourceError says recordingUnavailable and
             RecordingStatus::recording is absent, until an import is completed.
             At station start and after every import the profile removes each file of
             the folder that does not belong to the stored recording. While it cannot
             tell from current.json which recording is stored, it keeps every file
             named by a UUID and .wav or .json.
             A folder that cannot be made, read or cleared sets
             RecordingStatus::storageError to storageUnavailable; the error ends when
             the files of an import have been removed, or with a station start that
             finds the folder in order.
             An OpenRecording for the stored recording is answered with its samples as
             RecordedBlocks, in their order to the end of the file. When the file does
             not open, does not read as WavForm, or has another count of samples than
             the description says, it is answered with RecordingUnreadable, and the
             stored recording cannot be read from then on. */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline opens a WAV file from any place and "
                + "decodes it at once (File, Open); the profile takes the file into its "
                + "folder first, and receive shows it as a spectrum.";
        }
    }

    verification 'TC-018-001' {
        doc /* Recordings that are taken in, kept and given as samples. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-01'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "original_bytes_samples_blocks_and_restart_identity; "
                + "tests/profile/recording-fixtures.test.cjs; tests/recording.test.cjs";
        }
    }

    requirement 'CL-006-05' {
        subject profile : PersistedProfile;
        doc /* Profile MUST put a recording in the place of the stored one only when its
             import is whole and valid, and keep the stored one through every import
             that fails, is cancelled or runs out of time (ImportLifecycle). */
        @Debugging;
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/recording.rs"; }
    }
    #derivation connection { end #original ::> 'FR-018'; end #derive ::> 'CL-006-05'; }

    attribute def ImportLifecycle {
        doc /* How an import runs from its reservation to its end (ImportState).
             reserved: the import has an id and no file. Its first part turns it to
             receiving. A CancelImport ends it at once as cancelled.
             receiving: each part is added to the file of the import in the folder
             recordings, and the answer says how much has been taken. The part that
             completes the file turns the import to validating.
             validating: the file is made durable and read as WavForm, and its
             description is written. A file that is no recording ends the import with
             the fault WavForm names. A file that is one turns the import to
             committing.
             committing: current.json is put in place in one step and names the import's
             file. From that step on the file is the stored recording, with the id of
             the import, also when the import fails afterwards, the answer is lost or
             the station stops. The files of the recording stored before are removed,
             and the import is completed.
             A CancelImport in receiving or validating, and a reserved or receiving
             import that runs out of time, turn the import to cancelling with the error
             cancelled or uploadTimeout. An import runs out of time
             RecordingLimits::reservationMs after its reservation while it is reserved,
             RecordingLimits::uploadIdleMs after its latest part began while it
             receives, and RecordingLimits::uploadTotalMs after its reservation in
             either state.
             A part or a step that fails turns the import to cancelling with its
             error: the fault of WavForm, or storageUnavailable for a file that cannot
             be written.
             cancelling: the files of the import are removed. Once they are removed
             the import is cancelled when its error is cancelled, and failed
             otherwise. A part that is still being taken when the import turns to
             cancelling is answered with the error, and the files are removed after
             it.
             When the files cannot be removed, or are not removed in time after the
             import turned to cancelling, the import is failed with storageUnavailable and
             RecordingStatus::storageError is set; the files stay until they can be
             removed.
             completed, cancelled and failed are the ends of an import; ImportView
             keeps showing the import in its end.
             Until current.json is put in place, the stored recording, its files and
             RecordingStatus::recording are those of before the import.
             When the station stops, an import that has not ended is gone with its
             files. */
    }

    requirement 'CL-006-06' {
        subject profile : PersistedProfile;
        doc /* Profile MUST run one import at a time and answer every command of an
             import that it does not carry out with the reason (ImportAdmission). */
        @Debugging;
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/recording.rs; server/src/recording_http.rs"; }
    }
    #derivation connection { end #original ::> 'FR-018'; end #derive ::> 'CL-006-06'; }

    attribute def ImportAdmission {
        doc /* Which command of an import is carried out. A command is refused with the
             first of its reasons that holds (ImportRefused); a refused command changes
             nothing.
             ReserveImport. busy: ReceiveBusy::notReleased. storageUnavailable:
             RecordingStatus::storageError is set. busy: ReceiveBusy::jobRunning, or an
             import has not ended, or the files of an import that ended are still
             being removed. An admitted reservation makes an import in the state
             reserved, in the place of the import that ended last.
             ImportChunk. requestTooLarge: total is over RecordingLimits::fileBytes.
             notFound: no import of this id. uploadTimeout: the import ran out of
             time. cancelled: the import was cancelled. stateConflict: another part of
             the import is being taken, offset is not the count of bytes taken so far,
             or total is not the one of the first part. invalidState: the import is
             neither reserved nor receiving.
             CancelImport. notFound: no import of this id. invalidState: the import
             is committing. An import that has ended is answered as it is.
             ReadImport. notFound: no import of this id.
             A CancelImport is answered at once, before the files of the import are
             removed. */
    }

    verification 'TC-018-002' {
        doc /* Files that are no recording, and imports that fail, are cancelled or run out of time.
             */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-01'; verify 'CL-006-05'; verify 'CL-006-06'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "byte_level_riff_limits_and_rejection_table; "
                + "server/src/recording_tests.rs::parser_preserves_non_eof_os_read_errors; "
                + "server/src/recording_tests.rs::"
                + "import_failures_keep_old_source_and_quarantine_until_real_release; "
                + "server/src/recording_tests.rs::"
                + "post_commit_failure_never_reverts_new_original_on_restart; "
                + "server/src/recording_tests.rs::"
                + "deadlines_release_only_after_cleanup_and_startup_reconciles_quarantine; "
                + "server/src/recording_tests.rs::"
                + "absent_manifest_artifacts_are_unavailable_and_retained_until_valid_commit; "
                + "tests/recording.test.cjs";
        }
    }
}
