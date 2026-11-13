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
    private import WstxRequirementsFrontend::'CL-037-02';
    private import WstxRequirements::'FR-019';
    private import WstxTxLevel::'TC-044-014';
    private import WstxTxLevel::'TC-044-016';
    private import WstxRequirements::'TC-039-007';
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'TC-111-008';
    private import WstxRequirementsQso::'CL-111-02';
    private import WstxRequirements::'CL-111-04';
    private import WstxRequirementsQso::'CL-111-08';
    private import WstxRequirements::'FR-010';
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
    enum def ClockState { enum synchronized; enum unsynchronized; enum unknown; }
    enum def PeriodParity { enum even; enum odd; }
    // ------------------------------------------------------------------
    // #9 slice B transmit owner (delivered; consumer contract of WstxContact #10,
    // supervisor decision 2026-10-31 on #10). Implementation:
    // server/src/transmit/service.rs (owner), server/src/radio_control/actor.rs and
    // executor.rs (PttControl), server/src/playback.rs (AudioPlayback),
    // server/src/transmit_http.rs (station hardware, TransmitWire).
    enum def ArmState { enum disarmed; enum armed; }
    enum def DisarmCause {
        enum operator; enum halt; enum contactCompleted; enum contactCancelled;
        enum txWatchdog; enum refused; enum failed; enum deviceLost; enum startup;
        enum authorityChanged;
        enum partnerWorksOther; enum modeChanged; enum bandChanged; enum runEnded;
    }
    enum def ArmCause { enum operator; enum auto; }
    enum def TransmitRefusal {
        enum transmitUnsupported; enum notArmed; enum audioStarted; enum duplicateSequence;
        enum staleRequest; enum clockNotSynchronized; enum misalignedPeriod; enum stalePeriod;
        enum packRefused; enum frequencyOutOfRange; enum busy; enum notAuthorized;
        enum radioUnavailable;
    }
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
        doc /* The station's explicit transmit authority (WstxArchitecture::RadioAuthority),
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
             owned by WstxArchitecture::TransmitService; off at startup and after every
             DisarmCause. lastArmCause is who switched it on last (operator, or auto for
             a run or an MCP client) and is absent until the first switch-on of a boot.
             Arm/Disarm are requests from QsoAndLogging (the start actions
             WstxContact::StartActions, and Enable Tx) through the qso-to-transmit
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
             (WstxContact::AutoSequence, every 50 ms and directly after each accepted
             ContactCommand) to the begin of the next. When several stops are applied in
             one station step, lastDisarmCause is the first of this order, whichever
             arrived first: halt; deviceLost; authorityChanged; failed; refused;
             contactCancelled by Abort QSO; txWatchdog; partnerWorksOther; bandChanged;
             modeChanged; runEnded; contactCancelled by Cancel contact;
             contactCompleted; operator. A switch-on between two stops of a step begins
             the choice anew. A start action that arrives after a stop of the same
             station step is refused state_conflict (WstxContact::StartActions). */
    }
    dependency stopOrderClause from StopOrder to WstxTransmit::'CL-111-03';
    dependency transmitStateClause from TransmitArming to WstxTransmit::'CL-111-01';
    attribute def TransmitRequest {
        attribute contactId : String[0..1];
        attribute requestSequence : Integer;
        attribute mode : WstxOfflineDecode::Mode;
        attribute periodStartUtcMs : Integer;
        attribute messageText : String;
        attribute txOffsetHz : Integer;
        doc /* At most one request per station waits to be keyed. Admitted only
             while armed under TransmitAuthority; the service packs messageText
             (PackMessage), plans the start (PlanTransmitStart), encodes the 48 kHz
             waveform, keys PTT and plays (TransmitTiming). requestSequence is a
             strictly increasing safe integer per boot: a lower or equal sequence is
             duplicateSequence, never transmits twice and changes nothing (a retry does
             not disarm). A new admitted request REPLACES the pending one (replaced)
             while its audio has not started; a keyed request is replaced only by one
             for the same period. From keying a request for another period becomes the
             next pending request, started after the current one completes, and from
             audio start one for the same period is refused audioStarted (no disarm):
             the keyed request never makes another one busy or disarms (#10).
             Clock, alignment and lateness refusals (clockNotSynchronized,
             misalignedPeriod, stalePeriod) and packRefused or frequencyOutOfRange are
             checked at admission; the start is planned again at keying and at audio
             start, so a request that became stale is refused, never replayed. A
             request of another boot is refused at the wire (state_conflict). */
    }
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
             start (WstxContact::StartActions). It never changes TransmitArming or its
             causes: when the radio, the capability or that revision is lost Tune ends
             with PTT release, and a transmit state that is on stops for the same loss by its own
             rule. Stopped by SetTune(false), which needs no revision, HaltTransmit or
             the tune limit (WstxContact::TuneWatchdog, default 90 s, 1..300 s) with PTT
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
    attribute def TransmitHaltUse {
        doc /* HALT is the operator's emergency stop only (operator decision #39,
             2026-11-04): the browser HALT buttons and Alt+H, and the remote emergency
             stop MCP wstx_transmit_halt (UDP is send-only and has no Halt Tx, CL-040-03).
             The station and its automation
             never send HaltTransmit in normal flow: a completed contact and ending a run
             disarm, the partner-works-other stop and Abort QSO use
             AbortTransmission. */
    }
    dependency haltUseClause from TransmitHaltUse to WstxRequirements::'CL-010-03';
    dependency abortClause from AbortTransmission to WstxRequirements::'CL-010-03';
    attribute def TransmitWatchdog {
        doc /* WstxContact::TxWatchdog (#39, 2026-11-06): the owner holds the limit, 1..99
             repetitions (default 6 at each start), and no count: the contact consumer
             compares its dialogue Rep with the limit and reports that Rep for
             tx_remaining_calls (the Tx watchdog's only; a strategy run's own contact, which has
             no stop while attended, reports none: WstxStrategy::StrategyWatchdog, LeaveCountLabel;
             a busy partner's paused calls are not counted: WstxContact::BusyPartner). GET /transmit
             watchdog.tx_remaining_calls is therefore an integer or null: null exactly while armed for
             such a contact (never the leave count and never the limit minus the Rep as a fallback);
             0 while disarmed as before. The receive page's transmit line (recording) shows "WD <n>
             calls" for an integer and leaves the WD part out for null; MCP wstx_read passes it on. At the consumer's stop the owner disarms (txWatchdog)
             without keying, so PTT is never keyed for that send and no halt happens (HALT
             is the operator's emergency stop only), and reports tx_expired until the next
             Arm. A request submitted directly on the transmit route has no dialogue and
             is not bounded by it: each one is its own browser request. */
    }
    dependency armingPromise from TransmitArming to WstxRequirements::'FR-008';
    dependency authorityPromise from TransmitAuthority to WstxTransmit::'CL-009-03';
    dependency haltClausePromise from HaltTransmit to WstxTransmit::'CL-009-04';

    attribute def StationModeGate {
        attribute stationMode : WstxOfflineDecode::Mode[0..1];
        doc /* #11 CL-011-04 (review repair 2026-11-01). The transmit owner holds the
             station's operating mode (WstxContact::StationOperatingMode), set by the
             station at every change of that mode (live job start, admitted operating
             selection, owner start) and refreshed by every contact step. A request
             whose mode differs is refused staleRequest at admission (disarming as any
             admission refusal) and, if the mode changes after admission, refused
             staleRequest when its period starts, before PTT is keyed or audio starts
             (a request keyed before audio is released); it is never keyed or played.
             A transmission whose audio already started finishes, as with any disarm,
             and a mode selection is refused busy meanwhile (WstxContact::ModeChange).
             The gate does not depend on the 50 ms contact step. Absent stationMode
             (an owner not yet told) gates nothing. */
    }
    attribute def TransmitSafetyPolicy {
        attribute coverage : WstxRequirements::ImplementationState = WstxRequirements::ImplementationState::partial;
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
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/playback.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/radio_control/codec.rs";
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
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs";
    }
    dependency CL_009_04_to_FR_008 from 'CL-009-04' to 'FR-008';
    dependency CL_009_04_to_FR_006 from 'CL-009-04' to 'FR-006';
    verification 'TC-008-003' {
        doc /* TC-008-003 — Transmit authority, halt and failure handling
             CL-009-03, CL-009-04
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
             2 — Isolated automated tests; Windows development PC, no audio device,
             radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
        attribute executable : String = "server/tests/transmit_service.rs; server/src/transmit_http_tests.rs; server/src/contact_tests.rs";
    }
    verification 'TC-008-002' {
        doc /* TC-008-002 — Physical controlled FT8 transmit
             CL-009-03, CL-009-04
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
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
    }
    dependency CL_009_03_verified_by_TC_008_003 from 'CL-009-03' to 'TC-008-003';
    dependency CL_009_04_verified_by_TC_008_003 from 'CL-009-04' to 'TC-008-003';
    dependency CL_009_03_verified_by_TC_008_002 from 'CL-009-03' to 'TC-008-002';
    dependency CL_009_04_verified_by_TC_008_002 from 'CL-009-04' to 'TC-008-002';
    requirement 'CL-009-05' {
        doc /* Determine the station clock state for transmit from the station's own SNTP
             measurement, off the transmit and audio threads, at start and every 60 s
             with the servers ch.pool.ntp.org, time.windows.com, pool.ntp.org in that
             order (the next when one does not answer validly within 1.5 s):
             synchronized when the latest measurement is at most 10 min old and its
             |offset| is at most 500 ms, unsynchronized when outside, unknown without a
             recent measurement or when the system clock stepped by more than 100 ms
             since it; report the offset, server and age on GET /transmit and with the
             transmit state in the browser. #43, #92 (operator 2026-11-09: "we always
             know the time. It just might be wrong ... never an unknown time"; "accept
             the OTA time as the reference"): transmit is admitted by the station clock
             state of CL-043-03, which is never unknown and does not depend on this SNTP
             state: unsynchronized only while the stations heard show the station clock
             more than 1 s off to one side, otherwise synchronized. This SNTP state only
             gives the warnings pc_clock_off and ntp_unreachable (CL-043-03); it never
             refuses transmit and its offset is never applied.
             GET /transmit also reports clock_warning. Details:
             WstxTransmitClock::TransmitClock, AirClock, TransmitWire. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/clock.rs; server/src/transmit/air.rs; server/src/transmit_http.rs; server/src/main.rs; client/recording.js";
    }
    dependency CL_009_05_to_FR_006 from 'CL-009-05' to 'FR-006';
    verification 'TC-006-003' {
        doc /* TC-006-003 — Station SNTP clock measurement
             CL-009-05, CL-009-02
             Setup: hand-computed NTP timestamps; fake SNTP responders on 127.0.0.1
             (silent, kiss-of-death stratum 0, answering a fixed offset ahead of the
             request) with a fake station clock; a scripted blocking measurement
             source; the actual station router with an injected clock monitor.
             Steps: compute offsets and round trips including an NTP era boundary;
             present short, wrong-mode, stratum 0/16, zero-transmit, wrong-origin and
             leap-alarm replies; measure over silent, refusing, answering and later
             servers; a fake station clock stepping +10 s during the exchange; derive
             states at |offset| 500/501 ms, ages 10 min / 10 min + 1 ms and system
             clock steps of +-100/+-101/+-2000 ms after the measurement; plan FT8 and
             FT4 starts with each derived state; read the state while a measurement
             blocks; GET /transmit before and after measurements; the browser transmit
             status with a transmit.state fixture.
             Oracles: RFC 4330/5905 arithmetic by hand (590/20 ms, -705/10 ms, 495/10
             ms); every invalid reply refused, stratum 1 and 15 accepted; servers asked
             once each in order, none after the first valid answer, none answering
             gives no measurement; a step during the exchange leaves the offset at
             3 s (not -2 s); 500 ms synchronized, 501 ms unsynchronized, older than
             10 min unknown, a step above 100 ms unknown; only synchronized admitted (else
             clockNotSynchronized); reading never waits for a measurement; exact
             clock_measurement keys {server,offset_ms,round_trip_ms,age_ms}, null and
             unknown before the first answer; the status reads "clock synchronized
             +12 ms ch.pool.ntp.org 34 s ago".
             2 — Isolated automated tests; Windows development PC, loopback UDP only, no
             public time server, audio or radio; the actual server and Chromium for the
             status line. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-009-05';
            verify 'CL-009-02';
        }
        attribute executable : String = "server/tests/transmit_clock.rs; server/src/transmit_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_009_05_verified_by_TC_006_003 from 'CL-009-05' to 'TC-006-003';
    dependency CL_039_06_verified_by_TC_020_004 from 'CL-039-06' to 'TC-020-004';

    // #43 Optional clock from the air (defaults chosen on the CR, recorded in AirClock).
    requirement 'CL-043-01' {
        doc /* (#43; #92 operator 2026-11-09: the three situations of CL-043-03 are fixed
             behaviour; "accept the OTA time as the reference") The station clock has no
             source setting and no basis: station UTC is always the system clock plus
             the correction from the air (CL-043-02/03); NTP only measures the system
             clock. clock.json (#43) is no longer read or written; a file left by #43 is
             ignored and left in place. POST /clock no longer exists (the router's answer
             for an unknown route), and GET /transmit has no clock_source. GET /clock
             (operating access, no query, empty body) returns exactly {v 1, profile_id,
             boot_id, state synchronized|unsynchronized (never unknown), correction_ms,
             ntp {state, measurement null | {server, offset_ms, round_trip_ms, age_ms},
             windows_time running | stopped | disabled | unknown}, air {estimate null |
             {median_dt_ms, stations, plus, minus, age_ms}}, warning null | pc_clock_off
             | ntp_unreachable | stations_off, capture_warning null | uncorrelated |
             drift_high, clock_revision}. Pushed state (#92 operator 2026-11-09
             "Everywhere"; WstxStationProtocol::PushedStationState): a WebSocket event
             exactly {v:1, type:"clock.state", data:{profile_id, boot_id,
             clock_revision, clock:{state, correction_ms, warning, ntp_offset_ms,
             capture_warning}}}, at most 512 bytes, for every profile (receive-only
             too), sent to each peer with a display subscription once after its first
             subscription and then when a field of clock changes, coalesced to at most
             one per second per peer and sent within 1 s of the change; clock_revision is
             a station-wide safe integer increasing at each change of those fields (GET
             /clock carries the same value); ntp_offset_ms is the SNTP offset while
             warning is pc_clock_off, else null, so a healthy clock sends no event per
             SNTP round. The browser holds the clock state from these events (no GET
             /clock and no timer for it). The operator view is Settings > General >
             Clock: a status line with state, correction, the median DT of the stations
             heard, how many are heard and how many are above +0.1 s and below -0.1 s,
             its age, the SNTP offset, the warning text and remedy of CL-043-03; for
             these details the browser reads GET /clock only when the
             Settings drawer opens (at most every 10 s) or the General tab is chosen,
             never on a timer, so the thin link carries no clock polling. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/clock_http.rs; server/src/main.rs; server/src/recording.rs; server/src/transmit_http.rs; client/contact.js; client/recording.js";
    }
    dependency CL_043_01_to_FR_006 from 'CL-043-01' to 'FR-006';
    dependency CL_043_01_to_FR_016 from 'CL-043-01' to 'FR-016';
    requirement 'CL-043-03' {
        doc /* (#43; #92 operator 2026-11-09: "we always know the time. It just might be
             wrong ... never an unknown time"; "computer time not NTP time --> try to fix
             and if not possible, warning; WSJTX time not computer time --> try to fix
             and if not possible, warning"; "I think we should accept the OTA time as the
             reference because this is what counts. If other stations report differences
             in one direction, then for sure our station is wrong. And we have to do
             something against it."; "Our station should always be in the middle ... If
             the other stations show plus and minus, then we do not have to react"; the
             200 ms NTP/air disagreement warning: "Drop it") Three situations, each fixed
             where the station can and otherwise warned.
             (1) PC clock against NTP: the SNTP state of CL-009-05. The station never
             sets the Windows clock and never starts or configures a service (it runs
             without administrator rights); it reads the Windows Time service state
             (running, stopped or disabled; unknown when the query fails) without
             administrator rights and names the remedy. Warning pc_clock_off while the
             SNTP state is unsynchronized; else ntp_unreachable while at least one SNTP
             round since start has asked a server and no valid measurement is at most
             600 s old (not in the gap after a detected step, before the first round
             ends or with an empty server list).
             (2) Station time against the PC clock: the capture clock is re-anchored to
             the PC's UTC by CL-007-05 (#47), which is the fix; the applied correction
             of (3) is a deliberate difference, shown in the status line, never warned.
             capture_warning (the station, only while live receive runs; operator
             2026-11-09 "Also on large drift"): uncorrelated while a capture epoch exists
             and its clock is not correlated to UTC (no re-anchoring possible; null while
             no epoch exists yet, so a receive start or restart is no entry, CL-037-02),
             else drift_high while
             |capture_drift_ppm| (CL-007-05, known after the first 60 s) is above 1000 ppm
             (at 1000 ppm the audio frequency error reaches a quarter of the FT8 tone
             spacing at 1500 Hz, 1.5 of 6.25 Hz, and the drift within one FT8 period
             15 ms; a sound card crystal is normally within 100 ppm), else null.
             (3) Out of step with the stations heard, the reference on every SNTP state:
             each completed live decode window (prompt and late) re-estimates
             (CL-043-02); the latest estimate counts while at most 60 s old and
             unstepped. When it is evidence (at least 4 stations, at least 80 % of them
             on one side by more than 100 ms) the correction moves toward the middle,
             correction minus median_dt_ms, by at most 1000 ms in total within one period
             of the current mode; with mixed sides, fewer than 4 stations or no estimate
             it does not change: the last correction is kept. The correction starts at 0
             at station start; a system clock step is handled as CL-043-02; there is no
             search (no change without evidence). The SNTP offset is never applied and
             the Windows clock is never set. Station UTC is always the system clock plus
             the correction, used alike for live receive window alignment,
             period_start_utc and DT of results (in addition to the capture drift, #47),
             transmit planning and audio start (CL-009-02), the contact engine and UDP
             times. The station clock is never unknown: unsynchronized while the latest
             counting estimate is evidence with |median_dt_ms| above 1000 ms (FT8 still
             decodes within about +-1 s), else synchronized, whatever the SNTP state.
             Transmit is refused for the clock (clock_not_synchronized) only while the
             station clock is unsynchronized, never for a smaller one-sided offset while
             the correction catches up. Because each vote is taken from raw DT plus the
             current correction, the correction converges to the middle without
             oscillating; with the live window coverage of corrected DT (-1.7 s to
             +2.56 s) it finds system clock errors of about -2.5 s to +1.7 s; outside
             them too few stations decode, there is no evidence and the time is
             accepted. stations_off (#92 operator 2026-11-09 "Note above 500 ms"):
             while the SNTP state is synchronized and |correction| is above 500 ms, the
             cause lies outside the PC clock (for example audio latency).
             GET /clock warning and GET /transmit clock_warning carry the same value, the
             first that holds of pc_clock_off, ntp_unreachable, stations_off. Error field
             entries (CL-037-02), from clock.state (CL-043-01): while transmit is
             configured "Clock off · Tx blocked" (error) while the station clock is
             unsynchronized; for every profile (operator 2026-11-09 "Everywhere") one warn
             entry per warning and capture_warning, also while transmit works:
             pc_clock_off "PC clock <n> ms slow vs
             NTP · see Settings" ("fast" for a negative offset, n = |SNTP offset_ms|),
             ntp_unreachable "NTP not reachable · check the network", stations_off
             "Clock corrected <c> ms from the air · PC clock matches NTP, check audio
             latency" (c = correction_ms with sign); uncorrelated "Audio timing not tied to the
             PC clock · DT may be off"; drift_high "Sound card clock drifts over
             1000 ppm · check the audio device". The clock entries open Settings >
             General > Clock, the audio entries the receive details (which read GET
             /receive/clock on demand); each disappears when its condition clears. The Settings clock status
             line appends the warning text and for pc_clock_off the remedy by
             windows_time: stopped "Windows Time service is stopped: start it and set it
             to Automatic (services.msc, as administrator)"; disabled "Windows Time
             service is disabled: set it to Automatic and start it (services.msc, as
             administrator)"; running "Windows Time runs but the clock is off: Settings >
             Time & language > Date & time > Sync now"; unknown "Check the Windows Time
             service and sync the clock". GET /transmit clock_warning keeps carrying the
             warning value for other clients. Without evidence and with correction 0 the status line reads
             "Clock accepted (stations heard are not off to one side)" instead of the
             synchronized wording. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/air.rs; server/src/transmit/clock.rs; server/src/transmit/windows_time.rs; server/src/clock_http.rs; server/src/recording.rs; server/src/transmit_http.rs; server/src/main.rs; client/contact.js; client/recording.js";
    }
    dependency CL_043_03_to_FR_006 from 'CL-043-03' to 'FR-006';
    dependency CL_043_03_to_FR_005 from 'CL-043-03' to 'FR-005';
    dependency CL_043_03_verified_by_TC_043_001 from 'CL-043-03' to 'TC-043-001';
    dependency CL_009_05_verified_by_TC_043_001 from 'CL-009-05' to 'TC-043-001';
    verification 'TC-043-002' {
        doc /* TC-043-002 — Clock from the air: stable feedback with the receive windows
             CL-043-03, CL-007-05
             Setup: (a) the AirClock in a closed receive loop of 40 FT8 periods: the crowd
             of TC-043-001 plus a +1.2 s bad clock, decodable only while their corrected DT
             lies in the live window coverage -1.7 s to +2.56 s, both windows completing
             each period; (b) the actual live worker, window buffer and ClockTracker with
             a scripted capture clock 300 ppm slow (actual Recording, no SNTP measurement).
             Steps: (a) station clock errors -2 s, +1.5 s, +0.6 s, 0, +2 s and +3 s; the negative
             control replaces the correction in full by an estimate from corrected DT;
             (b) 301 s of capture, the air correction becoming -2000 ms at 150 s; then
             publish one CQ K1ABC decode 17.0 s after the anchor with 0.5 s drift at
             correction -2000 ms and 0; (c) the live worker analyzes the FT8 prompt window
             of a period-aligned CQ K1ABC with the system clock 2 s slow and correction
             +2000 ms.
             Oracles (#92): (a) for -2 s, +1.5 s and +0.6 s the applied correction
             settles within 50 ms of error - 25 ms within two periods, never moves again
             and approaches monotonically; 0 keeps correction 0 (mixed sides: 5 of 13
             votes above +100 ms); +2 s and +3 s keep correction 0 and stay synchronized over 20
             periods (no evidence, the time accepted, no alternation); the negative
             control alternates
             -2025, 0, -2025, ...; (b) 20 prompt windows (none lost or repeated), each after
             the first completing within 100 ms of +13.8 s of corrected UTC across the
             drift and the correction; the decode at period 00:00:15 with DT 0.0 s at
             -2000 ms and 2.0 s uncorrected, the estimator receiving raw DT 2000 ms both
             times; (c) the record, the FT8 SNR period start and the window diagnostics
             (period start frame and UTC, window offset -1200 ms) equal those of a correct
             clock, the SNR that of the file decode of the same period.
             2 — Isolated automated tests; Windows development PC, no audio device, radio
             or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-043-03';
            verify 'CL-007-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs; server/src/recording_tests.rs";
    }
    dependency CL_043_03_verified_by_TC_043_002 from 'CL-043-03' to 'TC-043-002';
    verification 'TC-043-003' {
        doc /* TC-043-003 — Clock view, wire and display
             CL-043-01, CL-043-03, CL-009-05
             Setup: the actual station router on a disposable profile directory with the
             station clock as main wires it (SNTP monitor that never measures); the actual
             transmit owner; the actual server and Chromium with routed clock.state events
             (as TC-092-005; the error-field clock entries come from clock.state, not
             transmit.state), a transmit-configured profile and GET /clock fixtures where
             stated.
             Steps (#92): open with clock.json missing and with a #43 file {schema_version
             1, profile_id, source ntp}; GET /clock; GET /transmit; hear twelve stations at
             raw DT +1555 ms over two periods; POST /clock; on the transmit owner hear two
             then six stations at raw DT +2000 ms for three periods, read its clock and
             UTC. In the browser: requests before Settings opens; open Settings >
             General; an estimate fixture (correction -1980 ms, 14 stations, 2 above
             +0.1 s, 3 below -0.1 s, median DT +20 ms, 3 s old, SNTP +12 ms); clock.state
             events with clock synchronized and correction 0, synchronized and -1980,
             unsynchronized (warning and capture_warning null).
             Oracles: the same behaviour with and without the file, the file unchanged;
             exact view keys of CL-043-01 (no source, basis, disagreement_ms or
             storage_error), state synchronized, correction 0; GET /transmit without
             clock_source, clock_warning null, clock synchronized; estimate median +1555
             ms, 12 stations all plus, correction -1000 then -1555 ms, synchronized;
             POST /clock answered as an unknown route; the owner synchronized with
             correction 0 with two stations (no evidence), with six -1000 (unsynchronized:
             median +2000) then -2000, synchronized, station UTC 2000 ms (+-10 ms) behind
             the system clock. Browser: no /clock request before Settings opens; no
             source select; the status line exactly "Clock synchronized, correction
             -1980 ms · stations heard: 14, 2 above +0.1 s, 3 below -0.1 s, median DT
             +0.02 s, 3 s ago · NTP +12 ms"; chips exactly none, none, Clock off · Tx
             blocked; the Clock line names the correction.
             2 — Isolated automated tests; Windows development PC, loopback only, no
             public time server, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/src/clock_http_tests.rs; tests/ui-operating.test.cjs";
    }
    dependency CL_043_01_verified_by_TC_043_003 from 'CL-043-01' to 'TC-043-003';
    dependency CL_043_03_verified_by_TC_043_003 from 'CL-043-03' to 'TC-043-003';
    dependency CL_009_05_verified_by_TC_043_003 from 'CL-009-05' to 'TC-043-003';
    verification 'TC-043-004' {
        doc /* TC-043-004 — Live clock from the air on HB9BLA
             CL-043-01, CL-043-02, CL-043-03, CL-009-05
             Setup: the gated candidate installed on HB9BLA, IC-7300 on COM3, USB Audio
             CODEC, FT8 receive on a band with at least ten stations heard; for the transmit steps, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). Steps (1)-(4)
             keep the PC clock disciplined by NTP and need no administrator rights (agents
             have none); step (5), the issue's offset-clock check, is performed by the
             operator with administrator rights.
             Steps (#92): (1) read GET /clock and GET /transmit for three periods (SNTP
             offset, air estimate); read Band Activity DT. (2)-(3) none (no source
             setting). (4) with the operator's consent for transmit, arm and send one CQ;
             check PSK Reporter spots of HB9BLA and a partner's DT. (5) operator,
             administrator: stop Windows Time (w32time) and any clock tool, set the PC
             clock 1.5 s fast, wait four FT8 periods and one SNTP round, read GET /clock,
             GET /transmit and Band Activity DT; repeat with the PC clock 1.5 s slow and
             2.0 s slow; restore the clock and its service.
             Expected: (1) state synchronized with |SNTP offset| at most 500 ms; the
             correction either unchanged (mixed sides) or moved to the stations' middle
             (the crowd's own DT bias, typically +0.1 to +0.2 s, and the correction are
             recorded); Band Activity median DT within +-0.1 s of 0 after a correction;
             warning null while |correction| is at most 500 ms; GET /transmit clock
             synchronized; no clock chip; (4) the
             transmission is admitted, starts at the period start + 0.5 s of station UTC,
             and PSK Reporter spots and the partner's DT (within +-0.5 s) confirm the
             transmitted timing; (5) warning pc_clock_off with windows_time stopped;
             within four periods state synchronized with correction_ms
             within 200 ms of -1500 and +1500 ms respectively, Band Activity median DT
             within +-0.5 s; at 2.0 s slow (the edge of the found range) correction_ms
             either within 200 ms of +2000 ms (enough edge stations decode) or 0 (the time
             accepted), state synchronized either way; each time GET /transmit clock
             synchronized (transmit admitted); a
             transmission under step (4)'s consent is spotted on time.
             Steps (1) and (5) without transmit are receive-only, cost 4; transmit
             steps are cost 5.
             5 — Live with transmit and external effects; explicit operator consent;
             HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-02';
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
    }
    dependency CL_043_01_verified_by_TC_043_004 from 'CL-043-01' to 'TC-043-004';
    dependency CL_043_03_verified_by_TC_043_004 from 'CL-043-03' to 'TC-043-004';
    dependency CL_009_05_verified_by_TC_043_004 from 'CL-009-05' to 'TC-043-004';
    dependency CL_043_03_verified_by_TC_092_001 from 'CL-043-03' to 'TC-092-001';
    verification 'TC-092-002' {
        doc /* TC-092-002 — Replay of the 10 m FT4 refusals of 2026-11-09
             CL-043-03, CL-009-05
             Setup: StationClock with a fake SNTP monitor holding a current
             measurement +525 ms (unsynchronized); FT4 votes (DT against station UTC) of
             6 stations: four at -339 ms, one at -50 and one at +100; PlanTransmitStart
             on the station clock.
             Steps: complete windows with these six; then with five at -339 and one at
             +100; then with 2 stations; then with none for 3 minutes; plan a transmit
             start in each window.
             Expected (independent oracle: the operator's rule of 2026-11-09 and the
             observed 2026-11-09 values): the first crowd 4 of 6 below -0.1 s (66 %): no
             change, correction 0; then 5 of 6 (83 %): median -339, correction +339;
             then kept +339 with 2 and with no stations; the station clock synchronized
             in every window; every start planned (no clock_not_synchronized); warning
             pc_clock_off throughout. Red on the parent, which falls to unknown and
             refuses.
             2 — Isolated automated tests; Windows development PC, no audio, radio or
             network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs";
    }
    dependency CL_043_03_verified_by_TC_092_002 from 'CL-043-03' to 'TC-092-002';
    dependency CL_009_05_verified_by_TC_092_002 from 'CL-009-05' to 'TC-092-002';
    verification 'TC-092-003' {
        doc /* TC-092-003 — The three situations: correction, state and warnings
             CL-043-03, CL-009-05
             Setup: StationClock with a fake SNTP monitor that records rounds (asked a
             server or not, answer or none), votes set directly (DT against station UTC)
             and a fake Windows Time service reader; explicit clocks.
             Steps: SNTP +12 ms (synchronized) with four votes at +1500 ms for two
             periods; corrections -500 and -501 ms with SNTP +12; SNTP +500 and +501 ms
             without votes; SNTP -1900 ms with no evidence; one round asked with no
             answer and no measurement; a measurement 600 s and 600 s + 1 ms old after
             failed rounds; a 101 ms step with a young measurement; an empty server list
             (no round asks); no round yet; the service reader answering running,
             stopped, disabled and failing; with live receive a correlated clock at
             capture drift 1000.0, -1000.0 and 1000.1 ppm, a rate not yet known, receive
             running before its first capture epoch, an uncorrelated epoch, then receive
             stopped with 1500 ppm; system clock steps of +300 and -300 ms with
             correction 0; the 2026-11-09 recovery: SNTP +525 ms, the mixed crowd of
             TC-092-002 (correction 0), Windows Time steps the system clock +525 ms, the
             SNTP step gap (unknown), the next round +3 ms; correction -2000 ms with SNTP
             changing from synchronized to unsynchronized and back. GET /clock and GET
             /transmit after each.
             Expected (TransmitClock 500 ms / 600 s / 100 ms, CL-043-03): with SNTP
             synchronized the votes still move the correction (-1000, then -1500,
             synchronized) and give stations_off; stations_off null at -500 and set at
             -501 with SNTP synchronized; SNTP +500 null and +501 pc_clock_off with the
             correction and state unchanged; SNTP -1900 without evidence correction 0,
             synchronized, pc_clock_off (the SNTP offset is never applied);
             ntp_unreachable; null at 600 s and ntp_unreachable at 600 s + 1 ms; null
             after the step, with the empty list and before the first round, the station
             clock synchronized in each; windows_time running, stopped, disabled,
             unknown; capture_warning null at 1000.0 and -1000.0 ppm, drift_high at
             1000.1 ppm, null without a known rate, null before the first epoch,
             uncorrelated for the uncorrelated epoch, null with receive stopped; the
             steps leave correction 0 and station UTC equal to the system clock; the
             recovery gives correction 0 and station UTC equal to the system clock at
             every step, pc_clock_off until the +525 ms step, null in the SNTP step gap
             (SNTP unknown with a young measurement: neither warning applies) and after
             the +3 ms round, no
             clock_not_synchronized; the -2000 ms correction is kept through every SNTP
             change (SNTP never resets it); GET /clock warning equals GET /transmit
             clock_warning; no clock_source key; clock_revision increases at each change of
             a clock.state field and only then.
             2 — Isolated automated tests; Windows development PC, no public time server,
             audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
        attribute executable : String = "server/tests/transmit_air_clock.rs; server/src/clock_http_tests.rs; server/src/transmit_http_tests.rs";
    }
    dependency CL_043_03_verified_by_TC_092_003 from 'CL-043-03' to 'TC-092-003';
    dependency CL_009_05_verified_by_TC_092_003 from 'CL-009-05' to 'TC-092-003';
    verification 'TC-092-004' {
        doc /* TC-092-004 — No clock source setting
             CL-043-01
             Setup: the actual station router on a disposable profile directory, SNTP
             monitor that never measures, twelve stations heard at a clock 2 s fast.
             Steps: open with clock.json missing, then with #43 files {source ntp},
             {source air} and malformed JSON; GET /clock and GET /transmit each time;
             POST /clock {v 1, profile_id, boot_id, source ntp}.
             Expected (CL-043-01): in every case the same view: exactly the keys of
             CL-043-01 (no source, basis, disagreement_ms or storage_error), correction
             -2000 ms after two periods, synchronized; GET /transmit without
             clock_source; each file byte for byte unchanged; POST /clock answered as an
             unknown route.
             2 — Isolated automated tests; Windows development PC, loopback only, no
             public time server, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-01';
        }
        attribute executable : String = "server/src/clock_http_tests.rs";
    }
    dependency CL_043_01_verified_by_TC_092_004 from 'CL-043-01' to 'TC-092-004';
    verification 'TC-092-005' {
        doc /* TC-092-005 — Clock entries in the error field and the clock status line
             CL-043-03, CL-037-02
             Setup: the actual server and Chromium at 1366x768 with routed transmit.state,
             receive state and GET /clock fixtures; a transmit-configured and a
             receive-only profile.
             Steps: routed clock.state events (no GET /clock outside Settings): transmit
             configured, clock synchronized, with warning pc_clock_off and ntp_offset_ms
             +525, then -620; ntp_unreachable; stations_off; null; clock unsynchronized
             with pc_clock_off; the receive-only profile with pc_clock_off, ntp_unreachable
             and stations_off; capture_warning uncorrelated, drift_high, then null on both
             profiles; count the /clock requests; click each entry; open Settings >
             General > Clock with GET /clock warning pc_clock_off and windows_time
             stopped, disabled, running and unknown, and with a view without evidence;
             stations_off with correction_ms -1980.
             Expected (CL-043-03 texts, CL-037-02): exactly one warn entry "PC clock
             525 ms slow vs NTP · see Settings" and no clock entry; "PC clock 620 ms fast
             vs NTP · see Settings"; "NTP not reachable · check the network"; "Clock
             corrected -1980 ms from the air · PC clock matches NTP, check audio latency";
             "No problems"; the two entries
             "Clock off · Tx blocked" (error) and the PC clock entry (warn); the same three
             warn entries on the receive-only profile and never "Clock off" there; "Audio
             timing not tied to the PC clock · DT may be off" and "Sound card clock drifts
             over 1000 ppm · check the audio device" (warn) on both profiles, gone at
             null; no /clock request before Settings opens; the clock entries open
             Settings clock, the audio entry the receive details; the status line remedy
             texts of CL-043-03 for each windows_time value, and without evidence and with correction 0 it
             begins "Clock accepted (stations heard are not off to one side)"; no source
             select; no view
             shows "Clock unknown" or "NTP and air clock disagree".
             2 — Isolated automated functional tests; Windows development PC, no radio or
             RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-03';
            verify 'CL-037-02';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_043_03_verified_by_TC_092_005 from 'CL-043-03' to 'TC-092-005';
    verification 'TC-092-006' {
        doc /* TC-092-006 — Live clock state on HB9BLA after the deploy
             CL-043-01, CL-043-03
             Setup: the deployed candidate on HB9BLA, receive running.
             Steps: read GET /clock and GET /transmit for three periods; look at the error
             field.
             Expected: no source key; state synchronized or unsynchronized, never
             unknown; ntp.windows_time as Windows reports it; the correction and the
             estimate (median DT, stations, plus, minus) recorded; warning null while
             |SNTP offset| and |correction| are at most 500 ms, else the CL-043-03 value,
             the same in both reads; the error field matches it; capture_drift_ppm from
             GET /receive/clock recorded.
             3 — Live read-only; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
        }
    }
    dependency CL_043_01_verified_by_TC_092_006 from 'CL-043-01' to 'TC-092-006';
    dependency CL_043_03_verified_by_TC_092_006 from 'CL-043-03' to 'TC-092-006';
    verification 'TC-092-007' {
        doc /* TC-092-007 — Live PC clock offset
             CL-043-03
             Setup: HB9BLA, FT8 receive on a band with at least ten stations heard; the
             operator with administrator rights stops Windows Time (w32time) and any
             clock tool.
             Steps: set the PC clock 1.5 s fast, wait four FT8 periods and one SNTP round,
             read GET /clock, GET /transmit, the error field and Settings clock; set it
             0.4 s fast and repeat; restore the clock and its service and wait 60 s.
             Expected: at 1.5 s correction_ms within 200 ms of -1500 (Band Activity
             median DT within +-0.1 s), state synchronized, the warn entry "PC clock n ms
             fast vs NTP · see Settings" with n 1300 to 1700, Settings naming the stopped
             Windows Time service and its remedy, no Clock off; at 0.4 s correction_ms
             within 200 ms of -400, synchronized, no PC clock entry (SNTP within
             500 ms); after the restore a step that leaves station UTC continuous, the
             correction then moving back toward the stations' middle, and the entry gone
             within 60 s.
             4 — Live receive-only; operator with administrator rights. Not run by the
             automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-043-03';
        }
    }
    dependency CL_043_03_verified_by_TC_092_007 from 'CL-043-03' to 'TC-092-007';
    verification 'TC-092-008' {
        doc /* TC-092-008 — Live call on a sparse band with NTP not correct
             CL-043-03, CL-009-05
             Setup: HB9BLA, IC-7300, 10 m FT4 with few stations; the operator's consent
             for transmit; NTP unsynchronized or unreachable (the operator's choice how).
             Steps: call stations or CQ for ten own periods; read GET /transmit and the
             error field.
             Expected (the reported failure of 2026-11-09): no clock_not_synchronized
             refusal over the ten periods; the yellow PC clock or NTP entry shown; PSK Reporter spots
             or a partner's DT within +-1 s.
             5 — Live with transmit and external effects; explicit operator consent;
             HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        objective {
            verify 'CL-043-03';
            verify 'CL-009-05';
        }
    }
    dependency CL_043_03_verified_by_TC_092_008 from 'CL-043-03' to 'TC-092-008';
    dependency CL_009_05_verified_by_TC_092_008 from 'CL-009-05' to 'TC-092-008';
    verification 'TC-092-009' {
        doc /* TC-092-009 — clock.state pushed to every profile
             CL-043-01, CL-043-03
             Setup: the actual server with a receive-only and a transmit-configured
             profile, a fake SNTP monitor and capture drift source, two WebSocket peers
             subscribed Detailed and Thin; loopback only.
             Steps: subscribe; wait 10 s with nothing changing; let the SNTP offset move
             from +12 to +40 ms (synchronized); set it to +525 ms; then +530 ms; three
             changes within 300 ms; set capture drift 1500 ppm; restore all; compare each
             event with GET /clock.
             Expected (CL-043-01): one event per peer after subscribing, exactly
             {v:1,type:"clock.state",data:{profile_id,boot_id,clock_revision,clock:{state,
             correction_ms,warning,ntp_offset_ms,capture_warning}}}, at most 512
             bytes; no event while nothing changes and none for +12 to +40 ms
             (ntp_offset_ms null); one event within 1 s with warning pc_clock_off and
             ntp_offset_ms 525, one with 530; the three quick changes coalesced into at
             most one event per second per peer, the last state delivered; capture_warning
             drift_high, then null; clock_revision increasing, equal to GET /clock's; the
             same on both profiles.
             2 — Isolated automated tests; Windows development PC, loopback only, no
             public time server, audio or radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-043-01';
            verify 'CL-043-03';
        }
        attribute executable : String = "server/src/clock_http_tests.rs";
    }
    dependency CL_043_01_verified_by_TC_092_009 from 'CL-043-01' to 'TC-092-009';
    dependency CL_043_03_verified_by_TC_092_009 from 'CL-043-03' to 'TC-092-009';
    requirement 'CL-044-13' {
        doc /* The server pushes the Tx level state (client-server rule of #10): each WebSocket peer with a display subscription receives radio.tx_level {v 1, type radio.tx_level, data {profile_id, boot_id, managed, level_db, stored, alc unknown|available|unavailable, assistant, result, meters null|{alc, po_pct, swr_x10}, power_limit_pct, warnings [...] (CL-044-14), keying_confirmed (CL-044-15)}} after each change; nothing is polled. Settings > Radio > Audio shows, for an IC-7300 CAT control only, a Set level button, a line with the level and the last result, the last ALC, Po and SWR, and the optional Profile power field (settings.radio.power_limit_pct) saved with Apply; the Tx level slider is shown only with alc unavailable. Set level and the slider send POST /radio/tx-level; a refusal is shown on the line. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/main.rs; client/recording.js; client/app.js";
    }
    dependency CL_044_13_to_FR_019 from 'CL-044-13' to 'FR-019';
    dependency CL_044_13_to_FR_009 from 'CL-044-13' to 'FR-009';
    // Operator decision 2026-11-04 (#44 comment 6628026397): monitoring in normal operation.
    // Operator decision 2026-11-06 (#44, live ALC 31-32 at Po 102 %): the level lowers above ALC 10.
    requirement 'CL-044-14' {
        doc /* In normal operation the station reads the radio's meters exactly once per transmission, in the middle of its audio: the transmit step calls the read when half of the audio remaining at audio start has played, once per transmission, on no Tune, and not at all when less than 2 s of audio remained at audio start. The call returns at once and the burst (CL-044-12: 15 13, 15 11, 15 12) runs on its own thread, so the transmit step, the audio and the release never wait for the radio, and a PTT exchange cancels the burst. Nothing is read while Set level runs. From the reading the level moves by at most one step, stored like CL-044-12 and taken by the next transmission's audio start only: ALC above raw 0010 or Po above the profile power: one down, not below -40 dB; else ALC exactly 0 and Po below 80 % of the profile power: one up, not above 0 dB and not back to the ceiling; otherwise unchanged. A lowering on the reading right after a step up makes the level just left the ceiling, so a level reading 0 below a level reading above 0010 settles on the lower one; any other lowering leaves the step up free, so the level follows a drive that falls later. The ceiling lives in memory until a stored Set level, a changed profile power or a restart. Set level's stop (CL-044-12, ALC 0, one step below the first rise) is inside this window, and one step up from it, the ALC onset (reads 4-7, about 6 per dB on the IC-7300), stays inside it. Without a profile power Po is neither over nor low, so there is no step up. Persistent trouble is an entry in the error field, from the third transmission in a row until a reading without it: alc_high (ALC at or above raw 0060, half the ALC zone; lowering below that is routine and shows no entry), po_low (Po below half the profile power), swr_high (SWR at or above 2.0, raw 0080). A clear fault, SWR at or above 3.0 (raw 0120), stops transmitting at once through the priority halt (DisarmCause halt) with the entry swr_fault, and automation may not arm again until an operator action (WatchdogFromOperator); the entry stays until a later reading below 3.0 or a stored Set level. The radio.tx_level data carries these as warnings [...]. A failed read judges nothing. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_level.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; client/recording.js; client/contact.js";
    }
    dependency CL_044_14_to_FR_009 from 'CL-044-14' to 'FR-009';
    verification 'TC-044-017' {
        doc /* TC-044-017 — One meter read per transmission and its bounded correction
             CL-044-14
             Setup: the actual transmit core on a virtual clock; the actual Recording, transmit owner on a recording double and CAT actor on a scripted IC-7300 reporting set meter values.
             Steps: (a) the decision table; (b) two FT8 transmissions and a Tune on the virtual clock; (c) the call without the hold, then with ALC 0060; (d) three transmissions in a row, then a good one; (e) SWR 0120, a reading without SWR, then the operator arms and SWR is clear; (f) the call while Set level runs; (g) the transmit step's call through the station's boxed hardware to the sink, and the sink startup installs; (h) ALC 0060 with the level file unwritable; (i) a radio reading ALC 0 at -10 dB and 0011 at -9 dB with low Po, 40 transmissions; (j) ALC 0031 at -9 dB moving 6 per dB, 40 transmissions; (k) Set level and then the correction on a radio with ALC 0 up to -9 dB and 0007 at -8 dB, rising 6 per dB, with low Po; (l) a step up, ALC 0011 and then 0 with low Po, the same profile power and then a changed one, again a step up and ALC 0011, and a stored Set level at the ceiling; (m) ALC 0013 with no step up before it, then ALC 0 twice with low Po, then 0005, 0013 and 0.
             Expected: (a) one down at ALC 0011, none at 0010, no warning from three readings of 0059, the floor and 0 dB hold, one up only with ALC 0 and Po below 80 %, none without a profile power, one down above it, none without ALC, fault at 0120 and not at 0119, warnings from the third reading, cleared by one good reading; (b) due exactly once at period + 6 820 ms in each, none for Tune, none for audio starting at period + 11 200 ms; (c) no byte without the hold; with it exactly 15 13, 15 11, 15 12, level -11 stored, nothing handed to the running audio; (d) alc_high from the third, level -13, gone with the good one; (e) one halt, disarmed halt, automation refused, entry swr_fault; the entry stays with the reading without SWR; after the clear reading no entry and still armed; (f) no byte; (g) one call reaches the sink, one burst from the installed sink; (h) the level stays -10, stored false, and the next Tune plays -10; (i) -10 dB for good after at most two transmissions from -10 dB and three from -9 dB, no warning; (j) -10, -11, -12, -13 dB and then unchanged, no warning; (k) Set level stores -9 dB, the correction takes it to -8 dB and stays, from -7 dB it comes back to -8 dB and stays; (l) the level stays with ALC 0 and the same profile power, and goes up one after the changed profile power and after the stored Set level; (m) -13, -12, -11, -11, -12, -11 dB.
             2 — Isolated automated tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-14';
        }
        attribute executable : String = "server/src/radio_level_tests.rs; server/src/transmit_http_tests.rs; server/tests/transmit_service.rs";
    }
    dependency CL_044_14_verified_by_TC_044_017 from 'CL-044-14' to 'TC-044-017';
    verification 'TC-044-018' {
        doc /* TC-044-018 — Tx trouble in the error field
             CL-044-14
             Setup: candidate server and Chromium; radio.tx_level events injected.
             Steps: inject the four warnings, then none.
             Expected: one error field entry each, swr_fault with error severity and the others warn, all gone after the empty list.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-14';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_14_verified_by_TC_044_018 from 'CL-044-14' to 'TC-044-018';
    verification 'TC-044-019' {
        doc /* TC-044-019 — Monitoring on HB9BLA
             CL-044-14
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's consent, 40 m, RF power set by the test to at least 30 W before the first Tx (CI-V 14 0A, starting at 0090, with the station stopped and idle, because it holds COM3; read back; the first Tx must read Po at least 30 %; if below, raise the value and repeat; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported). The mismatched-antenna / SWR 3.0 stop step is dropped by operator decision of 2026-11-08 ("bad SWR is handled by the transceiver"); the station's own stop at and above SWR 3.0 stays (CL-044-14), covered offline; the SWR display is #68.
             Steps: transmit during normal operation and record the radio.tx_level frames and the transmit timing; transmit with ALC above 0010. The evidence is the CI-V readback and the radio.tx_level frames, not the radio's display or a CI-V log (operator decision of 2026-11-08; the station keeps no CI-V log).
             Expected: at most one radio.tx_level meter frame per transmission (sent only when the values change); decode by another station unaffected; ALC above 0010 goes down one step at the next transmission until it reads 0010 or less, with no entry below 0060.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-044-14';
        }
    }
    dependency CL_044_14_verified_by_TC_044_019 from 'CL-044-14' to 'TC-044-019';
    dependency CL_044_13_verified_by_TC_044_014 from 'CL-044-13' to 'TC-044-014';
    verification 'TC-044-015' {
        doc /* TC-044-015 — Tx level in Settings > Radio > Audio
             CL-044-13
             Setup: candidate server and Chromium; radio.tx_level events injected, POST /radio/tx-level answered by a route fixture.
             Steps: open the Audio section for an IC-7300 CAT control; inject meters, a run, its result, alc unavailable; click Set level; move the slider; save a power limit; hide for a disabled control; 360 px.
             Expected: the button is in #settings-audio, no slider before alc unavailable, the line and meters show the pushed values, a malformed event is ignored, the click sends exactly one set_level, the slider sends one manual, Apply saves radio.power_limit_pct, all of it hidden when control is Disabled, no horizontal overflow at 360 px.
             2 — Isolated automated browser test; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-13';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_044_13_verified_by_TC_044_015 from 'CL-044-13' to 'TC-044-015';
    dependency CL_044_13_verified_by_TC_044_016 from 'CL-044-13' to 'TC-044-016';
    requirement 'CL-039-06' {
        doc /* The Tx watchdog limits the repetitions of one message (WstxContact::TxWatchdog, 2026-11-06) and is never paused by automation; only a different message, a new contact or an operator Enable Tx restarts its count, and only an Enable Tx or a strategy selection from the browser ends its stop. Only a human action in the browser is an operator action (an Enable Tx, accepted contact request or strategy selection from the browser), decided by the request principal the station reads from its credential at the auth boundary (#58: an MCP client has its own token and is never the browser principal on any route, including a direct /contact/command); commands of an automation run and MCP requests (including starting or restarting a run) never end a stop or extend the limit; their Enable Tx is refused tx_watchdog after a stop or when no browser action was seen this boot; only the browser may change the watchdog setting (set_watchdogs from MCP or automation is refused operator_required); a new target chosen by a run is a different message, so the watchdog bounds a run per message, not in total. At the limit Enable Tx goes off without a halt and a pounce or MCP policy run stops tx_watchdog, while a strategy run's own contact has no stop and is bounded by CL-039-21 instead; the station and its automation never use HALT in normal flow (HALT is the operator's emergency stop: HALT button, Alt+H, MCP wstx_transmit_halt). HALT from any source stops everything; grant, clock, period and safety-revision checks are unchanged; there is no band hopping. Details: WstxStrategy::WatchdogFromOperator; WstxContact::TxWatchdog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs; server/src/mcp.rs; server/src/authorization.rs";
    }
    dependency CL_039_06_to_FR_008 from 'CL-039-06' to 'FR-008';
    verification 'TC-039-005' {
        doc /* TC-039-005 — The Tx watchdog stop is never ended by automation
             CL-039-06
             Setup: as TC-039-004; for the unit cases the #9 Core on the hardware double; counts per WstxContact::TxWatchdog (#39, 2026-11-06).
             Steps: (1) browser limit 2; a pounce on K1ABC started from the browser (a strategy run has no stop: TC-039-022); publish CQ K1ABC at E; transmit the call at E+15 s and its repeat at E+45 s; reach E+75 s; cancel, select a strategy from the browser and publish another CQ. (2) MCP and browser: an MCP Enable Tx before any browser action; browser limit 1; an MCP Enable Tx (CQ) transmitted at E+15 s; MCP set_frequency; MCP set_watchdogs 99; reach E+45 s; a station calls HB9BLA in period E+30 s; an MCP Enable Tx; an MCP run start and a matching CQ; a browser action and an MCP Enable Tx. (3) MCP route: browser limit 1, an MCP Enable Tx and its CQ, MCP-principal commands through the tool and straight to /contact/command, then MCP Enable Tx on both. Unit: automatic arm before any operator action; activity, limit 2, automatic arm; operator arm.
             Expected: (1) remaining calls 1 after the first call (the run's selection does not extend it), the request at E+75 s is never keyed, the run stops tx_watchdog, tx_expired true, last cause tx_watchdog and halt_state unchanged (no halt); the selection arms again. (2) refused tx_watchdog; not spent after the one CQ and the MCP command, set_watchdogs refused operator_required, the next CQ never keyed and spent, still spent after the caller (an answer after a stop ends nothing), the MCP Enable Tx refused tx_watchdog, the MCP run stops tx_watchdog unarmed with no further key; still spent after an unrelated browser action; after a browser Enable Tx not spent and the MCP Enable Tx arms. (3) after the stop spent after every MCP request, both Enable Tx refused tx_watchdog, one key in total. Unit: spent before any action; not spent after the activity; remaining 2 after the automatic arm and after the operator arm.
             2 — Isolated automated functional tests; Windows development PC, transmit double; no RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-06';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    dependency CL_039_06_verified_by_TC_039_005 from 'CL-039-06' to 'TC-039-005';
    dependency CL_039_06_verified_by_TC_039_007 from 'CL-039-06' to 'TC-039-007';

    // The transmit state, its start actions and its stops (WstxTransmit::TransmitArming,
    // WstxContact::StartActions).
    requirement 'CL-111-01' {
        doc /* Transmit state. The station has one transmit state, on or off, with the cause of its last change in both directions. It is off at every station start (cause startup). It is on only from an accepted start action (CL-111-02) until the next stop (CL-111-03). While it is off no TransmitRequest is planned or keyed. A selection, a setting, a chosen Next message, a reconnect, a reload, a repeated command and a partner message never switch it on. Not delivered yet: three commands still switch the state on directly, and each is to be retired: the contact command enable_tx, through which the browser and the runs still start; the Set level assistant, which switches the state on (cause operator, ending a repetition-limit stop) and off around its tone; and the arm command of the transmit route. Details: WstxTransmit::TransmitArming. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs";
    }
    dependency CL_111_01_to_FR_007 from 'CL-111-01' to 'FR-007';
    dependency CL_111_01_to_FR_008 from 'CL-111-01' to 'FR-008';
    requirement 'CL-111-03' {
        doc /* Stops. A completed, cancelled or stopped sequence does not transmit: the state goes off with the cause of the stop, the pending request is dropped, and nothing is sent until the next start. Stop: cause; transmission on the air; what stays of the QSO. QSO completed: contactCompleted; none; completed, logged once. Cancel contact, F4: contactCancelled; finishes; cancelled, an own CQ becomes idle. Abort QSO, Esc: contactCancelled; stops now, no halt; cancelled. Halt Tx, Alt+H, MCP halt: halt; stops now; state kept, an own CQ ends. Repetition limit (Tx watchdog): txWatchdog; none keyed; state kept, an own CQ ends. Partner works another station on the own Tx frequency: partnerWorksOther; stops now by an abort, no halt; state kept (a contact that pauses for a busy partner moves Tx clear instead and stops only when that move is refused, CL-097-06). Mode change: modeChanged; as CL-011-04; cancelled. Band change: bandChanged; finishes, and a band selection in the program is refused busy during a transmission; cancelled as by a mode change: DX call and Tx1 to Tx5 cleared, Tx6 next, an own CQ becomes idle, a completed QSO keeps its fields. Radio or capability lost: deviceLost; released; state kept. Safety revision changed: authorityChanged; state kept. Refused or failed transmission: refused, failed; state kept. A run ends and leaves a contact it did not finish or cancel, with no other stop of this list: runEnded; finishes; state kept. A band change is any change of the station band the station sees: the station band (the radio's dial band, else the band of the operating selection) differs from the band the contact was prepared on. It covers a band selection in the program and a change at the radio's own dial. An unknown station band is no band change. The band-change stop shows bandChanged in every case, also when a run's contact is ended by it. The run's own stop reason stays (a pounce: band_changed). A pounce run's contact is cancelled like every other. A stop is admitted with any earlier contact revision, as cancel and abort are. In one station step any stop wins over any start: the start is refused state_conflict and nothing is sent. When several stops arrive in one step the shown cause is the first of: halt; deviceLost, authorityChanged, failed, refused; Abort QSO (contactCancelled); txWatchdog; partnerWorksOther; bandChanged, modeChanged, runEnded, Cancel contact (contactCancelled); contactCompleted. After a stop with the state kept, the QSO continues only by Reply on the partner's row or by "Send <exchange> next"; after a repetition-limit stop also by Reset. Enter in the DX call field does not continue a stopped QSO. An own CQ ended by the repetition limit is started again with the CQ button. Not delivered yet: no run raises runEnded, and a run that is neither a strategy nor a pounce stops contact_changed when the band change ends its contact. Details: WstxTransmit::StopOrder, WstxContact::BandChange, ModeChange, AutoSequence. */
        attribute coverage : ImplementationState = ImplementationState::partial;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs";
    }
    dependency CL_111_03_to_FR_007 from 'CL-111-03' to 'FR-007';
    dependency CL_111_03_to_FR_008 from 'CL-111-03' to 'FR-008';
    requirement 'CL-111-06' {
        doc /* Tune. tune {enabled, safety_revision}. Tune on is accepted whenever the transmit capability is available with a current grant and nothing is on the air or pending, whatever the transmit state. It is refused stale_revision with field safety_revision on another revision than the station's, busy while a transmission is keyed or a request is pending, transmit_unavailable without capability or grant. From an MCP client or a run it is refused tx_watchdog as an automatic start (CL-111-02): when no browser action was seen this boot, after a repetition-limit stop or after a clear fault (CL-044-14). Tune never changes the transmit state or its cause. The Tune watchdog is unchanged (default 90 s, 1..300 s). Tune off needs no revision. Details: WstxTransmit::SetTune. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
    }
    dependency CL_111_06_to_FR_008 from 'CL-111-06' to 'FR-008';
    verification 'TC-111-001' {
        doc /* TC-111-001 — The new causes and the resume
             CL-111-03
             Setup: the contact engine against the actual transmit owner core on a virtual UTC clock with hand-authored rows (transmit_state_tests on the bench of contact_tests), profile HB9BLA JN47; a QSO with K1ABC in replying, the state on, Tx1 sent once. For (c) the station with a run (strategy_tests).
             Steps: (a) the partner's message to another call within 50 Hz of my Tx frequency, in a contact that does not pause for a busy partner (an MCP policy run's contact, CL-097-06; a manual contact moves Tx clear instead, TC-097-017). (b) a mode change. (c) a run ends leaving its contact. (d) after each state-kept stop (Halt, the limit, partner works another as in (a), radio lost, refused): 3 own periods, then reply on the partner's row.
             Expected (the stop table of CL-111-03): (a) off, partnerWorksOther, state kept. (b) modeChanged, cancelled. (c) runEnded, state kept. (d) no request in the 3 own periods, then the reply transmits again with the same contact identity.
             Automated: (a), (b), (d). Not automated yet: (c).
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-03';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_111_03_verified_by_TC_111_001 from 'CL-111-03' to 'TC-111-001';
    verification 'TC-111-002' {
        doc /* TC-111-002 — What is not a start never transmits
             CL-111-01
             Setup: as TC-111-001, from a station start; for the reload and the repeated command_id the actual station router (contact_http_tests fixture).
             Steps: select_row, enter_dx, choose_next, set_frequency, every setting, snapshot reload, reconnect, a repeated command_id, a partner message while off.
             Expected (CL-111-01): zero requests over 3 own periods, state and cause unchanged.
             Not automated yet: the reconnect.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-01';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_111_01_verified_by_TC_111_002 from 'CL-111-01' to 'TC-111-002';
    verification 'TC-111-007' {
        doc /* TC-111-007 — Wire
             CL-111-01
             Setup: the actual station router (contact_http_tests fixture).
             Steps: GET /contact and the transmit.state event at a station start, after a start and after a stop; the largest snapshot and the first event with the longest cause of each direction.
             Expected (WstxContact::ContactSnapshot, WstxTransmitWire::TransmitWire): the transmit view carries the causes of CL-111-03 as snake_case values and last_arm_cause (operator, auto or null); the largest snapshot stays at most 4096 bytes and the event at most 1024.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-01';
        }
        attribute executable : String = "server/src/contact_http_tests.rs";
    }
    dependency CL_111_01_verified_by_TC_111_007 from 'CL-111-01' to 'TC-111-007';
    dependency CL_039_06_verified_by_TC_111_008 from 'CL-039-06' to 'TC-111-008';
    verification 'TC-111-009' {
        doc /* TC-111-009 — A band change stops and cancels
             CL-111-03
             Setup: as TC-111-001, the station band 20m; for the selection, the dial and the runs the actual station router (contact_http_tests, strategy_tests).
             Steps: (a) QSO in rogerReport, state on, admitted selection 20m to 40m. (b) the same QSO, the radio's dial moved to 7.074 MHz with no selection. (c) own CQ. (d) completed QSO. (e) a selection of the same band, a dial change inside the band, and an unknown station band. (f) a selection during a transmission. (g) a strategy run's contact at a dial band change. (h) a pounce run in its contact.
             Expected (CL-111-03): (a) off, bandChanged, cancelled, DX call cleared, no request in 3 periods. (b) the same. (c) idle, off. (d) fields kept. (e) nothing changes. (f) busy, QSO and state unchanged (guard, TC-044-023). (g) cancelled, cause bandChanged. (h) run stopped band_changed, contact cancelled, cause bandChanged.
             Automated: (a) and (b) as the station band at the engine and as the band of the operating selection at the station, (c), (d), (e); the dial as the station band is shown for a run's own CQ (TC-063-010). Not automated yet: (b) for a QSO at the station, (g), (h).
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-111-03';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_111_03_verified_by_TC_111_009 from 'CL-111-03' to 'TC-111-009';
    verification 'TC-111-010' {
        doc /* TC-111-010 — Tune
             CL-111-06
             Setup: as TC-111-001.
             Steps: (a) state off, no contact, ready: Tune on; Tune off. (b) a stale safety revision. (c) a request pending, and a transmission on the air. (d) no capability, and no grant. (e) reply while Tune is on; Tune ends; 3 periods. (f) the Tune watchdog at 1 s. (g) Tune on from an MCP principal at boot before any browser action, after a browser action, after a clear fault (require_operator), and after a repetition-limit stop.
             Expected (CL-111-06): (a) keyed, state and cause unchanged; released. (b) stale_revision, not keyed. (c) busy. (d) transmit_unavailable. (e) accepted, QSO prepared, refusal busy, state off, nothing sent. (f) Tune ends (guard, TC-008-001). (g) tx_watchdog and not keyed at boot, after the clear fault and after the limit; keyed after the browser action.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-06';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs";
    }
    dependency CL_111_06_verified_by_TC_111_010 from 'CL-111-06' to 'TC-111-010';
    verification 'TC-111-013' {
        doc /* TC-111-013 — A stop wins
             CL-111-03
             Setup: as TC-111-001.
             Steps: stop against start in one station step: Halt and reply; the limit and send_next; a band change and call_cq. Two stops in one step: Halt and radio lost; radio lost and Abort QSO; Abort QSO and the limit; the limit and partner works another; partner works another and a band change; Cancel contact and the limit; a band change and completion. The partner-works-other steps run in a contact that does not pause for a busy partner (an MCP policy run's contact, CL-097-06), as TC-111-001 (a).
             Expected (the order of CL-111-03): the start is state_conflict, state off, nothing keyed. Shown cause of the two stops, in the order of the steps: halt; deviceLost; contactCancelled; txWatchdog; partnerWorksOther; txWatchdog; bandChanged.
             2 — Isolated automated functional tests; Windows development PC, no radio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-111-03';
        }
        attribute executable : String = "server/src/transmit_state_tests.rs";
    }
    dependency CL_111_03_verified_by_TC_111_013 from 'CL-111-03' to 'TC-111-013';
    verification 'TC-111-015' {
        doc /* TC-111-015 — Live on the transceiver
             CL-111-01, CL-111-02, CL-111-03, CL-111-04, CL-111-08
             Setup: HB9BLA, the deployed candidate, the operator's browser, the transceiver on an antenna.
             Steps: double-click a CQ and run a QSO to its log; Halt during a transmission; limit 1, then Reset; Enter on a typed callsign; a band change at the radio's dial during a QSO; Tune with the state off.
             Expected (observation, the radio's Tx indicator): "Tx off · QSO complete", nothing keyed in the next 4 own periods; "Tx off · halted"; the second send is not keyed, Reset sends it once more; the typed callsign is called in the next own period; "Tx off · band changed", nothing keyed on the new band for 2 own periods; Tune keys with the state off.
             5 — Live with outside effects, with the operator's consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-111-01';
            verify 'CL-111-02';
            verify 'CL-111-03';
            verify 'CL-111-04';
            verify 'CL-111-08';
        }
    }
    dependency CL_111_01_verified_by_TC_111_015 from 'CL-111-01' to 'TC-111-015';
    dependency CL_111_03_verified_by_TC_111_015 from 'CL-111-03' to 'TC-111-015';
    requirement 'CL-061-04' {
        doc /* The station treats every T/R period in which it is on the air as a Tx period and decides it itself (WstxStationProtocol client-server rule, #10: the server decides and pushes, the browser renders). On the air means the transmit owner's PTT is keyed or not confirmed released, a transmission's audio runs, or Tune is on; the station records the period start (its UTC on the transmit owner's clock, the clock the transmitter keys on) of every such observation and the start of the last transmitted period (transmit.last_period_utc), the latest 16. The receive path reads this without waiting for the transmit owner. For a Tx period: (1) no decode attempt: the live worker skips its analysis windows (prompt and late), no record and no UDP decode is published for it and the decoder is not marked busy; the job's latest_decode for that period carries "transmitted": true with an empty range (first_sequence = next_sequence = the frozen publication end) and complete false (RadioIO LatestDecodePeriod); (2) no Rx level measurement while on the air and for the rest of that Tx period: station.tick rx_level_db is null then, and the measurement restarts with the next receive period, so a level and the "Audio level low/overdriven" error-field entries refer to receive periods only (the browser shows "Tx · not measured" while station.tick says transmitting); (3) the waterfall rows of a Tx period carry "tx": true (spectrum.frame and spectrum.detail.frame, the key present only then) and the browser paints them as Tx rows (RGB(90,20,30)) without a spectrum trace, never as received silence; (4) the period bar (red), the QSO pane line "TX now", the Band Activity marker (CL-061-03) and the meter state Tx while the error field shows no level entry. Audio capture keeps running throughout: no device stop or start and no loss epoch; only the use of the samples is suspended. HALT, the Tx watchdog and PTT release are unchanged. Without a correlated receive clock no period can be named: decoding continues and only the level stops while on the air. Deliberate differences from WSJT-X 3.3 (half duplex: MainWindow::transmitDisplay calls monitor(false), which suspends the audio input stream and cancels a pending FT8 decode, and stopTx resumes it with monitor(true); the signal meter is set to 0 and the waterfall receives no rows while transmitting): this station keeps capturing (one continuous source, no restart), marks the Tx rows instead of leaving them out, publishes the Tx period as a marked view, reports the level as unavailable (null) rather than 0 and suspends it to the end of the Tx period rather than to the end of the transmission. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/recording.rs; server/src/transmit/service.rs; client/recording.js; client/contact.js";
    }
    dependency CL_061_04_to_FR_007 from 'CL-061-04' to 'FR-007';
    dependency CL_061_04_to_FR_010 from 'CL-061-04' to 'FR-010';
    dependency CL_061_04_to_FR_019 from 'CL-061-04' to 'FR-019';
    verification 'TC-061-005' {
        doc /* TC-061-005 — The station does not decode or measure in its Tx period
             CL-061-04
             Setup: actual Recording manager and live worker with a correlated FT8 live ring anchored at 2026-10-27T12:00:00 UTC; the Tx periods noted directly on the station's Tx period record (an explicit fixture of the transmit owner's observation).
             Steps: note 12:00:15 as a Tx period; analyze the window of 12:00:15 (prompt) and its late window; analyze the window of 12:00:30; push live blocks inside 12:00:15 with full-scale samples while not on the air, then blocks in 12:00:30; push a block while on the air; then attach the actual transmit owner with a frozen-clock hardware double (no radio) at 12:00:23 in FT8 and in FT4, arm it and turn Tune on, push a block of a receive period, turn Tune off.
             Expected (independent: the noted period and the scripted windows): the 12:00:15 view has transmitted true, complete false, first_sequence = next_sequence and the late window keeps that view; the decoder busy count did not move for it; the 12:00:30 view has no transmitted key and complete true; no level is measured (rx_level null) during the 12:00:15 blocks; the 12:00:30 blocks give a level again after 1 s; while on the air rx_level is null and the waterfall rows carry tx true, receive rows carry no tx key; with the transmit owner on the air rx_level is null at once and the block adds no level, and after the release the recorded Tx period is exactly 12:00:15 (FT8) or 12:00:22.5 (FT4). On the parent code the 12:00:15 window is decoded and published complete.
             2 — Isolated Rust tests; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-04';
        }
        attribute executable : String = "server/src/recording_tx_tests.rs";
    }
    dependency CL_061_04_verified_by_TC_061_005 from 'CL-061-04' to 'TC-061-005';
    verification 'TC-061-006' {
        doc /* TC-061-006 — The browser renders Tx rows and shows level warnings only for receive periods
             CL-061-04
             Setup: actual station Router and browser client with a scripted correlated live receive, Detailed waterfall frames and station.tick events (explicit presentation fixtures).
             Steps: deliver a station.tick with rx_level_db 5 (low) while receiving; then a tick with transmitting true and rx_level_db null; then a tick after the transmission with rx_level_db null; then a tick of the next receive period with rx_level_db 5; send two Detailed rows with tx true and one without.
             Expected (independent: the scripted ticks and rows): the error field shows "Audio level low" for the first tick; while transmitting the meter reads "Tx · not measured" and neither "Audio level low" nor "Audio overdriven" is listed, nor after the transmission while rx_level_db is null; the receive tick shows "Audio level low" again; the waterfall paints the tx rows RGB(90,20,30) and the receive row with its levels. On the parent client the meter reads "Unavailable" while transmitting and the tx frames are refused (unknown key); on the parent station the level is still measured in the Tx period (TC-061-005).
             2 — Isolated automated browser test; Windows PC, no radio. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-061-04';
        }
        attribute executable : String = "tests/ui-operating.test.cjs";
    }
    dependency CL_061_04_verified_by_TC_061_006 from 'CL-061-04' to 'TC-061-006';
    verification 'TC-061-007' {
        doc /* TC-061-007 — Tx periods on HB9BLA
             CL-061-04
             Setup: the gated candidate installed on HB9BLA, 40 m FT8 and FT4, CQ, RF power set low by the test before the first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it holds COM3; read back; the operator's value is restored afterwards only if the radio still reads what the test set, otherwise it is left alone and reported), the operator's consent, one browser on the LAN.
             Steps: call CQ for at least three own periods; watch Band Activity, the waterfall, the meter and the error field; read GET /receive during a Tx period.
             Expected: each Tx period shows the Tx marker and no empty block, its waterfall rows are Tx rows, no "Audio level low" entry appears in or right after a Tx period, the receive periods decode and show their level; audio.loss_epochs does not grow from the transmissions; HALT stops the transmission as before.
             5 — Live with RF on the station, operator consent; HB9BLA. Not run by the automated gate. */
        attribute automation : AutomationState = AutomationState::planned;
        attribute method : String = "manual";
        objective {
            verify 'CL-061-04';
        }
    }
    dependency CL_061_04_verified_by_TC_061_007 from 'CL-061-04' to 'TC-061-007';
}
