package WstxProfileRecordings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-018';
    private import WstxRequirements::'CL-006-02';
    private import WstxRequirements::'CL-006-04';
    private import WstxRecordingReceive::ErrorCode;
    private import WstxRecordingReceive::JobView;
    private import WstxRecordingReceive::HttpValidation;
    private import WstxRecordingReceive::Limits;
    enum def ImportState { enum reserved; enum receiving; enum validating; enum committing; enum cancelling; enum completed; enum cancelled; enum failed; }
    attribute def RecordingMetadata {
        attribute schema_version : Integer = 1;
        attribute recording_id : String;
        attribute file_bytes : Integer;
        attribute frames : Integer;
        attribute rate_hz : Integer = 12000;
        assert constraint bytes { file_bytes > 0 and file_bytes <= 3145728 }
        assert constraint count { frames > 0 and frames <= 1440000 }
        assert constraint schemaRate { schema_version == 1 and rate_hz == 12000 }
        doc /* Exact JSON keys above<=1024UTF8bytes,UUID-derived filenames confined
             profile area;original WAV unchanged,no arbitrary path/name/credentials. */
    }
    attribute def RecordingManifest {
        attribute schema_version : Integer = 1;
        attribute recording_id : String;
        doc /* Exact JSON above<=256bytes;atomic replacement is import commit. */
    }
    attribute def RecordingView {
        attribute id : String;
        attribute rate_hz : Integer = 12000;
        attribute frames : Integer;
        attribute file_bytes : Integer;
        attribute utc_anchor : String[0..1];
        doc /* Wire UTC always null for recording;exact fields above. */
    }
    attribute def ImportView {
        attribute id : String;
        attribute 'state' : ImportState;
        attribute received_bytes : Integer;
        attribute total_bytes : Integer[0..1];
        attribute error : ErrorCode[0..1];
        attribute recording_id : String[0..1];
        doc /* Exact resource keys;active snapshot omits recording_id. total null before
             first chunk,then fixed. Latest terminal resource until next reservation/
             restart;active snapshot import null at terminal state. */
    }
    attribute def RecordingSnapshot {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
        attribute recording : RecordingView[0..1];
        attribute source_error : ErrorCode[0..1];
        attribute storage_error : ErrorCode[0..1];
        attribute importOperation : ImportView[0..1];
        attribute job : JobView[0..1];
        doc /* Exact wire import key maps importOperation and omits recording_id. GET200
             <=8192bytes,no mutation. Missing/corrupt committed original/metadata/manifest
             =>recordingnull,source_error recording_unavailable;valid IDs/generation/
             operations remain for fresh-browser replacement. No fabricated job;affected
             job fails. Healthy/absent source_error null. Replacement clears error;
             replay meanwhile409 recording_unavailable. Degraded storage_error
             storage_unavailable keeps GET200 and refuses new import/replay503. */
    }
    attribute def StartImportBody {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
    }
    attribute def UploadChunk {
        attribute startByte : Integer;
        attribute endByte : Integer;
        attribute totalBytes : Integer;
        attribute bodyBytes : Integer;
        assert constraint chunk { bodyBytes > 0 and bodyBytes <= 2048 }
        assert constraint range { startByte >= 0 and endByte - startByte + 1 == bodyBytes and endByte < totalBytes and totalBytes <= 3145728 }
        doc /* Exactly one Content-Range bytes start-end/total;start=current received,
             total immutable after first chunk. Only1chunk request at once. Browser
             waits response before next;no streaming-request API assumption. */
    }
    action def ImportRecording {
        in request : StartImportBody;
        in validation : HttpValidation;
        out resource : ImportView;
        doc /* **Input capability.** RIFF/WAVE little-endian integer PCM format tag 1,
             mono, 16 bits/sample, exactly 12,000 samples/s; 1 through 1,440,000 source frames
             (120 seconds), at most 3,145,728 file bytes. Require one `fmt ` before one nonempty
             `data` chunk, PCM format size 16 or 18 with zero extension length, block alignment 2,
             byte rate 24,000 and an even data length. RIFF size plus eight equals actual file length;
             all chunk lengths and odd-length padding remain inside that length. Accept at most 64
             chunks total, skipping other bounded chunks without interpreting metadata. Reject
             RF64/RIFX, extensible/compressed/float formats, stereo, other rates, duplicate required
             chunks, inconsistent sizes and truncated headers/data/padding. Unknown ancillary chunks
             alone do not make otherwise valid input unsupported. Preserve the entire original file,
             including ancillary chunks. This deliberately narrow capability needs no codec/resampler;
             the pinned recorded fixtures satisfy it. Device rates and future
             import formats remain separate capabilities, not coercions into this format.

             **Source persistence.** One committed original/metadata pair per selected
             profile, one pending import reservation and no recording library. Store under a confined
             profile-owned recording area, using server UUID-derived names, never client paths or
             filenames. Metadata schema version 1 (at most1024 UTF-8 bytes) records recording UUID, file byte count, frame count
             and rate; sample bytes remain the original WAV. Manifest schema version 1 (at most256 UTF-8 bytes) contains exactly
             `schema_version:1` and `recording_id`; the UUID derives the original/metadata filenames.
             Per-source metadata contains exactly `schema_version:1,recording_id,file_bytes,frames,rate_hz`.
             No credentials or arbitrary path is stored in these records. Flush validated original/metadata before
             atomically switching the current-recording manifest; that manifest replacement is the
             commit point. A failed/cancelled pre-commit import leaves the previous source unchanged.
             After commit the new source is authoritative even if the response is lost; obtain a fresh
             snapshot rather than automatically repeat the mutation. Keep at most old and pending/new
             originals during replacement; remove obsolete/temp files after commit and on restart.
             Cancellation invalidates publication/commit authorization before its HTTP acknowledgement;
             accepting that operation and constructing its response take at most250ms locally,
             excluding network transit. Normal cleanup finishes within1s in isolated Windows tests.
             After an I/O error or5s cleanup deadline, publish failed/storage_unavailable and set
             storage_error; keep the pending files/handles quarantined and retain the one occupied
             operation/worker slot. Refuse further import/replay with503 storage_unavailable until
             cleanup actually succeeds or restart reconciles the directory. Do not claim deletion,
             start replacement workers or revert an already committed source. A blocked OS call may
             finish later, but its invalidated token cannot commit; final release clears storage_error
             only after real cleanup. Status/profile/settings and cancellation observation stay usable.
             Restart attempts cleanup once before enabling imports; failure keeps the degraded state.
             These are bounded application outcomes, not a claim to interrupt a blocked Windows I/O
             system call. A commit already begun is reconciled via snapshot, not cancelled. A corrupt/missing committed
             source is `recording_unavailable`; the authenticated recording snapshot remains200 with
             `recording:null` and `source_error:"recording_unavailable"`, preserving current identity,
             generation and operation state so a fresh browser can replace it. Profile/status/settings
             remain available and no source is fabricated. Restart preserves the committed recording ID/bytes and changes boot ID. The fresh
             boot starts with generation0, `import:null` and `job:null`; prior reservations and jobs
             are forgotten. Interrupted replay is invalidated by the changed boot identity, with no
             durable cancelled-job record, synthetic replacement job or persisted cancellation marker.
             Old import/job IDs return404; no automatic replay occurs. Cleanup/source failures retain
             their explicit error fields without recreating a pending operation. Only the declared
             source metadata/manifest/original persist; receive operations remain boot-local.
             | Route/method | Exact input | Success / transition |
             |---|---|---|
             | POST /recording/imports | `{v:1,profile_id,boot_id,generation}` | 201 `{v:1,id,generation,state:"reserved"}`; reserve one import UUID, increment generation, expire reservation after 30 seconds without PUT; Location identifies import resource. |
             | PUT /recording/imports/{id} | `Content-Type: audio/wav` only; one <=2048-byte raw chunk, exact single `Content-Range: bytes start-end/total`, no content encoding. total is1..3,145,728; start equals received_bytes, end-start+1 equals body size, total cannot change. | reserved -> receiving; intermediate chunks return202 `{v:1,id,state:"receiving",received_bytes}` after append. Final chunk -> validating -> committing -> completed and201 `{v:1,id,state:"completed",recording_id,generation}` after manifest commit. No automatic replay. Inactivity timeout15s, total deadline1800s. At most one chunk request is accepted at a time; concurrent/out-of-order chunks return409 state_conflict. Body cap applies even without/with lying Content-Length. |
             | GET /recording/imports/{id} | No body | 200 `{v:1,id,state,received_bytes,total_bytes,error,recording_id}`; state includes completed/cancelled/failed; recording_id null until commit. Retain only latest terminal import resource until next reservation/restart. |
             | DELETE /recording/imports/{id} | No body | 200 same import representation after cancellation invalidates pre-commit work; reserved can terminate immediately, receiving/validating become cancelling until file worker cleanup finishes, then cancelled. Already completed returns unchanged completed, never deletes committed source; repeating cancelled returns same terminal state. Once committing begins cancellation is refused409 invalid_state; GET reconciles completion/failure. The commit transition and cancellation request serialize so cancellation accepted before it prevents commit. |
             | POST /recording/replay | `{v:1,profile_id,boot_id,generation,recording_id}` | 202 `{v:1,id,generation,state:"running"}`; increment generation/start job at frame0; reject import/replay busy. |
             | DELETE /recording/jobs/{id} | No body | 200 `{v:1,id,generation,state}`; current running -> cancelling and publication invalidation before response; terminal jobs return unchanged terminal state. Worker release bound is separate from HTTP round trip. |*/
    }
    action def RecoverRecordedSource {
        out 'snapshot' : RecordingSnapshot;
        assert constraint newBootGeneration { 'snapshot'.generation == 0 }
        doc /* contract 4.4/12.6 restart postconditions: preserve selected profile and committed
             source UUID/original bytes; generate a new boot identity. Fresh snapshot
             import and job are null, generation0. Prior boot operations are forgotten,
             their import resources/job DELETE return404. No durable cancelled job,
             synthetic new job, cancellation marker or automatic replay. Only declared
             source metadata/manifest/original persist. Startup source/cleanup errors
             remain explicit error fields without resurrecting a pending operation.
             This refines recovery of existing profile/recording usages, not a new part. */
    }
    enum def ImportEvent {
        enum chunk_started; enum all_bytes_received; enum valid_and_flushed;
        enum cancel_accepted; enum transport_lost; enum reservation_expired;
        enum upload_expired; enum cleanup_succeeded; enum cleanup_failed_or_deadline;
        enum io_failure; enum validation_failed; enum commit_succeeded;
    }
    calc def ImportExpired {
        in currentState : ImportState;
        in reservationElapsedMs : Integer;
        in receiveIdleMs : Integer;
        in totalElapsedMs : Integer;
        in limits : Limits;
        return expired : Boolean =
            (currentState == ImportState::reserved and reservationElapsedMs >= limits.reservationMs) or
            (currentState == ImportState::receiving and
                (receiveIdleMs >= limits.uploadIdleMs or totalElapsedMs >= limits.uploadTotalMs));
        doc /* contract 12.6: station monotonic elapsed time, not browser timers; equality
             expires. Event dispatch is serialized with chunk/cancel/commit admission.
             Emit reservation_expired or upload_expired for the corresponding state. */
    }
    state def ImportLifecycle {
        attribute acceptedEvent : ImportEvent;
        attribute cancellationCleanup : Boolean;
        doc /* Events are accepted serially by the one station state owner. A cancel
             accepted before committing invalidates commit authorization before its
             acknowledgement. cancellationCleanup records explicit/transport cancellation;
             timeout cleanup retains upload_timeout instead. These are event outcomes,
             not competing Boolean policy flags or a new owner. */
        entry; then reserved;
        state reserved; state receiving; state validating; state committing;
        state cancelling; state completed; state cancelled; state failed;
        transition upload first reserved if acceptedEvent == ImportEvent::chunk_started then receiving;
        transition validate first receiving if acceptedEvent == ImportEvent::all_bytes_received then validating;
        transition commit first validating if acceptedEvent == ImportEvent::valid_and_flushed then committing;
        transition cancelReserved first reserved if acceptedEvent == ImportEvent::cancel_accepted then cancelled;
        transition cancelReceiving first receiving if acceptedEvent == ImportEvent::cancel_accepted then cancelling;
        transition cancelValidation first validating if acceptedEvent == ImportEvent::cancel_accepted then cancelling;
        transition abortReceiving first receiving if acceptedEvent == ImportEvent::transport_lost then cancelling;
        transition abortValidation first validating if acceptedEvent == ImportEvent::transport_lost then cancelling;
        transition reservationTimeout first reserved if acceptedEvent == ImportEvent::reservation_expired then cancelling;
        transition uploadTimeout first receiving if acceptedEvent == ImportEvent::upload_expired then cancelling;
        transition cleanedCancellation first cancelling if acceptedEvent == ImportEvent::cleanup_succeeded and cancellationCleanup then cancelled;
        transition cleanedTimeout first cancelling if acceptedEvent == ImportEvent::cleanup_succeeded and not cancellationCleanup then failed;
        transition quarantine first cancelling if acceptedEvent == ImportEvent::cleanup_failed_or_deadline or acceptedEvent == ImportEvent::io_failure then failed;
        transition reservationIoError first reserved if acceptedEvent == ImportEvent::io_failure then failed;
        transition uploadIoError first receiving if acceptedEvent == ImportEvent::io_failure then failed;
        transition validationIoError first validating if acceptedEvent == ImportEvent::io_failure then failed;
        transition rejected first validating if acceptedEvent == ImportEvent::validation_failed then failed;
        transition committed first committing if acceptedEvent == ImportEvent::commit_succeeded then completed;
        transition commitError first committing if acceptedEvent == ImportEvent::io_failure then failed;
        doc /* contract 4.4/12.6: reservation expiry30s; receiving inactivity15s or total1800s
             emits upload_expired. Timeout error is upload_timeout; observed PUT transport
             loss cancels the import. cleanup_succeeded requires actual release/removal,
             not an elapsed timer. Normal cancellation cleanup<=1s; I/O failure or cleanup
             deadline5s publishes failed/storage_unavailable, quarantines files/handles and
             retains the occupied slot until actual cleanup/restart reconciliation.
             A replaced manifest remains authoritative after post-commit failure.
             DELETE in committing is409 invalid_state; terminal DELETE is unchanged.
             Terminal resources persist only until next reservation/restart. */
    }
    enum def SourceAvailability { enum absent; enum available; enum unavailable; }
    calc def RecordingAvailability {
        in committedSourceUnavailable : Boolean;
        in recordingPresent : Boolean;
        return availability : SourceAvailability = if committedSourceUnavailable ?
            SourceAvailability::unavailable else if recordingPresent ?
            SourceAvailability::available else SourceAvailability::absent;
        doc /* contract 12.6: authenticated GET remains200 with current identity/generation/
             operations; unavailable sets recording:null and source_error recording_unavailable.
             Browser labels absence/unavailability distinctly; idle replacement stays enabled.
             Replay returns409 recording_unavailable until successful replacement clears error.
             Affected job fails under ReceiveLifecycle; no job/source is manufactured.
             Authentication/transport failure is not an absent/unavailable-source snapshot. */
    }
    action importRecording : ImportRecording;
    action recoverSource : RecoverRecordedSource;
    satisfy WstxProfileRecordings::'CL-006-01' by importRecording;
    dependency storageOwner from importRecording to WstxArchitecture::physicalStation::backend::stations::profile::recordings;
    dependency recoveryOwner from recoverSource to WstxArchitecture::physicalStation::backend::stations::profile::recordings;
    requirement 'CL-006-01' {
        doc /* Import only the bounded WAV capability below; preserve original bytes and expose immutable, explicitly timed samples without a codec or implicit resampler. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_01_to_FR_003 from 'CL-006-01' to 'FR-003';
    dependency CL_006_01_to_FR_018 from 'CL-006-01' to 'FR-018';
    verification 'TC-018-001' {
        doc /* TC-018-001
             CL-006-01, CL-006-02
             Construct byte-level PCM WAVs with 1, 2048, 4096, 4097 and 1,440,000 frames, endpoint samples -32768,-1,0,1,32767 and legal ancillary/padding chunks. Import, inspect blocks/metadata, replay twice and restart. Use the pinned actual recordings from chapter13 after retaining their license/provenance manifest; the verified22 inputs all fit the selected PCM capability.
             Provenance sweep (issue70, tests/recording-fixtures.test.cjs, no server): every one of the 22 FT8 and 3 FT4 original recordings in WSTX_SAMPLE_DIR has the sha256 of its manifest entry, and its hand-parsed RIFF/fmt header is PCM, 1 channel, 16 bit, 12000 Hz with a data size within the import cap; the enumeration equals the two manifests (25 files). Import (tests/recording.test.cjs): the first .wav entry of each manifest, one FT8 and one FT4 original, imports with rate_hz 12000, file_bytes equal to its length and stored bytes unchanged, and its replay paints waterfall rows.
             Hand-authored RIFF byte offsets/counts and exact signed-value/32768 mapping match; concatenated blocks equal input samples, <=4096 per block, contiguous offsets and one EOS; original bytes unchanged. Source UUID survives restart and repeats; job IDs differ, generations advance within a boot and reset to0 on restart, recording UTC remains null and no device opens. Analytical spectra repeat within 0.5 dB quantization plus 0.05 dB numerical tolerance. The actual recording proves non-synthetic input; it is not the calibration oracle. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-018-002' {
        doc /* TC-018-002
             CL-006-01, CL-006-02, CL-006-04
             Table-mutate each required WAV field/chunk, zero data, odd data, duplicate fmt/data, RIFF mismatch/overflow, truncation at each header/data boundary, rate/channel/format changes, 65 chunks, frame count max+1 and file cap+1; create legal exactly-at-cap ancillary data. Exercise slow/aborted/timed-out upload, cancel before/after validation commit and storage write/flush/manifest/cleanup failures, including restart at commit boundaries.
             Hand-specified errors follow 12.6; unsupported capability differs from malformed structure, exact limits accepted. Before manifest commit old bytes/ID remain; after it new bytes/ID remain even with lost response. No partial source becomes replayable, no unbounded pending file remains; startup cleanup keeps committed data and reports failure explicitly. Other station/profile/status remains available. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-01';
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording-fixtures.test.cjs; tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    dependency CL_006_01_verified_by_TC_018_001 from 'CL-006-01' to 'TC-018-001';
    dependency CL_006_01_verified_by_TC_018_002 from 'CL-006-01' to 'TC-018-002';
}
