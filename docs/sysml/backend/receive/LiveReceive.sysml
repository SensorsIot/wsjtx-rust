package WstxLiveReceive {
    private import ScalarValues::*;
    private import WstxOfflineDecode::ResultRecord;
    private import WstxOfflineDecode::Mode;
    private import WstxRecordingReceive::DecodeJob;
    private import WstxRecordingReceive::ReceiveMode;
    private import WstxAudio::NativePacket;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-004';
    private import WstxRequirements::'FR-018';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'FR-002';
    private import WstxModemDecode::'CL-007-04';
    private import WstxRequirements::AutomationState;
    private import WstxModemDecode::'TC-004-001';
    private import WstxModemDecode::'TC-004-002';
    private import WstxModemDecode::'TC-004-003';
    private import WstxRequirements::'TC-002-001';
    private import WstxTransmit::'TC-043-002';
    private import WstxRequirements::'TC-057-002';
    private import WstxRequirements::'TC-057-003';
    private import WstxRadioIO::'CL-008-04';
    private import WstxRadioIO::'CL-008-05';
    private import WstxOperatingReceive::'CL-008-07';
    item def LiveTimedResultRecord :> ResultRecord {
        attribute period_start_utc : String[0..1];
        attribute dt_seconds : Real[0..1];
        doc /* Live-only manager extension4.7.4/12.8, native Decode unchanged.
             Both null without correlated source timing; otherwise nearest nominal
             period and signed relative seconds via WstxLiveReceive::RelativeDecodeTiming.
             Existing2048-byte live record cap and stricter1024-byte modem cap remain. */
    }
    item def ResultPage {
        attribute v : Integer = 1;
        attribute correlation : WstxRecordingReceive::Correlation;
        attribute mode : Mode;
        attribute 'state' : WstxRecordingReceive::ReceiveState;
        attribute error : WstxRecordingReceive::ErrorCode[0..1];
        attribute search_limited : Boolean;
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute available_count : Integer;
        attribute 'next' : Integer;
        attribute more : Boolean;
        item records : LiveTimedResultRecord[0..16];
        attribute latest_decode : WstxLiveReceive::LatestDecodePeriod[0..1];
        assert constraint pageCursor { first_sequence >= 0 and next_sequence >= first_sequence and next_sequence <= (900719925 * 10000000 + 4740991) and available_count == next_sequence - first_sequence and available_count <= 2048 and 'next' >= first_sequence and 'next' <= next_sequence }
        doc /* Exact12.8 live envelope<=16384bytes,record<=2048bytes; Thinlimit1/page3072.
             Each record sequence<next_sequence,start_frame<actually captured next_frame.
             cursor<first=>410cursor_expired,cursor>next=>400,cursor==next=>empty.
             No file decode operation/snapshot/page endpoint. */
    }
    action def LiveWindowSchedule {
        doc /* Live window schedule (#47, CL-007-05): with a correlated source UTC anchor the
             shared receive owner completes two windows per period at fixed source-counter
             residues of the advance: FT8 prompt +13.8 s/15 s of audio (DT -1.7..+0.66 s)
             and late +15.7 s/15 s (DT +0.2..+2.56 s); FT4 prompt +6.5 s/7.5 s (DT
             -1.5..+0.96 s) and late +7.9 s/7.5 s (DT -0.1..+2.36 s). Overlapping frames are
             deduplicated by the modem history. The late window arriving during the prompt
             decode waits in one slot until that decode completes; any other window arriving
             during a decode abandons it as an overrun (last_overrun names the newest skipped
             support). The residues come from the epoch's UTC anchor plus the measured
             capture-clock offset (CL-007-05): when it moved by more than 50 ms the residues
             are recomputed and each scheduled window's next completion moves by the signed
             correction of any size, staying the completion of the same UTC period (no
             wrap by a period). One moved into the past completes now; coinciding ones
             complete one after the other in schedule order (prompt, then late); each then
             returns to its grid, so none is dropped or repeated. A scheduled late window
             extends its period's view under the same id.
             Without a correlated anchor the counter grid (30 s/15 s, 15 s/7.5 s) applies. */
    }
    action def PublishResults {
        in job : DecodeJob;
        in records : ResultRecord[0..2048];
        out page : ResultPage;
        doc /* Stationauthority rechecks fullidentity/generation beforeappend. Cancelinvalid
             beforeack; terminalonlyafterrelease<=250ms; retain marked partials onstop/failure.
             Newjob/source/restart invalidates oldpages/callbacks. Reliable2048/2MiB live ring;
             evictionadvancesfirst_sequence, lifetime safecountersneverreset within an epoch.
             SearchLimited=>failed/decode_limit+search_limited=true,acceptedpartialsretained;
             accepted cancellation has priority. No invented calls/exception strings.
             Browser onependingpage,Thinlimit1/starts>=4sbehindexplicitstatus; optional
             spectrum<=1/2s; two32kbitclients<=3000accountedB/s/direction,status<=2s.
             No automaticmutationreplay or browsermodem/clockauthority. */
    }
    action liveWindowSchedule : LiveWindowSchedule;
    action publishResults : PublishResults;
    satisfy WstxRequirements::'CL-007-02' by publishResults;
    satisfy WstxLiveReceive::'CL-007-05' by liveWindowSchedule;
    dependency publicationOwner from publishResults to WstxArchitecture::physicalStation::backend::stations::web;
    dependency viewerOwner from publishResults to WstxArchitecture::physicalStation::frontend::browsers;
    attribute def SourceTiming {
        attribute sourceId : String;
        attribute segment : Integer;
        attribute nativeRate : Integer;
        attribute nativeAnchorFrame : Real;
        attribute canonicalAnchorFrame : Integer;
        attribute converterDelayNativeFrames : Real;
        attribute qpcAnchor100ns : Integer[0..1];
        attribute systemUtcAnchor : String[0..1];
        attribute uncertaintyNs : Integer[0..1];
        attribute correlated : Boolean;
        attribute externalAccuracy : String = "unknown";
        doc /* Exact rational12000/nativeRate mapping; group delay counted once.
             System-UTC/QPC bracket<=2ms; recheck1s, jump>20ms new timing segment.
             External clock accuracy is not inferred. No wall-time-derived sample count.
             Known gaps advance canonical count; unknown gaps/reopen new identity. */
    }
    attribute def EpochProposal {
        attribute proposalCounter : Integer;
        attribute reason : String;
        attribute trigger : String;
        attribute nativeRate : Integer;
        attribute firstDeviceFrame : Integer;
        attribute packetQpc100ns : Integer[0..1];
        attribute converterDelayNativeFrames : Real;
        doc /* Identity-free proposal. Receive authority alone allocates new immutable
             descriptor/source/job/generation/timing and acknowledges current counter.
             Until acknowledgement producer returns Pending, exposes no descriptor and
             emits no block. Stale acknowledgement rejected; no old IDs reused.
             trigger is a bounded diagnostic code naming the capture condition:
             capture_start, queue_full, queue_contention, pool_exhausted, invalid_packet,
             clock_step (capture-thread UTC/QPC recheck), timestamp_error, frame_backstep
             or native_discontinuity; loss flag and trigger are one atomic value. */
    }
    action def AcknowledgeEpoch {
        in proposal : EpochProposal;
        in descriptor : WstxAudio::SourceDescriptor;
        in timing : SourceTiming;
        out accepted : Boolean;
        doc /* acknowledge_epoch(proposalCounter,descriptor,timing) accepts only current
             source-local proposal. Capture I/O cannot invent station identities. */
    }
    item def LiveSampleBlock :> WstxAudio::SampleBlock {
        attribute timing : SourceTiming;
        doc /* Refines SAME immutable canonical12k SampleBlock, <=240frames here;
             descriptor.total_frames absent. No change to recordedPCM/32768 semantics.
             One converter only, no fake filter edges/silence, no gap-crossing window.
             Consumers retain<=2active references plus separately bounded FIFO. */
    }
    attribute def AnalysisOverrun {
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        assert constraint boundedInterval { first_frame >= 0 and first_frame < end_frame and end_frame <= (900719925 * 10000000 + 4740991) }
        doc /* Latest abandoned analysis window's half-open support, not missing audio.
             end_frame<=capturedNextFrame. Null until overrun, replace on next,
             clear on newjob/sourceepoch. ExactGET/receive.job key last_overrun. */
    }
    attribute def RelativeDecodeTiming {
        attribute mode : ReceiveMode;
        attribute correlated : Boolean;
        attribute observedStartSeconds : Real;
        attribute periodStartSeconds : Real;
        attribute periodSeconds : Real;
        attribute nominalStartSeconds : Real;
        attribute dtSeconds : Real;
        attribute externalAccuracyKnown : Boolean = false;
        assert constraint modeTiming {
            (mode == ReceiveMode::ft8 and periodSeconds == 15.0 and nominalStartSeconds == 0.5) or
            (mode == ReceiveMode::ft4 and periodSeconds == 7.5 and nominalStartSeconds == 0.452)
        }
        assert constraint relativeOffset {
            dtSeconds == observedStartSeconds - periodStartSeconds - nominalStartSeconds and
            dtSeconds >= -periodSeconds / 2.0 and dtSeconds < periodSeconds / 2.0
        }
        doc /* contract 4.7.4/12.8. Used only with correlated source timing. Observed start
             comes from canonical frame/UTC anchor at12000Hz, not arrival/browser time.
             Nearest nominal UTC grid start; ties select later period. Positive late,
             negative early. External accuracy unknown does not suppress relative DT.
             Without correlation live wire period_start_utc and dt_seconds are null.
             FT4 includes leading576-frame ramp:0.5-576/12000=0.452s. */
    }
    attribute def LatestDecodePeriod {
        attribute id : Integer;
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute period_start_utc : String[0..1];
        attribute complete : Boolean;
        attribute abandoned : Boolean;
        attribute qualifiedWindow : Boolean;
        assert constraint safeIdentity { id > 0 and id <= (900719925 * 10000000 + 4740991) }
        assert constraint frozenRange { first_sequence >= 0 and next_sequence >= first_sequence and next_sequence <= (900719925 * 10000000 + 4740991) }
        assert constraint neverFalseComplete { abandoned implies not complete }
        doc /* Existing manager owns this nullable metadata and existing ring, no new
             endpoint/cache/modem. Publish atomically at finished/overrun attempt only.
             Select latest UTC period with nominal support wholly inside actual window;
             FT8 support12.64s/period15s/offset0.5, FT4 5.04s/7.5s/0.452.
             No qualified period => no publication; never move selected period backwards.
             Without correlation range is that attempt's newly published records, time null.
             Correlated range encloses matching retained records, empty => both equal
             frozen publication end. Job snapshot and result page expose same exact keys.
             Gap clears view without reusing IDs; epoch resets it/ID. Cancellation/failure
             cannot create complete empty view; last published output keeps truthful status.
             Existing evictions/410/caps remain authoritative. */
    }
    attribute def LiveResultWindow {
        attribute latest_decode : LatestDecodePeriod[0..1];
        attribute last_overrun : AnalysisOverrun[0..1];
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
        attribute available_count : Integer;
        attribute capturedNextFrame : Integer;
        assert constraint retained { first_sequence >= 0 and next_sequence >= first_sequence and available_count == next_sequence - first_sequence and available_count <= 2048 }
        assert constraint safeCounters { next_sequence <= (900719925 * 10000000 + 4740991) and capturedNextFrame >= 0 and capturedNextFrame <= (900719925 * 10000000 + 4740991) }
        doc /* Live ONLY: sequence/start_frame safe nonnegative integers below lifetime
             next_sequence/capturedNextFrame, using safe lifetime domains rather than finite fixture bounds.
             Oldest eviction advancesfirst_sequence,2048records/2MiB, no counter reuse.
             Counterexhaustion fails beforeoverflow. Exact live page keys12.8; cursor<first
             gives410cursor_expired, cursor>next400, cursor==nextempty/morefalse.
             first6/next2054/count2048,cursor7limit1=>record7,next8,moretrue;cursor5=>410.
             Tests2047/2048/2049 andsafeintboundaries; Live record domains use safe lifetime counters and actual captured bounds. */
    }
    action def ConvertAndReceive {
        in packet : NativePacket;
        out block : LiveSampleBlock;
        doc /* Single DSP owner fans out to existing FFT and pure decoder. FIR passband
             0..3500Hz +-0.1dB, stop>=5500Hz >=60dB, exact rational output count and
             partition invariance2e-5; delay<=20ms/<=1024native support. No second
             conversion or AGC. Known gaps reset FIR/FFT/decoder without invented samples.
             FT8trailing30s/advance15s, FT4trailing15s/advance7.5s; no queued analyses,
             except that with a correlated UTC anchor one scheduled late window waits
             for the prompt analysis in progress (WstxLiveReceive::LiveWindowSchedule, #47).
             Missed boundary drops outstanding future and records latest abandoned
             window support in last_overrun; partials retained, no fabricated audio gap.
             Newest supported window replaces obsolete work, never claims complete history.
             Existing receive owner mutually excludes imports/file jobs/live; CPU50ms
             quanta service conversion/spectrum. Software backlog<=200ms, normalcancel250ms.
             Retain2048records/2MiB; livefirst_sequence eviction and410cursor_expired.
             Fixed0..3000display does not change decoder200..3500search. */
    }
    action convertReceive : ConvertAndReceive;
    satisfy WstxLiveReceive::'CL-008-02' by convertReceive;
    satisfy WstxRecordingReceive::'CL-008-03' by convertReceive;
    dependency conversionOwner from convertReceive to WstxArchitecture::physicalStation::backend::stations::receive;
    requirement 'CL-007-01' {
        doc /* Explicit FT4/FT8 selection MUST process the immutable canonical 12 kHz live source through the existing receive-job authority. Independent recorded fixtures MUST exercise the same pure modem without a physical radio; no file-decoding product operation is provided. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_01_to_FR_003 from 'CL-007-01' to 'FR-003';
    dependency CL_007_01_to_FR_004 from 'CL-007-01' to 'FR-004';
    dependency CL_007_01_to_FR_018 from 'CL-007-01' to 'FR-018';
    requirement 'CL-007-05' {
        doc /* Live decode latency (#47). With a correlated UTC source clock, on the reference PC HB9BLA under normal station load (receive, waterfall, one browser, UDP enabled), for any session length: live FT8 MUST publish every decode of a frame with DT -1.6 s to +0.56 s by its period start + 15.0 s, and live FT4 every decode with DT -1.4 s to +0.86 s by period start + 7.5 s. Every frame with DT -1.6 s to +2.4 s (FT8) or -1.4 s to +2.2 s (FT4) MUST be published, the later ones from a late window early in the next period, which waits for the prompt decode instead of cutting it short, and extends its period's view with them under the same view id (nothing new publishes nothing), so clients keep their rows and cursor. The receive owner MUST measure the capture clock against UTC continuously (each timestamped packet's canonical frame against its QPC/system-time UTC, averaged over about 1 s, a jump above 0.2 s restarting the average) and re-anchor the window schedule, period UTC and DT whenever the measured offset moved by more than 50 ms, without dropping, repeating or reordering a window for a correction of any size; the measured offset and rate are read on demand from GET /receive/clock (capture_drift_ms, capture_drift_ppm), never added to the high-frequency GET /receive snapshot, whose clock object and thin-link size stay unchanged. (At zero offset the prompt windows hold FT8 DT -1.7..+0.66 s and FT4 -1.5..+0.96 s, prompt plus late windows FT8 -1.7..+2.56 s and FT4 -1.5..+2.36 s; the ranges above keep 0.1 s for the re-anchoring residual: the 50 ms threshold and drift within one period.) No per-period decode count cap applies; the only search bound is the existing 256 qualified-candidate limit with explicit SearchLimited. Without a correlated UTC clock the source-counter window grid of WstxLiveReceive::LiveWindowSchedule applies and no latency is promised. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/receive.rs; server/src/recording.rs; server/src/decoder/search.rs; server/src/decoder/subtraction.rs";
    }
    dependency CL_007_05_to_FR_003 from 'CL-007-05' to 'FR-003';
    dependency CL_007_05_to_FR_004 from 'CL-007-05' to 'FR-004';
    dependency CL_007_05_to_FR_021 from 'CL-007-05' to 'FR-021';
    requirement 'CL-008-02' {
        doc /* Deliver immutable canonical 12 kHz mono samples and explicit timing/gaps through one common converter to the existing spectrum/decoder worker, without fabricating samples or UTC accuracy. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/audio.rs; server/src/audio/windows.rs; server/src/radio_control/mod.rs; server/src/receive.rs";
    }
    dependency CL_008_02_to_FR_002 from 'CL-008-02' to 'FR-002';
    dependency CL_008_02_to_FR_003 from 'CL-008-02' to 'FR-003';
    dependency CL_008_02_to_FR_004 from 'CL-008-02' to 'FR-004';
    verification 'TC-004-004' {
        doc /* TC-004-004 — Live decode latency on a recorded busy period (#47)
             FR-003, FR-004, FR-021; CL-007-04, CL-007-05
             Cost 2 (release, Windows PC, no radio): the hash-pinned busy recording websdr_test7.wav (27 decodes) is presented as the UTC-aligned FT8 prompt window, 15 s of audio completing at period start + 13.8 s, to the live modem history. The time from window completion to the last published decode is at most 1.0 s (best of three runs, leaving 0.2 s of the 1.2 s budget for capture and publication) and at least 25 distinct decodes are published, so no per-period cap applies. Cost 1: the UTC schedule places FT8 prompt/late windows at +13.8 s/+15.7 s and FT4 at +6.5 s/+7.9 s of the period from a correlated anchor, and none without one; the window buffer emits each scheduled window at its source-counter residue with its own length and wait flag; a late window arriving during the prompt decode waits for it, with no overrun and a complete prompt result. Cost 1 (drift, #47 re-review): through the live worker's clock tracking and the real window buffer, a capture clock 2000 ppm slow over 600 s plus a +0.4 s system clock step (1.6 s in all) keeps every prompt window within 0.1 s of +13.8 s UTC and holding a DT 0 frame, while the same capture without re-anchoring completes more than 1.2 s late; GET /receive/clock reports the offset and rate while the /receive clock object keeps its exact keys; the on-demand read has the operating-read authorization and refuses a query. Cost 1: a re-anchored schedule moves completions for a forward shift and a backward step without dropping or repeating a window, and UTC steps of +2 s, -2 s and +8 s taken just before a prompt completion still complete every period's prompt and late window exactly once, in order (coinciding completions one after the other, no shift by a period). Cost 1: the FT8 late window at its real geometry (UTC +0.7..+15.7 s), analysed by the live worker, leaves latest_decode and the whole snapshot unchanged when it adds nothing, and with a DT +1.2 s late starter keeps the view id and only grows next_sequence. Cost 2 (browser): a correlated period view extended in place (same id, period and first_sequence; next_sequence grown, complete false to true) adds the late row from the existing cursor, without clearing rows, moving the period to history or an error state, while any other same-id change stays a descriptor error.
             Cost 5 acceptance: live on HB9BLA, 10 consecutive FT8 periods publish their last decode by +15.0 s and FT4 by +7.5 s, with decode parity against jt9 on the same captured periods unchanged or better; the run records the receive session age and GET /receive/clock. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-04';
            verify 'CL-007-05';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-021';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::live_busy_period_publishes_every_decode_promptly; server/tests/receive_integration.rs::receive_schedule_completes_windows_at_period_residues; server/src/recording_tests.rs::live_window_schedule_follows_the_utc_period_grid; server/src/recording_tests.rs::late_window_waits_for_the_prompt_decode_without_overrun; server/src/recording_tests.rs::drifting_capture_clock_keeps_prompt_windows_on_the_utc_period; server/src/recording_tests.rs::late_window_republishes_its_period_view_with_late_starters; server/tests/receive_integration.rs::receive_reschedule_moves_completions_without_dropping_or_repeating; server/tests/receive_integration.rs::receive_clock_steps_keep_each_period_window_once_and_in_order; server/src/auth_tests.rs::plaintext_profile_operating_routes_and_ws_require_runtime_token; tests/ui-operating.test.cjs";
    }
    dependency CL_007_01_verified_by_TC_004_001 from 'CL-007-01' to 'TC-004-001';
    dependency CL_007_01_verified_by_TC_004_002 from 'CL-007-01' to 'TC-004-002';
    dependency CL_007_01_verified_by_TC_004_003 from 'CL-007-01' to 'TC-004-003';
    dependency CL_007_05_verified_by_TC_004_004 from 'CL-007-05' to 'TC-004-004';
    dependency CL_008_02_verified_by_TC_002_001 from 'CL-008-02' to 'TC-002-001';
    dependency CL_008_02_verified_by_TC_002_003 from 'CL-008-02' to 'TC-002-003';
    dependency CL_008_02_verified_by_TC_009_002 from 'CL-008-02' to 'TC-009-002';
    dependency CL_007_05_verified_by_TC_043_002 from 'CL-007-05' to 'TC-043-002';
    dependency CL_007_05_verified_by_TC_057_002 from 'CL-007-05' to 'TC-057-002';
    dependency CL_007_05_verified_by_TC_057_003 from 'CL-007-05' to 'TC-057-003';
    verification 'TC-009-002' {
        doc /* TC-009-002 — Controlled IC-7300 receive station
             CL-008-02, CL-008-04, CL-008-05, CL-008-07
             On the designated Windows IC-7300 PC, verify receive inhibit/keying settings, selected USB input and COM3 identity; inspect readback against radio indications, capture known on-air/reference receive signals, restore original receive settings. Compare decoded payloads with simultaneous reference receive observations.
             Correct physical input/port, no transmission, authoritative CAT observations, visible live spectrum/decodes and independent source timing/error records. Loss/reconnect and clock-quality labels agree with actual state. Reference counts alone are not exhaustive decoder truth.
             4 — Controlled live tests; HB9BLA radio PC and development browser, physical IC-7300, operator-authorized receive-only setup. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-02';
            verify 'CL-008-04';
            verify 'CL-008-05';
            verify 'CL-008-07';
        }
        attribute executable : String = "server/tests/radio_native.rs::read_only_selected_endpoint_discovery; server/tests/radio_hardware.rs::authorized_ic7300_frequency_query_evidence; server/tests/radio_hardware.rs::authorized_ic7300_readonly_inventory_evidence; server/tests/radio_hardware.rs::authorized_ic7300_prepare_usb_data; server/tests/radio_hardware.rs::authorized_ic7300_restore_lsb_data_off; server/tests/audio_hardware.rs::selected_radio_audio_capture_evidence; server/tests/audio_listen.rs::selected_radio_audio_to_listening_wav";
        attribute method : String = "manual";
    }
    verification 'TC-002-003' {
        doc /* TC-002-003 — Audio without CAT
             CL-008-02, CL-008-05
             Stream known packets with CAT disabled/unavailable and inject audio loss; exercise live spectrum and decoder fixture consumer.
             Correct samples/spectrum/results without any CAT bytes; own errors/reopen/epochs visible; engine glitches keep job/generation; GET /receive audio.loss_epochs counts unknown-loss rotations only and audio.last_loss names the latest trigger (null iff0); no default-device substitution or audio archiving.
             2 — Isolated automated tests; Windows PC, actual receive service and independent device/control fixtures. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-008-02';
            verify 'CL-008-05';
        }
        attribute executable : String = "server/tests/audio_contract.rs; server/tests/audio_receive.rs; server/src/recording_tests.rs";
    }
}
