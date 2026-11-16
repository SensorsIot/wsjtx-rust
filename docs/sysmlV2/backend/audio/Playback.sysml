package WstxPlayback {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioStreams::*;
    private import WstxAudioControl::AudioConfig;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    requirement 'CL-009-06' {
        subject audio : AudioInterface;
        doc /* Audio MUST play the program transmit gives it on the sound device the
             profile names for output, and report when the device has played all of it
             or is lost (ProgramPlayback). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-009-06'; }

    attribute def ProgramPlayback {
        doc /* How a program is played.
             The device is the render endpoint of AudioConfig::output_device.
             OpenOutput opens it and plays silence (OutputState::ready); a device that
             does not open is failed with its OutputError.
             PlayProgram is taken in the state ready, once for each opening.
             The program goes to every channel of the device, each sample multiplied by
             the scale and limited to full scale.
             A waveform plays from its sample skip to its last sample; nothing is
             written after it, and the state is finished when the device has played
             every sample. A tone plays until it is stopped.
             SetScale changes the scale of the program that plays from its next sample;
             a tone keeps its phase.
             A device that fails or disappears while open is failed with deviceLost.
             StopOutput ends the program at once and closes the device; it also ends an
             opening that has not finished. */
        attribute sampleRateHz : Integer = 48000 {
            doc /* The rate of the program and of the device. */ }
        attribute openMaxMs : Integer = 1000 {
            doc /* A device that has not opened within this is unavailable. */ }
        attribute renderBufferMs : Integer = 100 {
            doc /* A program is kept queued at the device up to this, so that a short
                 delay of the station does not interrupt it. */ }
        attribute silencePrefillMs : Integer = 20 {
            doc /* Without a program at most this much silence is queued, so the first
                 sample of a program is delayed by no more. */ }
        attribute stallMs : Integer = 500 {
            doc /* While a program plays, a device that takes no sample for longer than
                 this is failed with deviceLost. */ }
        attribute closeMaxMs : Integer = 250 {
            doc /* Audio waits up to this for the device to close after StopOutput. */ }
    }

    verification 'TC-008-004' {
        doc /* A program on a scripted output device.
             Setup: the playback function writing into buffers and a modelled device
             with a period of 10 ms; no sound device and no radio.
             (a) The waveform 0, 0.25, -0.5, 1.0 with skip 1 and scale 0.5 on two 16-bit
             channels: 4096, -8192 and 16384 on both channels, then silence.
             (b) A tone of 12000 Hz with scale 1: 0, 1, 0, -1; it does not end.
             (c) No program and 100 of 480 frames queued: 380 frames of silence. A
             program and 470 queued: 10 frames of it. After its last sample with 300
             queued: nothing written; with none queued: finished.
             (d) A device that takes no sample for 501 ms while a program plays: lost;
             one that takes samples again within that time: not lost.
             (e) A waveform through the device, undisturbed and with the station delayed
             40 ms once a second: its first sample within 30 ms of PlayProgram, its end
             reported within 100 ms of its length, no interruption.
             (f) Planned, no test yet: a PlayProgram while a program plays and after it
             has finished: PlayRefused with unavailable.
             (g) Planned, no test yet: a device that does not open: unavailable after
             1000 ms.
             (h) Planned, no test yet: StopOutput returns within 250 ms also when the
             device does not close. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-06'; }
        @TestedBy {
            test = "server/tests/transmit_service.rs::"
                + "output_renderer_plays_from_the_planned_sample_on_every_channel_then_silence; "
                + "server/tests/transmit_service.rs::"
                + "render_drain_stops_topping_up_and_watchdog_flags_a_stall; "
                + "server/tests/transmit_service.rs::"
                + "the_render_buffer_absorbs_render_delays_without_delaying_the_start_or_the_end";
        }
    }
}
