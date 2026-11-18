package WstxAudioDevice {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioControl::AudioState;
    private import WstxAudioControl::AudioConfig;
    private import WstxAudioStreams::SourceError;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

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

    verification 'TC-002-003' {
        doc /* The capture from a sound device: its state, its loss and its end. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-08'; }
        @TestedBy { test = "server/tests/audio_contract.rs"; }
    }
}
