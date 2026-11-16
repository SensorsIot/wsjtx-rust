package WstxCapture {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-002';
    private import WstxAudioPart::AudioInterface;
    private import WstxAudioStreams::*;
    private import WstxAudioControl::CaptureWarning;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The receive stream ---------------------------------------------------------------

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
        doc /* The receive stream from scripted packets.
             Setup: the audio function fed with hand-built packets and tones computed
             apart from it; no sound device and no radio.
             (a) Tones of 100, 1000, 3000 and 3500 Hz at 44100 and 48000 Hz: level
             within 0.1 dB; tones of 5500, 6000 and 9000 Hz: at most 0.001 of full
             scale.
             (b) One second of a 1000 Hz tone cut into packets of 8192 frames, and into
             packets of 1, 441, 37 and 2048 frames: the same number of samples, equal to
             within 0.00002.
             (c) An impulse at frame 2000: its peak in the stream within one frame of
             that place.
             (d) Float samples 0.25 and -1.0: unchanged; the lowest value of each
             integer encoding: -1.0; a sample that is not finite: refused.
             (e) A packet at frame 1000, then a flagged packet at frame 1960: one epoch,
             the second block at frame 240 and marked.
             (f) A packet without an arrival time: a new epoch that names
             timestampError, its frames counted from 0.
             (g) A flagged packet at the expected frame whose arrival time is 50 ms off:
             a new epoch that names nativeDiscontinuity; an oversize packet: invalidPacket;
             a packet that steps back: frameBackstep.
             (h) A flagged packet at the expected frame, 0.55 ms and 2 ms early or late:
             no epoch and no mark; 2.1 ms early or late: a new epoch.
             (i) 400 packets of which five are flagged, the first packet among them, and
             all continue in time: one epoch, no gap in the frame count, five counted.
             (j) Packets of 500 ms that receive does not take, then one more: refused,
             and the next epoch names queueFull; 64 packets of one frame, then one
             more: refused.
             (k) 100 packets with packets 10 and 11 silent and 40 and 70 flagged in
             time: 240 zero-filled and 240 glitch frames in the first 12000; none after
             a new epoch. 600 silent packets: 72000 zero-filled frames.
             (l) After a stop the stream fails with cancelled.
             (m) 720480 silent frames at 48000 Hz cut into packets of 8192 frames, and
             into packets of 441, 1024, 37 and 1920 frames: one epoch and 180056
             samples each time.
             (n) 1024 frames at frame 0, then a flagged packet at frame 48000: one
             epoch; the block after the gap stands at frame 12000 and is marked.
             (o) After a loss of unknown length, taking up the old epoch is refused with
             staleAcknowledgement; the new epoch counts from 0.
             (p) A two-channel FT8 signal of CQ K1ABC FN42 at 1000 Hz through the
             stream and the decoder: that message, within 1 Hz and within 240 frames
             of its start. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-008-02'; }
        @TestedBy { test = "server/tests/audio_contract.rs; server/tests/audio_receive.rs"; }
    }

    // ---- The capture clock ----------------------------------------------------------------

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
                 than this since the tie was last set. */ }
        attribute stepMs : Integer = 200 {
            doc /* A distance beyond this from the average starts the average and the
                 measurement of the rate anew. */ }
        attribute rateKnownSeconds : Integer = 60 {
            doc /* The rate of the drift is known after this much of the stream. */ }
        attribute driftWarnPpm : Integer = 1000 {
            doc /* CaptureWarning::driftHigh holds while the known rate is beyond this,
                 either way. */ }
    }

    verification 'TC-007-011' {
        doc /* The tie of the receive stream to station time.
             Setup: the audio function with scripted clock readings; for (c) a scripted
             capture through the live receive path; for (d) the station with a scripted
             capture clock. No sound device and no radio.
             (a) The PC clock read within 4 ms around the monotonic reading: tied, with
             2 ms of uncertainty; within 4.0001 ms: not tied.
             (b) The PC clock 20 ms off its last reading: no jump; 20.0001 ms: a jump. A
             reading that is not tied keeps the last one for this comparison.
             (c) A capture clock 2000 ppm slow over 600 s with a PC clock step of
             +0.4 s: from the third period on every prompt window of FT8 ends within
             0.1 s of its period start + 13.8 s; the drift reads at least 1500 ms and
             between 1800 and 2200 ppm. With the tie left unmoved the last window ends
             more than 1.2 s late.
             (d) Before the first epoch: no warning. Tied with a rate of 1000.0 and
             -1000.0 ppm: none; 1000.1 ppm: driftHigh; a rate not yet known: none. Not
             tied: uncorrelated. Capture stopped at 1500 ppm: none. */
        subject audio : AudioInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-007-11'; }
        @TestedBy {
            test = "server/tests/audio_contract.rs::audio_queue_and_clock_bounds; "
                + "server/tests/audio_contract.rs::"
                + "audio_clock_rejected_bracket_preserves_reference; "
                + "server/src/recording_tests.rs::"
                + "drifting_capture_clock_keeps_prompt_windows_on_the_utc_period; "
                + "server/src/transmit/clock_http_tests.rs::"
                + "warnings_windows_time_capture_and_revision";
        }
    }
}
