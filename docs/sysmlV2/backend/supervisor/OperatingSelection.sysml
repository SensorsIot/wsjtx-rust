package WstxOperatingSelection {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxSupervisorPart::Supervisor;
    private import WstxStationCommands::OperatingSelection;
    private import WstxStationCommands::OperatingBand;
    private import WstxStationCommands::SelectMode;
    private import WstxStationCommands::SelectBand;
    private import WstxStationCommands::CancelSelection;
    private import WstxStationCommands::SelectionAdmitted;
    private import WstxStationCommands::SelectionRefused;
    private import WstxStationCommands::SelectionError;
    private import WstxStationCommands::SelectionState;
    private import WstxRadioControl::ReserveRadio;
    private import WstxRadioControl::OperationRequest;
    private import WstxRadioControl::ControlError;
    private import WstxRadioControl::RadioStatus;
    private import WstxReceiveControl::StartLive;
    private import WstxReceiveControl::StopLive;
    private import WstxTransmitControl::TransmitStatus;
    private import WstxTransmitControl::StationMode;
    private import WstxTransmitControl::StationBand;
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* The mode and band the station operates on: how they are selected, how a
         selection is cancelled, and what the station's operating mode and band are. */

    requirement 'CL-008-07' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST change the operating mode and band by a selection
             only, and carry it out as SelectionRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-008-07'; }

    attribute def SelectionRule {
        doc /* A SelectMode or SelectBand passes the checks of
             WstxStationAuthority::GateRule and then these, in this order; a refusal
             (SelectionRefused) changes nothing.
             Another profile revision or operating revision than the station's:
             state_conflict. Another selection pending, an import of a
             recording or a replay of receive that has not ended: busy. A SelectMode
             while the transmitter is keyed, plays a transmission or tunes
             (TransmitStatus): busy.
             The band is the band of SelectBand, else the band of the selection, else
             the one band whose frequency for a mode (BandFrequency) is the dial radio
             control confirms on its ready connection; without one: select_band_first.
             The mode is the mode of SelectMode, else the station's operating mode
             (OperatingModeRule): a band keeps the mode and a mode keeps the band.
             A band without a frequency for the mode: selection_unavailable. The native
             session not ready, or a managed radio whose connection is not ready or was
             made under another profile revision (RadioStatus): radio_unavailable. The
             operating revision at its end: counter_exhausted.
             With a managed radio the supervisor then reserves radio control
             (LeaseRule) and makes the checks again.
             An admitted selection counts the operating revision up by one, ends the
             live job of receive (StopLive), makes its mode the operating mode at once
             and is answered by SelectionAdmitted in the phase releasing.
             Releasing: it waits until receive has given up the job; when receive does
             not, it ends release_blocked with release_failed.
             Applying: radio control reads whether the radio transmits, and a radio that
             transmits ends it with radio_unavailable; radio control sets the radio
             (OperationRequest receiveSetup: the frequency, USB with filter 1, the data
             mode on with filter 1), sets the AGC (ApplyAgc) and the reservation is
             released. On a native profile radio control tunes the radio's slice.
             Restarting: the selection becomes the mode, band and frequency asked for,
             with the origin native_readback, cat_readback, or manual without a radio,
             and the selection's command id; receive starts a live job in the mode
             (StartLive) on the profile's input device; without an input device it
             ends failed with audio_unconfigured. The receive started is remembered
             (WstxStartup::ResumeRule).
             Applied: the result success.
             A step that fails ends the selection failed with the step's error and
             undoes nothing already set: the selection set stays, and so do the
             settings the radio took.
             An error of radio control is given as busy for busy, cancelled for
             cancelled, radio_timeout for timeout, radio_rejected for rejected,
             readback_mismatch for readbackMismatch, radio_failed_close for failedClose,
             state_conflict for staleContext, invalid_request for invalidRequest and
             invalidConfiguration, selection_unavailable for unsupported, and
             radio_unavailable for the others (ControlError).
             A save of the profile that changes its revision ends a selection that is
             pending, failed with state_conflict, and counts the operating revision up.
             One selection runs at a time; no command waits in a queue.
             The state is given as SelectionState at every change. */
    }
    attribute def BandFrequency {
        doc /* The dial frequency of a band for a mode: the preferred entry of the mode on
             the band in WSJT-X's default list of frequencies, of the region ALL; on 4 m of
             region 1. 160 m and 4 m have none for FT4. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: models/FrequencyList.cpp, the "
                + "preferred FT8 and FT4 entries of the default frequency list";
        }
    }

    requirement 'CL-008-10' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST end a selection, or keep it from being carried out,
             on CancelSelection as CancelRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-008-10'; }

    attribute def CancelRule {
        doc /* A CancelSelection passes the checks of WstxStationAuthority::GateRule.
             A cancel with the command id of the latest cancel is answered as that one
             was, and changes nothing; with that command id and another target or
             operating revision it is refused with state_conflict.
             A cancel of the latest selection is refused with operation_superseded when
             the operating revision has moved since that selection was admitted, or when
             the cancel names neither the revision the selection was made from nor the
             one it was admitted at. Otherwise the selection's work stops, the live job
             it ended or started ends when it still runs, monitorWanted becomes false
             and its phase and result cancelled; the cancel's result is cancelled, or
             already_cancelled when the selection was.
             A cancel of a command id the station has not seen is fenced when it names
             the current operating revision and no selection is pending: a selection
             with that id that arrives later is refused with state_conflict. Otherwise it
             is refused with operation_superseded.
             An accepted cancel counts the operating revision up and is answered by
             SelectionAdmitted in the phase cancelled, with the new revision; the
             operating revision at its end refuses it with counter_exhausted.
             A StopLive of the job of the latest selection cancels that selection too. */
    }

    requirement 'CL-044-16' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST let a selection wait a short time for an exchange
             of radio control in work before it refuses it, as LeaseRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-044-16'; }

    attribute def LeaseRule {
        doc /* A selection reserves radio control with a wait (ReserveRadio::waitMs): a
             reading of the radio or another exchange in work delays it and does not
             refuse it. A reservation that radio control refuses (busy after the wait,
             or at once while the transmitter may be keyed) refuses the selection with
             busy, and nothing changes. */
    }

    requirement 'CL-011-02' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST hold the station's operating mode as
             OperatingModeRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-011-02'; }

    attribute def OperatingModeRule {
        doc /* The operating mode is FT8 at station start; then the mode of the latest live
             job of receive started in FT4 or FT8, or of the latest admitted selection.
             It stays when receive stops. A selection that would change it while the
             transmitter is keyed, plays or tunes is refused (SelectionRule). The
             supervisor gives it to transmit (StationMode) and with the contexts of
             the other functions (WstxStationAuthority::ContextRule) at every change. */
    }

    requirement 'CL-008-11' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST hold the station's band as StationBandRule
             says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-008-11'; }

    attribute def StationBandRule {
        doc /* The station's band is the ADIF band, in lower case, of the dial radio
             control confirms on its ready connection, else the band of the selection;
             absent when neither is known. The supervisor gives it to transmit
             (StationBand) and with the contexts of the other functions
             (WstxStationAuthority::ContextRule) at every change. */
    }

    requirement 'CL-008-12' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST take the dial of the radio as the selection while
             no band is selected, as ReadbackRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-008-12'; }

    attribute def ReadbackRule {
        doc /* While the selection has no band and no selection is pending, a dial that
             radio control confirms on its ready connection, made under the current
             profile revision, and that is the frequency of the operating mode on exactly
             one band (BandFrequency), becomes the selection with the origin cat_readback
             and no command id. It changes neither the operating mode nor the operating
             revision, sets nothing on the radio and starts nothing in receive. At
             station start and after every new connection it is taken again; a band
             already selected stays. */
    }

    verification 'TC-009-005' {
        doc /* Selections and cancels through the supervisor. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-07'; verify 'CL-008-10'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "selection_cancel_tracks_its_worker_through_unknown_source_epoch; "
                + "server/src/recording_tests.rs::"
                + "selection_old_command_cannot_cancel_unrelated_later_start; "
                + "server/src/recording_tests.rs::"
                + "selection_unknown_band_and_safe_counter_refuse_without_effects; "
                + "server/src/recording_tests.rs::"
                + "selection_release_timeout_retains_owner_and_never_commits_target; "
                + "server/src/recording_tests.rs::"
                + "selection_manual_mode_switch_uses_same_owner_and_profile_change_"
                + "blocks_restart; "
                + "server/src/recording_tests.rs::"
                + "selection_profile_success_publishes_cancellation_before_new_reader; "
                + "server/src/recording_tests.rs::"
                + "selection_profile_save_failure_preserves_existing_token";
        }
    }

    verification 'TC-044-023' {
        doc /* A band change meets radio control kept by another exchange. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-16'; }
        @TestedBy {
            test = "server/src/radio_level_tests.rs::"
                + "a_band_change_waits_for_the_lease_of_a_poll_and_is_accepted; "
                + "server/src/radio_level_tests.rs::"
                + "a_lease_that_stays_held_refuses_busy_at_the_bound_and_changes_nothing";
        }
    }

    verification 'TC-011-004' {
        doc /* The operating mode follows receive and is kept while the transmitter is
             busy. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-011-02'; }
        @TestedBy {
            test = "server/src/contact_http_tests.rs::"
                + "ft4_live_job_sets_the_contact_mode_and_tick_period_and_tune_blocks_"
                + "a_mode_change; "
                + "server/src/contact_http_tests.rs::"
                + "a_mode_selection_is_busy_while_ptt_is_keyed_and_while_transmitting; "
                + "server/src/contact_http_tests.rs::"
                + "the_operating_mode_persists_across_a_receive_stop_and_keeps_the_ft4_"
                + "contact";
        }
    }

    verification 'TC-009-008' {
        doc /* The dial of the radio becomes the selection. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-12'; }
        @TestedBy {
            test = "server/src/radioControl/cat_lifecycle_tests.rs::"
                + "station_port_released_by_other_program_reconnects_and_restores_"
                + "selection; "
                + "server/src/radioControl/cat_lifecycle_tests.rs::"
                + "station_readback_adoption_needs_exact_operating_mode_entry_and_"
                + "unknown_band";
        }
    }
}
