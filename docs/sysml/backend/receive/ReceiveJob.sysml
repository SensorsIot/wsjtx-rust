package WstxRecordingReceive {
    private import ScalarValues::*;
    private import WstxOfflineDecode::Mode;
    private import WstxOfflineDecode::Settings;
    private import WstxOfflineDecode::ResultRecord;
    private import WstxProfileRecordings::StartImportBody;
    private import WstxProfileRecordings::ImportView;
    private import WstxReceiveSpectrum::spectrum;
    private import WstxReceiveSpectrum::DetailedSpectrumFrame;
    private import WstxReceiveSpectrum::SpectrumFrame;
    private import WstxReceiveSpectrum::CalculateSpectrum;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-018';
    private import WstxRequirements::'FR-019';
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'FR-002';
    private import WstxRequirements::'FR-009';
    private import WstxRadioIO::'CL-008-05';
    private import WstxRequirements::'CL-010-05';
    private import WstxRequirements::'CL-010-07';
    private import WstxRequirements::'CL-010-08';
    private import WstxRequirements::AutomationState;
    private import WstxProfileRecordings::'TC-018-001';
    private import WstxProfileRecordings::'TC-018-002';
    private import WstxRequirements::'TC-022-005';
    private import WstxRequirements::'TC-002-001';
    private import WstxRequirements::'TC-009-001';
    private import WstxStationProtocol::'TC-009-005';
    private import WstxRequirements::'FR-003';
    private import WstxStationProtocol::DisplayProfile;
    private import WstxStationProtocol::TransferDisplay;
    doc /* Implementation contract from authoritative contract 4.4/6.4/12.6. Original Thin/recording and Detailed refinement implementations with executable
         verification companions exist;
         actual run/review/acceptance evidence belongs to issue #6. Existing
         usages only, no new deployment/universal job manager/TX authority.
         Shared RustFFT6.4.1 primary API https://docs.rs/rustfft/6.4.1/rustfft/,
         https://docs.rs/rustfft/6.4.1/rustfft/trait.Fft.html and
         https://docs.rs/rustfft/6.4.1/rustfft/struct.FftPlannerScalar.html.
         Independent DFT/math/oracles remain independent case expectations and direct math, not library output. */
    enum def ReceiveState { enum running; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def ReceiveKind { enum spectrum; enum live; }
    enum def ErrorCode {
        enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_request; enum unsupported_version;
        enum wrong_profile; enum state_conflict; enum not_found; enum busy;
        enum invalid_state; enum invalid_recording; enum unsupported_audio;
        enum recording_limit; enum storage_unavailable; enum upload_timeout;
        enum cancelled; enum no_recording; enum generation_exhausted;
        enum recording_unavailable; enum unavailable; enum counter_exhausted;
        enum invalid_samples; enum decode_limit; enum decode_failed;
    }
    attribute def Limits {
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
        attribute finalProcessingMs : Integer = 1000;
        attribute controlBytes : Integer = 1024;
        attribute eventBytes : Integer = 1024;
        attribute thinBytesPerSecond : Integer = 3000;
        attribute offBytesPerSecond : Integer = 1000;
        attribute statusDisplayMs : Integer = 2000;
        attribute pageBytes : Integer = 1536;
        attribute pageRecords : Integer = 1;
        attribute pollMs : Integer = 2000;
        attribute windowFrames : Integer = 360000;
        attribute advanceFrames : Integer = 180000;
    }
    attribute def DisplayLevels {
        attribute blackDbfs : Integer = -85;
        attribute rangeDb : Integer = 50;
        attribute sensitivityDb : Integer = 0;
        attribute speedMultiplier : Real = 1;
        attribute flatten : Boolean = false;
        attribute spectrumLine : Boolean = false;
        assert constraint localSliders { sensitivityDb >= -30 and sensitivityDb <= 30 and speedMultiplier >= 0.5 and speedMultiplier <= 8 }
        assert constraint displayRange { rangeDb >= 10 and rangeDb <= 80 and blackDbfs == -85 }
        doc /* #54 (CL-054-02), as WSJT-X's Wide Graph: a fixed dBFS-to-colour mapping; no level
             follows the signal over time and nothing resets it on a new job, source or profile.
             B is the fixed reference -85 dBFS. Sensitivity g (WSJT-X Zero, -30..+30, default 0)
             moves the scale: effective black E=clamp(B-g,-120,-R). Range R (WSJT-X Gain, a slider
             10..80 dB, default 50) is the span [E,E+R]. Speed sets 10*speedMultiplier CSS px per
             source second (default 1: about two FT8 periods in the default height); fixed source
             intervals move down independent of history length, clip at bottom; unobserved pixels
             dark/no-measurement. Sensitivity, Range, Speed, Flatten and the spectrum line are
             per-browser settings that apply at once and persist in browser storage. Flatten
             (default off, WSJT-X flat4 equivalent) subtracts per row the lower envelope across
             frequency (20th percentile of 32 blocks, linearly interpolated) and adds back its
             median: it evens out the passband shape, never a level change over time; the readout
             keeps the original native levels. Original calibrated levels unchanged.
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
    attribute def ReceiveContext {
        attribute profile_id : String;
        attribute boot_id : String;
        attribute source_id : String[0..1];
        attribute job_id : String;
        attribute generation : Integer;
        assert constraint safeGeneration { generation >= 0 and generation <= (900719925 * 10000000 + 4740991) }
        doc /* Opening live job may lack source only until initial provider epoch ACK.
             Recorded spectrum and acknowledged live jobs require their source UUID.
             This pending context never permits publication. Correlation remains the
             REQUIRED full source/job/generation tuple for every frame/result page. */
    }
    item def ReceiveJob :> WstxArchitecture::ProcessingRequest {
        attribute schema_version : Integer = 1;
        attribute correlation : ReceiveContext;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        attribute cancelRequested : Boolean;
        assert constraint progress { processed_frames >= 0 and ((kind == ReceiveKind::spectrum and processed_frames <= 1440000) or (kind == ReceiveKind::live and processed_frames <= (900719925 * 10000000 + 4740991))) }
        doc /* Shared receive lifecycle: recorded spectrum below and continuous live mode
             through WstxRadioIO/WstxModemDecode. One import OR recorded spectrum OR live receive,
             one worker/no pendingjobs; no CPU/file work holding state/profile lock. New
             generation on import/replay,refuse ceiling not wrap. Cancellation invalidates
             publication before ack;terminal progress remains until nextjob. No TX scope. */
    }
    attribute def JobView {
        attribute id : String;
        attribute source_id : String[0..1];
        attribute generation : Integer;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        doc /* source_id null only for live opening before first ACK; recorded source and all publication tuples remain required UUIDs. */
    }

    attribute def StartReplayBody :> StartImportBody { attribute recording_id : String; }
    action def CancelReceive {
        in jobId : String;
        out 'state' : ReceiveState;
        doc /* DELETE /recording/jobs/{id},nobody;running->cancelling,publication invalid
             before200{v1,id,generation,state};checkpoints<=50ms,terminalcancelled+release
             <=250ms onfourprocessWindowsworkload. TerminalDELETE unchanged,unknown/
             oldboot/foreignjob404,never cancels differentjob. terminalprogressretained. */
    }
    attribute def BrowserDisplayPreference {
        attribute effectiveOrigin : String;
        attribute profileUuid : String;
        attribute savedChoice : DisplayProfile[0..1];
        attribute effectiveChoice : DisplayProfile;
        attribute storageAvailable : Boolean;
        doc /* Browser-owned preference for one effective origin and validated saved-profile UUID.
             The browser storage boundary isolates origins; a versioned UUID key stores only
             off/thin/detail, never credentials, device identifiers, station settings or decoded traffic.
             Boot ID and revision do not alter identity. Environment-only/no-profile use is nonpersistent. */
    }
    action def RestoreDisplayChoice {
        in preference : BrowserDisplayPreference;
        out effectiveChoice : DisplayProfile;
        doc /* Use a valid saved choice if available. Otherwise Detailed on every origin,
             including remote HTTPS, using existing1024 native bins at2.9296875Hz. Invalid/missing values or
             unavailable storage use that normal default without disabling in-memory selection.
             Explicit choices survive reload/browser restart for this origin/profile only. */
    }
    action def SelectDisplayChoice {
        in explicitChoice : DisplayProfile;
        in preference : BrowserDisplayPreference;
        out updatedPreference : BrowserDisplayPreference;
        doc /* An explicit user selection changes effective and saved choice for this viewer only.
             If storage is unavailable, retain effective choice in memory without a persistence claim.
             Subscribe with existing off/thin/detail commands; do not change decoder/radio mode,
             source measurements, station settings or other viewers. Automatic server fallback changes
             effective choice only, never overwrites the explicit saved choice, and retains existing
             single Thin fallback/no retry loop. Detailed keeps fast-link/up-to10KiB/s notice and
             no32kbit/s promise; Thin retains all bandwidth limits. */
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

                          Keep spectrum above the fixed0..3000Hz ruler and waterfall. #54: the spectrum line is shown
             only with the per-browser option Show spectrum line (default off); hidden, the waterfall
             takes its height. Shown, its vertical scale is [E,0] dBFS, so no level clips at the top.
             The default signal height is 330 CSS px (splitter), at most 560. Allocate the remaining plot
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
             A run of Tx rows (#61 CL-061-05) takes one band of 4 CSSpx instead of its source time; every other row keeps p, and the mapping and labels of times beyond the band stay exact: T-t counts without the run's source time, plus the band.
             Profile changes still clear browser history/old-profile frames; existing bounded history,
             source identities and one pending repaint remain unchanged.

             **Display levels and palette.** The display is a local presentation of calibrated
             levels, independent of source samples, FFT/averaging, wire quantization, Thin bandwidth
             and future decoding (#54, CL-054-02). The waterfall corner holds labelled keyboard-operable
             Sensitivity (WSJT-X Zero), Range (WSJT-X Gain) and Speed range sliders, each with an
             adjacent numeric output, repainting on every input event; Settings > General > Display
             holds Flatten and Show spectrum line. DisplayLevels gives the values and the fixed
             mapping: there is no Black level input, no Auto black and no noise estimate, and a new
             source, job or display profile changes no level. Sensitivity and Range change
             waterfall colours only; the legend shows both effective ends in dBFS. Inputs are rounded
             with floor(value+0.5) and clamped; nonfinite values leave settings unchanged. Clipping
             affects presentation only; the native values remain available. Repaint all retained
             rows when presentation controls change; samples/wire data never change or restart.

             For an original quantized level q, t=clamp(((q-120)-E)/R,0,1). Map t to this project's
             own RGB anchors, interpolating each channel linearly between adjacent anchors and
             rounding with floor(channel+0.5): t=0:(0,0,12), .15:(0,0,80), .35:(0,80,220),
             .50:(0,220,240), .65:(30,230,80), .80:(255,235,0), .95:(255,40,0),1:(255,0,0).
             Saturated/above-range signal is exactly RGB(255,0,0), never white. Below-floor/no-signal
             is RGB(0,0,12); gaps are RGB(96,96,96) and appear only for a real gap (#54: rows the station did not send within its retained window, a source or job change, an unknown-loss source epoch of the same receive as one row between the kept rows (CL-061-01); one or two live Thin rows paced out between two sent rows are drawn with the next row, not as a gap; live Thin sends keep a fixed 2 s grid from the previous deadline, restarted at a send more than 1 s late, so sends stay at least 1 s apart). This continuous level-to-color
             mapping does not interpolate spatial bins/rows: each rendered cell has one exact RGB
             color, fully opaque. Spectrum trace is RGB(180,245,220). Ruler/grid/text overlays stay
             outside waterfall measured cell interiors. A narrow labeled color legend uses these exact same anchors, positions and linear RGB
             channel interpolation/rounding, ending in the same saturated red; it displays the
             effective waterfall range. Rainbow hue progression does not assert monotonic luminance. Flatten is the optional per-row passband equalisation of DisplayLevels; no palette editor, gain normalization over time or new framework.

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
        transition fail first running if processingFailed and workerReleased and not cancelAccepted then failed;
        doc /* contract 4.4: accepted cancellation already changes running to cancelling;
             otherwise processing failure prevents completion even with simultaneous EOS.
             While a failed worker is held, state remains nonterminal. Guards are disjoint;
             every terminal receive transition requires worker release. */
    }
    enum def ImportBrowserEvent {
        enum start; enum accepted; enum reservation_rejected; enum abort; enum response_lost;
        enum reconciled; enum terminal;
    }
    state def BrowserImportLifecycle {
        attribute acceptedEvent : ImportBrowserEvent;
        entry; then idle;
        state idle; state pending; state pendingCancel; state cleanupRequested; state uploading; state reconciling;
        transition begin first idle if acceptedEvent == ImportBrowserEvent::start then pending;
        transition reserved first pending if acceptedEvent == ImportBrowserEvent::accepted then uploading;
        transition cancelPending first pending if acceptedEvent == ImportBrowserEvent::abort then pendingCancel;
        transition cancelAcceptedReservation first pendingCancel if acceptedEvent == ImportBrowserEvent::accepted then cleanupRequested;
        transition cancelledReservationRejected first pendingCancel if acceptedEvent == ImportBrowserEvent::reservation_rejected then idle;
        transition cancelledReservationUnknown first pendingCancel if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition cleanupObserved first cleanupRequested if acceptedEvent == ImportBrowserEvent::terminal then reconciling;
        transition cleanupUnknown first cleanupRequested if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition reservationRejected first pending if acceptedEvent == ImportBrowserEvent::reservation_rejected then idle;
        transition reservationUnknown first pending if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition abortUpload first uploading if acceptedEvent == ImportBrowserEvent::abort then reconciling;
        transition uploadUnknown first uploading if acceptedEvent == ImportBrowserEvent::response_lost then reconciling;
        transition observed first reconciling if acceptedEvent == ImportBrowserEvent::reconciled then idle;
        transition finished first uploading if acceptedEvent == ImportBrowserEvent::terminal then idle;
        doc /* contract 12.6: pendingCancel retains local cancellation intent while awaiting
             the reservation response. It never starts PUT. An accepted response gives
             the exact import ID: cleanupRequested sends DELETE for that returned ID,
             with zero PUT requests, then reconciles GET. Rejected responses end pending
             cancellation without PUT/DELETE. Lost reservation/cleanup responses enter
             reconciling; no cancellation success or cleanup is inferred. An unknown
             reservation ID is observed through GET, never guessed or automatically retried.
             UI abort during upload stops PUT and sends DELETE independently, then uses GET
             to reconcile uncertain outcome. A lost reservation response is reconciled from
             GET /recording, which exposes any accepted import ID. Never retry a mutation,
             resume upload, replay, or infer rollback from a missing response. reconciling
             persists on unavailable transport; no fabricated successful snapshot.
             A known reservation rejection ends local pending, visibly reports the returned
             error and starts no PUT/DELETE/retry; authoritative busy/degraded/identity state
             remains unchanged until an independently validated snapshot changes it.
             idle means no local upload, not permission to ignore authoritative busy state. */
    }
    action cancelReceive : CancelReceive;
    action present : PresentStation;
    satisfy WstxRecordingReceive::'CL-006-04' by cancelReceive;
    dependency cancellationOwner from cancelReceive to WstxArchitecture::physicalStation::backend::stations::receive;
    dependency browserOwner from present to WstxArchitecture::physicalStation::frontend::browsers;
    item def DecodeJob :> WstxRecordingReceive::ReceiveJob {
        attribute :>> kind = WstxRecordingReceive::ReceiveKind::live;
        attribute settings : Settings;
        attribute available_count : Integer;
        attribute search_limited : Boolean;
        assert constraint boundedProgress {
            processed_frames >= 0 and processed_frames <= (900719925 * 10000000 + 4740991) and
            available_count >= 0 and available_count <= 2048
        }
        doc /* Existing station receive-job authority, kind=live with immutable mode.
             One import OR recorded spectrum OR continuous receive; no queue.
             Source-relative FT8/FT4 windows, reliable live ring and epoch rules12.8.
             Numerical recorded fixtures have no production receive operation. */
    }
    action def AdmitDecode {
        in source : WstxAudio::SourceDescriptor[0..1];
        in settings : Settings;
        out job : DecodeJob;
        doc /* Production12.8 live start only; selected-profile auth/Origin/schema,
             boot/generation/profile-revision and shared receive admission precede capture.
             Mode immutable. Source absent during opening before first provider ACK;
             no publication until acknowledged full tuple. Initialstart freshjob/gen,
             firstsourceACK samejob/gen;
             subsequent unknownepoch freshsource/job/gen beforeproviderACK and ring reset.
             Recorded waveforms are internal numerical/integration fixtures, no file API. */
    }
    action admitDecode : AdmitDecode;
    satisfy WstxLiveReceive::'CL-007-01' by admitDecode;
    dependency admissionOwner from admitDecode to WstxArchitecture::physicalStation::backend::stations::receive;

    package IndependentVerification {
        doc /* All cases cost 2 - isolated automated tests on Windows development PC.
             Actual candidate server/browser, disposable profiles, synthetic byte fixtures,
             independent direct DFT and pinned actual recordings with chapter13 provenance.
             No radio/audio device/live station. Definitions and candidate source presence are not acceptance results.
             Independent case expectations are retained in WstxRequirements and this package; production/library output is not their oracle. */
        verification receiveIsolation {
            subject operation : CancelReceive;
            objective { verify WstxRecordingReceive::'CL-006-02'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-018-003: setup/input/action: Two independent authenticated clients race import/replay/cancel using current/stale/wrong boot, profile, generation and token IDs; inject a late worker publication, disconnect/reconnect, restart during replay; separately restart during an uncommitted reserved/receiving import, then query the fresh snapshot and old import/job IDs before starting new work; run maximum source and four processes. In a separate current running job with no cancellation, hold worker release, report processing failure, then source completion, inspect state before release and finally release the worker. Enumerate every 12.6 endpoint with missing/wrong Origin/cookie, method, media type, body/schema and token errors. In a real browser, reject the reservation POST with known409 busy and separately503 storage_unavailable; observe local pending/error display and all subsequent requests.
                 Independent expected oracle: Exactly one serialized start wins. A known rejected reservation ends local pending and visibly reports its exact error, sends no PUT/DELETE/retried POST and preserves authoritative busy/degraded/identity state; it cannot fabricate an accepted import or successful snapshot. Restart preserves the last committed source UUID/bytes but changes boot, resets generation0 and returns import:null/job:null; prior import resource and job DELETE return404, with no cancelled-job record or automatic replay. Errors and snapshots match fixed state-transition table, lost-response recovery never auto-replays. Wrong identities cannot affect selected station. Replay cancel invalidates output before ack and reaches terminal/worker release <=250 ms under stated workload; import cancel prevents commit when accepted before committing, acknowledges locally<=250ms, cleans normally<=1s or becomes failed/storage_unavailable by5s with slot/files quarantined and no false deletion; progress never exceeds frame count. The held-worker failure vector stays running/nonterminal before release, becomes failed on release and is never completed, including simultaneous source completion. Instrument retained block/worker/slot counts against contract bounds; this is not a total RSS claim. Original station.get/auth/profile regression assertions remain in force. Also corrupt the committed original/metadata/manifest in separate fixtures, restart, open a fresh browser, obtain200 snapshot with source_error and valid identities, then import a valid replacement using those identities: replacement succeeds, clears source_error and replays; replay before replacement returns409 recording_unavailable. */
        }
        dependency tracereceiveIsolation from receiveIsolation to WstxRecordingReceive::'TC-018-003';
        verification calibratedDisplay {
            subject operation : CalculateSpectrum;
            objective { verify WstxRecordingReceive::'CL-006-03'; }
            doc /* TC-010-001: setup/input/action: Independently synthesize silence, DC, coherent tones at 750/1500/2250 Hz at amplitudes 0.5/0.25, two simultaneous tones, a noncoherent tone, clipped input and a burst with specified source-frame start/end. Compute selected windows using a direct DFT test oracle; replay through real browser.
                 Independent expected oracle: Direct DFT uses published formula without candidate FFT/provider helpers; peak group equals floor(k/4) for coherent bins and row interval follows window-start rule. Half-amplitude change is -6.0206 dB within 0.05 dB prequantization; quantized levels add <=0.5 dB. Silence equals floor; DC uses one-sided exception. Require normal and portable scalar FFT paths against the same direct DFT oracle, then compare full selected rows, axes/legend/row gaps in DOM/canvas sampling and source metadata, not screenshot resemblance alone. */
        }
        dependency tracecalibratedDisplay from calibratedDisplay to WstxRecordingReceive::'TC-010-001';
        verification boundedThinLink {
            subject operation : TransferDisplay;
            objective { verify WstxRecordingReceive::'CL-006-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-010-002: defined in WstxRecordingReceive::'TC-010-002'. */
        }
        dependency traceboundedThinLink from boundedThinLink to WstxRecordingReceive::'TC-010-002';
        verification integratedPanes {
            subject operation : PresentStation;
            objective { verify WstxRecordingReceive::'CL-006-03'; }
            doc /* TC-010-003: setup/input/action: Real browser at 1100x850 and 360x640: import actual recording, verify one station page, drag divider beyond both extremes, use keyboard/touch/zoom and resize during replay. Repeat four independent station windows.
                 Independent expected oracle: Measured pane bounds meet 160/200 px minima, separator is 12 px and accessible, keyboard steps16px/Home/End clamp, small-height page scrolls, no horizontal page overflow, controls and axes remain reachable. Pointer/keyboard actions change only that station's pane, no second waterfall window appears and data/source identity survives resize. Browser assertions plus desktop/narrow screenshots verify actual layout. */
        }
        dependency traceintegratedPanes from integratedPanes to WstxRecordingReceive::'TC-010-003';
        verification nativeBinDetail {
            subject operation : CalculateSpectrum;
            objective { verify WstxRecordingReceive::'CL-006-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-010-004: Executable companions: server/src/recording_tests.rs, server/src/protocol_tests.rs and tests/recording.test.cjs; cost2 automated Windows offline.
                 Setup/actions: Cost2, automated Windows Rust numerical tests and real browser/server fixtures. Synthesize independent PCM16 vectors: silence/DC, single tones at native k256 and k257 separately and summed with fixed phases/amplitudes; simultaneous750 and756.25 Hz tones; amplitude0.5/0.25 and bursts at source frames1920/2400/2880 and sources of1/2399/2400/2401/2879/2880/2881 frames with short/EOS windows. Compare N4096 normal/scalar FFT bins and complete selected power-averaged rows against a test-only f64 direct DFT of the hand-specified periodic Hann formula, without candidate FFT/window/quantizer helpers. Replay one source with simultaneous Thin and Detailed peers, then race cancellation/replacement.
                 Independent expected oracle: Native k256=750Hz and k257=752.9296875Hz remain separate values; Hann leakage/interference is compared to the independent DFT, not an assertion that adjacent equal tones must form two local maxima. 750/756.25Hz signal retains independently predicted bin peaks/valley; no four-bin pooling or frequency resampling. Prequantized error <=0.05dB on independently specified bins above -80dBFS and absolute amplitude error<=2e-6 elsewhere; quantized values differ by <=1 level from independently rounded DFT, exact silence0. One coherent half-amplitude tone gives -6.0206dBFS before PCM error. Row assignment uses global hop480: five starts/full2400-frame row, one to five at EOS, including start2400 in source_frames2401. Independent mean-square amplitude then10log10 differs from Thin maximum and from averaging dB; zero Hann endpoint yields legitimate final silence for2401. Intervals are2400 frames, shortened EOS, sequence<=599. One source/worker, the latest Thin frame and the retained Detailed rows (#54, at most 25), declared workspace/history limits and cancellation release<=250ms remain; stale publications cannot overwrite either profile. Thin numerical expectations from TC-010-001 remain unchanged. */
        }
        dependency tracenativeBinDetail from nativeBinDetail to WstxRecordingReceive::'TC-010-004';
        verification crispDetailTransport {
            subject operation : PresentStation;
            objective { verify WstxRecordingReceive::'CL-006-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-010-005: Executable companions: server/src/recording_tests.rs, server/src/protocol_tests.rs and tests/recording.test.cjs; cost2 automated Windows offline.
                 Setup/actions: Cost2, automated Windows real browser/candidate server plus deterministic injected wire fixtures. Exercise cleartext loopback and HTTPS defaults; explicit three-profile changes, old Thin-only/older server, simultaneous Thin/Detailed peers, malformed base64 alphabet/padding/pad bits/decoded lengths/values, unknown/missing keys, safe-integer/interval edges, wrong tuples/old sockets and skipped sequences. Use alternating known quantized levels in adjacent native bins/rows and read actual getImageData at1100x850 and360x640, DPR1/2,200% zoom, splitter extremes, resize and repaint; exercise the fixed level mapping (#54 DisplayLevels: reference, Zero/Gain sliders, no automatic level) and range/legend/readout consistency. Retain actual busy FT8 recording desktop/mobile screenshots and compare their trace/noise contrast, orientation and rulers qualitatively with WSJT-X/FlexRadio reference images. Stall Detailed output with a controlled sink returning Pending, then issue status/control and cancel/off.
                 Independent expected oracle: Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. At most 1 Hz Thin and, for Detailed, 5 rows/s steady with catch-up of retained rows at most 5.9 rows/s (#54 TransferDisplay); no second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. The 32 kbit/s Thin/Off budget is judged from the link byte log (#80, TC-080-001). Every origin defaults Detailed; explicit saved Thin/Off is honored and fallback attempts Thin once and labels unavailability. Explicit Detailed/Thin/Off survives reload and reopened browser context; origin/port/profile UUIDs isolate choices while boot/revision changes preserve them. Invalid/denied storage uses defaults without page errors or disabling memory selection. Only versioned UUID keys and enumerated values are stored, no secrets/traffic. Automatic fallback preserves saved Detailed; explicit Thin replaces it. Existing wire tests remain unchanged, with no synthesized decoded records. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness. */
        }
        dependency tracecrispDetailTransport from crispDetailTransport to WstxRecordingReceive::'TC-010-005';
        verification fullHeightSliderPresentation {
            subject operation : PresentStation;
            objective { verify WstxRecordingReceive::'CL-006-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-010-006: implemented executable companion in tests/recording.test.cjs.
                 Setup/actions: Cost2 automated Windows real browser/candidate fixtures. Inject independently known native rows of2,75,600 Detailed or120 Thin values with contrasting bins/rows and gaps; inspect actual RGBA/backing and CSS box dimensions at desktop1100x850/mobile360x640, DPR1/2,200% zoom and splitter bounds. Exercise Sensitivity-30/0/+30 and Speed1/2/8 via input, keyboard and numeric outputs, Range 10/50/80 (#54), new jobs/profiles and resize. Replay actual busy FT8 with a red saturated carrier, capture desktop/mobile screenshots and move both live sliders.
                 Independent expected oracle: Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With the fixed reference B=-85 and R=50 (#54), g=+10 yields E=-95 and g=-30 yields E=-55, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. No setting follows the signal or resets on a new job or profile; Sensitivity, Range and Speed persist per browser. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security assertions remain. */
        }
        dependency traceFullHeightSliders from fullHeightSliderPresentation to WstxRecordingReceive::'TC-010-006';
        verification sourceTimeScroll {
            subject operation : PresentStation;
            objective { verify WstxRecordingReceive::'CL-006-03'; verify WstxRecordingReceive::'CL-006-04'; }
            doc /* TC-010-007: implemented executable companion in tests/recording.test.cjs.
                 Setup/actions: Cost2 automated on the Windows development PC with real Chromium/candidate server and independently injected accepted source rows. Start empty; inject a uniquely marked row then successive Detailed0.2s rows and Thin1s rows, at Speed0.5/1/2/8. Inspect actual RGBA before/after each update, through enough source time to move the mark off the bottom. Exercise short/EOS rows, gaps, no input/completion/cancel/disconnect, invalid/stale frames, new replay/profile, resize, DPR1/2,200% zoom and minimum splitter height at360CSSpx, desktop and2048px width.
                 Independent expected oracle: With p=10*v and newest end T, independently calculate each row edges floor((T-b)*p*H/C)..floor((T-a)*p*H/C); a fixed mark advances by2*v CSSpx per Detailed update or10*v per Thin update, independent of N. Minimum speed0.5 gives5CSSpx/s, half Speed1; default2 gives20CSSpx/s. It exits below H and never sticks or repeats. Empty/unobserved pixels are exactly navy with no-measurement readout; explicit gaps grey. Changing height changes capacity C/p, not pixels per source second; changing speed changes displacement without modifying tuples/data/network. Short EOS uses actual duration; no source row means no motion; stale/invalid frames cannot move history. Pointer native/projected intervals, keyboard clamps and5s rulers match the same time mapping. Existing sliders remain visible and keyboard-operable; actual canvas remains full allotted height, spectrum:waterfall1:5 and fixed0..3000Hz. Existing palette/sensitivity and wire/numerical assertions remain unchanged. */
        }
        dependency traceSourceTimeScroll from sourceTimeScroll to WstxRecordingReceive::'TC-010-007';
    }
    doc /* Implementation freedoms: Rust file layout; existing-library/std storage
         commit primitives preserving the declared commit point; small bounded parser
         mechanics; test-only fault injection; canvas drawing mechanisms preserving the exact
         authoritative RGB palette and prescribed integer geometry. No implicit changes
         to wire/schema/state/units/bounds/authority/errors/oracles, extra dependencies,
         speculative FFT wrapper, device capabilities or transmit lifecycle. */
    doc /* contract 4.7.5/12.8.1 coordinated operating selection is modeled by
         WstxOperatingReceive. This companion retains the unchanged legacy strict
         receive/radio/result shapes and owner/cancellation/source contracts.
         New selection uses the same authority, explicit actual release before
         setters/new capture and a fresh context, not a second pipeline or actor. */

    doc /* Issue22 target health contract CL-022-05: browser/session authorization,
         CAT connection/readback and audio/decoder are separate lifecycles. HTTP401
         invalidates session readiness and affected current data within2seconds even
         if the old WS is open; retained-key proof can restore authorization without
         replaying mutations. Actual CAT identity/query provenance alone confirms radio
         frequency. Waiting/retry/quarantine marks retained radio facts unconfirmed;
         source/job/generation fences continue to govern latest decoded rows. Automatic
         CAT recovery never starts audio/decoder, clears unknown-operation barriers,
         replays user commands or keys PTT. Existing shared issue10 continuity helpers
         are reused. Authentication/challenge/recovery/status traffic is not part of a
         32 kbit/s link test; its bytes appear in the link byte log (#80). TC-022-008/009/010 own the
         independent target regression/native/live evidence. Actual dated freeze cause
         remains unproved until reproduced; this contract is not a diagnosis. */
    enum def ReceiveMode { enum spectrum; enum ft4; enum ft8; }
    requirement 'CL-006-02' {
        doc /* Profile-owned import/replay/cancellation have explicit pending, terminal and recoverable error states; replacement never destroys the previous committed source before commit. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_02_to_FR_018 from 'CL-006-02' to 'FR-018';
    dependency CL_006_02_to_FR_019 from 'CL-006-02' to 'FR-019';
    requirement 'CL-006-03' {
        doc /* Show measured spectrum and source-time waterfall together above station controls in one station page; use the defined axes/math, accessible divider and bounded selectable Detailed/Thin/Off display. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_03_to_FR_010 from 'CL-006-03' to 'FR-010';
    dependency CL_006_03_to_FR_019 from 'CL-006-03' to 'FR-019';
    dependency CL_006_03_to_FR_021 from 'CL-006-03' to 'FR-021';
    requirement 'CL-006-04' {
        doc /* Bound import, sample, worker and visualization resources; refuse excess work explicitly, discard obsolete display work, preserve status service and invalidate late receive output on cancellation/replacement. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/recording.rs; server/src/recording_http.rs; server/src/spectrum.rs; client/recording.js";
    }
    dependency CL_006_04_to_FR_021 from 'CL-006-04' to 'FR-021';
    requirement 'CL-008-03' {
        doc /* Publish independently truthful audio/control states, bounded live results and explicit loss/recovery while preserving worker, cancellation and thin-link bounds. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_03_to_FR_002 from 'CL-008-03' to 'FR-002';
    dependency CL_008_03_to_FR_009 from 'CL-008-03' to 'FR-009';
    dependency CL_008_03_to_FR_019 from 'CL-008-03' to 'FR-019';
    dependency CL_008_03_to_FR_021 from 'CL-008-03' to 'FR-021';
    verification 'TC-009-004' {
        doc /* TC-009-004 — Independent failure and shared worker
             CL-008-03, CL-008-05, CL-010-05, CL-010-07, CL-010-08
             Lose either interface, overrun/stop/reopen capture, stall CAT and combine native48k conversion, display and bounded decoder quanta for four profiles; seed live result counters2047/2048/2049, eviction/cursor and safe-integer boundaries; simulate later TX/halt ownership. Hold and release result-page/snapshot responses across a confirmed cancellation and unknown Start outcome; inject a current live frame while the recorded-input job is null.
             Independent availability, no false ready state, no cross-profile samples/results, conversion service<=50ms quanta and native-to-canonical software backlog<=200ms under the declared workload, <=250ms normal cancel, <=2s status (no 32 kbit/s link scenario, #80); failed close retains ownership. No real RF transmission. Delayed pages preserve newer confirmed lifecycle/error state and do not advance cursors; pre-mutation reads cannot clear the unknown-outcome control barrier, while a later explicit reconciliation can. Live progress updates only its matching live owner, with no exception or false disconnection when the recorded-input job is absent.
             2 — Isolated automated tests; Windows PC, actual services/browser/link model, independently scripted device/control and decoder-step fixtures. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-03';
            verify 'CL-008-05';
            verify 'CL-010-05';
            verify 'CL-010-07';
            verify 'CL-010-08';
        }
        attribute executable : String = "tests/receive-integration.test.cjs; tests/ui-operating.test.cjs; server/tests/audio_receive.rs; server/tests/radio_control.rs; server/tests/source_contract.rs; server/src/receive_http_tests.rs; server/src/recording_tests.rs; server/tests/audio_contract.rs";
    }
    verification 'TC-018-003' {
        doc /* TC-018-003
             CL-006-02, CL-006-04
             Two independent authenticated clients race import/replay/cancel using current/stale/wrong boot, profile, generation and token IDs; inject a late worker publication, disconnect/reconnect, restart during replay; separately restart during an uncommitted reserved/receiving import, then query the fresh snapshot and old import/job IDs before starting new work; run maximum source and four processes. In a separate current running job with no cancellation, hold worker release, report processing failure, then source completion, inspect state before release and finally release the worker. Enumerate every 12.6 endpoint with missing/wrong Origin/cookie, method, media type, body/schema and token errors. In a real browser, reject the reservation POST with known409 busy and separately503 storage_unavailable; observe local pending/error display and all subsequent requests.
             Exactly one serialized start wins. A known rejected reservation ends local pending and visibly reports its exact error, sends no PUT/DELETE/retried POST and preserves authoritative busy/degraded/identity state; it cannot fabricate an accepted import or successful snapshot. Restart preserves the last committed source UUID/bytes but changes boot, resets generation0 and returns import:null/job:null; prior import resource and job DELETE return404, with no cancelled-job record or automatic replay. Errors and snapshots match fixed state-transition table, lost-response recovery never auto-replays. Wrong identities cannot affect selected station. Replay cancel invalidates output before ack and reaches terminal/worker release <=250 ms under stated workload; import cancel prevents commit when accepted before committing, acknowledges locally<=250ms, cleans normally<=1s or becomes failed/storage_unavailable by5s with slot/files quarantined and no false deletion; progress never exceeds frame count. The held-worker failure vector stays running/nonterminal before release, becomes failed on release and is never completed, including simultaneous source completion. Instrument retained block/worker/slot counts against contract bounds; this is not a total RSS claim. Original station.get/auth/profile regression assertions remain in force. Also corrupt the committed original/metadata/manifest in separate fixtures, restart, open a fresh browser, obtain200 snapshot with source_error and valid identities, then import a valid replacement using those identities: replacement succeeds, clears source_error and replays; replay before replacement returns409 recording_unavailable. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-02';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-010-001' {
        doc /* TC-010-001
             CL-006-03
             Independently synthesize silence, DC, coherent tones at 750/1500/2250 Hz at amplitudes 0.5/0.25, two simultaneous tones, a noncoherent tone, clipped input and a burst with specified source-frame start/end. Compute selected windows using a direct DFT test oracle; replay through real browser.
             Direct DFT uses published formula without candidate FFT/provider helpers; peak group equals floor(k/4) for coherent bins and row interval follows window-start rule. Half-amplitude change is -6.0206 dB within 0.05 dB prequantization; quantized levels add <=0.5 dB. Silence equals floor; DC uses one-sided exception. Require normal and portable scalar FFT paths against the same direct DFT oracle, then compare full selected rows, axes/legend/row gaps in DOM/canvas sampling and source metadata, not screenshot resemblance alone. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/recording_tests.rs";
    }
    verification 'TC-010-002' {
        doc /* TC-010-002
             CL-006-03, CL-006-04
             #80 (operator 2026-11-09): the two-browser 32 kbit/s replay, Off and upload measurements, the stalled thin subscriber and the paced optional-output case are retired; the link budget is judged from the link byte log (CL-003-05, TC-080-001) and dead peer removal is TC-021-008. Actual server and browser on an unshaped local connection: import and replay a recording, an independent peer subscribes Off and another stays unsubscribed, another actor replays and imports; a read failing after an announcement; injected Thin frames with gaps, obsolete identities and more than 120 rows.
             The browser sends no recording.get and no timer GET /recording; a subscribed peer (Off included) receives one recording.state after subscribing and then only on a change, within 2 s, with received_bytes alone at most once per 5 s, shown without a read; a peer without a subscription receives none. A failed read after an announcement closes the socket and the reconnect reads again. The browser keeps at most 120 rows, shows missing rows as gaps and ignores obsolete identities. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-010-003' {
        doc /* TC-010-003
             CL-006-03
             Real browser at 1100x850 and 360x640: import actual recording, verify one station page, drag divider beyond both extremes, use keyboard/touch/zoom and resize during replay. Repeat four independent station windows.
             Measured pane bounds meet 160/200 px minima, separator is 12 px and accessible, keyboard steps16px/Home/End clamp, small-height page scrolls, no horizontal page overflow, controls and axes remain reachable. Pointer/keyboard actions change only that station's pane, no second waterfall window appears and data/source identity survives resize. Browser assertions plus desktop/narrow screenshots verify actual layout. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-03';
        }
        attribute executable : String = "tests/recording.test.cjs";
    }
    verification 'TC-010-004' {
        doc /* TC-010-004
             CL-006-03, CL-006-04
             Cost2, automated Windows Rust numerical tests and real browser/server fixtures. Synthesize independent PCM16 vectors: silence/DC, single tones at native k256 and k257 separately and summed with fixed phases/amplitudes; simultaneous750 and756.25 Hz tones; amplitude0.5/0.25 and bursts at source frames1920/2400/2880 and sources of1/2399/2400/2401/2879/2880/2881 frames with short/EOS windows. Compare N4096 normal/scalar FFT bins and complete selected power-averaged rows against a test-only f64 direct DFT of the hand-specified periodic Hann formula, without candidate FFT/window/quantizer helpers. Replay one source with simultaneous Thin and Detailed peers, then race cancellation/replacement.
             Native k256=750Hz and k257=752.9296875Hz remain separate values; Hann leakage/interference is compared to the independent DFT, not an assertion that adjacent equal tones must form two local maxima. 750/756.25Hz signal retains independently predicted bin peaks/valley; no four-bin pooling or frequency resampling. Prequantized error <=0.05dB on independently specified bins above -80dBFS and absolute amplitude error<=2e-6 elsewhere; quantized values differ by <=1 level from independently rounded DFT, exact silence0. One coherent half-amplitude tone gives -6.0206dBFS before PCM error. Row assignment uses global hop480: five starts/full2400-frame row, one to five at EOS, including start2400 in source_frames2401. Independent mean-square amplitude then10log10 differs from Thin maximum and from averaging dB; zero Hann endpoint yields legitimate final silence for2401. Intervals are2400 frames, shortened EOS, sequence<=599. One source/worker, the latest Thin frame and the retained Detailed rows (#54, at most 25), declared workspace/history limits and cancellation release<=250ms remain; stale publications cannot overwrite either profile. Thin numerical expectations from TC-010-001 remain unchanged. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "server/src/recording_tests.rs";
    }
    verification 'TC-010-005' {
        doc /* TC-010-005
             CL-006-03, CL-006-04
             Cost2, automated Windows real browser/candidate server plus deterministic injected wire fixtures. Exercise cleartext loopback and HTTPS defaults; explicit three-profile changes, old Thin-only/older server, simultaneous Thin/Detailed peers, malformed base64 alphabet/padding/pad bits/decoded lengths/values, unknown/missing keys, safe-integer/interval edges, wrong tuples/old sockets and skipped sequences. Use alternating known quantized levels in adjacent native bins/rows and read actual getImageData at1100x850 and360x640, DPR1/2,200% zoom, splitter extremes, resize and repaint; exercise the fixed level mapping (#54 DisplayLevels: reference, Zero/Gain sliders, no automatic level) and range/legend/readout consistency. Retain actual busy FT8 recording desktop/mobile screenshots and compare their trace/noise contrast, orientation and rulers qualitatively with WSJT-X/FlexRadio reference images. Stall Detailed output with a controlled sink returning Pending, then issue status/control and cancel/off.
             Detail events have exact schema,1024 decoded bytes, canonical1368-char base64 and<=2048 UTF-8 bytes; exactly-at-limit values accepted and malformed/obsolete input leaves canvas/history unchanged. At most 1 Hz Thin and, for Detailed, 5 rows/s steady with catch-up of retained rows at most 5.9 rows/s (#54 TransferDisplay); no second worker. Thin/control input1024 and binary1003 guards preserved. Optional write test independently requires readiness/control priority,4096 cap,1024+28 control reserve; Detailed fast-link status responses display<=2s on unshaped localhost with two peers. The 32 kbit/s Thin/Off budget is judged from the link byte log (#80, TC-080-001). Every origin defaults Detailed; explicit saved Thin/Off is honored and fallback attempts Thin once and labels unavailability. Pixel oracle computes integer edges/fixed source-time cell edges from contract, samples interiors and both sides of boundaries for exact palette colors/uniform cells, using independently calculated RGB interpolation/rounding from the stated anchors, with grey gaps and dark unobserved areas on a full-height canvas; no blended spatial colors. New rows enter at top; Auto ignores median0 then locks once at median-3dB, manual Black/Range disables it, job/profile reset restores30dB/Auto and original calibrated data remains invariant. Frequency500/100Hz ticks and visible source-time5s ruler agree with pixel/readout positions and clipping. Fixed0..3000Hz axis endpoints/ticks through resize/DPR/zoom, no horizontal frequency scroll, unmodified native1024-value buffer, peak-preserving max projection with every bin contributing at widths below1024, native/projected readout centers/ranges/levels/intervals, keyboard selection, recent-row orientation,600-row cap and no page overflow hold through geometry changes. Thin uses the same integer geometry with128 bins; original numerical/wire values stay unchanged. A narrow strong tone at every native-bin position contributes to its assigned column and never disappears when W<B. Screenshots establish actual layout and independently synthesized data establishes numerical correctness.  Preference persistence: with disposable browser storage and actual server/Chromium, verify unchanged defaults without a valid choice; explicit Detailed/Thin/Off survives reload and reopened browser context; origins/ports and profile UUIDs are isolated while boot/revision changes preserve choice. Invalid value or denied storage uses normal defaults without page error and leaves in-memory selection usable. Inspect only versioned UUID keys and enumerated values, with no secrets. Unknown-command runtime Thin fallback preserves stored Detailed; subsequent explicit Thin replaces it. Existing subscription commands, no retry loop and Detailed bounds remain unchanged; no synthetic decoded records are used. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs; tests/ui-operating.test.cjs; server/src/protocol_tests.rs";
    }
    verification 'TC-010-006' {
        doc /* TC-010-006
             CL-006-03, CL-006-04
             Cost2 automated Windows real browser/candidate fixtures. Inject independently known native rows of2,75,600 Detailed or120 Thin values with contrasting bins/rows and gaps; inspect actual RGBA/backing and CSS box dimensions at desktop1100x850/mobile360x640, DPR1/2,200% zoom and splitter bounds. Exercise Sensitivity-30/0/+30 and Speed1/2/8 via input, keyboard and numeric outputs, Range 10/50/80 (#54), new jobs/profiles and resize. Replay actual busy FT8 with a red saturated carrier, capture desktop/mobile screenshots and move both live sliders.
             Independent oracle: palette endpoint/saturated cells are exactly[255,0,0,255], floor/no-signal[0,0,12,255], no white signal cells; legend uses identical RGB anchors/endpoints. With the fixed reference B=-85 and R=50 (#54), g=+10 yields E=-95 and g=-30 yields E=-55, clamped[-120,-R]; original row arrays, source/job/generation and curve base scale stay unchanged. No setting follows the signal or resets on a new job or profile; Sensitivity, Range and Speed persist per browser. Fixed source-time scrolling, independent pixel movement, clipping, gap and unobserved-region oracles are specified in TC-010-007. Native/projected readouts and rulers agree with that mapping. Spectrum/waterfall CSS heights follow1:5 within2CSSpx rounding, actual bitmap sizes equal rounded CSS boxes times DPR, neither geometry nor intrinsic height drifts over repeated paints. No horizontal overflow/changed0..3000Hz span, interpolation, fake history or network/source-rate change. Real FT8 screenshots show a full-height waterfall canvas with unobserved regions dark, dark floor, red strongest traces and visible working live sliders; original numeric/wire/security assertions remain. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs";
    }
    verification 'TC-010-007' {
        doc /* TC-010-007
             CL-006-03, CL-006-04
             Cost2 automated on the Windows development PC with real Chromium/candidate server and independently injected accepted source rows. Start empty; inject a uniquely marked row then successive Detailed0.2s rows and Thin1s rows, at Speed0.5/1/2/8. Inspect actual RGBA before/after each update, through enough source time to move the mark off the bottom. Exercise short/EOS rows, gaps, no input/completion/cancel/disconnect, invalid/stale frames, new replay/profile, resize, DPR1/2,200% zoom and minimum splitter height at360CSSpx, desktop and2048px width.
             With p=10*v and newest end T, independently calculate each row edges floor((T-b)*p*H/C)..floor((T-a)*p*H/C); a fixed mark advances by2*v CSSpx per Detailed update or10*v per Thin update, independent of N. Minimum speed0.5 gives5CSSpx/s, half Speed1; default2 gives20CSSpx/s. It exits below H and never sticks or repeats. Empty/unobserved pixels are exactly navy with no-measurement readout; explicit gaps grey. Changing height changes capacity C/p, not pixels per source second; changing speed changes displacement without modifying tuples/data/network. Short EOS uses actual duration; no source row means no motion; stale/invalid frames cannot move history. Pointer native/projected intervals, keyboard clamps and5s rulers match the same time mapping. Existing sliders remain visible and keyboard-operable; actual canvas remains full allotted height, spectrum:waterfall1:5 and fixed0..3000Hz. Existing palette/sensitivity and wire/numerical assertions remain unchanged. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-006-03';
            verify 'CL-006-04';
        }
        attribute executable : String = "tests/recording.test.cjs";
    }
    dependency CL_006_02_verified_by_TC_018_001 from 'CL-006-02' to 'TC-018-001';
    dependency CL_006_02_verified_by_TC_018_002 from 'CL-006-02' to 'TC-018-002';
    dependency CL_006_02_verified_by_TC_018_003 from 'CL-006-02' to 'TC-018-003';
    dependency CL_006_03_verified_by_TC_010_001 from 'CL-006-03' to 'TC-010-001';
    dependency CL_006_03_verified_by_TC_010_002 from 'CL-006-03' to 'TC-010-002';
    dependency CL_006_03_verified_by_TC_010_003 from 'CL-006-03' to 'TC-010-003';
    dependency CL_006_03_verified_by_TC_010_004 from 'CL-006-03' to 'TC-010-004';
    dependency CL_006_03_verified_by_TC_010_005 from 'CL-006-03' to 'TC-010-005';
    dependency CL_006_03_verified_by_TC_010_006 from 'CL-006-03' to 'TC-010-006';
    dependency CL_006_03_verified_by_TC_010_007 from 'CL-006-03' to 'TC-010-007';
    dependency CL_006_04_verified_by_TC_010_002 from 'CL-006-04' to 'TC-010-002';
    dependency CL_006_04_verified_by_TC_010_004 from 'CL-006-04' to 'TC-010-004';
    dependency CL_006_04_verified_by_TC_010_005 from 'CL-006-04' to 'TC-010-005';
    dependency CL_006_04_verified_by_TC_010_006 from 'CL-006-04' to 'TC-010-006';
    dependency CL_006_04_verified_by_TC_010_007 from 'CL-006-04' to 'TC-010-007';
    dependency CL_006_04_verified_by_TC_018_002 from 'CL-006-04' to 'TC-018-002';
    dependency CL_006_04_verified_by_TC_018_003 from 'CL-006-04' to 'TC-018-003';
    dependency CL_006_04_verified_by_TC_022_005 from 'CL-006-04' to 'TC-022-005';
    dependency CL_008_03_verified_by_TC_002_001 from 'CL-008-03' to 'TC-002-001';
    dependency CL_008_03_verified_by_TC_009_001 from 'CL-008-03' to 'TC-009-001';
    dependency CL_008_03_verified_by_TC_009_004 from 'CL-008-03' to 'TC-009-004';
    dependency CL_008_03_verified_by_TC_009_005 from 'CL-008-03' to 'TC-009-005';

    // #52 Decode window diagnostics (approved on #52, 2026-11-02): what the station decoded.
    requirement 'CL-052-01' {
        doc /* For every live analysis window the receive owner keeps, in memory, the counters of the latest 20 windows: {mode, origin, frames, late, period_start_frame, period_start_utc, window_offset_ms (window start minus UTC period start), zero_samples (samples exactly 0), longest_zero_run, early_buffer_zero_samples (zeros inside the FT8 early buffer, the first 41*3456 frames of the period; null without a correlated clock), zero_filled_frames (frames the capture engine delivered as silence and the source filled with zeros), glitch_frames (frames of engine glitches accepted on a continuous timeline), capture (the capture's cumulative queue_contention, queue_full, pool_exhausted, invalid_packet, clock_step, timestamp_error, native_discontinuity, frame_backstep counters), capture_drift_ms, dump}; the capture counts are null when the input does not report them. GET /receive/diagnostics (receive read authorization, no query, empty body) returns exactly {v 1, profile_id, boot_id, window_dump, storage_error, dump_error, dumped_windows, windows}; it is read when Settings opens (at most every 30 s) or on Refresh, never polled, and nothing of it is added to GET /receive. The FT8 prompt-window dump is off by default and per profile: receive-diagnostics.json next to profile.json holds exactly {schema_version 1, profile_id, window_dump boolean}, written atomically; a missing file is off, a foreign, malformed or other-schema file is off with storage_error invalid_diagnostics. POST /receive/diagnostics {v 1, profile_id, boot_id, window_dump} with operator authority sets it (wrong profile wrong_profile, other boot state_conflict, any other key or type invalid_request) and acts from the next window without a restart; Settings > Expert shows it as "Save FT8 decode windows" with the latest window's counters. While on, each FT8 prompt window (not the late window, not FT4) is written off the decode path as diagnostic-windows/<origin, 15 digits>-<period UTC without separators>.wav, 12 kHz mono PCM16 as jt9 reads it, with a .json sidecar {v 1, rate_hz 12000, sample_format pcm16_mono, window: its counters}; the folder keeps the newest 20 windows within 16 MiB, deleting the oldest; a failed write sets dump_error dump_failed and never affects decoding. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_diagnostics.rs; server/src/recording.rs; server/src/receive_http.rs; server/src/main.rs; server/src/audio.rs; server/src/audio/windows.rs; client/contact.js";
    }
    dependency CL_052_01_to_FR_003 from 'CL-052-01' to 'FR-003';
    verification 'TC-052-001' {
        doc /* TC-052-001 — Decode window diagnostics
             CL-052-01
             Setup: actual Recording owner on a disposable profile directory; the actual station router (contact_http_tests fixture); the real PacketQueue/LiveSource with injected native packets; the browser on the actual station.
             Steps: (a) counters of a hand-built window with zeros at known frames and a known early buffer; (b) a PCM16 WAV of 0, 0.5, -1, 1; (c) defaults, POST on, reopen, foreign/other-schema/extra-key files, wrong profile and boot; (d) windows noted with the dump off, a late window, then 27 prompt windows with it on; (e) five windows of a third of the cap; (f) GET/POST through the router with refused bodies, a foreign origin and a query; (g) 100 native 480-frame packets at 48 kHz with packets 10 and 11 silent, 40 and 70 accepted glitches, then a timestamp error; one signal packet followed by 600 silent ones; (h) the Expert toggle in the browser.
             Expected (hand-calculated): (a) 6 zeros, longest run 3, 4 in the early buffer (frames 104, 110, 118, 119); (b) RIFF/WAVE, PCM 1 channel 12000 Hz 16 bit, samples 0, 16384, -32768, 32767; (c) off, then {schema_version 1, profile_id, window_dump true} and on after reopening, each bad file off with invalid_diagnostics, refusals wrong_profile and state_conflict; (d) nothing written while off or for the late window, then <origin>-20261102T0916000000000Z.wav and .json with the window's counters, the newest 20 windows kept, the view's last 20 windows from origin 10, dumped_windows 27; (e) the two newest windows kept; (f) 200 views, 403 wrong_profile and forbidden_origin, 409 state_conflict, 400 invalid_request, GET /receive without window counters; (g) zero-filled 240 and glitch 240 canonical frames in [0, 12000), 180 and 60 in [1260, 4860), none after the new epoch; 72000 zero-filled frames, counted in full beyond the 512-mark limit; (h) the checkbox in Settings > Expert reads back the saved value and one POST per change.
             2 — Isolated automated tests; Windows PC, no radio or audio device. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-052-01';
        }
        attribute executable : String = "server/src/receive_diagnostics_tests.rs; server/tests/audio_contract.rs::audio_zero_filled_and_glitch_frames_are_marked_per_window; tests/ui-operating.test.cjs; server/tests/audio_contract.rs::audio_sustained_silence_is_counted_in_full";
    }
    dependency CL_052_01_verified_by_TC_052_001 from 'CL-052-01' to 'TC-052-001';

}
