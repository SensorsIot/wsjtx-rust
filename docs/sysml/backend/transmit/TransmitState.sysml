package WstxTransmit {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-009';
    private import WstxRequirements::'FR-002';
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::AutomationState;
    private import WstxTransmitSchedule::'CL-009-02';
    private import WstxMcpEndpoint::'TC-020-004';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-005';
    private import WstxTransmitClock::'TC-043-001';
    private import WstxLiveReceive::'CL-007-05';
    private import WstxTransmitClock::'CL-043-02';
    private import WstxTransmitClock::'TC-092-001';
    private import WstxOperatingLayout::'CL-037-02';
    private import WstxRequirements::'FR-019';
    private import WstxTxLevel::'TC-044-014';
    private import WstxTxLevel::'TC-044-016';
    private import WstxContact::'TC-039-007';
    private import WstxRequirements::'FR-007';
    private import WstxQsoTransmit::'TC-111-008';
    private import WstxQsoTransmit::'CL-111-02';
    private import WstxOperatingLayout::'CL-111-04';
    private import WstxQsoTransmit::'CL-111-08';
    private import WstxRequirements::'FR-010';
    private import WstxTransmitControl::ArmState;
    private import WstxOperatingChain::TransmitRefusal;
    private import WstxTransmitControl::TransmitHaltUse;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    doc /* Canonical FT8 and FT4 transmit contract. Slice A (issue #9, FT4 issue #11
         slice A): message packing, channel symbols, waveform and pure period
         scheduling, none of which opens audio, keys PTT or touches a radio. Slice B
         (issue #9, CL-009-03/04): the station's transmit owner (arming under the
         explicit TransmitAuthority, TransmitRequest admission and replacement, CI-V
         PTT with readback, 48 kHz output, priority Halt, Tune, Tx watchdog, failure and
         restart handling, TransmitWire); WstxContact (#10) consumes it. Physical RF
         acceptance is TC-008-002 and is not claimed by automated tests. Declared
         coverage is not a test result.
         CL-009-01/02, CL-011-01 and TC-005-001/002, TC-006-001/002 are declared in
         WstxRequirements. FT4 reuses PackMessage unchanged (FT4 and FT8 share pack77).
         Behaviour oracle: WSJT-X 3.3.0-beta5 (revision d89fe3) lib/77bit/packjt77.f90,
         packjt77_grammar.f90, lib/ft8/genft8.f90, gen_ft8wave.f90, ft8_waveform.f90,
         Modulator/Modulator.cpp, TxStartPolicy.hpp and widgets/mainwindow.cpp. Its
         ft8code output was checked identical to the pinned beta4 baseline for every
         fixture message (fixtures/transmit/ft8code-vectors.json).
         Encoding reuses the receive payload codebook, CRC-14, LDPC(174,91) generator,
         Gray map and Costas arrays of the published protocol (QEX FT4/FT8, sections 2
         to 5 and appendix A); it adds no second codebook. */
    enum def DisarmCause {
        enum operator; enum halt; enum contactCompleted; enum contactCancelled;
        enum txWatchdog; enum refused; enum failed; enum deviceLost; enum startup;
        enum authorityChanged;
        enum partnerWorksOther; enum modeChanged; enum bandChanged; enum runEnded;
    }
    enum def ArmCause { enum operator; enum auto; }
    enum def TransmitFailure {
        enum pttTimeout; enum pttRejected; enum pttReadbackMismatch; enum pttIndeterminate;
        enum radioLost; enum audioUnavailable; enum audioDeviceLost; enum audioStalled;
        enum authorityChanged; enum ownerFault;
    }
    enum def TransmitCapability { enum unsupported; enum unavailable; enum available; }
    enum def PttState { enum released; enum keyed; enum indeterminate; }
    enum def HaltState { enum idle; enum pending; enum stopped; }
    attribute def TransmitAuthority {
        attribute armedOnStartup : Boolean = false;
        attribute persisted : Boolean = false;
        doc /* The station's explicit transmit authority (WstxRadioControlPart::RadioAuthority),
             evaluated at Arm, at every request admission, at keying and on every
             owner step. Capability: unsupported unless the saved profile has
             control.mode cat, control.ptt cat and an exact audio.output_device (a
             receive-only profile, ptt disabled, is never transmit capability);
             unavailable while the CL-022-03 automatic CAT gate is not eligible (no
             current grant, commissioning missing or invalidated) or its actor is not
             ready; otherwise available. Authority: an explicit operator Arm request
             carrying the current CL-022 safety revision of the selected radio scope,
             sent by a request with a current CL-022 grant (a plaintext profile has no
             grant and never arms). CL-022 receive-only commissioning is a precondition
             of CAT but is not transmit authority. The authority is per boot, never
             persisted or restored: every process start is disarmed (startup), and any
             safety revision change (control/profile edit, recommissioning) disarms
             (authorityChanged); loss of the radio or capability disarms (deviceLost).
             MCP and the browser use the same operation; neither can widen it. */
    }
    attribute def TransmitTiming {
        attribute haltMs : Integer = 250;
        attribute pttExchangeMs : Integer = 1000;
        attribute keyLeadMs : Integer = 0;
        attribute playbackScale : Real = 0.5;
        attribute sampleRateHz : Integer = 48000;
        attribute releaseMarginMs : Integer = 1000;
        attribute releaseBoundFt8Ms : Integer = 14500;
        attribute releaseBoundFt4Ms : Integer = 7000;
        attribute renderStallMs : Integer = 500;
        attribute renderBufferMs : Integer = 100;
        attribute silencePrefillMs : Integer = 20;
        // FT8 audio ends at period + 500 + 12640 ms, FT4 at period + 300 + 5040 ms.
        assert constraint releaseInsidePeriod {
            500 + 12640 + releaseMarginMs <= releaseBoundFt8Ms and
            300 + 5040 + releaseMarginMs <= releaseBoundFt4Ms and
            renderBufferMs < releaseMarginMs
        }
        doc /* Keying: the output device is opened first, then PTT is keyed at the period
             start (keyLeadMs after it; for an admitted late start at once), so the
             audio delay of Ft8Schedule/Ft4Schedule (500/300 ms) separates the confirmed
             key from the first sample. Audio starts only after the key readback, at
             the first owner step at or after period start + audio delay, and plays
             from the sample PlanTransmitStart gives for that instant (late start skips,
             never replays). PTT is released with readback after the device reports the
             last sample played, and at the latest at the device-independent release
             deadline audio start + remaining waveform duration + releaseMarginMs, never
             later than period start + releaseBoundFt8Ms (FT8) or releaseBoundFt4Ms
             (FT4), whatever the device reports. Every owner step asks the device first,
             also at or after the deadline: a device that reports every sample played
             completes normally (released, still armed, the contact continues) however
             late that step runs; a device that has not reported the end by the
             deadline (it stopped consuming, or never reports) is released at the
             deadline and fails audioStalled (disarm deviceLost). releaseMarginMs covers
             the render drain (renderBufferMs) and render or owner scheduling delays
             under load with headroom (#49: a 500 ms margin with a 20 ms render buffer
             failed a healthy FT8 transmission under build load). Disarm never unbounds
             a keyed transmission. haltMs: from HaltTransmit receipt, audio output stops
             without waiting for the owner lock and PTT is released and read back
             within 250 ms while CAT answers; a release exchange that fails or times
             out (pttExchangeMs per exchange, RadioIO 1 s) leaves PttState
             indeterminate, closes that CAT connection and is reported, never hidden.
             Halt priority: the halt flag is checked immediately before keying and
             aborts the output open and the wait for the CAT owner; a halt received
             during the open never keys, one received during the key exchange releases
             at once after it; halt_state stopped only after the confirmed release,
             otherwise pending with the true PttState. Owner fault: a panic of the
             transmit owner thread fails closed (audio stopped, one release attempt,
             requests failed ownerFault, disarmed failed, Arm refused for the boot)
             and halt keeps answering. ExitRelease: Ctrl+C, console close, logoff,
             shutdown and any process panic stop output and, only when the CI-V switch
             may be keyed, send one off-only release bounded to 500 ms.
             playbackScale: the unit-peak waveform is played at -6.02 dBFS at Tx level
             0 dB, the highest; the Tx level (CL-044-12, -40..0 dB in whole dB) attenuates
             below it digitally. A transmission takes the level at its audio start and
             keeps it to its end; a running Tune follows it at once. */
    }
    enum def StartupRelease { enum pending; enum notNeeded; enum released; enum failed; }
    action def StartupSafetyRelease {
        doc /* Safety release after a station boot (supervisor decision 2026-10-31 on #9):
             a crash while keyed can leave the radio transmitting (a CI-V TX switch
             latches). On the first fresh confirmed 1C 00 readback of the boot (whoever
             queried it, normally the CL-022 automatic poll), if it shows TX and this
             boot has never keyed, the transmit owner sends exactly one off-only release
             1C 00 00 with readback through PttControl (released, or failed if not
             confirmed); otherwise notNeeded. Once per boot, never a key, never
             anything else, regardless of the profile's PTT configuration; a later TX
             (for example the operator's microphone) is not ended. failed keeps Arm
             refused for the boot. This is the single permitted exception to "the
             automatic CAT lifecycle never sends a setter/PTT" (CL-022-03). Reported as
             GET /transmit startup_release pending|not_needed|released|failed. */
    }
    attribute def TransmitArming {
        attribute armState : ArmState = ArmState::disarmed;
        attribute lastDisarmCause : DisarmCause = DisarmCause::startup;
        attribute lastArmCause : ArmCause[0..1];
        doc /* The station's one transmit state (CL-111-01), on (armed) or off (disarmed),
             owned by WstxTransmitPart::TransmitService; off at startup and after every
             DisarmCause. lastArmCause is who switched it on last (operator, or auto for
             a run or an MCP client) and is absent until the first switch-on of a boot.
             Arm/Disarm are requests from QsoAndLogging (the start actions
             WstxQsoTransmit::StartActions, and Enable Tx) through the qso-to-transmit
             connection, or TransmitWire. Arming requires TransmitAuthority: unsupported capability
             is refused transmitUnsupported, unavailable radioUnavailable, a missing
             grant or a different safety revision notAuthorized, and a PTT switch left
             indeterminate, a failed StartupSafetyRelease or an owner fault
             radioUnavailable. These arm conditions are one query of the owner: call_cq,
             send_next and reset_repetitions ask it before they change anything; reply
             and call_dx prepare the QSO and are accepted when it refuses, and the
             state and its cause stay (CL-111-07); Tune checks the same conditions at its own start
             (SetTune). Disarm sends no new
             request and cancels requests that are not keyed; a transmission already
             keyed or playing finishes unless halted. */
    }
    attribute def StopOrder {
        doc /* CL-111-03. A station step is the time from the begin of one contact step
             (WstxStandardQso::AutoSequence, every 50 ms and directly after each accepted
             ContactCommand) to the begin of the next. When several stops are applied in
             one station step, lastDisarmCause is the first of this order, whichever
             arrived first: halt; deviceLost; authorityChanged; failed; refused;
             contactCancelled by Abort QSO; txWatchdog; partnerWorksOther; bandChanged;
             modeChanged; runEnded; contactCancelled by Cancel contact;
             contactCompleted; operator. A switch-on between two stops of a step begins
             the choice anew. A start action that arrives after a stop of the same
             station step is refused state_conflict (WstxQsoTransmit::StartActions). */
    }
    dependency stopOrderClause from StopOrder to WstxTransmit::'CL-111-03';
    dependency transmitStateClause from TransmitArming to WstxTransmit::'CL-111-01';
    enum def TransmitOutcomeKind { enum accepted; enum replaced; enum started; enum completed; enum halted; enum refused; enum failed; enum aborted; }
    attribute def TransmitOutcome {
        attribute outcomeSequence : Integer;
        attribute requestSequence : Integer;
        attribute kind : TransmitOutcomeKind;
        attribute refusal : TransmitRefusal[0..1];
        attribute failure : TransmitFailure[0..1];
        attribute audioStartUtcMs : Integer[0..1];
        doc /* started is reported at audio start, completed after the last sample and the
             confirmed PTT release, halted after HaltTransmit. refused (except
             duplicateSequence and audioStarted) and failed disarm (DisarmCause refused,
             failed, deviceLost or authorityChanged). outcomeSequence orders all outcomes
             of a boot; the consumer reads those after its cursor; the last 32 are
             retained. No outcome is inferred from a client timeout or a lost response. */
    }
    action def HaltTransmit {
        doc /* Immediate priority stop of a transmission or Tune: stops audio without the
             owner lock, releases PTT with readback (TransmitTiming haltMs), cancels the
             pending and next requests (halted) and disarms (DisarmCause halt). Always
             admitted for the selected profile (no boot or revision check), idempotent,
             independent of decode, receive or display congestion
             (ProcessingAndHaltOwnership). Wire: POST /transmit/halt exactly
             {v,profile_id,boot_id,command_id}, 202 {v:1,command_id,halt_state} with
             halt_state stopped (confirmed within 250 ms), pending (not yet confirmed;
             GET /transmit shows the result) or idle (nothing was keyed); a repeated
             command_id returns the same receipt (last 16). */
    }
    action def SetTune {
        in enable : Boolean;
        in safetyRevision : Integer[0..1];
        doc /* CL-111-06. Unmodulated tone at the given Tx offset (200..2950 Hz). Tune on
             is accepted whatever the transmit state, while the transmit capability is
             available, safetyRevision is the station's CL-022 safety revision
             (otherwise notAuthorized) and no request is pending and nothing is on the
             air (otherwise busy). From a run or an MCP client Tune on is refused
             tx_watchdog when no browser action was seen this boot, after a
             repetition-limit stop or after a clear fault (CL-044-14), as an automatic
             start (WstxQsoTransmit::StartActions). It never changes TransmitArming or its
             causes: when the radio, the capability or that revision is lost Tune ends
             with PTT release, and a transmit state that is on stops for the same loss by its own
             rule. Stopped by SetTune(false), which needs no revision, HaltTransmit or
             the tune limit (WstxQsoTransmit::TuneWatchdog, default 90 s, 1..300 s) with PTT
             release. On POST /transmit/command tune takes no revision and is accepted
             only while armed, under the armed revision. */
    }
    dependency tuneClause from SetTune to WstxTransmit::'CL-111-06';
    action def AbortTransmission {
        doc /* #39 (2026-11-04) Abort QSO: the contact consumer's immediate stop of the
             current transmission or Tune: stop audio, release PTT with readback (on
             failure PTT indeterminate, as for every release, and refusal radio_unavailable
             so the operator sees it), report every pending or
             current request as outcome aborted and disarm with the caller's cause. It is
             not HaltTransmit: halt_state and the halt count are unchanged. */
    }
    dependency haltUseClause from TransmitHaltUse to WstxContact::'CL-010-03';
    dependency abortClause from AbortTransmission to WstxContact::'CL-010-03';
    dependency armingPromise from TransmitArming to WstxRequirements::'FR-008';
    dependency authorityPromise from TransmitAuthority to WstxTransmit::'CL-009-03';
    dependency haltClausePromise from HaltTransmit to WstxTransmit::'CL-009-04';

    attribute def StationModeGate {
        attribute stationMode : WstxModeProcessing::Mode[0..1];
        doc /* #11 CL-011-04 (review repair 2026-11-01). The transmit owner holds the
             station's operating mode (WstxQsoTransmit::StationOperatingMode), set by the
             station at every change of that mode (live job start, admitted operating
             selection, owner start) and refreshed by every contact step. A request
             whose mode differs is refused staleRequest at admission (disarming as any
             admission refusal) and, if the mode changes after admission, refused
             staleRequest when its period starts, before PTT is keyed or audio starts
             (a request keyed before audio is released); it is never keyed or played.
             A transmission whose audio already started finishes, as with any disarm,
             and a mode selection is refused busy meanwhile (WstxQsoTransmit::ModeChange).
             The gate does not depend on the 50 ms contact step. Absent stationMode
             (an owner not yet told) gates nothing. */
    }
    attribute def TransmitSafetyPolicy {
        @ModelBindings::Status { build = WstxRequirements::ImplementationState::partial; }
        attribute armedOnStartup : Boolean = false;
        attribute haltWaitsForDecode : Boolean = false;
        attribute mcpMayOverrideLossPolicy : Boolean = false;
        doc /* Transmission is not enabled by the receive baseline. Before hardware
             TX, settle controller/device loss and authority expiry, local stop deadline
             and resource/VOX policy. MCP cannot invent a different safety policy.
             Obtain common authority, prepare selected audio and radio/PTT, schedule,
             then handle completion/halt/failure. Audio failure leaves control-side
             halt/release usable; control failure never fabricates radio-ready state.
             Browser timers or optional display congestion cannot hold transmit authority.
             Settled by #9 slice B (WstxTransmit::TransmitAuthority, TransmitTiming,
             PttControl): per-boot explicit authority, 250 ms halt, release on device
             or CAT loss, off-only recovery, no VOX; physical acceptance remains
             TC-008-002. */
    }
    dependency safetyBoundary from TransmitSafetyPolicy to WstxRequirements::'FR-008';
    requirement 'CL-009-03' {
        doc /* Manage PTT and transmit audio through the station's one transmit owner and
             its explicit transmit authority: arm only by an explicit operator request
             with a current CL-022 grant and the current safety revision on a profile
             with CAT PTT and an exact output device (receive-only commissioning is not
             authority); disarmed at every start; admit, replace (until audio start) or
             refuse TransmitRequests; key CI-V PTT with readback before audio, play the
             48 kHz waveform from its planned sample, release PTT with readback after the
             last sample; Tune and the Tx watchdog; report every TransmitOutcome. The
             automatic CAT lifecycle never emits PTT. Details: WstxTransmit::
             TransmitAuthority, TransmitArming, TransmitRequest, TransmitOutcome,
             TransmitTiming, TransmitClock, PttControl, AudioPlayback, SetTune,
             TransmitWatchdog, TransmitWire. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/transmit/playback.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/transmit/codec.rs"; }
    }
    dependency CL_009_03_to_FR_008 from 'CL-009-03' to 'FR-008';
    dependency CL_009_03_to_FR_009 from 'CL-009-03' to 'FR-009';
    dependency CL_009_03_to_FR_002 from 'CL-009-03' to 'FR-002';
    requirement 'CL-009-04' {
        doc /* Provide an immediate Halt that stops audio and releases PTT with readback
             within 250 ms while CAT answers, cancels pending requests and disarms; make
             audio device loss, CAT errors or timeouts, authority changes, an
             unsynchronized clock and late or stale requests release or never key PTT,
             report an unconfirmed release as indeterminate and recover it off-only, and
             never resume or replay a transmission after a restart or reconnect; after a
             boot, a radio found transmitting before the boot ever keyed gets exactly one
             off-only release with readback. Details: WstxTransmit::HaltTransmit,
             TransmitTiming, PttControl, StartupSafetyRelease, TransmitOutcome. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs"; }
    }
    dependency CL_009_04_to_FR_008 from 'CL-009-04' to 'FR-008';
    dependency CL_009_04_to_FR_006 from 'CL-009-04' to 'FR-006';
    verification 'TC-008-003' {
        doc /* Transmit authority, halt and failure handling
             (Planned on issue #9 as TC-008-001; that ID was taken by #10 for the Tx and
             Tune watchdogs, so the #9 halt/failure case is TC-008-003.)
             Setup: the actual transmit owner on a virtual UTC clock with a recording
             hardware double; the actual CI-V actor against an independent emulated
             IC-7300 peer; the actual station router, CL-022 lifecycle and scripted CI-V
             peer; the contact engine against the actual owner core on the virtual
             clock (contact_tests).
             Steps: request while disarmed; arm with unsupported/unavailable capability,
             a wrong safety revision and without a grant; FT8 request before the period,
             late, stale, misaligned, unsynchronized/unknown clock, bad text and offset,
             duplicate sequence; replacement before and after audio start; a request
             for another period while the pending one is keyed before its audio, also
             from the engine stepping between the key and the audio of a late start
             (#10); halt
             mid-audio on the virtual clock, through the owner thread and through the
             real actor; audio device loss, CAT loss, key timeout, output open failure,
             safety revision change; an end report 300/900 ms late and one seen only
             by an owner step after the deadline; a device that stops consuming half
             way (FT8, late FT8, FT4); the render fill decisions against a modelled
             10 ms engine with and without 40 ms render delays (#49); restart; Tx
             watchdog expiry and Tune limit;
             lifecycle polling with the transmit owner present; malformed and extra-key
             wire bodies, wrong Origin, stale boot, retained command_id.
             Oracles: no PTT or audio call/byte while disarmed or unauthorized or
             without an opened output; PTT bytes exactly FE FE 94 E0 1C 00 01 FD and
             1C 00 00 with 1C 00 readback; open before key at the period start, audio at
             period start + 500 ms with skip 0, late skip (t-500 ms)*48; replaced and
             audioStarted outcomes in order; a request for another period while keyed
             before audio is accepted as the next one, plays in its own period after
             the keyed one, never busy, still armed (#10); halt releases within 250 ms
             and disarms;
             every failure stops audio, attempts release and disarms with its cause; a
             late end report inside the bound completes, stays armed and the next
             request plays; a device that never reports the end is released at audio
             end + 1000 ms (FT8 P+14140 <= P+14500, FT4 P+6340 <= P+7000) as
             audioStalled, disarmed deviceLost; the 100 ms buffer starts the program
             within 30 ms and reports the end within 100 ms without underrun; an
             unconfirmed release is indeterminate and recovered off-only; restart is
             disarmed (startup) with nothing pending; watchdog expiry at the configured
             minute; no poll during the transmit hold; one off-only release on close of
             a keyed connection; exact wire shapes and refusals; a radio in TX at boot
             gets exactly one 1C 00 00 then a 1C 00 readback, a radio in RX at boot sees
             zero setter bytes.
             no audio device,
             radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
        @TestedBy { test = "server/tests/transmit_service.rs; server/src/transmit/transmit_http_tests.rs; server/src/contact_tests.rs"; }
    }
    verification 'TC-008-002' {
        doc /* Physical controlled FT8 transmit
             Setup: separately approved operation on the HB9BLA IC-7300 (COM3, USB Audio
             CODEC) into a dummy load or the station antenna, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), profile
             with control.ptt cat and the IC-7300 USB output, system clock
             synchronized by the station's SNTP measurement (CL-009-05), the radio's own transmit time-out timer set
             (mandatory, e.g. 3 min) and read back before any keying.
             Steps: arm, transmit FT8 messages in both parities, replace before audio
             start, halt mid-transmission, Tune and its limit, pull the USB audio or CAT
             cable during a transmission, restart the station.
             Oracles: PSK Reporter spots of HB9BLA for the transmitted CQ by
             independent receivers (frequency, time); the radio's TX indication, power
             meter and ALC follow PTT; halt and
             each failure end RF within the settled bound; restart does not transmit.
             5 — Tests with external effects and explicit operator consent; HB9BLA radio
             PC, physical IC-7300. Not run by the automated gate. */
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
    }
    requirement 'CL-044-13' {
        doc /* The server pushes the Tx level state (client-server rule of #10): each WebSocket peer with a display subscription receives radio.tx_level {v 1, type radio.tx_level, data {profile_id, boot_id, managed, level_db, stored, alc unknown|available|unavailable, assistant, result, meters null|{alc, po_pct, swr_x10}, power_limit_pct, warnings [...] (CL-044-14), keying_confirmed (CL-044-15)}} after each change; nothing is polled. Settings > Radio > Audio shows, for an IC-7300 CAT control only, a Set level button, a line with the level and the last result, the last ALC, Po and SWR, and the optional Profile power field (settings.radio.power_limit_pct) saved with Apply; the Tx level slider is shown only with alc unavailable. Set level and the slider send POST /radio/tx-level; a refusal is shown on the line. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/radio_level.rs; server/src/main.rs; client/recording.js; client/app.js"; }
    }
    dependency CL_044_13_to_FR_019 from 'CL-044-13' to 'FR-019';
    dependency CL_044_13_to_FR_009 from 'CL-044-13' to 'FR-009';
    // Operator decision 2026-11-04 (#44 comment 6628026397): monitoring in normal operation.
    // Operator decision 2026-11-06 (#44, live ALC 31-32 at Po 102 %): the level lowers above ALC 10.
    requirement 'CL-044-14' {
        doc /* In normal operation the station reads the radio's meters exactly once per transmission, in the middle of its audio: the transmit step calls the read when half of the audio remaining at audio start has played, once per transmission, on no Tune, and not at all when less than 2 s of audio remained at audio start. The call returns at once and the burst (CL-044-12: 15 13, 15 11, 15 12) runs on its own thread, so the transmit step, the audio and the release never wait for the radio, and a PTT exchange cancels the burst. Nothing is read while Set level runs. From the reading the level moves by at most one step, stored like CL-044-12 and taken by the next transmission's audio start only: ALC above raw 0010 or Po above the profile power: one down, not below -40 dB; else ALC exactly 0 and Po below 80 % of the profile power: one up, not above 0 dB and not back to the ceiling; otherwise unchanged. A lowering on the reading right after a step up makes the level just left the ceiling, so a level reading 0 below a level reading above 0010 settles on the lower one; any other lowering leaves the step up free, so the level follows a drive that falls later. The ceiling lives in memory until a stored Set level, a changed profile power or a restart. Set level's stop (CL-044-12, ALC 0, one step below the first rise) is inside this window, and one step up from it, the ALC onset (reads 4-7, about 6 per dB on the IC-7300), stays inside it. Without a profile power Po is neither over nor low, so there is no step up. Persistent trouble is an entry in the error field, from the third transmission in a row until a reading without it: alc_high (ALC at or above raw 0060, half the ALC zone; lowering below that is routine and shows no entry), po_low (Po below half the profile power), swr_high (SWR at or above 2.0, raw 0080). A clear fault, SWR at or above 3.0 (raw 0120), stops transmitting at once through the priority halt (DisarmCause halt) with the entry swr_fault, and automation may not arm again until an operator action (WatchdogFromOperator); the entry stays until a later reading below 3.0 or a stored Set level. The radio.tx_level data carries these as warnings [...]. A failed read judges nothing. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/radio_level.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; client/recording.js; client/contact.js"; }
    }
    dependency CL_044_14_to_FR_009 from 'CL-044-14' to 'FR-009';
    verification 'TC-044-017' {
        doc /* One meter read per transmission and its bounded correction
             Setup: the actual transmit core on a virtual clock; the actual Recording, transmit owner on a recording double and CAT actor on a scripted IC-7300 reporting set meter values.
             Steps: (a) the decision table; (b) two FT8 transmissions and a Tune on the virtual clock; (c) the call without the hold, then with ALC 0060; (d) three transmissions in a row, then a good one; (e) SWR 0120, a reading without SWR, then the operator arms and SWR is clear; (f) the call while Set level runs; (g) the transmit step's call through the station's boxed hardware to the sink, and the sink startup installs; (h) ALC 0060 with the level file unwritable; (i) a radio reading ALC 0 at -10 dB and 0011 at -9 dB with low Po, 40 transmissions; (j) ALC 0031 at -9 dB moving 6 per dB, 40 transmissions; (k) Set level and then the correction on a radio with ALC 0 up to -9 dB and 0007 at -8 dB, rising 6 per dB, with low Po; (l) a step up, ALC 0011 and then 0 with low Po, the same profile power and then a changed one, again a step up and ALC 0011, and a stored Set level at the ceiling; (m) ALC 0013 with no step up before it, then ALC 0 twice with low Po, then 0005, 0013 and 0.
             Expected: (a) one down at ALC 0011, none at 0010, no warning from three readings of 0059, the floor and 0 dB hold, one up only with ALC 0 and Po below 80 %, none without a profile power, one down above it, none without ALC, fault at 0120 and not at 0119, warnings from the third reading, cleared by one good reading; (b) due exactly once at period + 6 820 ms in each, none for Tune, none for audio starting at period + 11 200 ms; (c) no byte without the hold; with it exactly 15 13, 15 11, 15 12, level -11 stored, nothing handed to the running audio; (d) alc_high from the third, level -13, gone with the good one; (e) one halt, disarmed halt, automation refused, entry swr_fault; the entry stays with the reading without SWR; after the clear reading no entry and still armed; (f) no byte; (g) one call reaches the sink, one burst from the installed sink; (h) the level stays -10, stored false, and the next Tune plays -10; (i) -10 dB for good after at most two transmissions from -10 dB and three from -9 dB, no warning; (j) -10, -11, -12, -13 dB and then unchanged, no warning; (k) Set level stores -9 dB, the correction takes it to -8 dB and stays, from -7 dB it comes back to -8 dB and stays; (l) the level stays with ALC 0 and the same profile power, and goes up one after the changed profile power and after the stored Set level; (m) -13, -12, -11, -11, -12, -11 dB.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-14';
        }
        @TestedBy { test = "server/src/radio_level_tests.rs; server/src/transmit/transmit_http_tests.rs; server/tests/transmit_service.rs"; }
    }
    verification 'TC-044-018' {
        doc /* Tx trouble in the error field
             Setup: candidate server and Chromium; radio.tx_level events injected.
             Steps: inject the four warnings, then none.
             Expected: one error field entry each, swr_fault with error severity and the others warn, all gone after the empty list.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-14';
        }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-044-019' {
        doc /* Monitoring on HB9BLA
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's consent, 40 m, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). The mismatched-antenna / SWR 3.0 stop step is dropped by operator decision of 2026-11-08 ("bad SWR is handled by the transceiver"); the station's own stop at and above SWR 3.0 stays (CL-044-14), covered offline; the SWR display is #68.
             Steps: transmit during normal operation and record the radio.tx_level frames and the transmit timing; transmit with ALC above 0010. The evidence is the CI-V readback and the radio.tx_level frames, not the radio's display or a CI-V log (operator decision of 2026-11-08; the station keeps no CI-V log).
             Expected: at most one radio.tx_level meter frame per transmission (sent only when the values change); decode by another station unaffected; ALC above 0010 goes down one step at the next transmission until it reads 0010 or less, with no entry below 0060.
             Not run by the automated gate. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; method = "manual"; }
        objective {
            verify 'CL-044-14';
        }
    }
    verification 'TC-044-015' {
        doc /* Tx level in Settings > Radio > Audio
             Setup: candidate server and Chromium; radio.tx_level events injected, POST /radio/tx-level answered by a route fixture.
             Steps: open the Audio section for an IC-7300 CAT control; inject meters, a run, its result, alc unavailable; click Set level; move the slider; save a power limit; hide for a disabled control; 360 px.
             Expected: the button is in #settings-audio, no slider before alc unavailable, the line and meters show the pushed values, a malformed event is ignored, the click sends exactly one set_level, the slider sends one manual, Apply saves radio.power_limit_pct, all of it hidden when control is Disabled, no horizontal overflow at 360 px.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-13';
        }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }

    // The transmit state, its start actions and its stops (WstxTransmit::TransmitArming,
    // WstxContact::StartActions).
    requirement 'CL-111-01' {
        doc /* Transmit state. The station has one transmit state, on or off, with the cause of its last change in both directions. It is off at every station start (cause startup). It is on only from an accepted start action (CL-111-02) until the next stop (CL-111-03). While it is off no TransmitRequest is planned or keyed. A selection, a setting, a chosen Next message, a reconnect, a reload, a repeated command and a partner message never switch it on. Not delivered yet: three commands still switch the state on directly, and each is to be retired: the contact command enable_tx, through which the browser and the runs still start; the Set level assistant, which switches the state on (cause operator, ending a repetition-limit stop) and off around its tone; and the arm command of the transmit route. Details: WstxTransmit::TransmitArming. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/contact.rs"; }
    }
    dependency CL_111_01_to_FR_007 from 'CL-111-01' to 'FR-007';
    dependency CL_111_01_to_FR_008 from 'CL-111-01' to 'FR-008';
    requirement 'CL-111-03' {
        doc /* Stops. A completed, cancelled or stopped sequence does not transmit: the state goes off with the cause of the stop, the pending request is dropped, and nothing is sent until the next start. Stop: cause; transmission on the air; what stays of the QSO. QSO completed: contactCompleted; none; completed, logged once. Cancel contact, F4: contactCancelled; finishes; cancelled, an own CQ becomes idle. Abort QSO, Esc: contactCancelled; stops now, no halt; cancelled. Halt Tx, Alt+H, MCP halt: halt; stops now; state kept, an own CQ ends. Repetition limit (Tx watchdog): txWatchdog; none keyed; state kept, an own CQ ends. Partner works another station on the own Tx frequency: partnerWorksOther; stops now by an abort, no halt; state kept (a contact that pauses for a busy partner moves Tx clear instead and stops only when that move is refused, CL-097-06). Mode change: modeChanged; as CL-011-04; cancelled. Band change: bandChanged; finishes, and a band selection in the program is refused busy during a transmission; cancelled as by a mode change: DX call and Tx1 to Tx5 cleared, Tx6 next, an own CQ becomes idle, a completed QSO keeps its fields. Radio or capability lost: deviceLost; released; state kept. Safety revision changed: authorityChanged; state kept. Refused or failed transmission: refused, failed; state kept. A run ends and leaves a contact it did not finish or cancel, with no other stop of this list: runEnded; finishes; state kept. A band change is any change of the station band the station sees: the station band (the radio's dial band, else the band of the operating selection) differs from the band the contact was prepared on. It covers a band selection in the program and a change at the radio's own dial. An unknown station band is no band change. The band-change stop shows bandChanged in every case, also when a run's contact is ended by it. The run's own stop reason stays (a pounce: band_changed). A pounce run's contact is cancelled like every other. A stop is admitted with any earlier contact revision, as cancel and abort are. In one station step any stop wins over any start: the start is refused state_conflict and nothing is sent. When several stops arrive in one step the shown cause is the first of: halt; deviceLost, authorityChanged, failed, refused; Abort QSO (contactCancelled); txWatchdog; partnerWorksOther; bandChanged, modeChanged, runEnded, Cancel contact (contactCancelled); contactCompleted. After a stop with the state kept, the QSO continues only by Reply on the partner's row or by "Send <exchange> next"; after a repetition-limit stop also by Reset. Enter in the DX call field does not continue a stopped QSO. An own CQ ended by the repetition limit is started again with the CQ button. Not delivered yet: no run raises runEnded, and a run that is neither a strategy nor a pounce stops contact_changed when the band change ends its contact. Details: WstxTransmit::StopOrder, WstxQsoTransmit::BandChange, ModeChange, AutoSequence. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs"; }
    }
    dependency CL_111_03_to_FR_007 from 'CL-111-03' to 'FR-007';
    dependency CL_111_03_to_FR_008 from 'CL-111-03' to 'FR-008';
    requirement 'CL-111-06' {
        doc /* Tune. tune {enabled, safety_revision}. Tune on is accepted whenever the transmit capability is available with a current grant and nothing is on the air or pending, whatever the transmit state. It is refused stale_revision with field safety_revision on another revision than the station's, busy while a transmission is keyed or a request is pending, transmit_unavailable without capability or grant. From an MCP client or a run it is refused tx_watchdog as an automatic start (CL-111-02): when no browser action was seen this boot, after a repetition-limit stop or after a clear fault (CL-044-14). Tune never changes the transmit state or its cause. The Tune watchdog is unchanged (default 90 s, 1..300 s). Tune off needs no revision. Details: WstxTransmit::SetTune. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; client/contact.js"; }
    }
    dependency CL_111_06_to_FR_008 from 'CL-111-06' to 'FR-008';
    verification 'TC-111-001' {
        doc /* The new causes and the resume
             Setup: the contact engine against the actual transmit owner core on a virtual UTC clock with hand-authored rows (transmit_state_tests on the bench of contact_tests), profile HB9BLA JN47; a QSO with K1ABC in replying, the state on, Tx1 sent once. For (c) the station with a run (strategy_tests).
             Steps: (a) the partner's message to another call within 50 Hz of my Tx frequency, in a contact that does not pause for a busy partner (an MCP policy run's contact, CL-097-06; a manual contact moves Tx clear instead, TC-097-017). (b) a mode change. (c) a run ends leaving its contact. (d) after each state-kept stop (Halt, the limit, partner works another as in (a), radio lost, refused): 3 own periods, then reply on the partner's row.
             Expected (the stop table of CL-111-03): (a) off, partnerWorksOther, state kept. (b) modeChanged, cancelled. (c) runEnded, state kept. (d) no request in the 3 own periods, then the reply transmits again with the same contact identity.
             Automated: (a), (b), (d). Not automated yet: (c).
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-002' {
        doc /* What is not a start never transmits
             Setup: as TC-111-001, from a station start; for the reload and the repeated command_id the actual station router (contact_http_tests fixture).
             Steps: select_row, enter_dx, choose_next, set_frequency, every setting, snapshot reload, reconnect, a repeated command_id, a partner message while off.
             Expected (CL-111-01): zero requests over 3 own periods, state and cause unchanged.
             Not automated yet: the reconnect.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-01';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-007' {
        doc /* Wire
             Setup: the actual station router (contact_http_tests fixture).
             Steps: GET /contact and the transmit.state event at a station start, after a start and after a stop; the largest snapshot and the first event with the longest cause of each direction.
             Expected (WstxQsoControl::ContactSnapshot, WstxTransmitControl::TransmitWire): the transmit view carries the causes of CL-111-03 as snake_case values and last_arm_cause (operator, auto or null); the largest snapshot stays at most 4096 bytes and the event at most 1024.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-01';
        }
        @TestedBy { test = "server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-009' {
        doc /* A band change stops and cancels
             Setup: as TC-111-001, the station band 20m; for the selection, the dial and the runs the actual station router (contact_http_tests, strategy_tests).
             Steps: (a) QSO in rogerReport, state on, admitted selection 20m to 40m. (b) the same QSO, the radio's dial moved to 7.074 MHz with no selection. (c) own CQ. (d) completed QSO. (e) a selection of the same band, a dial change inside the band, and an unknown station band. (f) a selection during a transmission. (g) a strategy run's contact at a dial band change. (h) a pounce run in its contact.
             Expected (CL-111-03): (a) off, bandChanged, cancelled, DX call cleared, no request in 3 periods. (b) the same. (c) idle, off. (d) fields kept. (e) nothing changes. (f) busy, QSO and state unchanged (guard, TC-044-023). (g) cancelled, cause bandChanged. (h) run stopped band_changed, contact cancelled, cause bandChanged.
             Automated: (a) and (b) as the station band at the engine and as the band of the operating selection at the station, (c), (d), (e); the dial as the station band is shown for a run's own CQ (TC-063-010). Not automated yet: (b) for a QSO at the station, (g), (h).
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-010' {
        doc /* Tune
             Setup: as TC-111-001.
             Steps: (a) state off, no contact, ready: Tune on; Tune off. (b) a stale safety revision. (c) a request pending, and a transmission on the air. (d) no capability, and no grant. (e) reply while Tune is on; Tune ends; 3 periods. (f) the Tune watchdog at 1 s. (g) Tune on from an MCP principal at boot before any browser action, after a browser action, after a clear fault (require_operator), and after a repetition-limit stop.
             Expected (CL-111-06): (a) keyed, state and cause unchanged; released. (b) stale_revision, not keyed. (c) busy. (d) transmit_unavailable. (e) accepted, QSO prepared, refusal busy, state off, nothing sent. (f) Tune ends (guard, TC-008-001). (g) tx_watchdog and not keyed at boot, after the clear fault and after the limit; keyed after the browser action.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-06';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-013' {
        doc /* A stop wins
             Setup: as TC-111-001.
             Steps: stop against start in one station step: Halt and reply; the limit and send_next; a band change and call_cq. Two stops in one step: Halt and radio lost; radio lost and Abort QSO; Abort QSO and the limit; the limit and partner works another; partner works another and a band change; Cancel contact and the limit; a band change and completion. The partner-works-other steps run in a contact that does not pause for a busy partner (an MCP policy run's contact, CL-097-06), as TC-111-001 (a).
             Expected (the order of CL-111-03): the start is state_conflict, state off, nothing keyed. Shown cause of the two stops, in the order of the steps: halt; deviceLost; contactCancelled; txWatchdog; partnerWorksOther; txWatchdog; bandChanged.
             no radio or RF. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs"; }
    }
}
