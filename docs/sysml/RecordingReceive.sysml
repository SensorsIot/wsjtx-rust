// Canonical recorded receive contract SHA256: 8f412e30b6808b31ff6272848562bab3cf002b1c0a8b172847415e8c4a24f5fc
package WstxRecordingReceive {
    private import ScalarValues::*;
    doc /* Implementation contract from authoritative FSD4.4/6.4/12.6. Original Thin/recording and Detailed refinement implementations with executable
         verification companions exist;
         actual run/review/acceptance evidence belongs to issue #6. Existing
         usages only, no new deployment/universal job manager/TX authority.
         Shared RustFFT6.4.1 primary API https://docs.rs/rustfft/6.4.1/rustfft/,
         https://docs.rs/rustfft/6.4.1/rustfft/trait.Fft.html and
         https://docs.rs/rustfft/6.4.1/rustfft/struct.FftPlannerScalar.html.
         Independent DFT/math/oracles remain the original Markdown,not library output. */
    enum def ImportState { enum reserved; enum receiving; enum validating; enum committing; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def ReceiveState { enum running; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def DisplayProfile { enum off; enum thin; enum detail; }
    enum def ReceiveKind { enum spectrum; enum decode; enum live; }
    enum def ErrorCode {
        enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_request; enum unsupported_version;
        enum wrong_profile; enum state_conflict; enum not_found; enum busy;
        enum invalid_state; enum invalid_recording; enum unsupported_audio;
        enum recording_limit; enum storage_unavailable; enum upload_timeout;
        enum cancelled; enum no_recording; enum generation_exhausted;
        enum recording_unavailable; enum unavailable;
        enum invalid_samples; enum decode_limit; enum decode_failed;
    }
    attribute def Limits {
        attribute rateHz : Integer = 12000;
        attribute fileBytes : Integer = 3145728;
        attribute frames : Integer = 1440000;
        attribute riffChunks : Integer = 64;
        attribute blockSamples : Integer = 4096;
        attribute spectrumBlocks : Integer = 2;
        attribute workersPerStation : Integer = 1;
        attribute pendingJobs : Integer = 0;
        attribute fftSize : Integer = 2048;
        attribute detailFftSize : Integer = 4096;
        attribute detailHopFrames : Integer = 480;
        attribute commonHistorySamples : Integer = 8192;
        attribute defaultDisplayRangeDb : Integer = 30;
        attribute minDisplayRangeDb : Integer = 10;
        attribute maxDisplayRangeDb : Integer = 80;
        attribute detailBins : Integer = 1024;
        attribute detailRowFrames : Integer = 2400;
        attribute detailRows : Integer = 600;
        attribute detailIntervalMs : Integer = 200;
        attribute detailEventBytes : Integer = 2048;
        attribute detailBase64Chars : Integer = 1368;
        attribute outboundWriteBufferBytes : Integer = 4096;
        attribute controlHeadroomBytes : Integer = 1052;
        attribute hopFrames : Integer = 256;
        attribute displayBins : Integer = 128;
        attribute browserRows : Integer = 120;
        attribute pendingFramesPerPeer : Integer = 1;
        attribute pendingRepaint : Integer = 1;
        attribute displayIntervalMs : Integer = 1000;
        attribute checkpointMs : Integer = 50;
        attribute replayCancelReleaseMs : Integer = 250;
        attribute importCancelAckMs : Integer = 250;
        attribute normalCleanupMs : Integer = 1000;
        attribute faultCleanupOutcomeMs : Integer = 5000;
        attribute reservationMs : Integer = 30000;
        attribute uploadIdleMs : Integer = 15000;
        attribute uploadTotalMs : Integer = 1800000;
        attribute finalProcessingMs : Integer = 1000;
        attribute rawChunkBytes : Integer = 2048;
        attribute controlBytes : Integer = 1024;
        attribute snapshotBytes : Integer = 8192;
        attribute eventBytes : Integer = 1024;
        attribute thinBytesPerSecond : Integer = 3000;
        attribute offBytesPerSecond : Integer = 1000;
        attribute statusDisplayMs : Integer = 2000;
    }
    attribute def DisplayLevels {
        attribute blackDbfs : Integer = -120;
        attribute rangeDb : Integer = 30;
        attribute autoBlack : Boolean = true;
        attribute estimateFrozen : Boolean = false;
        attribute sensitivityDb : Integer = 0;
        attribute speedMultiplier : Real = 2;
        assert constraint localSliders { sensitivityDb >= -30 and sensitivityDb <= 30 and speedMultiplier >= 0.5 and speedMultiplier <= 8 }
        assert constraint displayRange { rangeDb >= 10 and rangeDb <= 80 and blackDbfs >= -120 and blackDbfs <= -rangeDb }
        doc /* Browser-local per job/profile state, no station-service mutation.
             Reset on job/source/profile: B=-120,R=30,Auto=true,frozen=false;
             preserve sensitivityDb/speedMultiplier until new page load. Effective
             waterfall black=clamp(B-sensitivityDb,-120,-R), curve retains baseB.
             Speed sets10*speedMultiplier CSSpx/source-second; fixed source intervals
             move down independent of history length, clip at bottom; unobserved
             pixels dark/no-measurement. Freeze without accepted rows; no source/network change.
             First lower-median q>0 row sets clamp(q-123,-120,-R), freezes.
             Median0/gap waits; manual B/R disables Auto. Re-enable uses latest
             qualifying retained row or waits. Original calibrated levels unchanged.
             Rounding, exact RGB palette, ruler/readout/geometry and all actions
             remain normative in PresentStation/CalculateSpectrum source contract. */
    }
    attribute def Correlation {
        attribute profile_id : String;
        attribute boot_id : String;
        attribute source_id : String;
        attribute job_id : String;
        attribute generation : Integer;
        doc /* Lowercase hyphenated UUIDs,never path/name/port. Station generation !=
             sample position/config revision/request ID/frame sequence; match full tuple
             before publication. New replay allocates job+generation,source unchanged. */
        assert constraint safeGeneration { generation >= 0 and generation <= (900719925 * 10000000 + 4740991) }
    }
    attribute def SourceDescriptor {
        attribute schema_version : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute source_id : String;
        attribute rate_hz : Integer;
        attribute channel : String = "mono_real";
        attribute total_frames : Integer[0..1];
        attribute utc_anchor : String[0..1];
        doc /* Immutable source lifetime. Recording12000Hz,known1..1440000frames,UTCnull;
             no filename timestamp. #8 settles live rates/clock/UTC/discontinuity before
             device code. Optional UTC separate from sample clock,not hardware support. */
        assert constraint schemaRate { schema_version == 1 and rate_hz > 0 }
    }
    item def SampleBlock :> WstxArchitecture::SampleBlock {
        attribute source : SourceDescriptor;
        attribute first_frame : Integer;
        attribute samples : Real[1..4096];
        attribute discontinuity : Boolean;
        attribute end_of_stream : Boolean;
        assert constraint nonnegativePosition { first_frame >= 0 }
        doc /* Finite f32 mono real,signedPCM16/32768 exactly. Arc<[f32]> or equivalent
             immutable shared owner;borrowers cannot mutate,producer reuse waits for
             last reference release. #6 spectrum path retains<=2blocks incl producer/
             consumers,no whole-file float array/backlog. #7 separately bounds modem
             history,not restricted to2blocks. Recordings start0,contiguous positions,
             discontinuityfalse,EOS last nonempty block. Semantic incompatible changes
             need coordinated new version. Unit conversion !=AGC/preprocessing/resampling. */
    }
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
    item def ReceiveJob :> WstxArchitecture::ProcessingRequest {
        attribute schema_version : Integer = 1;
        attribute correlation : Correlation;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        attribute cancelRequested : Boolean;
        assert constraint progress { processed_frames >= 0 and processed_frames <= 1440000 }
        doc /* Shared receive lifecycle: spectrum kind/settings below; target decode kind
             and immutable mode in StationDecode.sysml. One import OR spectrum OR decode,
             one worker/no pendingjobs; no CPU/file work holding state/profile lock. New
             generation on import/replay,refuse ceiling not wrap. Cancellation invalidates
             publication before ack;terminal progress remains until nextjob. No TX scope. */
    }
    attribute def JobView {
        attribute id : String;
        attribute source_id : String;
        attribute generation : Integer;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
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
    item def SpectrumFrame :> WstxArchitecture::ProcessingResult {
        attribute v : Integer = 1;
        attribute boot_id : String;
        attribute source_id : String;
        attribute job_id : String;
        attribute generation : Integer;
        attribute sequence : Integer;
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        attribute levels : Integer[128];
        assert constraint interval { sequence >= 0 and first_frame == 12000 * sequence and end_frame > first_frame and end_frame <= first_frame + 12000 }
        doc /* Exact envelope v1,type spectrum.frame,data with fields above except v;
             levels each0..120,q-120dBFS. end=min(first+12000,source_frames). sequence0
             per replay,advances despite droppedrows. Immutable producer-owned frame,
             <=1replaceable pending/peer,<=1send/s;browser120rows*128values,1pendingpaint.
             groupb[b*23.4375,(b+1)*23.4375)Hz. Ignore obsolete tuple/socket callbacks,
             show gaps,clear newsource/job. Required decode results never share drop rule. */
    }

    item def DetailedSpectrumFrame :> WstxArchitecture::ProcessingResult {
        attribute v : Integer = 1;
        attribute boot_id : String;
        attribute source_id : String;
        attribute job_id : String;
        attribute generation : Integer;
        attribute sequence : Integer;
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        attribute levels_b64 : String;
        assert constraint interval { sequence >= 0 and sequence < 600 and first_frame == 2400 * sequence and end_frame > first_frame and end_frame <= first_frame + 2400 }
        doc /* Exact spectrum.detail.frame envelope, <=2048 UTF8bytes; same current UUID/
             safe-integer tuple as Thin. Canonical padded standard RFC4648 base64 exactly
             1368chars decodes1024 bytes each0..120. Unknown/missing fields,
             noncanonical encoding, bad bounds/identities/socket are rejected atomically.
             Retain one latest immutable frame per profile in existing station state;
             per peer one replaceable selected frame, not two queues or another job. */
    }

    attribute def StartImportBody {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
    }
    attribute def StartReplayBody :> StartImportBody { attribute recording_id : String; }
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
    attribute def HttpValidation {
        attribute selectedProfile : Boolean;
        attribute originAllowed : Boolean;
        attribute authenticated : Boolean;
        attribute mediaAllowed : Boolean;
        attribute bodyBounded : Boolean;
        attribute schemaValid : Boolean;
        attribute versionSupported : Boolean;
        attribute sameProfile : Boolean;
        attribute sameBootGeneration : Boolean;
        attribute resourceKnown : Boolean;
        attribute stateAllowed : Boolean;
        doc /* Validation order: mode/route existence; Origin (403 forbidden_origin); TLS auth
             (401 unauthorized); content type/encoding (415 unsupported_media_type); declared or
             observed body bound (413 request_too_large, transport rejection may occur earlier);
             exact JSON/UUID/safe-integer/version schema (400 invalid_request/unsupported_version);
             profile mismatch (403 wrong_profile); boot/generation mismatch (409 state_conflict);
             resource existence (404 not_found); busy/state compatibility (409 busy/invalid_state);
             file structure (422 invalid_recording); supported PCM capability (422 unsupported_audio);
             frame/duration/chunk limit (422 recording_limit); I/O/cleanup (503 storage_unavailable).
             Malformed/missing/duplicate Content-Range is400 invalid_request; incorrect byte offset
             or changed total is409 state_conflict. An import total above the file cap is413
             request_too_large. A stalled/expired import is408 upload_timeout, explicit cancel is409 cancelled on an
             in-flight PUT; completed DELETE still returns200. A missing recording is409 no_recording;
             generation ceiling is409 generation_exhausted. Syntactic UUID errors are400; foreign
             well-formed UUIDs are404 except explicit profile_id mismatch. Errors do not echo input.
             Input progress is bytes received/declared Content-Range total while receiving; before
             the first chunk show awaiting upload rather than a fabricated percent. Validation/commit states are distinct from completed. */
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
        doc /* FSD4.4/12.6 restart postconditions: preserve selected profile and committed
             source UUID/original bytes; generate a new boot identity. Fresh snapshot
             import and job are null, generation0. Prior boot operations are forgotten,
             their import resources/job DELETE return404. No durable cancelled job,
             synthetic new job, cancellation marker or automatic replay. Only declared
             source metadata/manifest/original persist. Startup source/cleanup errors
             remain explicit error fields without resurrecting a pending operation.
             This refines recovery of existing profile/recording usages, not a new part. */
    }
    action def CancelImport {
        in importId : String;
        out resource : ImportView;
        doc /* Cancellation invalidates publication/commit authorization before its HTTP acknowledgement;
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
             system call. A commit already begun is reconciled via snapshot, not cancelled. */
    }
    action def ReplaySpectrum {
        in request : StartReplayBody;
        out job : ReceiveJob;
        out frames : SpectrumFrame[*];
        out detailedFrames : DetailedSpectrumFrame[*];
        doc /* **Receive lifecycle.** One active import OR replay per station, one CPU worker,
             no pending job queue; concurrent start gets `busy`. State owner transitions and token
             checks serialize; CPU/file work does not hold the state owner or profile-settings lock.
             A replay job has schema 1, profile/boot/source/job UUIDs, station generation (`u64`,
             wire-safe 0..9,007,199,254,740,991), kind `spectrum`, immutable settings, processed frame
             count and cooperative cancellation. #7 adds a separately approved decode settings kind
             using the same receive lifecycle. States are `running`, `cancelling`, `completed`,
             `cancelled`, `failed`; terminal progress remains in the snapshot until another job starts.
             Starting an import or replay allocates a fresh station generation; starting replay also
             allocates a fresh job UUID. Cancellation invalidates publication before returning its
             acknowledgement; every receive terminal transition follows worker release. For a
             current running job with no accepted cancellation, a processing failure remains
             nonterminal while the worker is held, then transitions to failed after release;
             it cannot become completed even if source EOS/completion is also observed. Completion
             requires source completion, worker release and absence of processing failure. These
             rules preserve the existing serialized cancellation/state ownership, rather than adding
             another cancellation priority policy. Do not reuse a generation
             on wrap; refuse new work with `generation_exhausted`. Every publication matches current
             profile/boot/source/job/generation. A prior job's completion/frames cannot replace the
             current snapshot. Source UUID is the persistent recording UUID, not a replay identity.
             Receive cancellation does not govern transmit authority or delay #9 halt.

             Spectrum replay in #6 is explicit, server-paced at source time (1x) for inspection,
             not speaker playback and not a radio operation. This pacing applies only to spectrum
             jobs; #7 must settle its offline decode pacing/runtime and bounded modem working history
             independently, using the same immutable source/sample and receive job identities. Completion occurs within1s after the source duration on the stated Windows workload,
             including final processing. Another browser may observe/cancel the same station-owned job. Browser
             closure/link loss removes its subscription; it does not cancel an accepted replay.
             Cancellation checks are at most 50 ms apart and worker release/terminal state occurs
             within 250 ms after cancellation is accepted, measured on the recorded Windows test PC
             with four profile processes and one active worker each. No hardware/global CPU-count
             auto-allocation is introduced. The UI reports the one-worker-per-station budget. */
    }
    action def CancelReceive {
        in jobId : String;
        out 'state' : ReceiveState;
        doc /* DELETE /recording/jobs/{id},nobody;running->cancelling,publication invalid
             before200{v1,id,generation,state};checkpoints<=50ms,terminalcancelled+release
             <=250ms onfourprocessWindowsworkload. TerminalDELETE unchanged,unknown/
             oldboot/foreignjob404,never cancels differentjob. terminalprogressretained. */
    }
    action def CalculateSpectrum {
        in samples : SampleBlock[*];
        out rows : SpectrumFrame[*];
        out detailedRows : DetailedSpectrumFrame[*];
        doc /* **Independent display definition (Thin, unchanged).** For 12 kHz input, use 2,048 real samples per
             window, hop 256 source frames, periodic Hann `w[n]=(1-cos(2*pi*n/2048))/2`; windows start
             at source frames 0,256,... while their start is before EOS. Right-pad the final partial
             windows with zeros, retaining actual source end in metadata. DFT convention is
             `X[k]=sum(x[n]*w[n]*exp(-i*2*pi*k*n/2048))`. Peak amplitude is `2*abs(X[k])/sum(w)` for
             positive interior bins and `abs(X[0])/sum(w)` for DC. Level is
             `20*log10(max(amplitude,10^(-120/20)))`, clipped to [-120,0] dBFS. This is calibrated
             peak-amplitude dBFS, not power density, SNR or receiver RF power. FFT output must agree
             with this independent definition regardless of the jointly selected provider. The joint
             technical selection is RustFFT **6.4.1** for both #6/#7: complex unnormalized
             forward negative-sign/inverse positive-sign transforms, DC-first ordering and caller-owned
             scaling. Use CPU `FftPlanner<f32>` for the normal path; retain an independently checked
             `FftPlannerScalar<f32>` portable path. A worker copies/window-converts source data into
             its own complex buffer, obtains `get_inplace_scratch_len()` for the plan and reuses
             worker-owned scratch with `process_with_scratch`; neither mutable buffer aliases the
             original immutable samples. #6 uses N=2048 for Thin and N=4096 for Detailed; #7 owns its supported transform sizes and
             bounded modem working history. Plan once per needed size/worker, never per display row;
             check lengths before processing so invalid input cannot reach a panic precondition.
             No generic FFT wrapper or additional RealFFT dependency is needed. This is the central
             owned dependency contract; the implementation declares RustFFT once in the server crate.
             The independent math/oracles remain this definition, rather than library output. Normative primary API: [RustFFT6.4.1 normalization/output order](https://docs.rs/rustfft/6.4.1/rustfft/),
             [`Fft` scratch/buffer contract](https://docs.rs/rustfft/6.4.1/rustfft/trait.Fft.html) and
             [`FftPlannerScalar`](https://docs.rs/rustfft/6.4.1/rustfft/struct.FftPlannerScalar.html).
             The explicit DFT formula above fixes sign/scaling independently of the provider.

             Expose 128 groups over [0,3000) Hz: group b is bins 4b..4b+3, each original bin separated
             by 12000/2048 Hz; group interval is [b*23.4375,(b+1)*23.4375) Hz. Retain maximum amplitude
             before converting to dBFS. One waterfall row covers each one-second source interval
             [j,j+1), shortened at EOS, taking maxima of windows whose start falls in that interval.
             Consequently window support can extend into the next interval; this smoothing is part
             of the time oracle. The spectrum is the same row's one-second peak hold. Quantize level
             as `floor(clipped_dBFS+120+0.5)` to integer 0..120; decoded level is q-120 dBFS with at
             most 0.5 dB quantization error. A 0.5-amplitude coherent tone has approximately -6.0206
             dBFS before PCM quantization, not a code-generated golden value. Silence is -120 dBFS.
             Label frequency in Hz, time relative to recording start in seconds and level in dBFS.
             Show gaps on skipped row sequences; never interpolate a missing row as observed signal.
             Browser retains at most 120 rows of 128 values; replacing the source/job clears history.

             **Detailed display definition.** Detailed is a fast-link profile with 1,024 native
             frequency bins, not a sharpened/resampled Thin image. For 12 kHz input use N=4096,
             hop480 (40ms), periodic Hann with denominator4096 and the same DFT sign, amplitude/DC rule,
             dBFS floor/clipping and integer quantization as Thin with N substituted throughout.
             Expose k=0..1023 at center frequency k*2.9296875 Hz, covering [0,3000) Hz without
             frequency pooling. The displayed bin's frequency cell is [k*2.9296875,(k+1)*2.9296875)
             Hz; this is display geometry, not a claim that the Hann response has rectangular support.
             A row j covers source frames [2400*j,min(2400*(j+1),source_frames)); use global
             window starts0,480,... strictly before EOS. Every nonempty row includes its start2400*j,
             so a full row has exactly five windows and a partial final row has one through five.
             For each bin k, let A[m,k] be each window's calibrated peak-amplitude estimate above;
             compute P[k]=sum(A[m,k]^2)/M over the M actual window starts in this row, then
             L[k]=clamp(10*log10(max(P[k],1e-12)),-120,0) and q=floor(L[k]+120+0.5).
             There is no frequency pooling, logarithmic averaging or maximum hold in Detailed.
             For source_frames2401, row1=[2400,2401) includes only start2400: the lone sample
             multiplies Hann w[0]=0 and the row is legitimately silence, not missing/fabricated data.
             Right-pad partial windows at EOS; window support is 4096/12000 seconds, can cross row
             boundaries and MUST be stated in the legend alongside 2.9296875 Hz bins and 0.2 s rows.
             The spectrum shows the latest row's levels. Row sequence starts0 and advances even
             when output is skipped; send at most5 rows/s/peer, paced against the source clock.
             Thin continues its exact N2048/four-bin/one-second definition and event schema.

             One replay/source reader and one existing station-owned worker produce both profiles
             concurrently; selecting Detailed never starts another job or reparses/reloads the file.
             Reuse RustFFT6.4.1 with one plan/buffer/scratch per needed size, the existing sample
             parser/immutable boundary, identities and cancellation checks. Keep at most two source
             blocks plus at most8192 f32 samples in a common bounded history, the two bounded FFT
             workspaces (2048 and4096 complex elements plus their plan-reported scratch), per-profile
             row accumulators (128 maxima for Thin,1024 power sums and a window count for Detailed) and one latest immutable frame per profile in station state. No
             subscriber-specific FFT or unbounded queue. Process the two independent start schedules
             against this same forward-only SourceFile reader. Release common history before the
             minimum next needed start; read only when space remains and retain lookahead only for
             those windows. Pad outside EOS without increasing actual source positions/progress;
             no second source file/parser, whole-recording float array or additional sample backlog. Starting/replacing/cancelling clears both
             latest frames; publication checks the existing complete current job tuple. Browser keeps
             at most600 Detailed rows (120s, 614400 level bytes), or120 Thin rows (15360 level bytes),
             including explicit gap slots, and one pending repaint. These are application retention
             bounds, not total RSS promises.

             **Crisp canvas geometry.** Render every frequency/time cell using integer device-pixel
             edges with a DPR-sized backing bitmap, image smoothing disabled and pixelated CSS image
             rendering; no blur/filter or interpolation of measured values. The whole fixed[0,3000)Hz span always fits the plot width; frequency mapping is f/3000*W,
             0Hz at left and3000Hz at right. Resize/DPR/zoom changes geometry only, not frequency
             span, FFT dimensions or native data. No horizontal frequency scrolling or minimum1024
             pixel canvas width. Let B be1024 Detailed or128 Thin and W the integer backing width.
             When W>=B, bin k spans[floor(k*W/B),floor((k+1)*W/B)) device pixels. When W<B,
             assign every native bin k to column floor(k*W/B); that column displays the maximum
             original q of its assigned bins, exactly once each, with no interpolation, frequency
             resampling of the retained array or skipped zero-width cells. This display-only maximum
             projection preserves narrow strong signals; it cannot show1024 separate bins in fewer
             than1024 physical columns. The complete original native array remains unchanged.
             Readout names the projected column's native-bin range and its maximum, and separately
             identifies the nearest native bin to the pointer frequency (clamped, ties upward) or the
             exact keyboard-selected bin. Native keyboard stepping never edits/aggregates the data.
             Axis labels/controls stay reachable with no horizontal page or frequency plot overflow.
             A pointer/focusable readout exposes selected
             native bin index, center Hz, original q-120 dBFS and row source interval; keyboard Left/Right moves one
             bin and Up/Down one retained row, clamped to available data. Gaps report no measurement.

             **Waterfall space and Speed.** The canvas fills its entire allotted box. New
             observed rows enter at the top and advance older rows downward at a fixed source-time
             scale; accumulated history is never stretched to fill the canvas. The Speed slider is
             v=0.5..8 in0.5 steps, default2, with numeric output 10*v CSS pixels per source second and
             Slow/Fast ends. Set p=10*v CSSpx/s. Detailed advances 2*v CSSpx per full0.2s row;
             Thin advances10*v CSSpx per full1s row. This changes only local presentation, never
             source replay, decoder, network cadence, sample clock or retained values.
             Round finite speed input to the nearest half-step with floor(2*value+0.5)/2,
             then clamp to[0.5,8]; nonfinite/unparseable input leaves speed unchanged.

             Let C be the actual CSS waterfall height, H=round(C*DPR) its backing height (minimum1),
             and T the newest accepted row's end_frame/12000. A row with source interval[a,b)
             occupies downward integer device-pixel edges
             [floor((T-b)*p*H/C),floor((T-a)*p*H/C)), clipped to[0,H).
             Thus the latest row starts at0; each new accepted source interval shifts existing
             history by its source-time duration times p, independent of retained row count N.
             Older rows leave through the bottom without sticking, stretching, wrapping or repeating.
             A shortened final row uses its actual interval. Paint absent/unobserved history dark
             RGB(0,0,12), including the part below a short recording; it is not a measurement.
             Explicit missing sequence slots remain grey RGB(96,96,96), never noise or repeated data.
             Zero-height rows, if any after integer rounding, contribute to pixel floor((T-b)*p*H/C).
             When several rows contribute to one pixel, use their per-bin maximum and mark the group
             unknown grey if any contributor is a gap. Native arrays remain unchanged.

             The visible source-time capacity is C/p seconds, independent of N. Display this
             capacity and the actual observed source interval separately. Retain the existing
             bounded history so reducing speed can expose earlier observations; never fabricate
             measurements for time outside retained observations. Time advances only on accepted
             source rows. Completed, cancelled, disconnected or stalled input freezes its last
             history; resizing or local controls may repaint but do not advance time. Replay is
             explicit and resets its job/history normally, without automatic looping.

             Pointer selection uses the exact source intervals contributing to its integer pixel.
             For measured pixels, choose the newest contributing native row as initial selection;
             Up/Down steps one visible native row, clamped. The readout separates the selected
             native bin/row value and interval from the projected native-bin/time ranges and maximum.
             For a gap, report unknown; for an unobserved pixel, report no measurement, without
             clamping it to the oldest measured row. Left/Right still steps native frequency bins.
             Speed or geometry changes recompute visible rows/readouts without mutating native data.

                          Keep spectrum above the fixed0..3000Hz ruler and waterfall. Allocate the remaining plot
             budget after headings/rulers/legend approximately1:5 to spectrum:waterfall, using explicit
             zero flex bases and min-height0 so intrinsic canvas bitmap heights cannot feed back into
             layout. Each backing bitmap is round(its actual CSS box * DPR), minimum1, and each
             canvas fills its allotted box exactly after drag, resize and zoom. Plot areas therefore
             use approximately17%/83% of their combined height, subject only to integer rounding.
             Headers, rulers and controls remain reachable at the existing pane minima and360px.
             No horizontal page/frequency scrolling or changed frequency span.

             Frequency ruler retains major500Hz/minor100Hz ticks with positions f/3000*W. Time ruler
             labels T at the top and source time t every5s within the viewport,
             at y=floor((T-t)*p*H/C)/DPR, omitting negative source times and colliding labels less
             than16CSSpx apart. The time scale and native/projected readouts use this same mapping;
             labels do not imply observations in unmeasured areas. Label elapsed source seconds, never synthetic UTC/RF frequency/dBm.
             Profile changes still clear browser history/old-profile frames; existing bounded history,
             source identities and one pending repaint remain unchanged.

             **Display levels and palette.** The display is a local presentation of calibrated
             levels, independent of source samples, FFT/averaging, wire quantization, Thin bandwidth
             and future decoding. Provide labeled keyboard-operable Black level (dBFS), Range (dB)
             and Auto black controls in the station page, plus labeled keyboard-operable Sensitivity
             and Speed range sliders. Sliders repaint on every input event with an adjacent current
             numeric output; no server persistence/new WS commands. Sensitivity g is integer-30..+30
             dB, default0. Speed is the fixed source-time scroll scale defined above. Both slider
             values persist through source/job/profile-display changes and resize within this page;
             only a new page load resets defaults. Existing Black/Range/Auto reset behavior remains.
             Range R is integer10..80dB, default30. Black B is integer[-120,-R]dBFS; default-120
             until Auto finds a noise estimate. Inputs are rounded with floor(value+0.5) and clamped;
             nonfinite/unparseable values leave current settings unchanged. Increasing R clamps B
             down to -R if necessary. The spectrum curve continues to use base[B,B+R] for its vertical scale. Sensitivity
             changes waterfall colors only: effective black E=clamp(B-g,-120,-R), with waterfall
             mapping span exactly[E,E+R]. Its color legend shows both effective ends in dBFS,
             Sensitivity output shows the signed dB offset, and the curve scale title identifies its
             base range. Neither curve data/scale nor original q-120 bin readouts are changed by
             Sensitivity. Clipping affects presentation only; the native values remain available.

             Auto black defaults on after each new source/job or display profile change, resetting
             R=30 and B=-120, without resetting Sensitivity or Speed. Sort a valid row's Bins quantized values and take the lower median
             qmed=sorted[floor((Bins-1)/2)]. Ignore gaps and rows with qmed=0 (silence/sparse-only
             floor); continue waiting instead of locking a false noise floor. On the first accepted
             row with qmed>0, set B=clamp(qmed-120-3,-120,-R), then freeze for this job/profile until
             manual action or reset. If no qualifying row exists, keep B=-120. Editing Black or Range
             turns Auto off. Moving Sensitivity leaves Auto enabled/frozen state unchanged: it is
             an offset applied after base noise estimation, not a new noise estimate. Turning Auto on clears its frozen estimate and derives it from the latest
             qualifying retained row, or waits for the next one if none exists. Repaint all retained
             rows when presentation controls change; samples/wire data never change or restart.

             For an original quantized level q, t=clamp(((q-120)-E)/R,0,1). Map t to this project's
             own RGB anchors, interpolating each channel linearly between adjacent anchors and
             rounding with floor(channel+0.5): t=0:(0,0,12), .15:(0,0,80), .35:(0,80,220),
             .50:(0,220,240), .65:(30,230,80), .80:(255,235,0), .95:(255,40,0),1:(255,0,0).
             Saturated/above-range signal is exactly RGB(255,0,0), never white. Below-floor/no-signal
             is RGB(0,0,12); gaps are RGB(96,96,96). This continuous level-to-color
             mapping does not interpolate spatial bins/rows: each rendered cell has one exact RGB
             color, fully opaque. Spectrum trace is RGB(180,245,220). Ruler/grid/text overlays stay
             outside waterfall measured cell interiors. A narrow labeled color legend uses these exact same anchors, positions and linear RGB
             channel interpolation/rounding, ending in the same saturated red; it displays the
             effective waterfall range. Rainbow hue progression does not assert monotonic luminance. No flattening, palette editor, gain normalization or new framework.

             Conventional presentation references, consulted2026-10-25: [WSJT-X User Guide9.2/14.7](https://wsjt.sourceforge.io/wsjtx-main_en.html#_wide_graph) describes spectral averaging,
             bin visibility and display level controls; [FlexRadio SmartSDR User Guide, Waterfall](https://edge.flexradio.com/www/offload/20260423063240/SmartSDR-Software-User-Guide.pdf)
             describes noise-floor black level and display range. These inform the operator's visual
             expectation, not numerical conformance or copied assets/code. The exact formulas,
             geometry and original palette above are authoritative for this implementation. A real
             busy FT8 recording MUST show multiple recognizable narrow time-varying transmissions
             against a dark noise floor with distinguishable brighter signals, reviewed at desktop
             and360px alongside these reference images; analytical tones alone do not meet visual
             acceptance. Readout remains calibrated dBFS rather than implying receiver RF power. */
    }
    action def TransferDisplay {
        in 'frame' : SpectrumFrame[0..1];
        in detailedFrame : DetailedSpectrumFrame[0..1];
        in requestedProfile : DisplayProfile;
        doc /* **Opt-in WebSocket extension.** Keep `wstx.v1`, 1024-byte incoming request/frame/message
             limits; outbound Thin/control payloads remain <=1024 bytes. Set the outbound write
             buffer cap to4096 bytes to admit a <=2048-byte Detailed event while reserving a full
             1024-byte control payload and two conservative14-byte framing allowances. Preserve existing station.get/status/error envelopes, validation order,
             binary1003, heartbeats and liveness unchanged. Add exact three-field requests
             `{v:1,type:"recording.get"|"spectrum.thin"|"spectrum.detail"|"spectrum.off",id}`. `recording.get` returns
             `{v:1,type:"recording.state",id,data:{generation,source_id,job_id,state}}` with nullable
             IDs/state; full snapshot stays HTTP. Thin/detail/off acknowledge
             `{v:1,type:"spectrum.subscription",id,data:{profile:"thin"|"detail"|"off"}}`. Selected-profile
             absence returns recoverable `unavailable` for these commands. Every new connection starts
             off; legacy peers receive only existing status/heartbeat messages. New browser obtains
             status/profile/recording HTTP snapshots before opting into the selected profile and showing current
             recording data; unknown_command from an older server visibly disables recording display.
             Default browser selection is Detailed only on cleartext HTTP loopback (localhost,
             127.0.0.1 or [::1]); HTTPS, including HTTPS localhost, defaults Thin. The selector offers
             "Detailed (fast link, up to 10 KiB/s per viewer)", "Thin (32 kbit/s link)" and Off.
             Detailed is explicitly selectable on HTTPS but carries no32 kbit/s promise. A server
             that supports recording/Thin but refuses spectrum.detail with unknown_command triggers
             one Thin subscription and visible "Detailed unavailable; using Thin" feedback. A server
             refusing recording.get/Thin disables recording display visibly as before. Never loop
             retries or replay a mutation. An environment-only server returns unavailable.
             No side effects occur through new WS requests apart from that connection's subscription.

             Only subscribed thin peers receive events
             `{v:1,type:"spectrum.frame",data:{boot_id,source_id,job_id,generation,sequence,first_frame,end_frame,levels}}`.
             IDs are UUIDs, sequence starts0 per replay row and increments even when rows are dropped;
             frame interval is [first_frame,end_frame), with first=12000*sequence, end=min(first+12000,
             source_frames). `levels` is exactly128 integers0..120 under 4.4's frequency/level contract.
             No null/unbounded extension fields. Each encoded event remains<=1024 bytes. No unsolicited
             recording snapshot/status payload change or application compression. Incoming binary still
             closes1003. Obsolete boot/source/job/generation events and callbacks from old sockets are
             ignored. Event loss cannot be used to infer missed decoder results.

             Detailed peers instead receive exactly
             `{v:1,type:"spectrum.detail.frame",data:{boot_id,source_id,job_id,generation,sequence,first_frame,end_frame,levels_b64}}`.
             The UUID/safe-integer identity rules are unchanged, first=2400*sequence,
             end=min(first+2400,source_frames), sequence0..599. levels_b64 is canonical RFC4648
             standard base64 with padding: exactly1368 ASCII characters decoding to1024 bytes,
             each0..120. Reject wrong alphabet/padding/length/noncanonical pad bits, values>120,
             unknown/missing fields, unsafe/out-of-range sequence/interval or stale identity/socket;
             never render partially accepted data. Every encoded Detailed event is<=2048 UTF-8
             bytes; no binary messages, lossy nibble packing or application compression.

             One replaceable pending display event per peer, of its selected profile, and <=1 Thin
             or <=5 Detailed sends per second; no replay of old
             frames after reconnect or off. Ready status replies and heartbeats take precedence;
             optional display output never waits in the connection loop and is skipped when send
             readiness/control headroom is unavailable. Its guard enforces event payload <=2048 and
             payload+1024+2*14<=4096; this intentionally replaces the previous996-byte guard, not
             bypasses it. A partially flushed optional write retains the original2s deadline;
             subsequent control output cannot reset or extend that deadline. Switching/off/reconnect
             forgets prior frame cursors and pending replacements; already buffered output remains
             bounded and is rejected by browser profile/identity guards. No old rows are replayed.
             Maintain existing two-second write deadline and bounded peer removal. Browser schedules
             at most one pending repaint and bounds history as in4.4. For two thin clients, steady
             60-second accounted traffic is<=3000 bytes/s each direction under12.4's unchanged link
             model; off preserves the status-only<=1000 budget. Every status refresh remains<=2s,
             including during one paced HTTP upload sharing that link. Browser sends one <=2048-byte chunk and waits for its response before the next; this
             bounds bulk bytes queued ahead of a small control request without relying on a browser
             streaming-request API. No completion-time promise is made for bulk import.
             Report upload and cold-page bytes/timing separately; fixtures are uploaded before the
             steady-state display measurement. Reconnection resets subscription and refreshes snapshots,
             never resumes or retries a mutation implicitly. */
    }
    action def PresentStation {
        attribute levels : DisplayLevels;
        doc /* **Crisp canvas geometry.** Render every frequency/time cell using integer device-pixel
             edges with a DPR-sized backing bitmap, image smoothing disabled and pixelated CSS image
             rendering; no blur/filter or interpolation of measured values. The whole fixed[0,3000)Hz span always fits the plot width; frequency mapping is f/3000*W,
             0Hz at left and3000Hz at right. Resize/DPR/zoom changes geometry only, not frequency
             span, FFT dimensions or native data. No horizontal frequency scrolling or minimum1024
             pixel canvas width. Let B be1024 Detailed or128 Thin and W the integer backing width.
             When W>=B, bin k spans[floor(k*W/B),floor((k+1)*W/B)) device pixels. When W<B,
             assign every native bin k to column floor(k*W/B); that column displays the maximum
             original q of its assigned bins, exactly once each, with no interpolation, frequency
             resampling of the retained array or skipped zero-width cells. This display-only maximum
             projection preserves narrow strong signals; it cannot show1024 separate bins in fewer
             than1024 physical columns. The complete original native array remains unchanged.
             Readout names the projected column's native-bin range and its maximum, and separately
             identifies the nearest native bin to the pointer frequency (clamped, ties upward) or the
             exact keyboard-selected bin. Native keyboard stepping never edits/aggregates the data.
             Axis labels/controls stay reachable with no horizontal page or frequency plot overflow.
             A pointer/focusable readout exposes selected
             native bin index, center Hz, original q-120 dBFS and row source interval; keyboard Left/Right moves one
             bin and Up/Down one retained row, clamped to available data. Gaps report no measurement.

             **Waterfall space and Speed.** The canvas fills its entire allotted box. New
             observed rows enter at the top and advance older rows downward at a fixed source-time
             scale; accumulated history is never stretched to fill the canvas. The Speed slider is
             v=0.5..8 in0.5 steps, default2, with numeric output 10*v CSS pixels per source second and
             Slow/Fast ends. Set p=10*v CSSpx/s. Detailed advances 2*v CSSpx per full0.2s row;
             Thin advances10*v CSSpx per full1s row. This changes only local presentation, never
             source replay, decoder, network cadence, sample clock or retained values.
             Round finite speed input to the nearest half-step with floor(2*value+0.5)/2,
             then clamp to[0.5,8]; nonfinite/unparseable input leaves speed unchanged.

             Let C be the actual CSS waterfall height, H=round(C*DPR) its backing height (minimum1),
             and T the newest accepted row's end_frame/12000. A row with source interval[a,b)
             occupies downward integer device-pixel edges
             [floor((T-b)*p*H/C),floor((T-a)*p*H/C)), clipped to[0,H).
             Thus the latest row starts at0; each new accepted source interval shifts existing
             history by its source-time duration times p, independent of retained row count N.
             Older rows leave through the bottom without sticking, stretching, wrapping or repeating.
             A shortened final row uses its actual interval. Paint absent/unobserved history dark
             RGB(0,0,12), including the part below a short recording; it is not a measurement.
             Explicit missing sequence slots remain grey RGB(96,96,96), never noise or repeated data.
             Zero-height rows, if any after integer rounding, contribute to pixel floor((T-b)*p*H/C).
             When several rows contribute to one pixel, use their per-bin maximum and mark the group
             unknown grey if any contributor is a gap. Native arrays remain unchanged.

             The visible source-time capacity is C/p seconds, independent of N. Display this
             capacity and the actual observed source interval separately. Retain the existing
             bounded history so reducing speed can expose earlier observations; never fabricate
             measurements for time outside retained observations. Time advances only on accepted
             source rows. Completed, cancelled, disconnected or stalled input freezes its last
             history; resizing or local controls may repaint but do not advance time. Replay is
             explicit and resets its job/history normally, without automatic looping.

             Pointer selection uses the exact source intervals contributing to its integer pixel.
             For measured pixels, choose the newest contributing native row as initial selection;
             Up/Down steps one visible native row, clamped. The readout separates the selected
             native bin/row value and interval from the projected native-bin/time ranges and maximum.
             For a gap, report unknown; for an unobserved pixel, report no measurement, without
             clamping it to the oldest measured row. Left/Right still steps native frequency bins.
             Speed or geometry changes recompute visible rows/readouts without mutating native data.

                          Keep spectrum above the fixed0..3000Hz ruler and waterfall. Allocate the remaining plot
             budget after headings/rulers/legend approximately1:5 to spectrum:waterfall, using explicit
             zero flex bases and min-height0 so intrinsic canvas bitmap heights cannot feed back into
             layout. Each backing bitmap is round(its actual CSS box * DPR), minimum1, and each
             canvas fills its allotted box exactly after drag, resize and zoom. Plot areas therefore
             use approximately17%/83% of their combined height, subject only to integer rounding.
             Headers, rulers and controls remain reachable at the existing pane minima and360px.
             No horizontal page/frequency scrolling or changed frequency span.

             Frequency ruler retains major500Hz/minor100Hz ticks with positions f/3000*W. Time ruler
             labels T at the top and source time t every5s within the viewport,
             at y=floor((T-t)*p*H/C)/DPR, omitting negative source times and colliding labels less
             than16CSSpx apart. The time scale and native/projected readouts use this same mapping;
             labels do not imply observations in unmeasured areas. Label elapsed source seconds, never synthetic UTC/RF frequency/dBm.
             Profile changes still clear browser history/old-profile frames; existing bounded history,
             source identities and one pending repaint remain unchanged.

             **Display levels and palette.** The display is a local presentation of calibrated
             levels, independent of source samples, FFT/averaging, wire quantization, Thin bandwidth
             and future decoding. Provide labeled keyboard-operable Black level (dBFS), Range (dB)
             and Auto black controls in the station page, plus labeled keyboard-operable Sensitivity
             and Speed range sliders. Sliders repaint on every input event with an adjacent current
             numeric output; no server persistence/new WS commands. Sensitivity g is integer-30..+30
             dB, default0. Speed is the fixed source-time scroll scale defined above. Both slider
             values persist through source/job/profile-display changes and resize within this page;
             only a new page load resets defaults. Existing Black/Range/Auto reset behavior remains.
             Range R is integer10..80dB, default30. Black B is integer[-120,-R]dBFS; default-120
             until Auto finds a noise estimate. Inputs are rounded with floor(value+0.5) and clamped;
             nonfinite/unparseable values leave current settings unchanged. Increasing R clamps B
             down to -R if necessary. The spectrum curve continues to use base[B,B+R] for its vertical scale. Sensitivity
             changes waterfall colors only: effective black E=clamp(B-g,-120,-R), with waterfall
             mapping span exactly[E,E+R]. Its color legend shows both effective ends in dBFS,
             Sensitivity output shows the signed dB offset, and the curve scale title identifies its
             base range. Neither curve data/scale nor original q-120 bin readouts are changed by
             Sensitivity. Clipping affects presentation only; the native values remain available.

             Auto black defaults on after each new source/job or display profile change, resetting
             R=30 and B=-120, without resetting Sensitivity or Speed. Sort a valid row's Bins quantized values and take the lower median
             qmed=sorted[floor((Bins-1)/2)]. Ignore gaps and rows with qmed=0 (silence/sparse-only
             floor); continue waiting instead of locking a false noise floor. On the first accepted
             row with qmed>0, set B=clamp(qmed-120-3,-120,-R), then freeze for this job/profile until
             manual action or reset. If no qualifying row exists, keep B=-120. Editing Black or Range
             turns Auto off. Moving Sensitivity leaves Auto enabled/frozen state unchanged: it is
             an offset applied after base noise estimation, not a new noise estimate. Turning Auto on clears its frozen estimate and derives it from the latest
             qualifying retained row, or waits for the next one if none exists. Repaint all retained
             rows when presentation controls change; samples/wire data never change or restart.

             For an original quantized level q, t=clamp(((q-120)-E)/R,0,1). Map t to this project's
             own RGB anchors, interpolating each channel linearly between adjacent anchors and
             rounding with floor(channel+0.5): t=0:(0,0,12), .15:(0,0,80), .35:(0,80,220),
             .50:(0,220,240), .65:(30,230,80), .80:(255,235,0), .95:(255,40,0),1:(255,0,0).
             Saturated/above-range signal is exactly RGB(255,0,0), never white. Below-floor/no-signal
             is RGB(0,0,12); gaps are RGB(96,96,96). This continuous level-to-color
             mapping does not interpolate spatial bins/rows: each rendered cell has one exact RGB
             color, fully opaque. Spectrum trace is RGB(180,245,220). Ruler/grid/text overlays stay
             outside waterfall measured cell interiors. A narrow labeled color legend uses these exact same anchors, positions and linear RGB
             channel interpolation/rounding, ending in the same saturated red; it displays the
             effective waterfall range. Rainbow hue progression does not assert monotonic luminance. No flattening, palette editor, gain normalization or new framework.

             Conventional presentation references, consulted2026-10-25: [WSJT-X User Guide9.2/14.7](https://wsjt.sourceforge.io/wsjtx-main_en.html#_wide_graph) describes spectral averaging,
             bin visibility and display level controls; [FlexRadio SmartSDR User Guide, Waterfall](https://edge.flexradio.com/www/offload/20260423063240/SmartSDR-Software-User-Guide.pdf)
             describes noise-floor black level and display range. These inform the operator's visual
             expectation, not numerical conformance or copied assets/code. The exact formulas,
             geometry and original palette above are authoritative for this implementation. A real
             busy FT8 recording MUST show multiple recognizable narrow time-varying transmissions
             against a dark noise floor with distinguishable brighter signals, reviewed at desktop
             and360px alongside these reference images; analytical tones alone do not meet visual
             acceptance. Readout remains calibrated dBFS rather than implying receiver RF power.

             **Integrated UI.** One browser window/page per station. Spectrum and waterfall
             occupy the upper pane; profile/status/import/replay/controls and future decoded messages
             occupy the lower pane. No placeholder decoded messages or signal data. Horizontal
             separator is focusable with `role=separator`, horizontal orientation, accessible name,
             current/min/max pane sizes and visible focus. Pointer/mouse/touch drag changes upper
             height; Up/Down change it by 16 px, Home/End select min/max. Minimum upper/lower pane
             heights are 160/200 CSS px excluding a 12 px separator. If available height is smaller,
             scroll the page rather than violate minima. Lower controls also scroll independently
             when needed. Initial split is 50% of available height clamped to minima. Recompute/clamp
             on viewport changes; no server persistence of pane size. Verify 1100x850 and 360x640,
             keyboard-only use, touch input, 200% zoom and literal rendering of source/status text.
             No horizontal page overflow; axis labels and primary controls remain reachable. */
    }
    state def ImportLifecycle {
        attribute chunkStarted : Boolean;
        attribute allBytesReceived : Boolean;
        attribute validAndFlushed : Boolean;
        attribute cancelAccepted : Boolean;
        attribute cleanupSucceeded : Boolean;
        attribute storageFaultOrDeadline : Boolean;
        attribute commitSucceeded : Boolean;
        attribute validationFailed : Boolean;
        entry; then reserved;
        state reserved; state receiving; state validating; state committing;
        state cancelling; state completed; state cancelled; state failed;
        transition upload first reserved if chunkStarted then receiving;
        transition validate first receiving if allBytesReceived then validating;
        transition commit first validating if validAndFlushed and not cancelAccepted then committing;
        transition cancelReserved first reserved if cancelAccepted then cancelled;
        transition cancelReceiving first receiving if cancelAccepted then cancelling;
        transition cancelValidation first validating if cancelAccepted then cancelling;
        transition cleaned first cancelling if cleanupSucceeded then cancelled;
        transition quarantine first cancelling if storageFaultOrDeadline then failed;
        transition rejected first validating if validationFailed then failed;
        transition committed first committing if commitSucceeded then completed;
        transition commitError first committing if storageFaultOrDeadline then failed;
        doc /* Flags are stationevents,not freepolicy. Reservation/uploadtimeout enters
             cleanup with upload_timeout;transportloss samecleanup. FailedblockedI/O
             retains slot. Restartreconcilesactualmanifest,notHTTPresponse. */
    }
    state def ReceiveLifecycle {
        attribute cancelAccepted : Boolean;
        attribute workerReleased : Boolean;
        attribute sourceComplete : Boolean;
        attribute processingFailed : Boolean;
        entry; then running;
        state running; state cancelling; state completed; state cancelled; state failed;
        transition cancel first running if cancelAccepted then cancelling;
        transition release first cancelling if workerReleased then cancelled;
        transition complete first running if sourceComplete and workerReleased and not processingFailed and not cancelAccepted then completed;
        transition fail first running if processingFailed and workerReleased then failed;
    }
    action importRecording : ImportRecording;
    action recoverSource : RecoverRecordedSource;
    action cancelImport : CancelImport;
    action replaySpectrum : ReplaySpectrum;
    action cancelReceive : CancelReceive;
    action spectrum : CalculateSpectrum;
    action transfer : TransferDisplay;
    action present : PresentStation;
    satisfy WstxRequirements::'CL-006-01' by importRecording;
    satisfy WstxRequirements::'CL-006-02' by replaySpectrum;
    satisfy WstxRequirements::'CL-006-03' by spectrum;
    satisfy WstxRequirements::'CL-006-04' by cancelReceive;
    dependency storageOwner from importRecording to WstxArchitecture::physicalStation::controller::stations::profile::recordings;
    dependency recoveryOwner from recoverSource to WstxArchitecture::physicalStation::controller::stations::profile::recordings;
    dependency importAuthority from cancelImport to WstxArchitecture::physicalStation::controller::stations::station;
    dependency receiveOwner from replaySpectrum to WstxArchitecture::physicalStation::controller::stations::receive;
    dependency cancellationOwner from cancelReceive to WstxArchitecture::physicalStation::controller::stations::receive;
    dependency spectrumOwner from spectrum to WstxArchitecture::physicalStation::controller::stations::receive;
    dependency transferOwner from transfer to WstxArchitecture::physicalStation::controller::stations::web;
    dependency browserOwner from present to WstxArchitecture::physicalStation::viewer::browsers;
    dependency sharedInput from SampleBlock to WstxArchitecture::physicalStation::controller::stations::audio;

    package IndependentVerification {
        doc /* All cases cost 2 - isolated automated tests on Windows development PC.
             Actual candidate server/browser, disposable profiles, synthetic byte fixtures,
             independent direct DFT and pinned actual recordings with chapter13 provenance.
             No radio/audio device/live station. Definitions and candidate source presence are not acceptance results.
             Original Markdown remains the independent expectation for implementation. */
        verification validRecording {
            subject operation : ImportRecording;
            objective { verify WstxRequirements::'CL-006-01'; verify WstxRequirements::'CL-006-02'; }
            doc /* TC-018-001: setup/input/action: Construct byte-level PCM WAVs with 1, 2048, 4096, 4097 and 1,440,000 frames, endpoint samples -32768,-1,0,1,32767 and legal ancillary/padding chunks. Import, inspect blocks/metadata, replay twice and restart. Use the pinned actual recordings from chapter13 after retaining their license/provenance manifest; the verified22 inputs all fit the selected PCM capability.
                 Independent expected oracle: Hand-authored RIFF byte offsets/counts and exact signed-value/32768 mapping match; concatenated blocks equal input samples, <=4096 per block, contiguous offsets and one EOS; original bytes unchanged. Source UUID survives restart and repeats; job IDs differ, generations advance within a boot and reset to0 on restart, recording UTC remains null and no device opens. Analytical spectra repeat within 0.5 dB quantization plus 0.05 dB numerical tolerance. The actual recording proves non-synthetic input; it is not the calibration oracle. */
        }
        dependency tracevalidRecording from validRecording to WstxRequirements::'TC-018-001';
        verification invalidRecording {
            subject operation : ImportRecording;
            objective { verify WstxRequirements::'CL-006-01'; verify WstxRequirements::'CL-006-02'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-018-002: setup/input/action: Table-mutate each required WAV field/chunk, zero data, odd data, duplicate fmt/data, RIFF mismatch/overflow, truncation at each header/data boundary, rate/channel/format changes, 65 chunks, frame count max+1 and file cap+1; create legal exactly-at-cap ancillary data. Exercise slow/aborted/timed-out upload, cancel before/after validation commit and storage write/flush/manifest/cleanup failures, including restart at commit boundaries.
                 Independent expected oracle: Hand-specified errors follow 12.6; unsupported capability differs from malformed structure, exact limits accepted. Before manifest commit old bytes/ID remain; after it new bytes/ID remain even with lost response. No partial source becomes replayable, no unbounded pending file remains; startup cleanup keeps committed data and reports failure explicitly. Other station/profile/status remains available. */
        }
        dependency traceinvalidRecording from invalidRecording to WstxRequirements::'TC-018-002';
        verification receiveIsolation {
            subject operation : CancelReceive;
            objective { verify WstxRequirements::'CL-006-02'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-018-003: setup/input/action: Two independent authenticated clients race import/replay/cancel using current/stale/wrong boot, profile, generation and token IDs; inject a late worker publication, disconnect/reconnect, restart during replay; separately restart during an uncommitted reserved/receiving import, then query the fresh snapshot and old import/job IDs before starting new work; run maximum source and four processes. In a separate current running job with no cancellation, hold worker release, report processing failure, then source completion, inspect state before release and finally release the worker. Enumerate every 12.6 endpoint with missing/wrong Origin/cookie, method, media type, body/schema and token errors.
                 Independent expected oracle: Exactly one serialized start wins. Restart preserves the last committed source UUID/bytes but changes boot, resets generation0 and returns import:null/job:null; prior import resource and job DELETE return404, with no cancelled-job record or automatic replay. Errors and snapshots match fixed state-transition table, lost-response recovery never auto-replays. Wrong identities cannot affect selected station. Replay cancel invalidates output before ack and reaches terminal/worker release <=250 ms under stated workload; import cancel prevents commit when accepted before committing, acknowledges locally<=250ms, cleans normally<=1s or becomes failed/storage_unavailable by5s with slot/files quarantined and no false deletion; progress never exceeds frame count. The held-worker failure vector stays running/nonterminal before release, becomes failed on release and is never completed, including simultaneous source completion. Instrument retained block/worker/slot counts against contract bounds; this is not a total RSS claim. Original station.get/auth/profile regression assertions remain in force. Also corrupt the committed original/metadata/manifest in separate fixtures, restart, open a fresh browser, obtain200 snapshot with source_error and valid identities, then import a valid replacement using those identities: replacement succeeds, clears source_error and replays; replay before replacement returns409 recording_unavailable. */
        }
        dependency tracereceiveIsolation from receiveIsolation to WstxRequirements::'TC-018-003';
        verification calibratedDisplay {
            subject operation : CalculateSpectrum;
            objective { verify WstxRequirements::'CL-006-03'; }
            doc /* TC-010-001: setup/input/action: Independently synthesize silence, DC, coherent tones at 750/1500/2250 Hz at amplitudes 0.5/0.25, two simultaneous tones, a noncoherent tone, clipped input and a burst with specified source-frame start/end. Compute selected windows using a direct DFT test oracle; replay through real browser.
                 Independent expected oracle: Direct DFT uses published formula without candidate FFT/provider helpers; peak group equals floor(k/4) for coherent bins and row interval follows window-start rule. Half-amplitude change is -6.0206 dB within 0.05 dB prequantization; quantized levels add <=0.5 dB. Silence equals floor; DC uses one-sided exception. Require normal and portable scalar FFT paths against the same direct DFT oracle, then compare full selected rows, axes/legend/row gaps in DOM/canvas sampling and source metadata, not screenshot resemblance alone. */
        }
        dependency tracecalibratedDisplay from calibratedDisplay to WstxRequirements::'TC-010-001';
        verification boundedThinLink {
            subject operation : TransferDisplay;
            objective { verify WstxRequirements::'CL-006-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-010-002: setup/input/action: Existing independently calibrated shared TLS link: 4000 bytes/s each direction, 150 ms one-way, two real browsers. After upload/page load, replay >=60 s with both thin; issue paired status refresh at ten preselected source times. Repeat off; stall one reader, replace/cancel job and reconnect. Separately upload while refreshing.
                 Independent expected oracle: Over 60 steady-state seconds thin total <=3000 accounted bytes/s each direction and every connected refresh displays <=2 s; off preserves existing <=1000 idle budget. No >1 frame/s/peer, >1024-byte event or >1 pending optional frame; no raw audio streaming. Missing rows are gaps, obsolete frames ignored, reconnection obtains snapshot before subscription. Upload bytes/time and cold asset metrics are reported separately; upload must not break status<=2 s. Counter oracle is simulator's actual-stream+defined overhead, not physical-link certification. */
        }
        dependency traceboundedThinLink from boundedThinLink to WstxRequirements::'TC-010-002';
        verification integratedPanes {
            subject operation : PresentStation;
            objective { verify WstxRequirements::'CL-006-03'; }
            doc /* TC-010-003: setup/input/action: Real browser at 1100x850 and 360x640: import actual recording, verify one station page, drag divider beyond both extremes, use keyboard/touch/zoom and resize during replay. Repeat four independent station windows.
                 Independent expected oracle: Measured pane bounds meet 160/200 px minima, separator is 12 px and accessible, keyboard steps16px/Home/End clamp, small-height page scrolls, no horizontal page overflow, controls and axes remain reachable. Pointer/keyboard actions change only that station's pane, no second waterfall window appears and data/source identity survives resize. Browser assertions plus desktop/narrow screenshots verify actual layout. */
        }
        dependency traceintegratedPanes from integratedPanes to WstxRequirements::'TC-010-003';
        verification nativeBinDetail {
            subject operation : CalculateSpectrum;
            objective { verify WstxRequirements::'CL-006-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-010-004: Executable companions: server/src/recording_tests.rs, server/src/protocol_tests.rs and tests/recording.test.cjs; cost2 automated Windows offline.
                 Setup/actions: Cost2, automated Windows Rust numerical tests and real browser/server fixtures. Synthesize independent PCM16 vectors: silence/DC, single tones at native k256 and k257 separately and summed with fixed phases/amplitudes; simultaneous750 and756.25 Hz tones; amplitude0.5/0.25 and bursts at source frames1920/2400/2880 and sources of1/2399/2400/2401/2879/2880/2881 frames with short/EOS windows. Compare N4096 normal/scalar FFT bins and complete selected power-averaged rows against a test-only f64 direct DFT of the hand-specified periodic Hann formula, without candidate FFT/window/quantizer helpers. Replay one source with simultaneous Thin and Detailed peers, then race cancellation/replacement.
                 Independent expected oracle: Native k256=750Hz and k257=752.9296875Hz remain separate values; Hann leakage/interference is compared to the independent DFT, not an assertion that adjacent equal tones must form two local maxima. 750/756.25Hz signal retains independently predicted bin peaks/valley; no four-bin pooling or frequency resampling. Prequantized error <=0.05dB on independently specified bins above -80dBFS and absolute amplitude error<=2e-6 elsewhere; quantized values differ by <=1 level from independently rounded DFT, exact silence0. One coherent half-amplitude tone gives -6.0206dBFS before PCM error. Row assignment uses global hop480: five starts/full2400-frame row, one to five at EOS, including start2400 in source_frames2401. Independent mean-square amplitude then10log10 differs from Thin maximum and from averaging dB; zero Hann endpoint yields legitimate final silence for2401. Intervals are2400 frames, shortened EOS, sequence<=599. One source/worker, two latest frames, declared workspace/history limits and cancellation release<=250ms remain; stale publications cannot overwrite either profile. Thin numerical expectations from TC-010-001 remain unchanged. */
        }
        dependency tracenativeBinDetail from nativeBinDetail to WstxRequirements::'TC-010-004';
        verification crispDetailTransport {
            subject operation : PresentStation;
            objective { verify WstxRequirements::'CL-006-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-010-005: Executable companions: server/src/recording_tests.rs, server/src/protocol_tests.rs and tests/recording.test.cjs; cost2 automated Windows offline.
                 Setup/actions: Cost2, automated Windows real browser/candidate server plus deterministic injected wire fixtures. Exercise cleartext loopback and HTTPS defaults; explicit three-profile changes, old Thin-only/older server, simultaneous Thin/Detailed peers, malformed base64 alphabet/padding/pad bits/decoded lengths/values, unknown/missing keys, safe-integer/interval edges, wrong tuples/old sockets and skipped sequences. Use alternating known quantized levels in adjacent native bins/rows and read actual getImageData at1100x850 and360x640, DPR1/2,200% zoom, splitter extremes, resize and repaint; exercise Auto silence-then-noise, lower-median/round/clamp vectors, freeze/reset/manual overrides and range/legend/readout consistency. Retain actual busy FT8 recording desktop/mobile screenshots and compare their trace/noise contrast, orientation and rulers qualitatively with WSJT-X/FlexRadio reference images. Stall Detailed output with a controlled sink returning Pending, then issue status/control and cancel/off.
                 Independent expected oracle: Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. No >5Hz Detailed or >1Hz Thin, backfill or second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve, unchanged2s removal from first pending write; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. TC-010-002 unchanged TLS32kbit/s Thin/Off regression still runs. HTTP loopback defaults Detailed, HTTPS defaults Thin; fallback attempts Thin once and labels unavailability. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness. */
        }
        dependency tracecrispDetailTransport from crispDetailTransport to WstxRequirements::'TC-010-005';
        verification fullHeightSliderPresentation {
            subject operation : PresentStation;
            objective { verify WstxRequirements::'CL-006-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-010-006: implemented executable companion in tests/recording.test.cjs.
                 Setup/actions: Cost2 automated Windows real browser/candidate fixtures. Inject independently known native rows of2,75,600 Detailed or120 Thin values with contrasting bins/rows and gaps; inspect actual RGBA/backing and CSS box dimensions at desktop1100x850/mobile360x640, DPR1/2,200% zoom and splitter bounds. Exercise Sensitivity-30/0/+30 and Speed1/2/8 via input, keyboard and numeric outputs, manual Black/Range, Auto silence/noise/freeze/reset, new jobs/profiles and resize. Replay actual busy FT8 with a red saturated carrier, capture desktop/mobile screenshots and move both live sliders.
                 Independent expected oracle: Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With base B=-83,R=30, g=+10 yields E=-93 and g=-30 yields E=-53, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. Sensitivity does not disable/re-estimate Auto; manual Black/Range does, new-job/profile resets only existing base/Auto settings and preserves both slider values. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security/Thin32k assertions remain. */
        }
        dependency traceFullHeightSliders from fullHeightSliderPresentation to WstxRequirements::'TC-010-006';
        verification sourceTimeScroll {
            subject operation : PresentStation;
            objective { verify WstxRequirements::'CL-006-03'; verify WstxRequirements::'CL-006-04'; }
            doc /* TC-010-007: implemented executable companion in tests/recording.test.cjs.
                 Setup/actions: Cost2 automated on the Windows development PC with real Chromium/candidate server and independently injected accepted source rows. Start empty; inject a uniquely marked row then successive Detailed0.2s rows and Thin1s rows, at Speed0.5/1/2/8. Inspect actual RGBA before/after each update, through enough source time to move the mark off the bottom. Exercise short/EOS rows, gaps, no input/completion/cancel/disconnect, invalid/stale frames, new replay/profile, resize, DPR1/2,200% zoom and minimum splitter height at360CSSpx, desktop and2048px width.
                 Independent expected oracle: With p=10*v and newest end T, independently calculate each row edges floor((T-b)*p*H/C)..floor((T-a)*p*H/C); a fixed mark advances by2*v CSSpx per Detailed update or10*v per Thin update, independent of N. Minimum speed0.5 gives5CSSpx/s, half Speed1; default2 gives20CSSpx/s. It exits below H and never sticks or repeats. Empty/unobserved pixels are exactly navy with no-measurement readout; explicit gaps grey. Changing height changes capacity C/p, not pixels per source second; changing speed changes displacement without modifying tuples/data/network. Short EOS uses actual duration; no source row means no motion; stale/invalid frames cannot move history. Pointer native/projected intervals, keyboard clamps and5s rulers match the same time mapping. Existing sliders remain visible and keyboard-operable; actual canvas remains full allotted height, spectrum:waterfall1:5 and fixed0..3000Hz. Existing palette/sensitivity, wire/numerical and Thin32kbit/s assertions remain unchanged. */
        }
        dependency traceSourceTimeScroll from sourceTimeScroll to WstxRequirements::'TC-010-007';
    }
    doc /* Implementation freedoms: Rust file layout; existing-library/std storage
         commit primitives preserving the declared commit point; small bounded parser
         mechanics; test-only fault injection; canvas palette colors/drawing mechanisms within the prescribed integer geometry. No implicit changes
         to wire/schema/state/units/bounds/authority/errors/oracles, extra dependencies,
         speculative FFT wrapper, device capabilities or transmit lifecycle. */
}
