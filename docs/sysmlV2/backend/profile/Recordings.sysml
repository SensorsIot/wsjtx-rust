package WstxRecordings {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-018';
    private import WstxProfilePart::PersistedProfile;
    private import WstxRecordingTransfer::*;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The recording and its file ---------------------------------------------------------

    requirement 'CL-006-01' {
        subject profile : PersistedProfile;
        doc /* Profile MUST take in only a recording whose file is a WAV file of the one
             form and within the limits, keep that file byte for byte, and give receive
             its samples from it (WavForm, StoredRecording). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/recording.rs"; }
    }
    #derivation connection { end #original ::> 'FR-018'; end #derive ::> 'CL-006-01'; }

    attribute def WavForm {
        doc /* Which file is a recording. The file is read in this order, and the first
             fault found decides.
             A file over RecordingLimits::fileBytes: recording_limit.
             The file begins with RIFF, a length and WAVE, and that length plus 8 is
             the length of the file; otherwise invalid_recording.
             Chunks follow to the end of the file, each with its name and its length;
             a chunk of odd length is followed by one byte that is not counted in it.
             Fewer than 8 bytes left for a chunk, and a chunk that reaches beyond the
             end of the file: invalid_recording. More chunks than
             RecordingLimits::importMaxRiffChunks: recording_limit.
             There is one fmt chunk, before the data chunk; a second one, and one after
             the data chunk: invalid_recording. Its length is 16 or 18; otherwise
             unsupported_audio.
             The fmt chunk names PCM (format 1), one channel, RecordingLimits::rateHz
             and 16 bits for a sample. A file that names another of these is of another
             form: unsupported_audio, unless a fault of the build of the file is found
             as well, which decides.
             A fmt chunk of this form names 2 bytes for a sample frame and 24000 bytes
             for a second, and its two further bytes, when its length is 18, are 0;
             otherwise invalid_recording.
             There is one data chunk, after the fmt chunk, with an even length above
             0; a file without one, with two, with an empty one or one of odd length:
             invalid_recording. Two of its bytes are one sample, the low byte first.
             A chunk of another name is passed over unread; it is kept with the file.
             More samples than RecordingLimits::importMaxFrames: recording_limit.
             A file that ends where a part of it is expected: invalid_recording. A file
             that cannot be read for another reason: storage_unavailable. */
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
             schema_version 1, recording_id, file_bytes, frames and rate_hz; and
             current.json with schema_version 1 and the recording_id of the stored
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
             RecordingStatus::source_error says recording_unavailable and
             RecordingStatus::recording is absent, until an import is completed.
             At station start and after every import the profile removes each file of
             the folder that does not belong to the stored recording. While it cannot
             tell from current.json which recording is stored, it keeps every file
             named by a UUID and .wav or .json.
             A folder that cannot be made, read or cleared sets
             RecordingStatus::storage_error to storage_unavailable; the error ends when
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
        doc /* Recordings that are taken in, kept and given as samples.
             Setup: the profile on a folder of its own, with WAV files built byte by
             byte; for (c) the recordings of the two fixture lists, 22 of FT8 and 3 of
             FT4; for (d) a station on the loopback interface. No sound device and no
             radio.
             (a) Files of 1, 2048, 4096, 4097 and RecordingLimits::importMaxFrames
             samples that run through the values -32768, -1, 0, 1 and 32767: each
             import is completed, and the file in the folder recordings is byte for
             byte the one given.
             (b) The samples of each, asked for: blocks of at most 4096 samples that
             begin at 0 and follow each other without a gap; each sample is its value
             divided by 32768; the last block, and no other, is marked as the end.
             (c) After a station start on the same folder: the same recording id, the
             same count of samples, RecordingLimits::rateHz.
             (d) Each recording of the two lists has the SHA-256 its list names, is
             PCM, one channel, 16 bits at RecordingLimits::rateHz, and is within
             RecordingLimits::fileBytes. The first of each list, and a tone of 3 s,
             imported through the station: file_bytes is the length of the file, and
             the stored file is byte for byte the one given. */
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

    // ---- The import ---------------------------------------------------------------------------

    requirement 'CL-006-05' {
        subject profile : PersistedProfile;
        doc /* Profile MUST put a recording in the place of the stored one only when its
             import is whole and valid, and keep the stored one through every import
             that fails, is cancelled or runs out of time (ImportLifecycle). */
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
             cancelled or upload_timeout. An import runs out of time
             RecordingLimits::reservationMs after its reservation while it is reserved,
             RecordingLimits::uploadIdleMs after its latest part began while it
             receives, and RecordingLimits::uploadTotalMs after its reservation in
             either state.
             A part or a step that fails turns the import to cancelling with its
             error: the fault of WavForm, or storage_unavailable for a file that cannot
             be written.
             cancelling: the files of the import are removed. Once they are removed
             the import is cancelled when its error is cancelled, and failed
             otherwise. A part that is still being taken when the import turns to
             cancelling is answered with the error, and the files are removed after
             it.
             When the files cannot be removed, or are not removed in time after the
             import turned to cancelling, the import is failed with storage_unavailable and
             RecordingStatus::storage_error is set; the files stay until they can be
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
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/recording.rs; server/src/recording_http.rs"; }
    }
    #derivation connection { end #original ::> 'FR-018'; end #derive ::> 'CL-006-06'; }

    attribute def ImportAdmission {
        doc /* Which command of an import is carried out. A command is refused with the
             first of its reasons that holds (ImportRefused); a refused command changes
             nothing.
             ReserveImport. busy: ReceiveBusy::notReleased. storage_unavailable:
             RecordingStatus::storage_error is set. busy: ReceiveBusy::jobRunning, or an
             import has not ended, or the files of an import that ended are still
             being removed. An admitted reservation makes an import in the state
             reserved, in the place of the import that ended last.
             ImportChunk. request_too_large: total is over RecordingLimits::fileBytes.
             not_found: no import of this id. upload_timeout: the import ran out of
             time. cancelled: the import was cancelled. state_conflict: another part of
             the import is being taken, start is not the count of bytes taken so far,
             or total is not the one of the first part. invalid_state: the import is
             neither reserved nor receiving.
             CancelImport. not_found: no import of this id. invalid_state: the import
             is committing. An import that has ended is answered as it is.
             ReadImport. not_found: no import of this id.
             A CancelImport is answered at once, before the files of the import are
             removed. */
    }

    verification 'TC-018-002' {
        doc /* Files that are no recording, and imports that fail, are cancelled or run
             out of time.
             Setup: the profile on a folder of its own, with WAV files built byte by
             byte from a file of the three samples 0, 1 and -1 with a header of 44
             bytes, and with a fault set at one step of an import; for (k) to (n) a
             station on the loopback interface. No sound device and no radio.
             (a) invalid_recording: another byte at the place 0, 8, 12 or 36 of the
             file; the byte 255 at the place 4, 16, 28, 32 or 40; the file cut off
             after each count of bytes from 0 to 49; a file without a sample; the four
             bytes RIFF alone.
             (b) unsupported_audio: the byte 3 at the place 20, 22, 24 or 34.
             (c) recording_limit: one sample more than RecordingLimits::importMaxFrames;
             one byte more than RecordingLimits::fileBytes; one chunk more than
             RecordingLimits::importMaxRiffChunks.
             (d) Taken: a chunk JUNK of one byte and its filling byte before the fmt
             chunk, 3 samples; a file of exactly RecordingLimits::fileBytes; exactly
             RecordingLimits::importMaxRiffChunks chunks.
             (e) A file that is opened for writing only: storage_unavailable.
             (f) With the recording 1, 2, 3 stored, an import of 4, 5, 6 that fails
             when a part is added, when the file is made durable, when the description
             is written, when current.json is written, and when it is put in place:
             storage_unavailable each time; the stored recording is the first, its file
             byte for byte as before, also after a station start.
             (g) An import that fails after current.json is put in place:
             storage_unavailable; the stored recording is the new one with its bytes,
             also after a station start.
             (h) An import reserved 31 s ago; one whose latest part began 16 s ago;
             one reserved 1801 s ago: each ends with upload_timeout, a further part is
             refused with upload_timeout, and the stored recording is the one of
             before.
             (i) While a part is being taken, a second part: state_conflict. Then a
             CancelImport, and the files not removed after 6 s: storage_error is
             storage_unavailable and a reservation is refused with it. The first part
             then ends refused with storage_unavailable, the files are removed, and
             storage_error is absent.
             (j) Files of an import that cannot be removed: storage_error is
             storage_unavailable and the file is still there, also after a station
             start while the fault lasts. After a station start without the fault: no
             storage_error, the recording of before, the file gone.
             (k) An empty folder: no recording and no source_error. A WAV file and its
             description under a UUID, without current.json: source_error is
             recording_unavailable, no recording, both files kept. A completed import
             then: no source_error, the new recording, the two files gone.
             (l) Through the station. Two reservations at once: one admitted, one
             refused. With an import reserved, a reservation: busy.
             (m) Through the station, on a reserved import. A part from byte 1:
             state_conflict. A total one above RecordingLimits::fileBytes:
             request_too_large. The first 2 of 100 bytes: receiving. A CancelImport:
             answered before the files are removed, and the import is
             cancelled within 600 ms; a further part is refused with cancelled. A
             CancelImport while a part is on its way and not whole: cancelled, and no
             recording is stored.
             (n) Through the station, with a recording stored. An import whose length
             after RIFF is wrong, in two parts: the first is taken, the second refused
             with invalid_recording; the stored recording is the one of before. Then,
             each followed by a station start: the stored file removed; the description
             holding {}; current.json holding {}; current.json removed. Each time
             source_error is recording_unavailable and no recording is shown; where the
             stored file was not removed it is still there, and an import of the four
             bytes RIFF is refused and leaves it there; a whole import then ends
             source_error. */
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
