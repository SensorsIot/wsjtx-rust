package WstxReceiveControl {
    private import ScalarValues::*;
    private import WstxAudioStreams::CaptureEvent;
    private import WstxAudioStreams::CaptureCounts;
    private import WstxAudioStreams::EpochTie;
    private import WstxDecodes::ResultRecord;
    private import WstxDecodes::PeriodView;
    private import WstxModeProcessing::APrioriContext;

    doc /* The configuration of the receive function; what the station service gives
         receive (its configuration, its commands, and when the station is on the air)
         and what receive reports: its job, the state of live receive, the records it
         keeps and the counters of its decode windows. */

    // ---- The configuration of receive -------------------------------------------------------

    attribute def ReceiveConfig {
        doc /* The configuration of the receive function. */
        attribute window_dump : Boolean = false {
            doc /* The window dump switch. On: receive writes each prompt decode window
                 of FT8 to a file, for the diagnosis of the decoder. */ }
    }
    item def ReceiveConfiguration {
        doc /* The configuration of receive. The station service gives it at station
             start and whenever the station config changes. */
        attribute config : ReceiveConfig;
        attribute folder : String {
            doc /* The profile's folder (WstxProfileAccess::ProfileFolder), in which
                 receive writes the dumped decode windows. */ }
    }

    // ---- The job ----------------------------------------------------------------------------

    enum def ReceiveMode {
        doc /* What a live job does with the receive stream.
             spectrum: it makes spectrum rows.
             ft4, ft8: it makes spectrum rows and decodes that mode. */
        enum spectrum;
        enum ft4;
        enum ft8;
    }
    enum def ReceiveKind {
        doc /* live: a job on the receive stream.
             spectrum: the replay of the stored recording as spectrum rows. */
        enum live;
        enum spectrum;
    }
    enum def ReceiveState {
        doc /* running: the job works.
             cancelling: its end was asked for and it has not yet let go of its source.
             completed: a replay has shown the whole recording.
             cancelled: it ended because its end was asked for.
             failed: it ended with an error. */
        enum running;
        enum cancelling;
        enum completed;
        enum cancelled;
        enum failed;
    }
    enum def ErrorCode {
        doc /* Why receive refuses a command or a job has failed.
             not_found: the command names a job, a source or a recording that is not
             the current one.
             busy: another job, an import of a recording or a band or mode selection
             has not ended.
             storage_unavailable: the storage of the profile has an error.
             counter_exhausted: a count has reached its end.
             no_recording: no recording is stored.
             recording_unavailable: the stored recording cannot be read.
             audio_unavailable: the receive stream cannot be had.
             unsupported_audio: the format of the radio connection is none audio takes.
             audio_close_failed: the radio connection did not close.
             audio_failed: the receive stream failed in another way.
             cancelled: the receive stream was stopped while the job ran.
             decode_limit: a decode window or a decoded frame is outside the limits.
             invalid_request: a request for records that cannot be answered.
             dump_failed: a window could not be written. */
        enum state_conflict;
        enum not_found;
        enum busy;
        enum storage_unavailable;
        enum counter_exhausted;
        enum no_recording;
        enum recording_unavailable;
        enum audio_unavailable;
        enum unsupported_audio;
        enum audio_close_failed;
        enum audio_failed;
        enum cancelled;
        enum decode_limit;
        enum invalid_request;
        enum dump_failed;
    }
    attribute def JobView {
        doc /* One job of receive. */
        attribute id : String;
        attribute source_id : String[0..1] {
            doc /* The source the job works on: the recording, or the current epoch of
                 the receive stream. Absent for a live job until it has taken up its
                 first epoch. */ }
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer {
            doc /* How far the job has come in its source. */ }
        attribute error : ErrorCode[0..1] { doc /* Present in the state failed. */ }
    }

    // ---- Commands ---------------------------------------------------------------------------

    item def StartLive {
        doc /* Start a live job in this mode. */
        attribute mode : ReceiveMode;
    }
    item def StopLive {
        doc /* End the live job. */
        attribute jobId : String;
    }
    item def StartReplay {
        doc /* Show the stored recording as spectrum rows. */
        attribute recordingId : String;
    }
    item def CancelJob {
        doc /* End a job, of either kind. */
        attribute jobId : String;
    }
    item def JobAccepted {
        doc /* The answer to an accepted StartLive, StopLive, StartReplay or CancelJob:
             the job as it is after the command. */
        attribute job : JobView;
    }
    item def Refused {
        doc /* The answer to a command receive does not carry out. Nothing has changed. */
        attribute error : ErrorCode;
    }
    item def OnAir {
        doc /* Whether the station is on the air: it keys the radio, plays a
             transmission or tunes. The station service gives it whenever one of the two
             values changes; they are on_air and last_period_utc_ms of the transmit
             function's TransmitStatus. */
        attribute onAir : Boolean;
        attribute lastPeriodStartMs : Integer[0..1] {
            doc /* The start, in station time, of the period the station last
                 transmitted in. Absent before the first transmission. */ }
    }

    item def ContactContext {
        doc /* What the station knows about its calls and its contact, for the decoding
             of the next windows. The station service gives it at station start and
             whenever it changes. */
        attribute context : APrioriContext;
    }

    // ---- The records receive keeps ------------------------------------------------------------

    item def ReadRecords {
        doc /* Ask for the kept records of the live job from a sequence on. */
        attribute sourceId : String;
        attribute jobId : String;
        attribute cursor : Integer { doc /* The sequence of the first record wanted. */ }
        attribute limit : Integer { doc /* The most records wanted. */ }
    }
    item def RecordsPage {
        doc /* The answer to ReadRecords: the kept records from the cursor on, in the
             order of their sequence, at most as many as asked for. */
        attribute first_sequence : Integer { doc /* The oldest record kept. */ }
        attribute next_sequence : Integer {
            doc /* The sequence the next record will have. */ }
        item records : ResultRecord[0..*];
        attribute more : Boolean {
            doc /* True when kept records after the last one of the page exist. */ }
        item latest_decode : PeriodView[0..1] {
            doc /* The view last published. Absent until the first one. */ }
    }
    item def CursorExpired {
        doc /* The answer to ReadRecords for a cursor before the oldest record kept. */
        attribute first_sequence : Integer;
        attribute next_sequence : Integer;
    }

    // ---- The state receive reports --------------------------------------------------------

    attribute def FrameSpan {
        doc /* A run of samples of the stream, from first_frame up to, and not including,
             end_frame. */
        attribute first_frame : Integer;
        attribute end_frame : Integer;
    }
    attribute def LiveView {
        doc /* The state of live receive. */
        attribute mode : ReceiveMode;
        attribute tie : EpochTie[0..1] {
            doc /* The tie of the current epoch to station time, as audio gave it.
                 Absent while the epoch is not tied. */ }
        attribute next_frame : Integer {
            doc /* The sample of the current epoch that comes next. */ }
        attribute first_sequence : Integer { doc /* The oldest record kept. */ }
        attribute next_sequence : Integer;
        attribute search_limited : Boolean {
            doc /* True after a window held more candidates than the decoder
                 searches. */ }
        attribute last_overrun : FrameSpan[0..1] {
            doc /* The window last given up because the next one came due. Absent until
                 that has happened in the current epoch. */ }
        attribute rx_level_db : Integer[0..1] {
            doc /* The level of the receive stream. Absent while none is measured. */ }
        attribute loss_epochs : Integer {
            doc /* How many epochs after the first began with a loss in the capture. */ }
        attribute last_loss : CaptureEvent[0..1] {
            doc /* What caused the latest of them. Absent while loss_epochs is 0. */ }
    }
    item def ReceiveStatus {
        doc /* The state of receive at the moment it is read. */
        attribute job : JobView[0..1] {
            doc /* The job last admitted, also after its end. Absent before the first
                 one. */ }
        attribute live : LiveView[0..1] {
            doc /* Present from the admission of a live job until the next start is
                 admitted. */ }
        item latest_decode : PeriodView[0..1] {
            doc /* The view last published. Absent without live receive, until the
                 first view, and again after a break in the stream. */ }
        attribute decoding : Boolean { doc /* True while a window is being decoded. */ }
        attribute decode_windows : Integer {
            doc /* How many windows have been given to the decoder since station
                 start. */ }
    }

    // ---- The counters of the decode windows -------------------------------------------------

    attribute def WindowCounters {
        doc /* What receive counted in one window it gave to the decoder. */
        attribute mode : ReceiveMode;
        attribute origin : Integer { doc /* The first sample of the window. */ }
        attribute frames : Integer { doc /* Its length. */ }
        attribute late : Boolean { doc /* True for the late window of a period. */ }
        attribute period_start_frame : Integer[0..1] {
            doc /* The sample at which the window's period starts. Absent while the
                 epoch is not tied. */ }
        attribute period_start_utc : String[0..1] { doc /* Absent likewise. */ }
        attribute window_offset_ms : Integer[0..1] {
            doc /* The start of the window against the start of its period. Absent
                 likewise. */ }
        attribute zero_samples : Integer { doc /* Samples that are exactly 0. */ }
        attribute longest_zero_run : Integer;
        attribute early_buffer_zero_samples : Integer[0..1] {
            doc /* The zeros in the first 41 symbols of an FT8 period. Absent without a
                 period start. */ }
        attribute zero_filled_frames : Integer {
            doc /* CaptureMarks::zeroFilledFrames of the window. */ }
        attribute glitch_frames : Integer {
            doc /* CaptureMarks::glitchFrames of the window. */ }
        attribute capture : CaptureCounts;
        attribute capture_drift_ms : Integer[0..1] {
            doc /* How far the capture clock had moved from its tie. Absent until
                 measured. */ }
        attribute dump : String[0..1] {
            doc /* The name of the file the window was written to. Absent for a window
                 that was not written. */ }
    }
    item def ReadDiagnostics {
        doc /* Ask for the counters of the latest windows. */
    }
    item def DiagnosticsView {
        doc /* The answer to ReadDiagnostics. */
        attribute window_dump : Boolean { doc /* ReceiveConfig::window_dump. */ }
        attribute dump_error : ErrorCode[0..1] {
            doc /* dump_failed after a window could not be written, until the next one
                 is written. */ }
        attribute dumped_windows : Integer {
            doc /* How many windows were written since station start. */ }
        attribute windows : WindowCounters[0..*] ordered {
            doc /* The latest windows, the oldest first. */ }
    }

    port def ReceiveControlPort {
        doc /* Written from the station service's side; receive uses the conjugate.
             StartLive, StopLive, StartReplay and CancelJob are answered by JobAccepted
             or Refused; ReadRecords by RecordsPage, CursorExpired or Refused;
             ReadDiagnostics by DiagnosticsView. ReceiveConfiguration, OnAir and
             ContactContext have no answer. */
        out item configuration : ReceiveConfiguration;
        out item startLive : StartLive;
        out item stopLive : StopLive;
        out item startReplay : StartReplay;
        out item cancelJob : CancelJob;
        out item onAir : OnAir;
        out item context : ContactContext;
        out item readRecords : ReadRecords;
        out item readDiagnostics : ReadDiagnostics;
        in item accepted : JobAccepted;
        in item refused : Refused;
        in item page : RecordsPage;
        in item expired : CursorExpired;
        in item diagnostics : DiagnosticsView;
        in item status : ReceiveStatus;
    }
    interface def ReceiveControl {
        doc /* The station service commands the receive function; receive reports its
             state. */
        end station : ReceiveControlPort;
        end receive : ~ReceiveControlPort;
    }
}
