package WstxReceiveStartup {
    private import ScalarValues::*;
    private import WstxOperatingLayout::'TC-007-009';
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-003';
    private import WstxRequirements::'FR-021';
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::AutomationState;
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
}
