package WstxProfileRecordings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-018';
    private import WstxRecordingReceive::'CL-006-02';
    private import WstxRecordingReceive::'CL-006-04';
    private import WstxRecordingReceive::ErrorCode;
    private import WstxRecordingReceive::JobView;
    private import WstxStationProtocol::HttpValidation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    doc /* The recordings function of the profile part (WstxArchitecture::RecordedSource,
         deployed as physicalStation::backend::stations::profile::recordings): one imported
         recording per profile, kept with its metadata and manifest in the profile directory
         (WstxArchitecture::OutsideThing::profileFiles) across restarts, and its samples
         offered, timed and immutable, through the port samples of RecordedSource. Replay
         is the receive part's, the cancellation of an import the station's
         (WstxRecordingReceive::CancelImport). */
    @ImplementedIn { module = "server/src/recording.rs; server/src/recording_http.rs"; }

    attribute def RecordingLimits {
        doc /* The bounds of an import and of the stored recording. */
        attribute rateHz : Integer = 12000 {
            doc /* The one sample rate an imported recording has. */
        }
        attribute fileBytes : Integer = 3145728 {
            doc /* The largest recording file. */
        }
        attribute importMaxFrames : Integer = 1440000 {
            doc /* The most source frames of a recording, 120 s at rateHz. */
        }
        attribute importMaxRiffChunks : Integer = 64 {
            doc /* The most RIFF chunks of a recording, fmt and data included. */
        }
        attribute rawChunkBytes : Integer = 2048 {
            doc /* The largest body of one upload PUT. */
        }
        attribute reservationMs : Integer = 30000 {
            doc /* A reservation without its first chunk expires after this time. */
        }
        attribute uploadIdleMs : Integer = 15000 {
            doc /* An upload without a chunk for this time expires. */
        }
        attribute uploadTotalMs : Integer = 1800000 {
            doc /* An upload not complete after this time expires. */
        }
        attribute importCancelAckMs : Integer = 250 {
            doc /* The station accepts a cancellation and builds its response within this
                 time, network transit excluded. */
        }
        attribute normalCleanupMs : Integer = 1000 {
            doc /* Cleanup of a cancelled or expired import ends within this time in isolated
                 Windows tests. */
        }
        attribute faultCleanupOutcomeMs : Integer = 5000 {
            doc /* A cleanup not ended after this time is published as failed. */
        }
        attribute snapshotBytes : Integer = 8192 {
            doc /* The largest GET /recording body. */
        }
    }

    enum def ImportState {
        enum reserved; enum receiving; enum validating; enum committing; enum cancelling;
        enum completed; enum cancelled; enum failed;
    }
    attribute def RecordingMetadata {
        doc /* The metadata file of a stored recording: a JSON object of at most 1024 UTF-8
             bytes with exactly these keys; file_bytes is 1..RecordingLimits::fileBytes,
             frames 1..RecordingLimits::importMaxFrames and rate_hz RecordingLimits::rateHz.
             Its file name derives from the recording UUID inside the profile's recording
             area; it holds no path, file name or credential, and the original WAV stays
             unchanged beside it. */
        attribute schema_version : Integer = 1;
        attribute recording_id : String;
        attribute file_bytes : Integer;
        attribute frames : Integer;
        attribute rate_hz : Integer;
        assert constraint schema { schema_version == 1 }
    }
    attribute def RecordingManifest {
        doc /* The current-recording manifest: a JSON object of at most 256 bytes with exactly
             these keys. Its replacement is the import commit point. */
        attribute schema_version : Integer = 1;
        attribute recording_id : String;
    }
    attribute def RecordingView {
        doc /* The recording of GET /recording with exactly these keys; utc_anchor is always
             null for a recording. */
        attribute id : String;
        attribute rate_hz : Integer;
        attribute frames : Integer;
        attribute file_bytes : Integer;
        attribute utc_anchor : String[0..1];
    }
    attribute def ImportView {
        doc /* The import resource with exactly these keys. total_bytes is null before the
             first chunk and fixed after it; recording_id is null until the commit. The latest
             terminal resource is kept until the next reservation or restart. */
        attribute id : String;
        attribute 'state' : ImportState;
        attribute received_bytes : Integer;
        attribute total_bytes : Integer[0..1];
        attribute error : ErrorCode[0..1];
        attribute recording_id : String[0..1];
    }
    attribute def RecordingSnapshot {
        doc /* The 200 body of GET /recording, at most RecordingLimits::snapshotBytes; the GET
             changes nothing. Its key import carries importOperation without recording_id and
             is null once the import is terminal. */
        doc /* A missing or corrupt committed original, metadata or manifest gives recording
             null and source_error recording_unavailable; the IDs, the generation and the
             operations stay, so that a fresh browser can replace the recording. No job is
             fabricated, and an affected job fails. A healthy or absent source has
             source_error null; a replacement clears it. */
        doc /* A degraded store gives storage_error storage_unavailable: GET still answers 200,
             and a new import or replay is refused with 503. */
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
        attribute recording : RecordingView[0..1];
        attribute source_error : ErrorCode[0..1];
        attribute storage_error : ErrorCode[0..1];
        attribute importOperation : ImportView[0..1];
        attribute job : JobView[0..1];
    }
    attribute def StartImportBody {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
    }
    attribute def UploadChunk {
        doc /* One upload PUT: a body of 1..RecordingLimits::rawChunkBytes and exactly one
             Content-Range bytes start-end/total, where start is the bytes received so far and
             total, at most RecordingLimits::fileBytes, does not change after the first chunk.
             One chunk request is accepted at a time; the browser waits for its response
             before the next and assumes no streaming request. */
        attribute startByte : Integer;
        attribute endByte : Integer;
        attribute totalBytes : Integer;
        attribute bodyBytes : Integer;
        assert constraint range {
            startByte >= 0 and bodyBytes > 0 and endByte - startByte + 1 == bodyBytes
                and endByte < totalBytes
        }
    }

    action def ImportRecording {
        in request : StartImportBody;
        in validation : HttpValidation;
        out resource : ImportView;
        doc /* The import form: RIFF WAVE, little-endian integer PCM, format tag 1, mono, 16 bits
             per sample, exactly RecordingLimits::rateHz, 1 to RecordingLimits::importMaxFrames
             source frames and at most RecordingLimits::fileBytes. One fmt chunk of size 16 or 18
             with zero extension length comes before one nonempty data chunk; block alignment
             is 2, byte rate 24,000 and the data length even. The RIFF size plus eight is the
             file length, and every chunk length and odd-length padding lies inside it. */
        @FollowsSource { reference = "RIFF WAVE PCM, format tag 1"; }
        doc /* At most RecordingLimits::importMaxRiffChunks chunks are accepted; another bounded
             chunk is skipped without interpreting it, and unknown ancillary chunks alone do
             not make a valid file unsupported. RF64, RIFX, extensible, compressed and float
             formats, stereo, another rate, a duplicate fmt or data chunk, inconsistent sizes
             and a truncated header, data or padding are refused, with the errors of
             WstxStationProtocol::HttpValidation: a malformed structure differs from an
             unsupported capability. */
        doc /* The import keeps the whole original file, ancillary chunks included. It uses no
             codec and no resampler; a device rate or another format is a separate capability,
             never coerced into this one. The pinned recorded fixtures fit this form. */
        doc /* A profile holds one committed recording with its metadata, one pending
             reservation and no recording library, in a confined recording area under server
             names derived from the UUID, never client paths or file names. The samples stay
             the original WAV. */
        doc /* The import commit point is the replacement of the manifest, after the original
             and the metadata are complete. Before it a failed or cancelled import leaves the
             previous recording unchanged; after it the new recording is authoritative, also
             when the response is lost, and the browser reads a fresh snapshot rather than
             repeat the mutation. During a replacement at most the old and the new original
             exist; obsolete and temporary files are removed after the commit and on restart. */
        doc /* A cancellation invalidates publication and commit before its acknowledgement and
             is answered within RecordingLimits::importCancelAckMs; cleanup ends within
             RecordingLimits::normalCleanupMs. After an I/O error, or a cleanup not ended within
             RecordingLimits::faultCleanupOutcomeMs, the import is failed with
             storage_unavailable and storage_error is set: the pending files and handles stay
             quarantined, the one slot stays occupied, and import and replay are refused with
             503 storage_unavailable until cleanup succeeds or a restart reconciles the
             directory. */
        doc /* Nothing claims a deletion, starts a replacement worker or reverts a committed
             recording. A blocked operating-system call may end later, but its invalidated
             token cannot commit; storage_error clears only after real cleanup. Status,
             profile, settings and the observation of the cancellation stay usable. These are
             bounded outcomes of the application, not an interruption of a blocked Windows I/O
             call. A commit that has begun is reconciled through the snapshot, not cancelled. */
        doc /* A corrupt or missing committed recording gives recording_unavailable as
             RecordingSnapshot states; profile, status and settings stay available and no
             recording is fabricated. */
        doc /* A restart keeps the committed recording ID and bytes and changes the boot ID; the
             new boot starts with generation 0, import null and job null. Earlier reservations
             and jobs are forgotten and their IDs answer 404; an interrupted replay is
             invalidated by the changed boot identity, with no durable cancelled job, synthetic
             job or cancellation marker, and nothing is replayed. Cleanup and source failures
             keep their error fields without recreating a pending operation. Only the
             metadata, the manifest and the original persist. */
        doc /* POST /recording/imports with {v:1,profile_id,boot_id,generation}: 201
             {v:1,id,generation,state:"reserved"}; it reserves one import UUID, increments the
             generation, and the reservation expires after RecordingLimits::reservationMs
             without a PUT; Location identifies the import resource. */
        doc /* PUT /recording/imports/{id} with Content-Type audio/wav only, one UploadChunk and
             no content encoding: reserved becomes receiving; an intermediate chunk answers 202
             {v:1,id,state:"receiving",received_bytes} after the append; the final chunk passes
             validating and committing to completed and answers 201
             {v:1,id,state:"completed",recording_id,generation} after the manifest commit.
             Nothing is replayed. The upload expires after RecordingLimits::uploadIdleMs
             without a chunk or RecordingLimits::uploadTotalMs in total. A concurrent or
             out-of-order chunk answers 409 state_conflict. The body cap holds with a missing
             or false Content-Length. */
        doc /* GET /recording/imports/{id}: 200
             {v:1,id,state,received_bytes,total_bytes,error,recording_id}, state including
             completed, cancelled and failed. */
        doc /* DELETE /recording/imports/{id}: 200 with the same representation after the
             cancellation invalidates the work before the commit: reserved ends at once,
             receiving and validating become cancelling until the file worker's cleanup ends,
             then cancelled. A completed import is returned unchanged and its recording kept; a
             cancelled one returns the same terminal state. Once committing has begun the
             cancellation is refused with 409 invalid_state and GET reconciles the outcome.
             Commit and cancellation are serialized, so that a cancellation accepted first
             prevents the commit. */
        doc /* | POST /recording/replay | `{v:1,profile_id,boot_id,generation,recording_id}` |
             202 `{v:1,id,generation,state:"running"}`; increment generation/start job at
             frame0; reject import/replay busy. |
             | DELETE /recording/jobs/{id} | No body | 200 `{v:1,id,generation,state}`; current
             running -> cancelling and publication invalidation before response; terminal jobs
             return unchanged terminal state. Worker release bound is separate from HTTP
             round trip. | */
    }
    action def RecoverRecordedSource {
        out 'snapshot' : RecordingSnapshot;
        assert constraint newBootGeneration { 'snapshot'.generation == 0 }
        doc /* After a restart the selected profile and the committed recording UUID and
             original bytes are kept under a new boot identity; the snapshot has import and
             job null and generation 0. Earlier operations are forgotten: their import
             resources and job DELETE answer 404. There is no durable cancelled job,
             synthetic job, cancellation marker or automatic replay. Startup source and
             cleanup errors stay explicit fields without resurrecting a pending operation. */
    }
    enum def ImportEvent {
        enum chunk_started; enum all_bytes_received; enum valid_and_flushed;
        enum cancel_accepted; enum transport_lost; enum reservation_expired;
        enum upload_expired; enum cleanup_succeeded; enum cleanup_failed_or_deadline;
        enum io_failure; enum validation_failed; enum commit_succeeded;
    }
    calc def ImportExpired {
        doc /* Expiry on the station's monotonic clock, not the browser's timers; reaching a
             limit expires. It is judged serially with chunk, cancel and commit admission and
             emits reservation_expired or upload_expired for its state. */
        in currentState : ImportState;
        in reservationElapsedMs : Integer;
        in receiveIdleMs : Integer;
        in totalElapsedMs : Integer;
        in limits : RecordingLimits;
        return expired : Boolean =
            (currentState == ImportState::reserved
                and reservationElapsedMs >= limits.reservationMs) or
            (currentState == ImportState::receiving and
                (receiveIdleMs >= limits.uploadIdleMs or totalElapsedMs >= limits.uploadTotalMs));
    }
    state def ImportLifecycle {
        doc /* The one station state owner accepts the events serially. A cancellation accepted
             before committing invalidates the commit before its acknowledgement.
             cancellationCleanup records an explicit or transport cancellation; a timeout
             cleanup keeps upload_timeout. An observed loss of the PUT transport cancels the
             import. cleanup_succeeded needs an actual release and removal, not an elapsed
             timer. A replaced manifest stays authoritative after a failure that follows the
             commit. DELETE in committing answers 409 invalid_state, DELETE of a terminal
             import returns it unchanged, and a terminal resource lasts until the next
             reservation or restart. */
        attribute acceptedEvent : ImportEvent;
        attribute cancellationCleanup : Boolean;
        entry; then reserved;
        state reserved; state receiving; state validating; state committing;
        state cancelling; state completed; state cancelled; state failed;
        transition upload first reserved
            if acceptedEvent == ImportEvent::chunk_started then receiving;
        transition validate first receiving
            if acceptedEvent == ImportEvent::all_bytes_received then validating;
        transition commit first validating
            if acceptedEvent == ImportEvent::valid_and_flushed then committing;
        transition cancelReserved first reserved
            if acceptedEvent == ImportEvent::cancel_accepted then cancelled;
        transition cancelReceiving first receiving
            if acceptedEvent == ImportEvent::cancel_accepted then cancelling;
        transition cancelValidation first validating
            if acceptedEvent == ImportEvent::cancel_accepted then cancelling;
        transition abortReceiving first receiving
            if acceptedEvent == ImportEvent::transport_lost then cancelling;
        transition abortValidation first validating
            if acceptedEvent == ImportEvent::transport_lost then cancelling;
        transition reservationTimeout first reserved
            if acceptedEvent == ImportEvent::reservation_expired then cancelling;
        transition uploadTimeout first receiving
            if acceptedEvent == ImportEvent::upload_expired then cancelling;
        transition cleanedCancellation first cancelling
            if acceptedEvent == ImportEvent::cleanup_succeeded and cancellationCleanup
            then cancelled;
        transition cleanedTimeout first cancelling
            if acceptedEvent == ImportEvent::cleanup_succeeded and not cancellationCleanup
            then failed;
        transition quarantine first cancelling
            if acceptedEvent == ImportEvent::cleanup_failed_or_deadline
                or acceptedEvent == ImportEvent::io_failure then failed;
        transition reservationIoError first reserved
            if acceptedEvent == ImportEvent::io_failure then failed;
        transition uploadIoError first receiving
            if acceptedEvent == ImportEvent::io_failure then failed;
        transition validationIoError first validating
            if acceptedEvent == ImportEvent::io_failure then failed;
        transition rejected first validating
            if acceptedEvent == ImportEvent::validation_failed then failed;
        transition committed first committing
            if acceptedEvent == ImportEvent::commit_succeeded then completed;
        transition commitError first committing
            if acceptedEvent == ImportEvent::io_failure then failed;
    }
    enum def SourceAvailability { enum absent; enum available; enum unavailable; }
    calc def RecordingAvailability {
        doc /* An authenticated GET /recording answers 200 with the current identity,
             generation and operations in every case; unavailable gives recording null and
             source_error recording_unavailable, and replay answers 409 recording_unavailable
             until a replacement clears it. The browser labels absent and unavailable
             distinctly and keeps the replacement enabled while idle. An affected job fails
             under WstxRecordingReceive::ReceiveLifecycle; no job or recording is made up. A
             failed authentication or transport is not an absent or unavailable recording. */
        in committedSourceUnavailable : Boolean;
        in recordingPresent : Boolean;
        return availability : SourceAvailability = if committedSourceUnavailable ?
            SourceAvailability::unavailable else if recordingPresent ?
            SourceAvailability::available else SourceAvailability::absent;
    }
    action importRecording : ImportRecording;
    action recoverSource : RecoverRecordedSource;
    satisfy 'CL-006-01' by importRecording;
    dependency storageOwner from importRecording
        to WstxArchitecture::physicalStation::backend::stations::profile::recordings;
    dependency recoveryOwner from recoverSource
        to WstxArchitecture::physicalStation::backend::stations::profile::recordings;

    requirement 'CL-006-01' {
        doc /* The profile MUST import only a recording within RecordingLimits and the PCM WAV
             form, keep its original bytes, and offer its samples, timed and immutable,
             without a codec or an implicit resampler. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
        }
    }
    dependency CL_006_01_to_FR_003 from 'CL-006-01' to 'FR-003';
    dependency CL_006_01_to_FR_018 from 'CL-006-01' to 'FR-018';

    verification 'TC-018-001' {
        doc /* TC-018-001 — Valid recordings
             Setup: byte-built PCM WAVs with 1, 2,048, 4,096, 4,097 and
             RecordingLimits::importMaxFrames frames, endpoint samples -32768, -1, 0, 1 and
             32767 and legal ancillary and padding chunks; the pinned original recordings
             with their license and provenance manifests (22 FT8 and 3 FT4).
             (a) Import keeps the original bytes. Blocks of at most 4,096 samples concatenate
                 to the input, contiguous, with one end of stream. Each sample is exactly its
                 value / 32768.
             (b) The source UUID survives a restart. Job IDs differ, generations advance
                 within a boot and reset to 0 at restart. The recording UTC stays null, and no
                 device opens.
             (c) Every original recording of the two manifests has its sha256 and a PCM, mono,
                 16-bit, RecordingLimits::rateHz header within RecordingLimits::fileBytes. The
                 first FT8 and the first FT4 original import with rate_hz
                 RecordingLimits::rateHz and file_bytes equal to their length, and their
                 replay paints rows.
             (d) Two replays give equal spectra, within 0.5 dB quantization plus 0.05 dB.
             Oracle: hand-authored RIFF offsets and the manifests; the original recordings
             prove real input, not the calibration.
             2 — Isolated automated tests; Windows PC, disposable profiles, no radio. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
        }
        @TestedBy {
            test = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
        }
    }
    verification 'TC-018-002' {
        doc /* TC-018-002 — Invalid recordings and import faults
             Setup: table-mutated WAVs; slow, aborted and timed-out uploads; storage faults at
             each commit step (write, flush, metadata, manifest, cleanup), with restarts at
             the commit boundaries.
             (a) Each of these gives its error: a malformed field or chunk, zero or odd data,
                 a duplicate fmt or data chunk, a RIFF size mismatch or overflow, a truncation
                 at each header or data boundary, a rate, channel or format change,
                 RecordingLimits::importMaxRiffChunks + 1 chunks, frames over
                 RecordingLimits::importMaxFrames, a file one byte over
                 RecordingLimits::fileBytes. An unsupported capability gets a different error
                 from a malformed structure. A file exactly at the caps is accepted.
             (b) Before the manifest commit, the old bytes and ID remain; after it, the new
                 ones remain, also with a lost response.
             (c) No partial source becomes replayable, and no unbounded pending file is left.
                 Cleanup keeps committed data and reports its own failure.
             (d) Other stations, other profiles and the status stay available.
             Oracle: hand-specified errors of WstxStationProtocol::HttpValidation.
             2 — Isolated automated tests; Windows PC, disposable profiles, no radio. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        @TestedBy {
            test = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
        }
    }
    dependency CL_006_01_verified_by_TC_018_001 from 'CL-006-01' to 'TC-018-001';
    dependency CL_006_01_verified_by_TC_018_002 from 'CL-006-01' to 'TC-018-002';
}
