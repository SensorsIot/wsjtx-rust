package WstxCapture {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioStreams::*;
    private import WstxAudioControl::CaptureWarning;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::CodeDiffers;

    requirement 'CL-008-02' {
        subject audio : AudioInterface;
        doc /* Audio MUST give receive the audio of the radio connection as one mono stream
             at 12 kHz in which every loss is marked and no sample is made up
             (CaptureStream). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-008-02'; }

    attribute def CaptureStream {
        doc /* How the packets of a radio connection become the receive stream.
             The stream is channel 0 of the packets, scaled to full scale 1 and brought
             to 12 kHz by one conversion for every connection and rate.
             The stream does not depend on how the connection cuts its frames into
             packets.
             Each sample stands at its place in the packets to within one frame of the
             stream.
             A gap of known length (NativePacket::firstFrame) leaves the frames of the gap
             out and counts on; the block after it is marked.
             A loss of unknown length ends the epoch and starts a new one
             (EpochProposal), which names what caused it; samples of the old epoch that
             receive has not taken are discarded. Such a loss is: a packet audio could
             not take, a packet without an arrival time, a packet that steps back, a
             jump of the PC clock, and a packet flagged as a discontinuity whose arrival
             time does not continue the packet before it.
             A flagged packet that continues the packet before it in place and in time
             stays in the stream without a mark on the block; its frames are counted
             (CaptureMarks).
             Every CaptureEvent is counted for the diagnosis of the capture. */
        attribute passbandHighHz : Integer = 3500 {
            doc /* Up to this frequency the conversion changes the level by at most
                 passbandRippleDb. */ }
        attribute passbandRippleDb : Real = 0.1;
        attribute stopbandLowHz : Integer = 5500 {
            doc /* From this frequency upward the conversion lowers the level by at least
                 stopbandDb. */ }
        attribute stopbandDb : Integer = 60;
        attribute queueMs : Integer = 500 {
            doc /* Audio holds up to this much audio that receive has not taken; a packet
                 beyond it is a loss (CaptureEvent::queueFull). */ }
        attribute queuePackets : Integer = 64 {
            doc /* Audio holds up to this many packets that receive has not taken. */ }
        attribute glitchToleranceMs : Integer = 2 {
            doc /* A flagged packet continues the packet before it in time when its
                 arrival time is within this of the time expected. */ }
    }

    verification 'TC-002-001' {
        doc /* The receive stream from scripted packets. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-02'; }
        @TestedBy {
            test = "server/tests/audio_contract.rs; server/tests/audio_receive.rs; "
                + "server/src/audio/audio_tests.rs::each_loss_event_names_its_epoch_trigger; "
                + "server/tests/source_contract.rs::"
                + "epoch_requires_current_owner_ack_and_rejects_old_identity; "
                + "server/tests/receive/audio_listen.rs::"
                + "packet_queue_counts_invalid_full_and_clock_step_losses";
        }
    }

    requirement 'CL-007-11' {
        subject audio : AudioInterface;
        doc /* Audio MUST tie the frame count of each epoch to station time, follow the
             drift of the capture clock against it, and warn when the tie is missing or
             the drift is high (CaptureClock). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-002'; end #derive ::> 'CL-007-11'; }

    attribute def CaptureClock {
        doc /* How the receive stream keeps time.
             An epoch is tied when its first packet has an arrival time and the PC clock
             was read within bracketMaxMs around a reading of the monotonic clock; its
             first frame then stands at that reading of the PC clock, and the station
             time of a frame is its PC clock time plus the clock's correction.
             Otherwise the epoch is not tied, and CaptureWarning::uncorrelated holds
             while the capture runs.
             Audio gives receive the tie of an epoch, and every move of it, as a
             CaptureTie.
             Every packet with an arrival time gives the distance of the capture clock
             from the tie; the distances are averaged over about one second.
             Without an epoch, and while the capture does not run, no warning holds. */
        attribute bracketMaxMs : Integer = 2;
        attribute clockJumpMs : Integer = 20 {
            doc /* A jump of the PC clock against the monotonic clock beyond this ends
                 the epoch (CaptureEvent::clockStep). */ }
        attribute reanchorMs : Integer = 50 {
            doc /* The tie is moved to the averaged distance when that has moved by more
                 than this since the tie was last set. */
            @CodeDiffers {
                what = "Receive moves the tie, not audio: ClockTracker in "
                    + "server/src/receive/recording.rs moves it beyond RESCHEDULE_TICKS, 50 ms.";
            }
        }
        attribute stepMs : Integer = 200 {
            doc /* A distance beyond this from the average starts the average and the
                 measurement of the rate anew. */
            @CodeDiffers {
                what = "Receive starts the average anew, not audio: ClockTracker in "
                    + "server/src/receive/recording.rs does so beyond STEP_TICKS, 200 ms.";
            }
        }
        attribute rateKnownSeconds : Integer = 60 {
            doc /* The rate of the drift is known after this much of the stream. */
            @CodeDiffers {
                what = "Receive measures the rate, not audio: ClockTracker in "
                    + "server/src/receive/recording.rs gives it after 60 s of the stream.";
            }
        }
        attribute driftWarnPpm : Integer = 1000 {
            doc /* CaptureWarning::driftHigh holds while the known rate is beyond this,
                 either way. */
            @CodeDiffers {
                what = "Receive raises driftHigh, not audio: server/src/receive/recording.rs "
                    + "warns beyond CAPTURE_DRIFT_WARN_PPM, 1000 ppm.";
            }
        }
    }

    verification 'TC-007-011' {
        doc /* The tie of the receive stream to station time. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-11'; }
        @TestedBy {
            test = "server/tests/audio_contract.rs::audio_queue_and_clock_bounds; "
                + "server/tests/audio_contract.rs::"
                + "audio_clock_rejected_bracket_preserves_reference; "
                + "server/src/receive/recording_tests.rs::"
                + "drifting_capture_clock_keeps_prompt_windows_on_the_utc_period; "
                + "server/src/transmit/clock_http_tests.rs::"
                + "warnings_windows_time_capture_and_revision";
        }
    }
}
