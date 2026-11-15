package WstxTransmit {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-002';
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-008';
    private import WstxRequirements::'FR-009';
    private import WstxRequirements::'FR-019';
    private import WstxTransmitPart::TransmitService;
    private import WstxTransmitControl::ArmState;
    private import WstxTransmitControl::ArmCause;
    private import WstxTransmitControl::DisarmCause;
    private import WstxTransmitControl::TransmitHaltUse;
    private import WstxTransmitControl::TransmitWatchdog;
    private import WstxTransmitControl::TransmitWire;
    private import WstxOperatingChain::TransmitRefusal;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelNotes::FollowsSource;
    private import RequirementDerivation::*;
    doc /* The station's transmit owner: arming under TransmitAuthority, admission and
         replacement of TransmitRequests, CI-V PTT with readback, 48 kHz output, the priority
         halt, Tune, the Tx watchdog, failure and restart handling, and TransmitWire. */
    @FollowsSource {
        reference = "WSJT-X 3.3.0-beta5 (revision d89fe3) Modulator/Modulator.cpp, "
            + "TxStartPolicy.hpp and widgets/mainwindow.cpp";
    }
    enum def TransmitFailure {
        enum pttTimeout; enum pttRejected; enum pttReadbackMismatch; enum pttIndeterminate;
        enum radioLost; enum audioUnavailable; enum audioDeviceLost; enum audioStalled;
        enum authorityChanged; enum ownerFault;
    }
    enum def PttState { enum released; enum keyed; enum indeterminate; }
    attribute def TransmitAuthority {
        doc /* The station's explicit transmit authority (WstxRadioControlPart::RadioAuthority),
             evaluated at Arm, at every request admission, at keying and on every owner step. */
        doc /* Capability: unsupported unless the saved profile has control.mode cat,
             control.ptt cat and an exact audio.output_device (a receive-only profile, ptt
             disabled, is never transmit capability); unavailable while the CL-022-03 automatic
             CAT gate is not eligible (no current grant, commissioning missing or invalidated)
             or its actor is not ready; otherwise available. */
        doc /* Authority: an explicit operator Arm request carrying the current CL-022 safety
             revision of the selected radio scope, sent by a request with a current CL-022
             grant; a plaintext profile has no grant and never arms. */
        doc /* CL-022 receive-only commissioning is a precondition of CAT but is not transmit
             authority. */
        doc /* Any safety revision change (control or profile edit, recommissioning) disarms
             (authorityChanged); loss of the radio or capability disarms (deviceLost). */
        doc /* MCP and the browser use the same operation; neither can widen it. */
        doc /* PTT is CAT PTT; there is no VOX. */
        doc /* A control failure never makes up a radio-ready state. */
        doc /* Browser timers and display congestion cannot hold transmit authority. */
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
        doc /* Keying: the output device is opened first, then PTT is keyed at the period start
             (keyLeadMs after it; for an admitted late start at once), so the audio delay of
             Ft8Schedule and Ft4Schedule separates the confirmed key from the first sample. */
        doc /* Audio starts only after the key readback, at the first owner step at or after
             period start + audio delay, and plays from the sample PlanTransmitStart gives for
             that instant: a late start skips and never replays. */
        doc /* PTT is released with readback after the device reports the last sample played,
             and at the latest at the device-independent release deadline audio start +
             remaining waveform duration + releaseMarginMs, never later than period start +
             releaseBoundFt8Ms (FT8) or releaseBoundFt4Ms (FT4), whatever the device reports. */
        doc /* Every owner step asks the device first, also at or after the deadline: a device
             that reports every sample played completes normally (released, still armed, the
             contact continues) however late that step runs; a device that has not reported
             the end by the deadline (it stopped consuming, or never reports) is released at
             the deadline and fails audioStalled (disarm deviceLost). */
        doc /* releaseMarginMs covers the render drain (renderBufferMs) and render or owner
             scheduling delays under load, with headroom. */
        doc /* Disarm never unbounds a keyed transmission. */
        doc /* haltMs: from HaltTransmit receipt, audio output stops without waiting for the
             owner lock, and PTT is released and read back within haltMs while CAT answers. */
        doc /* A release exchange that fails or times out (pttExchangeMs per exchange) leaves
             PttState indeterminate, closes that CAT connection and is reported, never hidden. */
        doc /* Halt priority: the halt flag is checked immediately before keying and aborts the
             output open and the wait for the CAT owner; a halt received during the open never
             keys, and one received during the key exchange releases at once after it. */
        doc /* halt_state is stopped only after the confirmed release, otherwise pending with
             the true PttState. */
        doc /* Owner fault: a panic of the transmit owner thread fails closed (audio stopped, one
             release attempt, requests failed ownerFault, disarmed failed, Arm refused for the
             boot) and halt keeps answering. */
        doc /* playbackScale: the unit-peak waveform is played at -6.02 dBFS at Tx level 0 dB,
             the highest; the Tx level (CL-044-12) attenuates below it digitally. */
    }
    action def ExitRelease {
        doc /* On Ctrl+C, console close, logoff, shutdown and any process panic, output stops
             and, only when the CI-V switch may be keyed, one off-only release bounded to
             500 ms is sent. */
    }
    enum def StartupRelease { enum pending; enum notNeeded; enum released; enum failed; }
    action def StartupSafetyRelease {
        @FollowsSource {
            reference = "Icom IC-7300 Full Manual A7292-4EX-12a section 19, command 1C 00 "
                + "(transmit switch): readback 1C 00, release 1C 00 00";
        }
        doc /* A CI-V transmit switch latches, so a crash while keyed can leave the radio
             transmitting. */
        doc /* On the first fresh confirmed transmit switch readback of a boot (whoever queried
             it, normally the CL-022 automatic poll), if it shows TX and this boot has never
             keyed, the transmit owner sends exactly one off-only release with readback through
             PttControl: released, or failed if not confirmed; otherwise notNeeded. */
        doc /* It happens once per boot, is never a key and never anything else, regardless of
             the profile's PTT configuration; a later TX (for example the operator's
             microphone) is not ended. */
        doc /* failed keeps Arm refused for the boot. */
        doc /* It is the single permitted exception to "the automatic CAT lifecycle never sends
             a setter/PTT" (CL-022-03). */
        doc /* It is reported as GET /transmit startup_release
             pending|not_needed|released|failed. */
    }
    attribute def TransmitArming {
        attribute armState : ArmState = ArmState::disarmed;
        attribute lastDisarmCause : DisarmCause = DisarmCause::startup;
        attribute lastArmCause : ArmCause[0..1];
        doc /* The station's one transmit state (CL-111-01), on (armed) or off (disarmed), owned
             by WstxTransmitPart::TransmitService; off at startup and after every DisarmCause. */
        doc /* lastArmCause is who switched it on last (operator, or auto for a run or an MCP
             client) and is absent until the first switch-on of a boot. */
        doc /* Arm/Disarm are requests from QsoAndLogging (the start actions
             WstxQsoTransmit::StartActions, and Enable Tx) through the qso-to-transmit
             connection, or TransmitWire. */
        doc /* Arming requires TransmitAuthority: unsupported capability is refused
             transmitUnsupported, unavailable radioUnavailable, a missing grant or a different
             safety revision notAuthorized, and a PTT switch left indeterminate, a failed
             StartupSafetyRelease or an owner fault radioUnavailable. */
        doc /* These arm conditions are one query of the owner: call_cq, send_next and
             reset_repetitions ask it before they change anything; reply
             and call_dx prepare the QSO and are accepted when it refuses, and the
             state and its cause stay (CL-111-07); Tune checks the same conditions at its own
             start (SetTune). */
        doc /* Disarm sends no new request and cancels requests that are not keyed; a
             transmission already keyed or playing finishes unless halted. */
    }
    attribute def StopOrder {
        doc /* A station step is the time from the begin of one contact step
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
    enum def TransmitOutcomeKind {
        enum accepted; enum replaced; enum started; enum completed; enum halted; enum refused;
        enum failed; enum aborted;
    }
    attribute def TransmitOutcome {
        attribute outcomeSequence : Integer;
        attribute requestSequence : Integer;
        attribute kind : TransmitOutcomeKind;
        attribute refusal : TransmitRefusal[0..1];
        attribute failure : TransmitFailure[0..1];
        attribute audioStartUtcMs : Integer[0..1];
        doc /* started is reported at audio start, completed after the last sample and the
             confirmed PTT release, halted after HaltTransmit. */
        doc /* refused (except duplicateSequence and audioStarted) and failed disarm (DisarmCause
             refused, failed, deviceLost or authorityChanged). */
        doc /* outcomeSequence orders all outcomes of a boot; the consumer reads those after its
             cursor; the last 32 are retained. */
        doc /* No outcome is inferred from a client timeout or a lost response. */
    }
    action def HaltTransmit {
        doc /* The immediate priority stop of a transmission or Tune: it stops audio without the
             owner lock, releases PTT with readback (TransmitTiming haltMs), cancels the pending
             and next requests (halted) and disarms (DisarmCause halt). */
        doc /* It is always admitted for the selected profile (no boot or revision check),
             idempotent, and independent of decode, receive or display congestion
             (WstxRequirements::ProcessingAndHaltOwnership). */
        doc /* An audio failure leaves the control-side halt and release usable. */
        doc /* Wire: POST /transmit/halt exactly {v,profile_id,boot_id,command_id}, 202
             {v:1,command_id,halt_state} with halt_state stopped (confirmed within haltMs),
             pending (not yet confirmed; GET /transmit shows the result) or idle (nothing was
             keyed); a repeated command_id returns the same receipt (last 16). */
    }
    action def SetTune {
        in enable : Boolean;
        in safetyRevision : Integer[0..1];
        doc /* An unmodulated tone at the given Tx offset (200..2950 Hz). */
        doc /* Tune on is accepted whatever the transmit state, while the transmit capability
             is available, safetyRevision is the station's CL-022 safety revision (otherwise
             notAuthorized) and no request is pending and nothing is on the air (otherwise
             busy). */
        doc /* Tune on from a run or an MCP client is an automatic start
             (WstxQsoTransmit::StartActions). */
        doc /* It never changes TransmitArming or its causes: when the radio, the capability or
             that revision is lost Tune ends with PTT release, and a transmit state that is on
             stops for the same loss by its own rule. */
        doc /* Tune is stopped with PTT release by SetTune(false), which needs no revision, by
             HaltTransmit or by the tune limit (WstxQsoTransmit::TuneWatchdog). */
        doc /* On POST /transmit/command tune takes no revision and is accepted only while armed,
             under the armed revision. */
    }
    action def AbortTransmission {
        doc /* Abort QSO (CL-010-03): the contact consumer's immediate stop of the current
             transmission or Tune: it stops audio, releases PTT with readback, reports every
             pending or current request as outcome aborted and disarms with the caller's
             cause. */
        doc /* A failed release leaves PTT indeterminate, as for every release, and is refused
             radio_unavailable so the operator sees it. */
        doc /* It is not HaltTransmit: halt_state and the halt count are unchanged. */
    }
    attribute def StationModeGate {
        attribute stationMode : WstxModeProcessing::Mode[0..1];
        doc /* The transmit owner holds the station's operating mode
             (WstxQsoTransmit::StationOperatingMode), set by the station at every change of
             that mode (live job start, admitted operating selection, owner start) and
             refreshed by every contact step (CL-011-04). */
        doc /* A request whose mode differs is refused staleRequest at admission (disarming as
             any admission refusal) and, if the mode changes after admission, refused
             staleRequest when its period starts, before PTT is keyed or audio starts (a
             request keyed before audio is released); it is never keyed or played. */
        doc /* A transmission whose audio already started finishes, as with any disarm, and a
             mode selection is refused busy meanwhile (WstxQsoTransmit::ModeChange). */
        doc /* The gate does not depend on the 50 ms contact step. An absent stationMode (an
             owner not yet told) gates nothing. */
    }

    attribute transmitAuthority : TransmitAuthority;
    attribute transmitTiming : TransmitTiming;
    attribute transmitArming : TransmitArming;
    attribute stopOrder : StopOrder;
    attribute transmitOutcome : TransmitOutcome;
    attribute stationModeGate : StationModeGate;
    attribute transmitHaltUse : TransmitHaltUse;
    attribute transmitWatchdog : TransmitWatchdog;
    attribute transmitWire : TransmitWire;
    action haltTransmit : HaltTransmit;
    action setTune : SetTune;
    action abortTransmission : AbortTransmission;
    action startupSafetyRelease : StartupSafetyRelease;
    action exitRelease : ExitRelease;

    satisfy 'CL-009-03' by transmitAuthority;
    satisfy 'CL-009-03' by transmitArming;
    satisfy 'CL-009-03' by transmitOutcome;
    satisfy 'CL-009-03' by transmitTiming;
    satisfy 'CL-009-03' by stationModeGate;
    satisfy 'CL-009-03' by setTune;
    satisfy 'CL-009-03' by transmitWatchdog;
    satisfy 'CL-009-03' by transmitWire;
    satisfy 'CL-009-04' by haltTransmit;
    satisfy 'CL-009-04' by transmitHaltUse;
    satisfy 'CL-009-04' by transmitTiming;
    satisfy 'CL-009-04' by startupSafetyRelease;
    satisfy 'CL-009-04' by exitRelease;
    satisfy 'CL-009-04' by transmitOutcome;
    satisfy 'CL-111-01' by transmitArming;
    satisfy 'CL-111-03' by stopOrder;
    satisfy 'CL-111-03' by abortTransmission;
    satisfy 'CL-111-06' by setTune;

    requirement 'CL-009-03' {
        subject transmit : TransmitService;
        doc /* The station MUST manage PTT and transmit audio through its one transmit owner and
             its explicit transmit authority. */
        doc /* It MUST arm only by an explicit operator request with a current CL-022 grant and
             the current safety revision, on a profile with CAT PTT and an exact output device;
             receive-only commissioning is not authority. */
        doc /* It MUST be disarmed at every start, and the authority MUST never be persisted or
             restored. */
        doc /* It MUST admit, replace (until audio start) or refuse TransmitRequests. */
        doc /* It MUST key CI-V PTT with readback before audio, play the 48 kHz waveform from its
             planned sample and release PTT with readback after the last sample. */
        doc /* It MUST provide Tune and the Tx watchdog and report every TransmitOutcome. */
        doc /* The automatic CAT lifecycle MUST never emit PTT. */
        doc /* TransmitClock (the clock), PttControl (radio control) and AudioPlayback (audio)
             serve it. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/transmit/playback.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs; server/src/transmit/codec.rs";
        }
    }
    #derivation connection {
        end #original ::> 'FR-008';
        end #derive ::> 'CL-009-03';
    }
    #derivation connection {
        end #original ::> 'FR-009';
        end #derive ::> 'CL-009-03';
    }
    #derivation connection {
        end #original ::> 'FR-002';
        end #derive ::> 'CL-009-03';
    }
    requirement 'CL-009-04' {
        subject transmit : TransmitService;
        doc /* The station MUST provide an immediate Halt that stops audio and releases PTT with
             readback within TransmitTiming haltMs while CAT answers, cancels pending requests
             and disarms. */
        doc /* Audio device loss, CAT errors or timeouts, authority changes, an unsynchronized
             clock and late or stale requests MUST release PTT or never key it. */
        doc /* An unconfirmed release MUST be reported as indeterminate and recovered off-only. */
        doc /* A transmission MUST never be resumed or replayed after a restart or reconnect. */
        doc /* After a boot, a radio found transmitting before the boot ever keyed MUST get
             exactly one off-only release with readback. */
        doc /* PttControl (radio control) serves it. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/transmit/service.rs; server/src/transmit_http.rs; server/src/radio_control/actor.rs; server/src/radio_control/executor.rs";
        }
    }
    #derivation connection {
        end #original ::> 'FR-008';
        end #derive ::> 'CL-009-04';
    }
    #derivation connection {
        end #original ::> 'FR-006';
        end #derive ::> 'CL-009-04';
    }
    verification 'TC-008-003' {
        doc /* Transmit authority, halt and failure handling
             Setup: the actual transmit owner on a virtual UTC clock with a recording hardware
             double; the actual CI-V actor against an independent emulated IC-7300 peer; the
             actual station router, CL-022 lifecycle and scripted CI-V peer; the contact engine
             against the actual owner core on the virtual clock (contact_tests). No audio
             device, radio or RF.
             (a) A request while disarmed; Arm with unsupported and unavailable capability, a
             wrong safety revision and without a grant: no PTT or audio call or byte while
             disarmed or unauthorized or without an opened output.
             (b) An FT8 request before the period: the output opened before the key at the
             period start, PTT bytes exactly FE FE 94 E0 1C 00 01 FD and 1C 00 00 with 1C 00
             readback, audio at period start + 500 ms with skip 0.
             (c) A late FT8 request: skip (t-500 ms)*48.
             (d) Stale, misaligned, unsynchronized and unknown clock, bad text and offset and
             duplicate sequence requests: each refused with its refusal, nothing keyed.
             (e) Replacement before and after audio start: replaced and audioStarted outcomes in
             order.
             (f) A request for another period while the pending one is keyed before its audio,
             also from the engine stepping between the key and the audio of a late start:
             accepted as the next one, played in its own period after the keyed one, never busy,
             still armed.
             (g) Halt mid-audio on the virtual clock, through the owner thread and through the
             real actor: released within 250 ms and disarmed.
             (h) Audio device loss, CAT loss, key timeout, output open failure and a safety
             revision change: each stops audio, attempts the release and disarms with its
             cause.
             (i) An end report 300 and 900 ms late, and one seen only by an owner step after the
             deadline: completed, still armed, and the next request plays.
             (j) A device that stops consuming half way (FT8, late FT8, FT4): released at audio
             end + 1000 ms (FT8 P+14140 <= P+14500, FT4 P+6340 <= P+7000) as audioStalled,
             disarmed deviceLost.
             (k) The render fill decisions against a modelled 10 ms engine with and without
             40 ms render delays: the 100 ms buffer starts the program within 30 ms and reports
             the end within 100 ms without underrun.
             (l) A release that is not confirmed: indeterminate and recovered off-only.
             (m) A restart: disarmed (startup) with nothing pending.
             (n) Tx watchdog expiry and the Tune limit: watchdog expiry at the configured
             minute.
             (o) Lifecycle polling with the transmit owner present, and close of a keyed
             connection: no poll during the transmit hold; one off-only release on the close.
             (p) Malformed and extra-key wire bodies, wrong Origin, a stale boot and a retained
             command_id: exact wire shapes and refusals.
             (q) A radio in TX at boot and one in RX at boot: exactly one 1C 00 00 then a 1C 00
             readback; zero setter bytes. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
        @TestedBy {
            test = "server/tests/transmit_service.rs; server/src/transmit/transmit_http_tests.rs; server/src/contact_tests.rs";
        }
    }
    verification 'TC-008-002' {
        doc /* Physical controlled FT8 transmit
             Setup: separately approved operation on the HB9BLA IC-7300 (COM3, USB Audio CODEC)
             into a dummy load or the station antenna, RF power set low by the test before the
             first Tx (CI-V 14 0A, value 0003, with the station stopped and idle, because it
             holds COM3; read back; the operator's value is restored afterwards only if the
             radio still reads what the test set, otherwise it is left alone and reported),
             profile with control.ptt cat and the IC-7300 USB output, system clock synchronized
             by the station's SNTP measurement (CL-009-05), the radio's own transmit time-out
             timer set (mandatory, e.g. 3 min) and read back before any keying. Explicit
             operator consent; not run by the automated gate.
             (a) Arm, transmit FT8 messages in both parities, replace before audio start, Tune
             and its limit: PSK Reporter spots of HB9BLA for the transmitted CQ by independent
             receivers (frequency, time); the radio's TX indication, power meter and ALC follow
             PTT.
             (b) Halt mid-transmission, and pull the USB audio or CAT cable during a
             transmission: RF ends within the settled bound in each.
             (c) Restart the station: the restart does not transmit. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; }
        objective {
            verify 'CL-009-03';
            verify 'CL-009-04';
        }
    }
    requirement 'CL-044-13' {
        subject transmit : TransmitService;
        doc /* The server MUST push the Tx level state: each WebSocket peer with a display
             subscription receives radio.tx_level {v 1, type radio.tx_level, data {profile_id,
             boot_id, managed, level_db, stored, alc unknown|available|unavailable, assistant,
             result, meters null|{alc, po_pct, swr_x10}, power_limit_pct, warnings [...]
             (CL-044-14), keying_confirmed (CL-044-15)}} after each change; nothing is polled. */
        doc /* Settings > Radio > Audio shows, for an IC-7300 CAT control only, a Set level
             button, a line with the level and the last result, the last ALC, Po and SWR, and the
             optional Profile power field (settings.radio.power_limit_pct) saved with Apply; the
             Tx level slider is shown only with alc unavailable. Set level and the slider send
             POST /radio/tx-level; a refusal is shown on the line. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/radio_level.rs; server/src/main.rs; client/recording.js; client/app.js";
        }
    }
    #derivation connection {
        end #original ::> 'FR-019';
        end #derive ::> 'CL-044-13';
    }
    #derivation connection {
        end #original ::> 'FR-009';
        end #derive ::> 'CL-044-13';
    }
    requirement 'CL-044-14' {
        subject transmit : TransmitService;
        doc /* In normal operation the station MUST read the radio's meters exactly once per
             transmission, in the middle of its audio: the transmit step calls the read when
             half of the audio remaining at audio start has played, once per transmission, on
             no Tune, and not at all when less than 2 s of audio remained at audio start. */
        doc /* The call returns at once and the burst (CL-044-12: 15 13, 15 11, 15 12) runs on
             its own thread, so the transmit step, the audio and the release never wait for the
             radio, and a PTT exchange cancels the burst. */
        doc /* Nothing is read while Set level runs. */
        doc /* From the reading the level moves by at most one step, stored like CL-044-12 and
             taken by the next transmission's audio start only: ALC above raw 0010 or Po above
             the profile power: one down, not below -40 dB; else ALC exactly 0 and Po below
             80 % of the profile power: one up, not above 0 dB and not back to the ceiling;
             otherwise unchanged. */
        doc /* A lowering on the reading right after a step up makes the level just left the
             ceiling, so a level reading 0 below a level reading above 0010 settles on the lower
             one; any other lowering leaves the step up free, so the level follows a drive that
             falls later. */
        doc /* The ceiling lives in memory until a stored Set level, a changed profile power or
             a restart. */
        doc /* Set level's stop (CL-044-12, ALC 0, one step below the first rise) is inside this
             window, and one step up from it, the ALC onset (reads 4-7, about 6 per dB on the
             IC-7300), stays inside it. */
        doc /* Without a profile power Po is neither over nor low, so there is no step up. */
        doc /* Persistent trouble is an entry in the error field, from the third transmission in
             a row until a reading without it: alc_high (ALC at or above raw 0060, half the ALC
             zone; lowering below that is routine and shows no entry), po_low (Po below half the
             profile power), swr_high (SWR at or above 2.0, raw 0080). A clear fault, SWR at or
             above 3.0 (raw 0120), stops transmitting at once through the priority halt
             (DisarmCause halt) with the entry swr_fault, and automation may not arm again until
             an operator action (WatchdogFromOperator); the entry stays until a later reading
             below 3.0 or a stored Set level. The radio.tx_level data carries these as warnings
             [...]. */
        doc /* A failed read judges nothing. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/radio_level.rs; server/src/transmit/service.rs; server/src/transmit_http.rs; client/recording.js; client/contact.js";
        }
    }
    #derivation connection {
        end #original ::> 'FR-009';
        end #derive ::> 'CL-044-14';
    }
    verification 'TC-044-017' {
        doc /* One meter read per transmission and its bounded correction
             Setup: the actual transmit core on a virtual clock; the actual Recording, transmit
             owner on a recording double and CAT actor on a scripted IC-7300 reporting set
             meter values. No radio or RF.
             (a) The decision table: one down at ALC 0011, none at 0010, no warning from three
             readings of 0059, the floor and 0 dB hold, one up only with ALC 0 and Po below
             80 %, none without a profile power, one down above it, none without ALC, fault at
             0120 and not at 0119, warnings from the third reading, cleared by one good
             reading.
             (b) Two FT8 transmissions and a Tune on the virtual clock: due exactly once at
             period + 6 820 ms in each, none for Tune, none for audio starting at period +
             11 200 ms.
             (c) The call without the hold, then with ALC 0060: no byte without the hold; with
             it exactly 15 13, 15 11, 15 12, level -11 stored, nothing handed to the running
             audio.
             (d) Three transmissions in a row, then a good one: alc_high from the third, level
             -13, gone with the good one.
             (e) SWR 0120, a reading without SWR, then the operator arms and SWR is clear: one
             halt, disarmed halt, automation refused, entry swr_fault; the entry stays with the
             reading without SWR; after the clear reading no entry and still armed.
             (f) The call while Set level runs: no byte.
             (g) The transmit step's call through the station's boxed hardware to the sink, and
             the sink startup installs: one call reaches the sink, one burst from the installed
             sink.
             (h) ALC 0060 with the level file unwritable: the level stays -10, stored false, and
             the next Tune plays -10.
             (i) A radio reading ALC 0 at -10 dB and 0011 at -9 dB with low Po, 40
             transmissions: -10 dB for good after at most two transmissions from -10 dB and
             three from -9 dB, no warning.
             (j) ALC 0031 at -9 dB moving 6 per dB, 40 transmissions: -10, -11, -12, -13 dB and
             then unchanged, no warning.
             (k) Set level and then the correction on a radio with ALC 0 up to -9 dB and 0007
             at -8 dB, rising 6 per dB, with low Po: Set level stores -9 dB, the correction
             takes it to -8 dB and stays, from -7 dB it comes back to -8 dB and stays.
             (l) A step up, ALC 0011 and then 0 with low Po, the same profile power and then a
             changed one, again a step up and ALC 0011, and a stored Set level at the ceiling:
             the level stays with ALC 0 and the same profile power, and goes up one after the
             changed profile power and after the stored Set level.
             (m) ALC 0013 with no step up before it, then ALC 0 twice with low Po, then 0005,
             0013 and 0: -13, -12, -11, -11, -12, -11 dB. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-14';
        }
        @TestedBy {
            test = "server/src/radio_level_tests.rs; server/src/transmit/transmit_http_tests.rs; server/tests/transmit_service.rs";
        }
    }
    verification 'TC-044-018' {
        doc /* Tx trouble in the error field
             Setup: candidate server and Chromium; radio.tx_level events injected. No radio or
             RF.
             (a) The four warnings injected: one error field entry each, swr_fault with error
             severity and the others warn.
             (b) Then none: all entries gone. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-14';
        }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }
    verification 'TC-044-019' {
        doc /* Monitoring on HB9BLA
             Setup: the gated candidate installed on HB9BLA with the IC-7300, the operator's
             consent, 40 m, RF power set by the test to at least 30 W before the first Tx (CI-V
             14 0A, starting at 0090, with the station stopped and idle, because it holds COM3;
             read back; the first Tx must read Po at least 30 %; if below, raise the value and
             repeat; the operator's value is restored afterwards only if the radio still reads
             what the test set, otherwise it is left alone and reported). The station's own stop
             at and above SWR 3.0 is not provoked here; TC-044-017 shows it. The evidence is the
             CI-V readback and the radio.tx_level frames, not the radio's display or a CI-V log.
             Not run by the automated gate.
             (a) Transmit during normal operation and record the radio.tx_level frames and the
             transmit timing: at most one radio.tx_level meter frame per transmission (sent only
             when the values change); decode by another station unaffected.
             (b) Transmit with ALC above 0010: the level goes down one step at the next
             transmission until it reads 0010 or less, with no entry below 0060. */
        @TestLevel { cost = 5; location = TestLocation::station; }
        @Automation { run = AutomationState::planned; method = "manual"; }
        objective {
            verify 'CL-044-14';
        }
    }
    verification 'TC-044-015' {
        doc /* Tx level in Settings > Radio > Audio
             Setup: candidate server and Chromium; radio.tx_level events injected, POST
             /radio/tx-level answered by a route fixture. No radio or RF.
             (a) Open the Audio section for an IC-7300 CAT control: the button is in
             #settings-audio, no slider before alc unavailable.
             (b) Inject meters, a run, its result and alc unavailable: the line and meters show
             the pushed values, a malformed event is ignored.
             (c) Click Set level: exactly one set_level is sent.
             (d) Move the slider: one manual is sent.
             (e) Save a power limit: Apply saves radio.power_limit_pct.
             (f) A disabled control: all of it hidden.
             (g) 360 px: no horizontal overflow. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-13';
        }
        @TestedBy { test = "tests/ui-operating.test.cjs"; }
    }

    requirement 'CL-111-01' {
        subject transmit : TransmitService;
        doc /* The station MUST have one transmit state, on or off, with the cause of its last
             change in both directions. */
        doc /* It MUST be off at every station start (cause startup). */
        doc /* It is on only from an accepted start action (CL-111-02) until the next stop
             (CL-111-03). */
        doc /* While it is off, a TransmitRequest MUST NOT be planned or keyed. */
        doc /* A selection, a setting, a chosen Next message, a reconnect, a reload, a repeated
             command and a partner message MUST never switch it on. */
        doc /* Not delivered yet: three commands still switch the state on directly, and each is
             to be retired: the contact command enable_tx, through which the browser and the runs
             still start; the Set level assistant, which switches the state on (cause operator,
             ending a repetition-limit stop) and off around its tone; and the arm command of the
             transmit route. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/transmit/service.rs; server/src/contact.rs"; }
    }
    #derivation connection {
        end #original ::> 'FR-007';
        end #derive ::> 'CL-111-01';
    }
    #derivation connection {
        end #original ::> 'FR-008';
        end #derive ::> 'CL-111-01';
    }
    requirement 'CL-111-03' {
        subject transmit : TransmitService;
        doc /* A completed, cancelled or stopped sequence MUST NOT transmit: the state goes off
             with the cause of the stop, the pending request is dropped, and nothing is sent
             until the next start. */
        doc /* Stop: cause; transmission on the air; what stays of the QSO. QSO completed:
             contactCompleted; none; completed, logged once. Cancel contact, F4:
             contactCancelled; finishes; cancelled, an own CQ becomes idle. Abort QSO, Esc:
             contactCancelled; stops now, no halt; cancelled. Halt Tx, Alt+H, MCP halt: halt;
             stops now; state kept, an own CQ ends. Repetition limit (Tx watchdog): txWatchdog;
             none keyed; state kept, an own CQ ends. Partner works another station on the own Tx
             frequency: partnerWorksOther; stops now by an abort, no halt; state kept (a contact
             that pauses for a busy partner moves Tx clear instead and stops only when that move
             is refused, CL-097-06). Mode change: modeChanged; as CL-011-04; cancelled. Band
             change: bandChanged; finishes, and a band selection in the program is refused busy
             during a transmission; cancelled as by a mode change: DX call and Tx1 to Tx5
             cleared, Tx6 next, an own CQ becomes idle, a completed QSO keeps its fields. Radio
             or capability lost: deviceLost; released; state kept. Safety revision changed:
             authorityChanged; state kept. Refused or failed transmission: refused, failed; state
             kept. A run ends and leaves a contact it did not finish or cancel, with no other
             stop of this list: runEnded; finishes; state kept. */
        doc /* A band change is any change of the station band the station sees: the station band
             (the radio's dial band, else the band of the operating selection) differs from the
             band the contact was prepared on. It covers a band selection in the program and a
             change at the radio's own dial. An unknown station band is no band change. The
             band-change stop shows bandChanged in every case, also when a run's contact is ended
             by it. The run's own stop reason stays (a pounce: band_changed). A pounce run's
             contact is cancelled like every other. */
        doc /* A stop is admitted with any earlier contact revision, as cancel and abort are. In
             one station step any stop wins over any start: the start is refused state_conflict
             and nothing is sent. When several stops arrive in one step the shown cause is the
             first in StopOrder. */
        doc /* After a stop with the state kept, the QSO continues only by Reply on the partner's
             row or by "Send <exchange> next"; after a repetition-limit stop also by Reset. Enter
             in the DX call field does not continue a stopped QSO. An own CQ ended by the
             repetition limit is started again with the CQ button. */
        doc /* Not delivered yet: no run raises runEnded, and a run that is neither a strategy
             nor a pounce stops contact_changed when the band change ends its contact. */
        doc /* WstxQsoTransmit::BandChange, ModeChange and AutoSequence serve it. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn {
            module = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; server/src/automation.rs";
        }
    }
    #derivation connection {
        end #original ::> 'FR-007';
        end #derive ::> 'CL-111-03';
    }
    #derivation connection {
        end #original ::> 'FR-008';
        end #derive ::> 'CL-111-03';
    }
    requirement 'CL-111-06' {
        subject transmit : TransmitService;
        doc /* The station MUST offer Tune as tune {enabled, safety_revision}. */
        doc /* Tune on MUST be accepted whenever the transmit capability is available with a
             current grant and nothing is on the air or pending, whatever the transmit state. */
        doc /* It is refused stale_revision with field safety_revision on another revision than
             the station's, busy while a transmission is keyed or a request is pending, and
             transmit_unavailable without capability or grant. */
        doc /* From an MCP client or a run it is refused tx_watchdog as an automatic start
             (CL-111-02): when no browser action was seen this boot, after a repetition-limit
             stop or after a clear fault (CL-044-14). */
        doc /* Tune MUST never change the transmit state or its cause. */
        doc /* Its limit is WstxQsoTransmit::TuneWatchdog. Tune off needs no revision. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/transmit/service.rs; server/src/contact.rs; server/src/contact_http.rs; client/contact.js";
        }
    }
    #derivation connection {
        end #original ::> 'FR-008';
        end #derive ::> 'CL-111-06';
    }
    verification 'TC-111-001' {
        doc /* The new causes and the resume
             Setup: the contact engine against the actual transmit owner core on a virtual UTC
             clock with hand-authored rows (transmit_state_tests on the bench of contact_tests),
             profile HB9BLA JN47; a QSO with K1ABC in replying, the state on, Tx1 sent once. For
             (c) the station with a run (strategy_tests). No radio or RF.
             (a) The partner's message to another call within 50 Hz of my Tx frequency, in a
             contact that does not pause for a busy partner (an MCP policy run's contact,
             CL-097-06; a manual contact moves Tx clear instead, TC-097-017): off,
             partnerWorksOther, state kept.
             (b) A mode change: modeChanged, cancelled.
             (c) A run ends leaving its contact: runEnded, state kept. Planned: not automated
             yet.
             (d) After each state-kept stop (Halt, the limit, partner works another as in (a),
             radio lost, refused): 3 own periods, then reply on the partner's row: no request in
             the 3 own periods, then the reply transmits again with the same contact identity. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs";
        }
    }
    verification 'TC-111-002' {
        doc /* What is not a start never transmits
             Setup: as TC-111-001, from a station start; for the reload and the repeated
             command_id the actual station router (contact_http_tests fixture). No radio or RF.
             (a) select_row, enter_dx, choose_next, set_frequency, every setting, snapshot
             reload, reconnect, a repeated command_id and a partner message while off: zero
             requests over 3 own periods, state and cause unchanged. Planned: the reconnect is
             not automated yet. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-01';
        }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs";
        }
    }
    verification 'TC-111-007' {
        doc /* Wire
             Setup: the actual station router (contact_http_tests fixture). No radio or RF.
             (a) GET /contact and the transmit.state event at a station start, after a start and
             after a stop: the transmit view (WstxQsoControl::ContactSnapshot,
             WstxTransmitControl::TransmitWire) carries the causes of CL-111-03 as snake_case
             values and last_arm_cause (operator, auto or null).
             (b) The largest snapshot and the first event with the longest cause of each
             direction: the snapshot stays at most 4096 bytes and the event at most 1024. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-01';
        }
        @TestedBy { test = "server/src/contact_http_tests.rs"; }
    }
    verification 'TC-111-009' {
        doc /* A band change stops and cancels
             Setup: as TC-111-001, the station band 20m; for the selection, the dial and the
             runs the actual station router (contact_http_tests, strategy_tests). No radio or
             RF.
             (a) QSO in rogerReport, state on, admitted selection 20m to 40m: off, bandChanged,
             cancelled, DX call cleared, no request in 3 periods.
             (b) The same QSO, the radio's dial moved to 7.074 MHz with no selection: the same.
             (c) Own CQ: idle, off.
             (d) Completed QSO: fields kept.
             (e) A selection of the same band, a dial change inside the band, and an unknown
             station band: nothing changes.
             (f) A selection during a transmission: busy, QSO and state unchanged (guard,
             TC-044-023).
             (g) A strategy run's contact at a dial band change: cancelled, cause bandChanged.
             (h) A pounce run in its contact: run stopped band_changed, contact cancelled, cause
             bandChanged.
             Automated: (a) and (b) as the station band at the engine and as the band of the
             operating selection at the station, (c), (d), (e); the dial as the station band is
             shown for a run's own CQ (TC-063-010). Planned: (b) for a QSO at the station, (g),
             (h). */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs; server/src/contact_http_tests.rs";
        }
    }
    verification 'TC-111-010' {
        doc /* Tune
             Setup: as TC-111-001. No radio or RF.
             (a) State off, no contact, ready: Tune on; Tune off: keyed, state and cause
             unchanged; released.
             (b) A stale safety revision: stale_revision, not keyed.
             (c) A request pending, and a transmission on the air: busy.
             (d) No capability, and no grant: transmit_unavailable.
             (e) Reply while Tune is on; Tune ends; 3 periods: accepted, QSO prepared, refusal
             busy, state off, nothing sent.
             (f) The Tune watchdog at 1 s: Tune ends (guard, TC-008-001).
             (g) Tune on from an MCP principal at boot before any browser action, after a
             browser action, after a clear fault (require_operator), and after a
             repetition-limit stop: tx_watchdog and not keyed at boot, after the clear fault and
             after the limit; keyed after the browser action. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-06';
        }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs; server/src/contact_tests.rs; server/src/contact_http_tests.rs";
        }
    }
    verification 'TC-111-013' {
        doc /* A stop wins
             Setup: as TC-111-001. The partner-works-other steps run in a contact that does not
             pause for a busy partner (an MCP policy run's contact, CL-097-06), as TC-111-001
             (a). No radio or RF.
             (a) Stop against start in one station step: Halt and reply; the limit and
             send_next; a band change and call_cq: the start is state_conflict, state off,
             nothing keyed.
             (b) Halt and radio lost in one step: halt.
             (c) Radio lost and Abort QSO: deviceLost.
             (d) Abort QSO and the limit: contactCancelled.
             (e) The limit and partner works another: txWatchdog.
             (f) Partner works another and a band change: partnerWorksOther.
             (g) Cancel contact and the limit: txWatchdog.
             (h) A band change and completion: bandChanged. */
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-111-03';
        }
        @TestedBy { test = "server/src/transmit_state_tests.rs"; }
    }
}
