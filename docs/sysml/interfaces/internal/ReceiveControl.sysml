package WstxReceiveControl {
    private import ScalarValues::*;
    port def ReceiveControlPort {
        out item command : ReceiveCommand;
        in attribute 'state' : ReceiveState;
    }
    item def ReceiveCommand { doc /* Start, stop, mode, band. */ }
    interface def ReceiveControl {
        doc /* The station service commands the receive function; receive reports its state. */
        end station : ReceiveControlPort;
        end receive : ~ReceiveControlPort;
    }
    enum def ReceiveState { enum running; enum cancelling; enum completed; enum cancelled; enum failed; }
    enum def ReceiveKind { enum spectrum; enum live; }
    enum def ErrorCode {
        enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_request; enum unsupported_version;
        enum wrong_profile; enum state_conflict; enum not_found; enum busy;
        enum invalid_state; enum invalid_recording; enum unsupported_audio;
        enum recording_limit; enum storage_unavailable; enum upload_timeout;
        enum cancelled; enum no_recording; enum generation_exhausted;
        enum recording_unavailable; enum unavailable; enum counter_exhausted;
        enum invalid_samples; enum decode_limit; enum decode_failed;
    }
    attribute def JobView {
        attribute id : String;
        attribute source_id : String[0..1];
        attribute generation : Integer;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        doc /* source_id null only for live opening before first ACK; recorded source and all publication tuples remain required UUIDs. */
    }
}
