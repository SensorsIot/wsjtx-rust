package WstxAudioStreams {
    private import ScalarValues::*;
    private import WstxSoundDevice::Encoding;

    doc /* The sample streams of the station: the packets a radio connection gives to
         audio, the receive stream audio gives to receive, and the program transmit
         gives to audio for playing. */

    // ---- From a radio connection to audio -----------------------------------------------

    item def NativeFormat {
        doc /* The form of the packets of one connection, fixed while it is open. */
        attribute rate : Integer { doc /* 44100 or 48000 Hz. */ }
        attribute channels : Integer { doc /* 1 or 2; channel 0 is used. */ }
        attribute encoding : Encoding;
    }
    item def NativePacket {
        doc /* A run of frames as the radio connection delivers them. */
        attribute frames : Integer {
            doc /* From 1 to maxNativePacketFrames. */ }
        attribute firstFrame : Integer {
            doc /* The place of the first frame in the connection's own count. A place
                 beyond the one expected is a gap of known length. */ }
        attribute arrivalTime : Integer[0..1] {
            doc /* When the first frame was taken, on the PC's monotonic clock. Absent
                 when the connection cannot say; the packet then starts a new epoch. */ }
        attribute silent : Boolean {
            doc /* The connection delivered no samples for these frames; they count as
                 zeros and as measured. */ }
        attribute discontinuity : Boolean {
            doc /* The connection reports that frames may be missing before this one. */ }
        attribute maxNativePacketFrames : Integer = 8192;
    }
    item def InputStatus {
        doc /* Whether the connection can deliver packets now. */
        attribute available : Boolean;
        attribute retryAfterMs : Integer[0..1] {
            doc /* The time to the connection's next attempt. Absent while it is
                 available, and when no attempt is planned. */ }
    }
    port def CaptureSamples {
        doc /* Written from the side that delivers the packets. */
        out item format : NativeFormat;
        out item packet : NativePacket;
        out item input : InputStatus;
    }
    interface def CaptureSamplesLink {
        doc /* The packets of a radio's native network connection to audio. */
        end audio : ~CaptureSamples;
        end session : CaptureSamples;
    }

    // ---- From audio to its sound device adapter -----------------------------------------

    item def RenderFrames {
        doc /* Frames for the opened render endpoint, in its own format. */
    }
    port def AudioExchange {
        doc /* Written from the adapter's side: the packets of the opened capture endpoint
             to audio, and the frames to play from audio. */
        out item format : NativeFormat;
        out item packet : NativePacket;
        in item frames : RenderFrames;
    }
    interface def AudioExchangeLink {
        doc /* Audio and the adapter of its sound device. */
        end audio : ~AudioExchange;
        end adapter : AudioExchange;
    }

    // ---- From audio to receive ------------------------------------------------------------

    enum def EpochReason {
        enum captureStart;
        enum captureLoss;
    }
    enum def CaptureEvent {
        doc /* What can break the stream or disturb it.
             queueContention, queueFull, poolExhausted: audio could not take a packet.
             invalidPacket: a packet outside the limits of NativePacket.
             clockStep: the PC clock jumped against the monotonic clock.
             timestampError: a packet without an arrival time.
             nativeDiscontinuity: a packet flagged as a discontinuity.
             frameBackstep: a packet whose first frame lies before the one expected. */
        enum queueContention;
        enum queueFull;
        enum poolExhausted;
        enum invalidPacket;
        enum clockStep;
        enum timestampError;
        enum nativeDiscontinuity;
        enum frameBackstep;
    }
    item def StartCapture {
        doc /* Receive asks for the stream of the profile's radio connection. */
    }
    item def StopCapture {
        doc /* Receive ends the stream; it then fails with cancelled. */
    }
    item def EpochProposal {
        doc /* The start of an epoch: a stretch of the stream without a loss of unknown
             length. Frames are counted from 0 in each epoch.
             Audio sends no sample of an epoch before receive has taken the epoch up. */
        attribute proposal : Integer {
            doc /* The number of the proposal, higher for each one. */ }
        attribute reason : EpochReason;
        attribute trigger : CaptureEvent[0..1] {
            doc /* What broke the stream. Absent for a capture start. */ }
        attribute arrivalTime : Integer[0..1] {
            doc /* The arrival time of the epoch's first packet; absent when that packet
                 has none. Without it the epoch is not tied to station time. */ }
    }
    item def SampleBlock {
        doc /* A run of samples of the receive stream: mono, 12 kHz, each a finite number
             with full scale 1. */
        attribute firstFrame : Integer {
            doc /* The place of the first sample in its epoch. */ }
        attribute samples : Real[1..*];
        attribute discontinuity : Boolean {
            doc /* True for the first block of an epoch and for the first block after a
                 gap of known length. The frame count runs on across such a gap, and no
                 sample stands for a frame that was not captured. */ }
    }
    attribute def EpochTie {
        doc /* Where an epoch stands on the PC clock. */
        attribute anchorFrame : Integer { doc /* A frame of the epoch. */ }
        attribute utc : String {
            doc /* The PC clock time of that frame: UTC as date and time with seven
                 decimals of a second. */ }
        attribute uncertaintyNs : Integer {
            doc /* How closely the PC clock was read. */ }
    }
    item def CaptureTie {
        doc /* The tie of the current epoch. Audio sends it when the epoch is tied and
             again whenever it moves the tie. An epoch for which none was sent is not
             tied. */
        attribute tie : EpochTie;
    }
    attribute def CaptureCounts {
        doc /* How often each CaptureEvent has happened since the capture was started. */
        attribute queueContention : Integer;
        attribute queueFull : Integer;
        attribute poolExhausted : Integer;
        attribute invalidPacket : Integer;
        attribute clockStep : Integer;
        attribute timestampError : Integer;
        attribute nativeDiscontinuity : Integer;
        attribute frameBackstep : Integer;
    }
    item def CaptureMarks {
        doc /* For a span of frames of the current epoch that receive names. */
        attribute zeroFilledFrames : Integer {
            doc /* Frames the connection delivered as silent. */ }
        attribute glitchFrames : Integer {
            doc /* Frames of packets flagged as a discontinuity that were kept on the
                 timeline. */ }
        attribute events : CaptureCounts;
    }
    enum def SourceError {
        doc /* Why a stream failed.
             unavailable: the connection is missing or failed.
             unsupportedFormat: its format is none audio takes.
             invalidBlock: a packet or sample that cannot be used.
             counterExhausted: the frame count has reached its end.
             cancelled: the stream was stopped.
             failedClose: the connection did not close.
             invalidContext, staleAcknowledgement: receive took up an epoch that is not
             the current one. */
        enum invalidContext;
        enum staleAcknowledgement;
        enum counterExhausted;
        enum invalidBlock;
        enum unavailable;
        enum unsupportedFormat;
        enum cancelled;
        enum failedClose;
    }
    item def StreamFailure {
        doc /* The stream has stopped. After unavailable it goes on with a new epoch when
             the connection is open again. */
        attribute error : SourceError;
    }
    item def EpochAccepted {
        doc /* Receive has taken up an epoch. An acceptance that does not name the
             proposal last made is refused with staleAcknowledgement. */
        attribute proposal : Integer;
    }
    port def ReceiveSamples {
        doc /* Written from the side that gives the stream. */
        out item epoch : EpochProposal;
        out item tie : CaptureTie;
        out item samples : SampleBlock;
        out item marks : CaptureMarks;
        out item failed : StreamFailure;
        in item accepted : EpochAccepted;
        in item start : StartCapture;
        in item stop : StopCapture;
    }
    interface def ReceiveSamplesLink {
        doc /* The receive stream to the receive function. */
        end source : ReceiveSamples;
        end receive : ~ReceiveSamples;
    }

    // ---- From transmit to audio -----------------------------------------------------------

    enum def OutputState {
        doc /* opening: the output device is being opened.
             ready: open and playing silence, without a program.
             playing: a program plays.
             finished: the device has played every sample of the program.
             failed: see OutputError.
             closed: the device is closed. */
        enum opening;
        enum ready;
        enum playing;
        enum finished;
        enum failed;
        enum closed;
    }
    enum def OutputError {
        doc /* unavailable: the endpoint is missing or inactive, or does not open.
             unsupportedFormat: its format is none audio plays to.
             deviceLost: the endpoint failed or disappeared while open, or took no
             sample for too long while a program played. */
        enum unavailable;
        enum unsupportedFormat;
        enum deviceLost;
    }
    item def OpenOutput {
        doc /* Open the profile's output device and play silence. */
    }
    item def PlayProgram {
        doc /* One program to play: a waveform, or a tone that lasts until it is stopped. */
        attribute samples : Real[0..*] {
            doc /* The waveform: mono samples at 48 kHz with a peak of 1. Empty for a
                 tone. */ }
        attribute skip : Integer {
            doc /* The sample of the waveform at which playing starts. */ }
        attribute toneHz : Real[0..1] { doc /* The frequency of a tone. */ }
        attribute scale : Real {
            doc /* The factor every sample is multiplied by. */ }
    }
    item def SetScale {
        doc /* Another factor for the program that plays, from its next sample. */
        attribute scale : Real;
    }
    item def StopOutput {
        doc /* Stop the program at once and close the device. */
    }
    item def OutputStatus {
        attribute 'state' : OutputState;
        attribute error : OutputError[0..1] { doc /* Present in the state failed. */ }
    }
    item def PlayRefused {
        doc /* A PlayProgram outside the state ready: refused with the error of a failed
             output, and as unavailable otherwise. */
        attribute error : OutputError;
    }
    port def Playback {
        doc /* Written from transmit's side; audio uses the conjugate. */
        out item open : OpenOutput;
        out item play : PlayProgram;
        out item level : SetScale;
        out item stop : StopOutput;
        in item status : OutputStatus;
        in item refused : PlayRefused;
    }
    interface def PlaybackLink {
        doc /* The program to play, and how far the device has played it. */
        end transmit : Playback;
        end audio : ~Playback;
    }
}
