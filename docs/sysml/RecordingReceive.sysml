// Canonical recorded receive contract SHA256: 77890d0530bc12f65a79cbae6a9e0b58666098bb22ae2d79113bf978df21dd5b
package WstxRecordingReceive {
    private import ScalarValues::*;
    doc /* Implementation contract from authoritative FSD4.4/6.4/12.6. Independent
         readiness review pending; no features implemented/tests executed. Existing
         usages only, no new deployment/universal job manager/TX authority.
         Shared RustFFT6.4.1 primary API https://docs.rs/rustfft/6.4.1/rustfft/,
         https://docs.rs/rustfft/6.4.1/rustfft/trait.Fft.html and
         https://docs.rs/rustfft/6.4.1/rustfft/struct.FftPlannerScalar.html.
         Independent DFT/math/oracles remain the original Markdown,not library output. */
    enum def ImportState { enum reserved; enum receiving; enum validating; enum committing; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def ReceiveState { enum running; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def DisplayProfile { enum off; enum thin; }
    enum def ReceiveKind { enum spectrum; }
    enum def ErrorCode {
        enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_request; enum unsupported_version;
        enum wrong_profile; enum state_conflict; enum not_found; enum busy;
        enum invalid_state; enum invalid_recording; enum unsupported_audio;
        enum recording_limit; enum storage_unavailable; enum upload_timeout;
        enum cancelled; enum no_recording; enum generation_exhausted;
        enum recording_unavailable; enum unavailable;
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
        attribute kind : ReceiveKind = ReceiveKind::spectrum;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        attribute cancelRequested : Boolean;
        assert constraint progress { processed_frames >= 0 and processed_frames <= 1440000 }
        doc /* Immutable spectrum settings below. One import OR replay,oneworker,no
             pendingjobs;no CPU/file work holding state/profile-settings lock. #7 adds
             approved mode settings with separate decode pacing/history budgets. New
             generation on import/replay,refuse ceiling not wrap. Cancellation invalidates
             publication before ack;terminal progress remains until nextjob. No TX scope. */
    }
    attribute def JobView {
        attribute id : String;
        attribute source_id : String;
        attribute generation : Integer;
        attribute kind : ReceiveKind = ReceiveKind::spectrum;
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
             remain available and no source is fabricated. Restart preserves the committed recording ID/bytes, changes boot ID,
             forgets reservations and marks interrupted replay cancelled. No automatic replay occurs.
             | Route/method | Exact input | Success / transition |
             |---|---|---|
             | POST /recording/imports | `{v:1,profile_id,boot_id,generation}` | 201 `{v:1,id,generation,state:"reserved"}`; reserve one import UUID, increment generation, expire reservation after 30 seconds without PUT; Location identifies import resource. |
             | PUT /recording/imports/{id} | `Content-Type: audio/wav` only; one <=2048-byte raw chunk, exact single `Content-Range: bytes start-end/total`, no content encoding. total is1..3,145,728; start equals received_bytes, end-start+1 equals body size, total cannot change. | reserved -> receiving; intermediate chunks return202 `{v:1,id,state:"receiving",received_bytes}` after append. Final chunk -> validating -> committing -> completed and201 `{v:1,id,state:"completed",recording_id,generation}` after manifest commit. No automatic replay. Inactivity timeout15s, total deadline1800s. At most one chunk request is accepted at a time; concurrent/out-of-order chunks return409 state_conflict. Body cap applies even without/with lying Content-Length. |
             | GET /recording/imports/{id} | No body | 200 `{v:1,id,state,received_bytes,total_bytes,error,recording_id}`; state includes completed/cancelled/failed; recording_id null until commit. Retain only latest terminal import resource until next reservation/restart. |
             | DELETE /recording/imports/{id} | No body | 200 same import representation after cancellation invalidates pre-commit work; reserved can terminate immediately, receiving/validating become cancelling until file worker cleanup finishes, then cancelled. Already completed returns unchanged completed, never deletes committed source; repeating cancelled returns same terminal state. Once committing begins cancellation is refused409 invalid_state; GET reconciles completion/failure. The commit transition and cancellation request serialize so cancellation accepted before it prevents commit. |
             | POST /recording/replay | `{v:1,profile_id,boot_id,generation,recording_id}` | 202 `{v:1,id,generation,state:"running"}`; increment generation/start job at frame0; reject import/replay busy. |
             | DELETE /recording/jobs/{id} | No body | 200 `{v:1,id,generation,state}`; current running -> cancelling and publication invalidation before response; terminal jobs return unchanged terminal state. Worker release bound is separate from HTTP round trip. |*/
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
             acknowledgement; terminal transition follows worker release. Do not reuse a generation
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
        doc /* **Independent display definition.** For 12 kHz input, use 2,048 real samples per
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
             original immutable samples. #6 fixes N=2048; #7 owns its supported transform sizes and
             bounded modem working history. Plan once per needed size/worker, never per display row;
             check lengths before processing so invalid input cannot reach a panic precondition.
             No generic FFT wrapper or additional RealFFT dependency is needed. This is the central
             owned dependency contract; future crate adoption is implementation work, not performed
             by this document. Normative primary API: [RustFFT6.4.1 normalization/output order](https://docs.rs/rustfft/6.4.1/rustfft/),
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
             Browser retains at most 120 rows of 128 values; replacing the source/job clears history. */
    }
    action def TransferDisplay {
        in 'frame' : SpectrumFrame;
        in requestedProfile : DisplayProfile;
        doc /* **Opt-in WebSocket extension.** Keep `wstx.v1`, 1024-byte request/frame/message limits,
             2048-byte write buffer, existing station.get/status/error envelopes, validation order,
             binary1003, heartbeats and liveness unchanged. Add exact three-field requests
             `{v:1,type:"recording.get"|"spectrum.thin"|"spectrum.off",id}`. `recording.get` returns
             `{v:1,type:"recording.state",id,data:{generation,source_id,job_id,state}}` with nullable
             IDs/state; full snapshot stays HTTP. Thin/off acknowledge
             `{v:1,type:"spectrum.subscription",id,data:{profile:"thin"|"off"}}`. Selected-profile
             absence returns recoverable `unavailable` for these commands. Every new connection starts
             off; legacy peers receive only existing status/heartbeat messages. New browser obtains
             status/profile/recording HTTP snapshots before opting into thin and showing current
             recording data; unknown_command from an older server visibly disables recording display.
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

             One replaceable pending display event per peer and <=1 send per second; no replay of old
             frames after reconnect or off. Ready status replies and heartbeats take precedence;
             optional display output is skipped when send readiness/control headroom is unavailable.
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
        doc /* **Integrated UI.** One browser window/page per station. Spectrum and waterfall
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
        transition complete first running if sourceComplete and workerReleased and not cancelAccepted then completed;
        transition fail first running if processingFailed then failed;
    }
    action importRecording : ImportRecording;
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
             No radio/audio device/live station. Definitions are not execution results.
             Original Markdown remains the independent expectation for implementation. */
        verification validRecording {
            subject operation : ImportRecording;
            objective { verify WstxRequirements::'CL-006-01'; verify WstxRequirements::'CL-006-02'; }
            doc /* TC-018-001: setup/input/action: Construct byte-level PCM WAVs with 1, 2048, 4096, 4097 and 1,440,000 frames, endpoint samples -32768,-1,0,1,32767 and legal ancillary/padding chunks. Import, inspect blocks/metadata, replay twice and restart. Use the pinned actual recordings from chapter13 after retaining their license/provenance manifest; the verified22 inputs all fit the selected PCM capability.
                 Independent expected oracle: Hand-authored RIFF byte offsets/counts and exact signed-value/32768 mapping match; concatenated blocks equal input samples, <=4096 per block, contiguous offsets and one EOS; original bytes unchanged. Source UUID survives restart and repeats; jobs/generations differ, recording UTC remains null and no device opens. Analytical spectra repeat within 0.5 dB quantization plus 0.05 dB numerical tolerance. The actual recording proves non-synthetic input; it is not the calibration oracle. */
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
            doc /* TC-018-003: setup/input/action: Two independent authenticated clients race import/replay/cancel using current/stale/wrong boot, profile, generation and token IDs; inject a late worker publication, disconnect/reconnect, restart during replay; run maximum source and four processes. Enumerate every 12.6 endpoint with missing/wrong Origin/cookie, method, media type, body/schema and token errors.
                 Independent expected oracle: Exactly one serialized start wins; errors and snapshots match fixed state-transition table, lost-response recovery never auto-replays. Wrong identities cannot affect selected station. Replay cancel invalidates output before ack and reaches terminal/worker release <=250 ms under stated workload; import cancel prevents commit when accepted before committing, acknowledges locally<=250ms, cleans normally<=1s or becomes failed/storage_unavailable by5s with slot/files quarantined and no false deletion; progress never exceeds frame count. Instrument retained block/worker/slot counts against contract bounds; this is not a total RSS claim. Original station.get/auth/profile regression assertions remain in force. Also corrupt the committed original/metadata/manifest in separate fixtures, restart, open a fresh browser, obtain200 snapshot with source_error and valid identities, then import a valid replacement using those identities: replacement succeeds, clears source_error and replays; replay before replacement returns409 recording_unavailable. */
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
    }
    doc /* Implementation freedoms: Rust file layout; existing-library/std storage
         commit primitives preserving the declared commit point; small bounded parser
         mechanics; test-only fault injection; canvas colors/drawing. No implicit changes
         to wire/schema/state/units/bounds/authority/errors/oracles, extra dependencies,
         speculative FFT wrapper, device capabilities or transmit lifecycle. */
}
