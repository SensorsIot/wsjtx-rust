package WstxRequirementsReceive {
    private import ScalarValues::*;
    private import WstxRequirements::*;
    requirement 'CL-007-01' {
        doc /* Explicit FT4/FT8 selection MUST process the immutable canonical 12 kHz live source through the existing receive-job authority. Independent recorded fixtures MUST exercise the same pure modem without a physical radio; no file-decoding product operation is provided. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/decoder/mod.rs; server/src/receive.rs; client/recording.js";
    }
    dependency CL_007_01_to_FR_003 from 'CL-007-01' to 'FR-003';
    dependency CL_007_01_to_FR_004 from 'CL-007-01' to 'FR-004';
    dependency CL_007_01_to_FR_018 from 'CL-007-01' to 'FR-018';
    requirement 'CL-007-05' {
        doc /* Live decode latency (#47). With a correlated UTC source clock, on the reference PC HB9BLA under normal station load (receive, waterfall, one browser, UDP enabled), for any session length: live FT8 MUST publish every decode of a frame with DT -1.6 s to +0.56 s by its period start + 15.0 s, and live FT4 every decode with DT -1.4 s to +0.86 s by period start + 7.5 s. Every frame with DT -1.6 s to +2.4 s (FT8) or -1.4 s to +2.2 s (FT4) MUST be published, the later ones from a late window early in the next period, which waits for the prompt decode instead of cutting it short, and extends its period's view with them under the same view id (nothing new publishes nothing), so clients keep their rows and cursor. The receive owner MUST measure the capture clock against UTC continuously (each timestamped packet's canonical frame against its QPC/system-time UTC, averaged over about 1 s, a jump above 0.2 s restarting the average) and re-anchor the window schedule, period UTC and DT whenever the measured offset moved by more than 50 ms, without dropping, repeating or reordering a window for a correction of any size; the measured offset and rate are read on demand from GET /receive/clock (capture_drift_ms, capture_drift_ppm), never added to the high-frequency GET /receive snapshot, whose clock object and thin-link size stay unchanged. (At zero offset the prompt windows hold FT8 DT -1.7..+0.66 s and FT4 -1.5..+0.96 s, prompt plus late windows FT8 -1.7..+2.56 s and FT4 -1.5..+2.36 s; the ranges above keep 0.1 s for the re-anchoring residual: the 50 ms threshold and drift within one period.) No per-period decode count cap applies; the only search bound is the existing 256 qualified-candidate limit with explicit SearchLimited. Without a correlated UTC clock the source-counter window grid of AdvanceDecode applies and no latency is promised. */
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
             Cost 2 (release, Windows PC, no radio): the hash-pinned busy recording websdr_test7.wav (27 decodes) is presented as the UTC-aligned FT8 prompt window, 15 s of audio completing at period start + 13.8 s, to the live modem history. The time from window completion to the last published decode is at most 1.0 s (best of three runs, leaving 0.2 s of the 1.2 s budget for capture and publication) and at least 25 distinct decodes are published, so no per-period cap applies. Cost 1: the UTC schedule places FT8 prompt/late windows at +13.8 s/+15.7 s and FT4 at +6.5 s/+7.9 s of the period from a correlated anchor, and none without one; the window buffer emits each scheduled window at its source-counter residue with its own length and wait flag; a late window arriving during the prompt decode waits for it, with no overrun and a complete prompt result. Cost 1 (drift, #47 re-review): through the live worker's clock tracking and the real window buffer, a capture clock 2000 ppm slow over 600 s plus a +0.4 s system clock step (1.6 s in all) keeps every prompt window within 0.1 s of +13.8 s UTC and holding a DT 0 frame, while the same capture without re-anchoring completes more than 1.2 s late; GET /receive/clock reports the offset and rate while the /receive clock object keeps its exact keys; the on-demand read has the operating-read authorization and refuses a query. Cost 1: a re-anchored schedule moves completions for a forward shift and a backward step without dropping or repeating a window, and UTC steps of +2 s, -2 s and +8 s taken just before a prompt completion still complete every period's prompt and late window exactly once, in order (coinciding completions one after the other, no shift by a period). Cost 1: the FT8 late window at its real geometry (UTC +0.7..+15.7 s), analysed by the live worker, leaves latest_decode and the whole snapshot unchanged when it adds nothing, and with a DT +1.2 s late starter keeps the view id and only grows next_sequence. Cost 2 (browser): a correlated period view extended in place (same id, period and first_sequence; next_sequence grown, complete false to true) adds the late row from the existing cursor, without clearing rows, moving the period to history or an error state, while any other same-id change stays a descriptor error. Cost 1: band-ranked known-word refinement agrees with the exhaustive full-rate grid search on a crowded synthetic frame within 32 frames and 0.02 Hz and returns a full-rate score.
             Cost 5 acceptance: live on HB9BLA, 10 consecutive FT8 periods publish their last decode by +15.0 s and FT4 by +7.5 s, with decode parity against jt9 on the same captured periods unchanged or better; the run records the receive session age and GET /receive/clock. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-007-04';
            verify 'CL-007-05';
            verify 'FR-003';
            verify 'FR-004';
            verify 'FR-021';
        }
        attribute executable : String = "server/tests/decoder_signal.rs::live_busy_period_publishes_every_decode_promptly; server/tests/receive_integration.rs::receive_schedule_completes_windows_at_period_residues; server/src/recording_tests.rs::live_window_schedule_follows_the_utc_period_grid; server/src/recording_tests.rs::late_window_waits_for_the_prompt_decode_without_overrun; server/src/recording_tests.rs::drifting_capture_clock_keeps_prompt_windows_on_the_utc_period; server/src/recording_tests.rs::late_window_republishes_its_period_view_with_late_starters; server/tests/receive_integration.rs::receive_reschedule_moves_completions_without_dropping_or_repeating; server/tests/receive_integration.rs::receive_clock_steps_keep_each_period_window_once_and_in_order; server/src/auth_tests.rs::plaintext_profile_operating_routes_and_ws_require_runtime_token; tests/ui-operating.test.cjs; server/src/decoder/search_test.rs::ranked_refinement_matches_exhaustive_grid_search";
    }
    dependency CL_007_01_verified_by_TC_004_001 from 'CL-007-01' to 'TC-004-001';
    dependency CL_007_01_verified_by_TC_004_002 from 'CL-007-01' to 'TC-004-002';
    dependency CL_007_01_verified_by_TC_004_003 from 'CL-007-01' to 'TC-004-003';
    dependency CL_007_05_verified_by_TC_004_004 from 'CL-007-05' to 'TC-004-004';
    dependency CL_008_02_verified_by_TC_002_001 from 'CL-008-02' to 'TC-002-001';
    dependency CL_008_02_verified_by_TC_002_003 from 'CL-008-02' to 'TC-002-003';
    dependency CL_008_02_verified_by_TC_009_002 from 'CL-008-02' to 'TC-009-002';
    dependency CL_045_01_verified_by_TC_007_009 from 'CL-045-01' to 'TC-007-009';

    // #45 Resume receive (Monitor) after a station restart (defaults recorded on issue #45).
    requirement 'CL-045-01' {
        doc /* The station persists its last started receive choice and the "Monitor off at startup" setting in receive-startup.json next to profile.json of the selected profile, written atomically like the profile's other private files: {schema_version 1, profile_id, monitor_off_at_startup boolean (default false, as WSJT-X), last_receive null | {mode spectrum|ft4|ft8, band one of the preferred-table bands or null, input_device the audio input it opened}}. A successful receive start (POST /receive/start, or a band/mode selection that restarted receive) records mode, the station's band at that moment and the input; the operator's POST /receive/stop clears last_receive; a receive that ends by failure keeps it. A missing file reads as the defaults; a foreign, malformed, oversize (over 1024 bytes) or out-of-domain file reads as the defaults with storage_error invalid_startup and is replaced by the next write; a failed write leaves receive unchanged and reports storage_error storage_unavailable. GET /receive/startup (operating access, no query, empty body) returns {v 1, profile_id, boot_id, monitor_off_at_startup, last_receive, storage_error, resume {state idle|off|waiting|started|started_untuned|skipped|failed, error}}; POST /receive/startup {v, profile_id, boot_id, monitor_off_at_startup boolean}, exact keys, same Origin/authorization and refusal codes as POST /receive/stop, sets the setting for the next station start and returns the view. The setting's operator control is Settings > General (layout of #37). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs; server/src/recording.rs; server/src/receive_http.rs; server/src/main.rs; server/src/profile.rs";
    }
    dependency CL_045_01_to_FR_016 from 'CL-045-01' to 'FR-016';
    dependency CL_045_01_to_FR_003 from 'CL-045-01' to 'FR-003';
    requirement 'CL-045-02' {
        doc /* When the station starts with its profile, and monitor_off_at_startup is false and last_receive is stored, it resumes that receive once, without a browser or operator action, using the profile's current audio input (none configured: resume failed audio_unconfigured; a native FlexRadio profile's input is its session, for which it waits up to the same 20 s, then fails radio_unavailable). An FT4/FT8 choice with a band is resumed as the same band selection the band button makes (receive-only CAT setup under configured CAT; nominal dial from the preferred table); with configured CAT it waits up to 20 s for the CAT lifecycle (CL-022-03/04) to report the radio ready, retrying the transient admission refusals radio_unavailable, busy and state_conflict every 250 ms within that wait, and if the radio is not ready in time or the selection fails it starts receive on the stored mode on the radio's present dial (resume started_untuned) and keeps the stored band. A spectrum choice or a choice without a band starts receive on the stored mode. A missing audio device follows the existing live-audio error/retry state of the started job; the resume never exits or restarts the process. With monitor_off_at_startup true (resume off) or nothing stored (resume idle) no receive starts; a receive, selection or import that exists before the resume acts (operator or MCP) is never replaced (resume skipped). */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs; server/src/main.rs";
    }
    dependency CL_045_02_to_FR_003 from 'CL-045-02' to 'FR-003';
    dependency CL_045_02_to_FR_021 from 'CL-045-02' to 'FR-021';
    requirement 'CL-045-03' {
        doc /* Resuming receive never arms, keys or tunes the transmitter: the transmit owner stays disarmed with no PTT exchange, and the only CAT writes are the receive-only setup of a band selection, refused while the radio reports TX. TC-008-002 "restart does not transmit" stays true. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/receive_startup.rs";
    }
    dependency CL_045_03_to_FR_008 from 'CL-045-03' to 'FR-008';
    verification 'TC-045-001' {
        doc /* TC-045-001 — Persisted receive choice and startup resume
             CL-045-01, CL-045-02, CL-045-03
             Setup: actual Recording owner on a disposable profile directory with the injected native-packet live input (receive_http_tests::Input), no radio actor; for HTTP the actual station router (contact_http_tests fixture); for transmit a transmit-capable fixture with CAT PTT configured and the recording hardware double (Bench).
             Steps: (a) start ft8 on input first-input; band selection 40m ft4 on band-input; set Monitor-off; reopen; operator Stop; reopen. (b) receive-startup.json with a foreign profile_id, mode jt65, band 2m, an extra key, schema_version 2, empty input_device, 1024 padding bytes, malformed JSON; resume. (c) stored ft4/20m, manual control, resume. (d) Monitor-off true with a stored choice; start then Stop then reopen; an operator start before the resume. (e) stored ft8/40m with configured CAT that never becomes ready, wait 300 ms; stored ft8/40m whose first three admissions are refused radio_unavailable, busy, state_conflict. (f) GET/POST /receive/startup valid, other profile, other boot, extra key, v 2, string boolean, foreign Origin, a query. (g) resume on the transmit-capable fixture, manual band path and configured-CAT fallback.
             Expected (issue #45 defaults and the canonical preferred table, hand-written file contents): (a) file {schema_version 1, profile_id, monitor_off_at_startup false, last_receive {ft8, null, first-input}}, then {ft4, 40m, band-input}; reopened view Monitor-off true and the same choice; after Stop last_receive null with Monitor-off kept. (b) every case: defaults, storage_error invalid_startup, resume idle, no job. (c) resume started, selection band 20m mode ft4 nominal_hz 14080000, job ft4 running on profile-input. (d) resume off and generation 0; resume idle with no job; resume skipped with the operator's ft8 job unchanged. (e) resume started_untuned, ft8 job running, selection band null, file band 40m kept; after the three refusals resume started, selection 40m nominal_hz 7074000, job running. (f) 200 and file true; 403 wrong_profile, 409 state_conflict, 400 invalid_request, 400 unsupported_version, 400 invalid_request, 403 forbidden_origin, 400; setting unchanged by refusals. (g) resume started / started_untuned, transmit arm/PTT/transmitting/outcomes unchanged, Bench PTT log empty.
             2 — Isolated automated functional tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-045-01';
            verify 'CL-045-02';
            verify 'CL-045-03';
        }
        attribute executable : String = "server/src/receive_startup_tests.rs";
    }
    dependency CL_045_01_verified_by_TC_045_001 from 'CL-045-01' to 'TC-045-001';
    dependency CL_045_02_verified_by_TC_045_001 from 'CL-045-02' to 'TC-045-001';
    dependency CL_045_03_verified_by_TC_045_001 from 'CL-045-03' to 'TC-045-001';
    verification 'TC-045-002' {
        doc /* TC-045-002 — Live resume after a station restart
             CL-045-01, CL-045-02, CL-045-03
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3 with commissioned receive-only CAT, USB Audio CODEC input, no browser connected during the restarts.
             Steps: FT8 receive on a band, restart the station task; set Monitor off at startup, restart; clear it, Stop receive, restart.
             Expected: within one FT8 period after the station answers, GET /receive shows a running ft8 job and GET /receive/selection the same band, GET /receive/startup resume started; with Monitor-off no job (resume off); after Stop no job (resume idle); PTT released and transmit disarmed throughout, no RF.
             4 — Live on the station with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-045-01';
            verify 'CL-045-02';
            verify 'CL-045-03';
        }
    }
    dependency CL_045_01_verified_by_TC_045_002 from 'CL-045-01' to 'TC-045-002';
    dependency CL_045_02_verified_by_TC_045_002 from 'CL-045-02' to 'TC-045-002';
    dependency CL_045_03_verified_by_TC_045_002 from 'CL-045-03' to 'TC-045-002';
    dependency CL_007_05_verified_by_TC_043_002 from 'CL-007-05' to 'TC-043-002';
    dependency CL_007_05_verified_by_TC_057_002 from 'CL-007-05' to 'TC-057-002';
    dependency CL_007_05_verified_by_TC_057_003 from 'CL-007-05' to 'TC-057-003';
}
