package WstxTransmitState {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-006';
    private import WstxRequirements::'FR-008';
    private import WstxTransmitPart::TransmitService;
    private import WstxTransmitControl::*;
    private import WstxOperatingChain::TransmitRequest;
    private import WstxModeProcessing::EncodeRequest;
    private import WstxModeProcessing::Waveform;
    private import WstxModeProcessing::EncodeRefusal;
    private import WstxModeProcessing::EncodeRefusalReason;
    private import WstxModeProcessing::AcceptedMessage;
    private import WstxModeProcessing::Period;
    private import WstxAudioStreams::OpenOutput;
    private import WstxAudioStreams::PlayProgram;
    private import WstxAudioStreams::StopOutput;
    private import WstxAudioStreams::OutputStatus;
    private import WstxAudioStreams::OutputState;
    private import WstxAudioStreams::PlayRefused;
    private import WstxStationTime::StationTime;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;

    requirement 'CL-111-01' {
        subject transmit : TransmitService;
        doc /* Transmit MUST hold the one transmit state of the station, off at every
             station start, switch it on only by an Arm it admits, and report the state
             with the cause of its last change in each direction (TransmitArming). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-111-01'; }

    attribute def TransmitArming {
        doc /* How the transmit state (ArmState) is switched on.
             At station start the state is disarmed with the cause startup and without
             a cause of switching on; nothing of an earlier run is taken up, neither the
             state nor a request.
             The Capability is unsupported while TransmitProfile::configured is false;
             unavailable while it is true and radio control reports the radio as not
             ready; available otherwise.
             Arm is refused with the first of these that holds: transmitUnsupported for
             the Capability unsupported; radioUnavailable for unavailable, while
             TransmitStatus::ptt is indeterminate, while startupRelease is failed, and
             after transmit itself has failed (TransmitFailure::ownerFault).
             An admitted Arm makes the state armed, sets lastArmCause to Arm::cause
             and clears TransmitStatus::refusal; it is admitted alike while the state
             is on.
             A refused Arm leaves the state and both causes as they are and sets
             TransmitStatus::refusal.
             The state goes off only by a stop (Stops). */
    }

    requirement 'CL-111-03' {
        subject transmit : TransmitService;
        doc /* Transmit MUST switch the transmit state off at every stop, with the cause
             of the stop, and of several stops within one step of the contact show the
             cause that stands first in a fixed order (Stops). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-111-03'; }

    attribute def Stops {
        doc /* What switches the transmit state off, and which cause is shown.
             The stops are: Disarm and Abort, with the cause they name; Halt, with halt;
             a refused request that switches off
             (Admission, Transmission), with refused; a failed transmission, with the
             cause Failures gives; and, while the state is on, a Capability that is not
             available, with deviceLost.
             Every stop makes the state disarmed. Disarm and the lost Capability drop
             each request that is not keyed, with the outcome refused and notArmed; a
             transmission that is keyed goes on to its end. A Disarm leaves the radio's
             switch and haltState as they are.
             The shown cause, TransmitStatus::lastDisarmCause, is that of the stop
             standing first in this order, whichever came first: halt; deviceLost;
             failed; refused; contactCancelled given by Abort; txWatchdog;
             bandChanged; modeChanged; contactCancelled given by
             Disarm; contactCompleted.
             The stops compared are those since the later of the last StepBegins and
             the last admitted Arm.
             TransmitStatus::stoppedInStep is true from a stop until the next
             StepBegins. */
    }

    verification 'TC-111-013' {
        doc /* What a stop leaves, and the cause shown of two stops within one step of the contact.
             */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-03'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_013_of_two_stops_in_one_step_the_first_of_the_order_is_shown; "
                + "server/tests/transmit_service.rs::"
                + "tx_watchdog_stop_never_keys_and_tune_ends_at_its_limit; "
                + "server/tests/transmit_service.rs::watchdog_stop_never_touches_ptt";
        }
    }

    requirement 'CL-009-03' {
        subject transmit : TransmitService;
        doc /* Transmit MUST put every request it admits on the air in the period the
             request names, keyed before its audio and released after its last sample,
             and report every step of a request as an outcome (Admission,
             Transmission). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-006'; end #derive ::> 'CL-009-03'; }

    attribute def Admission {
        doc /* Which TransmitRequest is admitted. A request is refused with the first of
             these that holds, in this order; its outcome is refused with that
             TransmitRefusal, which TransmitStatus::refusal shows too.
             duplicateSequence: requestSequence is 0 or not higher than that of every
             request before, admitted or not; nothing else changes.
             transmitUnsupported: the Capability is unsupported.
             notArmed: the transmit state is off.
             radioUnavailable: the Capability is not available.
             busy: the Tune tone is on.
             staleRequest: the request names another mode than StationMode::mode; an
             absent mode refuses nothing.
             clockNotSynchronized, misalignedPeriod, stalePeriod: the start cannot be
             planned now (StartPlan in the schedule of transmit).
             audioStarted: the audio of the transmission for the same period and mode
             has started; the state stays on.
             packRefused, frequencyOutOfRange: the modes part refuses the EncodeRequest
             made of the message, the mode, the Tx offset as toneZeroHz and the rate
             48 kHz; frequencyOutOfRange for EncodeRefusalReason::frequencyOutOfRange,
             packRefused for every other reason.
             A refusal from transmitUnsupported on, except notArmed and audioStarted,
             switches a state that is on off with the cause refused (Stops).
             An admitted request has the outcome accepted and clears
             TransmitStatus::refusal; transmit gives the modes part its message as
             AcceptedMessage.
             At most two requests are held: the current one and one for a later
             period.
             While the current request is not keyed, an admitted request takes its
             place. While it is keyed, a request for the same period and mode takes its
             place until its audio starts, and one for another period becomes the next
             one, in the place of a next one already held. The request that gives way
             has the outcome replaced.
             The next request becomes the current one when the transmission before it
             has completed. */
    }

    attribute def Transmission {
        doc /* How the current request goes on the air. Every step is counted in station
             time (StationTime), and transmit takes a step at least every few
             milliseconds.
             Nothing happens before the period start of the request.
             From the period start on, a request that is not keyed is first examined
             again: another mode than StationMode::mode refuses it with staleRequest,
             and a start that cannot be planned with the refusal of the plan; the state
             goes off with the cause refused.
             Then transmit opens the output (OpenOutput) and, when it is open, keys the
             radio; the transmission counts as keyed when radio control has confirmed
             the key. A key that radio control does not take because the radio's switch
             is in use refuses the request with busy.
             From the audio delay after the period start on, the start is planned once
             more and the waveform is played (PlayProgram) from the sample the plan
             gives, at the scale of the audio drive; a plan that fails refuses the request
             as above, and the radio is released.
             The start of the audio sets lastText and lastPeriodUtcMs and gives the
             outcome started with the station time of that moment.
             When audio reports the program as finished (OutputState::finished),
             transmit stops the output and releases the radio; the confirmed release
             gives the outcome completed, and the transmit state stays on.
             A transmission also completes when that report is seen only after the
             release deadline.
             The release deadline is the start of the audio plus the length of the
             samples still to play plus releaseMarginMs, and not later than the release
             bound of the mode after the period start. A transmission whose end audio
             has not reported by then fails with audioStalled (Failures).
             A Disarm does not move the deadline of a keyed transmission.
             TransmitStatus::outcomes holds the latest keptOutcomes outcomes. */
        attribute releaseMarginMs : Integer = 1000;
        attribute releaseBoundFt8Ms : Integer = 14500;
        attribute releaseBoundFt4Ms : Integer = 7000;
        attribute keptOutcomes : Integer = 32;
        attribute period : Period;
    }

    verification 'TC-008-003' {
        doc /* The transmit state, the admission of a request and its transmission. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-01'; verify 'CL-009-03'; }
        @TestedBy {
            test = "server/tests/transmit_service.rs::"
                + "nothing_is_keyed_or_played_without_explicit_armed_authority; "
                + "server/tests/transmit_service.rs::"
                + "ptt_is_keyed_at_period_start_with_readback_before_audio_at_planned_sample; "
                + "server/tests/transmit_service.rs::"
          + "late_start_skips_the_elapsed_prefix_and_stale_or_unsynchronized_requests_are_refused; "
                + "server/tests/transmit_service.rs::"
                + "pending_request_is_replaced_until_audio_start_then_queued_for_the_next_period; "
                + "server/tests/transmit_service.rs::"
                + "a_request_for_another_period_while_keyed_before_audio_is_queued_not_refused; "
                + "server/src/contact_tests.rs::"
                + "the_owner_never_keys_a_request_of_another_station_mode_without_a_contact_step; "
                + "server/tests/transmit_service.rs::"
                + "restart_never_resumes_an_armed_station_or_its_request; "
                + "server/src/transmit/transmit_http_tests.rs::"
          + "automatic_lifecycle_with_a_transmit_owner_never_emits_ptt_and_no_output_means_no_key; "
                + "server/tests/transmit_service.rs::"
                + "a_late_completion_report_inside_the_bound_completes_and_stays_armed; "
                + "server/tests/transmit_service.rs::"
                + "a_finished_device_completes_even_when_the_owner_step_runs_after_the_deadline";
        }
    }

    requirement 'CL-009-04' {
        subject transmit : TransmitService;
        doc /* Transmit MUST end a transmission or a tone at once on Halt, release the
             radio on every failure of the radio or the output, and switch off a
             radio it finds transmitting at station start or leaves keyed
             at the end of the process (HaltTransmit, Failures, SafetyReleases). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-009-04'; }

    attribute def HaltTransmit {
        doc /* What Halt and Abort do.
             Halt is taken at every moment and in every state; it waits for no step of
             transmit that is under way, for no decoding and for no display.
             Halt stops the output at once (StopOutput), then releases the radio when a
             transmission is keyed, the tone is on or TransmitStatus::ptt is not
             released; it ends the tone, gives the current and the next request the
             outcome halted, and switches the transmit state off with the cause halt.
             A Halt that arrives while the output is being opened or while the key
             waits for the radio ends that wait: the radio is not keyed. One that
             arrives while the key is exchanged is followed by the release.
             HaltReceipt::haltState is idle when nothing was keyed, stopped when the
             release was confirmed, and pending when it was not confirmed within
             haltBoundMs; TransmitStatus::haltState shows the same.
             Abort does what Halt does, with these differences: it waits for a step of
             transmit that is under way, the outcome is aborted, the cause is the one
             it names, haltState stays as it is, and a release that is not confirmed
             sets TransmitStatus::refusal to radioUnavailable.
             When the station process ends (ProcessEnds), transmit stops the output and
             releases the radio as for a Halt. */
        attribute haltBoundMs : Integer = 250 {
            doc /* From the Halt to the stopped output and the confirmed release, while
                 radio control answers. */ }
    }

    attribute def Failures {
        doc /* How a transmission that was begun fails. Every failure stops the output,
             releases the radio when it is keyed or its switch is not released, gives
             the request the outcome failed with the TransmitFailure, switches the
             transmit state off with the cause named here, and drops a next request
             with the outcome refused and notArmed.
             The output does not open: audioUnavailable, deviceLost; the radio is not
             keyed.
             The key is not confirmed: pttTimeout, pttRejected, pttReadbackMismatch or
             pttIndeterminate as radio control reports it, and radioLost when radio
             control cannot be reached; the cause is failed for pttRejected and
             pttReadbackMismatch and deviceLost for the others.
             The program is refused (PlayRefused): audioUnavailable or audioDeviceLost
             by its error, deviceLost.
             The output fails while the program plays: audioDeviceLost, deviceLost.
             The release deadline passes (Transmission): audioStalled, deviceLost.
             The release after the last sample is not confirmed: pttIndeterminate,
             deviceLost.
             While a transmission is keyed, the Capability is not available:
             radioLost, deviceLost.
             Transmit itself fails: ownerFault for the current and the next request,
             with the cause failed; Arm is refused from then on (TransmitArming), and
             Halt is still answered.
             A release that is not confirmed leaves TransmitStatus::ptt indeterminate.
             While it is indeterminate, no request waits, no tone is on and the
             Capability is available, transmit asks for the release again; it does not
             key. */
        attribute keyExchangeMaxMs : Integer = 1000 {
            doc /* Transmit waits this long for radio control to confirm a key or a
                 release. */ }
    }

    attribute def SafetyReleases {
        doc /* The releases transmit asks for outside a transmission.
             At station start: when radio control first reports, from a fresh reading
             of the radio, whether the radio transmits, and it does, and transmit has
             not keyed since station start, transmit asks for one release. A confirmed
             release gives StartupRelease::released, one that is not confirmed failed;
             in every other case the result is notNeeded. This happens once for each
             run of the station and whatever TransmitProfile::configured says; a radio
             that transmits later is left alone.
             At the end of the process: beside the stop of HaltTransmit, when the
             radio's switch may be on, one release is asked for and waited for at most
             exitReleaseMaxMs; no other part's work is waited for before it. */
        attribute exitReleaseMaxMs : Integer = 500;
    }

    verification 'TC-008-005' {
        doc /* Halt, the failures of a transmission and the releases outside one. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-04'; }
        @TestedBy {
            test = "server/tests/transmit_service.rs::"
                + "halt_mid_audio_stops_audio_and_releases_ptt_and_disarms; "
                + "server/tests/transmit_service.rs::"
                + "service_halt_is_confirmed_within_the_bound_while_the_owner_is_busy; "
                + "server/tests/transmit_service.rs::"
                + "halt_through_the_real_actor_unkeys_mid_audio_within_the_bound; "
                + "server/tests/transmit_service.rs::"
                + "halt_during_a_slow_output_open_never_keys; "
                + "server/tests/transmit_service.rs::"
                + "halt_during_a_slow_key_releases_within_the_bound; "
                + "server/tests/transmit_service.rs::"
                + "boxed_station_hardware_aborts_the_key_wait_on_halt; "
                + "server/tests/transmit_service.rs::"
                + "audio_loss_cat_loss_and_ptt_errors_release_and_disarm; "
                + "server/tests/transmit_service.rs::"
                + "ptt_is_released_at_the_hard_deadline_when_the_device_never_finishes_or_stalls; "
                + "server/tests/transmit_service.rs::"
                + "a_device_that_stops_consuming_half_way_is_stalled_and_released_by_the_bound; "
                + "server/tests/transmit_service.rs::"
                + "owner_panic_mid_audio_fails_closed_releases_and_halt_still_answers; "
                + "server/tests/transmit_service.rs::"
            + "arm_is_refused_while_ptt_is_indeterminate_and_submit_checks_the_safety_revision; "
                + "server/tests/transmit_service.rs::"
                + "startup_safety_release_is_off_only_once_per_boot_and_only_when_tx_is_observed; "
                + "server/src/transmit/transmit_http_tests.rs::"
                + "radio_transmitting_at_boot_gets_exactly_one_off_only_release_with_readback; "
                + "server/tests/transmit_service.rs::"
                + "abort_with_a_failed_release_is_reported_not_silent; "
                + "server/tests/transmit_service.rs::"
                + "abort_stops_tune_without_a_halt";
        }
    }

    requirement 'CL-009-07' {
        subject transmit : TransmitService;
        doc /* Transmit MUST shift the tone of a split operation as SplitRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-009-07'; }

    attribute def SplitRule {
        doc /* With TransmitConfig::split rig or fakeIt on a profile that keys the radio
             over CAT (TransmitProfile::configured), the shift is the Tx offset rounded
             down to a multiple of 500 Hz, less 1500 Hz. Transmit gives the split and the
             shift with the KeyRequest, and plays the waveform and the Tune tone at the
             Tx offset less the shift, from 1500 to 1999 Hz. Otherwise the shift is 0. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: MainWindow::setXIT, "
                + "requested_xit = (n/500)*500 - 1500";
        }
    }

    requirement 'CL-111-06' {
        subject transmit : TransmitService;
        doc /* Transmit MUST play the Tune tone on request, whatever the transmit state
             and without changing it, and end the tone at its limit (TuneTone). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-008'; end #derive ::> 'CL-111-06'; }

    attribute def TuneTone {
        doc /* The Tune tone: an unmodulated tone at SetTune::txOffsetHz, at the scale of
             the audio drive.
             SetTune to switch on is refused with the first of these that holds:
             transmitUnsupported for the Capability unsupported; radioUnavailable while
             the Capability is not available, TransmitStatus::ptt is indeterminate,
             startupRelease is failed, or transmit has failed; busy while a request is
             held or a tone is on; frequencyOutOfRange for an offset below offsetMinHz
             or above offsetMaxHz.
             An admitted tone opens the output, keys the radio and plays the tone as
             the program, in automatic first to find the level (LevelFinding); an
             output that does not open or does not take the program refuses it with
             busy, and a key that is not confirmed with
             radioUnavailable, each after a release.
             The tone ends, with a release: by SetTune to switch off, which is always
             admitted; by Halt and Abort; when it has lasted TransmitConfig::tuneSeconds
             (the Tune limit, as the last TransmitProfile gave it; a changed limit holds
             for the next tone); when the output fails; and when the Capability is not
             available.
             Neither the start nor the end of the tone changes the transmit state or
             its causes, with one exception: a tone that ends by a failed output or by
             the lost Capability switches a state that is on off with the cause
             deviceLost. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Configuration.cpp, "
                + "TuneWatchdogTime with its default";
        }
        attribute offsetMinHz : Integer = 200;
        attribute offsetMaxHz : Integer = 2950;
    }

    verification 'TC-111-010' {
        doc /* The Tune tone. */
        subject transmit : TransmitService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-111-06'; }
        @TestedBy {
            test = "server/src/transmit_state_tests.rs::"
                + "tc_111_010_tune_is_independent_of_the_transmit_state; "
                + "server/tests/transmit_service.rs::"
                + "tx_watchdog_stop_never_keys_and_tune_ends_at_its_limit";
        }
    }
}
