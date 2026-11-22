package WstxAudioDevice {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioControl::AudioState;
    private import WstxAudioControl::AudioConfig;
    private import WstxAudioStreams::SourceError;
    private import WstxCapture::'CL-008-02';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-008-08' {
        subject audio : AudioInterface;
        doc /* Audio MUST capture from the input device of its configuration, report the
             state of that capture, and open the device again after it is lost
             (DeviceLifecycle). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-008-08'; }

    attribute def DeviceLifecycle {
        doc /* How the capture from a sound device is opened, lost and closed.
             The device is the capture endpoint of AudioConfig::inputDevice.
             A capture without a named endpoint is refused with SourceError::unavailable.
             The state is one of AudioState and is reported at once, also while the
             device opens or closes.
             A device that fails with SourceError::unavailable while the capture is
             wanted is opened again, the same endpoint; every other error ends the
             capture until it is started again.
             Every opening starts a new epoch of the receive stream.
             A device that does not close has the state unavailable with
             SourceError::failedClose; closing is tried again until it succeeds, and the
             device is not opened meanwhile. */
        attribute firstRetryMs : Integer = 1000 {
            doc /* The wait before the first attempt to open again. */ }
        attribute maxRetryMs : Integer = 8000 {
            doc /* Each further attempt waits twice as long as the one before, up to
                 this. A new start of the capture begins at firstRetryMs again. */ }
        attribute closeMaxMs : Integer = 250 {
            doc /* A stop is answered with the state closed within this time, or with
                 failedClose. */ }
    }

    verification 'TC-002-002' {
        doc /* The station's own IC-7300: its receive audio captured. */
        subject audio : AudioInterface;
        @TestLevel { cost = 4; location = TestLocation::station; }
        @Automation { run = AutomationState::partial; method = "automated"; }
        objective { verify 'CL-008-08'; verify 'CL-008-02'; }
        @TestedBy {
            test = "server/tests/receive/audio_hardware.rs::"
                + "selected_radio_audio_capture_evidence; "
                + "server/tests/receive/audio_listen.rs::selected_radio_audio_to_listening_wav";
        }
    }

    verification 'TC-002-003' {
        doc /* The capture from a sound device: its state, its loss and its end. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-08'; }
        @TestedBy {
            test = "server/tests/audio_contract.rs::audio_overflow_and_duplicate_epoch; "
                + "server/tests/audio_contract.rs::audio_lifecycle_retries; "
                + "server/tests/audio_contract.rs::"
                + "audio_capture_without_a_named_endpoint_is_refused_unavailable; "
                + "server/tests/audio_contract.rs::audio_controller_profiles_and_stop; "
                + "server/tests/audio_contract.rs::"
                + "realtime_bound_audio_controller_profiles_and_stop; "
                + "server/tests/audio_contract.rs::"
                + "audio_failed_stop_quarantines_owner_and_apartment_without_reopen; "
                + "server/tests/audio_contract.rs::"
                + "audio_successful_stop_preserves_prior_outcome_without_quarantine";
        }
    }
}
