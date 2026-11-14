package WstxModeProcessing {
    private import ScalarValues::*;
    private import WstxReceiveControl::ErrorCode;
    private import WstxReceiveControl::ReceiveKind;
    private import WstxReceiveControl::ReceiveState;
    port def ReceiveProcessing {
        out item request : ProcessingRequest;
        in item result : ProcessingResult;
    }
    port def EncodeProcessing {
        out item request : EncodeRequest;
        in item waveform : Waveform;
    }
    interface def ReceiveProcessingLink {
        doc /* Samples to decode and the decodes back. */
        end receive : ReceiveProcessing;
        end modes : ~ReceiveProcessing;
    }
    interface def EncodeProcessingLink {
        doc /* A message to encode and its waveform back. */
        end transmit : EncodeProcessing;
        end modes : ~EncodeProcessing;
    }
    item def ProcessingRequest {
        doc /* Receive job/cancel lifecycle correlates profile, boot, source, job and
             generation with immutable settings/results. WstxRecordingReceive owns
             recorded spectrum lifetimes, bounds and cancellation; WstxOfflineDecode
             refines mode settings/results on that lifecycle. Transmit lifecycle and
             independent halt remain outside receive jobs. */
    }
    item def ProcessingResult {
        doc /* WstxDisplayData::SpectrumFrame owns spectrum units, identity,
             bounds and replaceable display delivery. WstxDecodes::ResultRecord
             and WstxLiveReceive::ResultPage own mode payloads and required result
             delivery/retention.
             These have different delivery obligations despite sharing processing. */
    }
    item def EncodeRequest;
    item def Waveform;
    attribute def ReceiveContext {
        attribute profile_id : String;
        attribute boot_id : String;
        attribute source_id : String[0..1];
        attribute job_id : String;
        attribute generation : Integer;
        assert constraint safeGeneration { generation >= 0 and generation <= (900719925 * 10000000 + 4740991) }
        doc /* Opening live job may lack source only until initial provider epoch ACK.
             Recorded spectrum and acknowledged live jobs require their source UUID.
             This pending context never permits publication. Correlation remains the
             REQUIRED full source/job/generation tuple for every frame/result page. */
    }
    item def ReceiveJob :> WstxModeProcessing::ProcessingRequest {
        attribute schema_version : Integer = 1;
        attribute correlation : ReceiveContext;
        attribute kind : ReceiveKind;
        attribute 'state' : ReceiveState;
        attribute processed_frames : Integer;
        attribute error : ErrorCode[0..1];
        attribute cancelRequested : Boolean;
        assert constraint progress { processed_frames >= 0 and ((kind == ReceiveKind::spectrum and processed_frames <= 1440000) or (kind == ReceiveKind::live and processed_frames <= (900719925 * 10000000 + 4740991))) }
        doc /* Shared receive lifecycle: recorded spectrum below and continuous live mode
             through WstxRadioIO/WstxModemDecode. One import OR recorded spectrum OR live receive,
             one worker/no pendingjobs; no CPU/file work holding state/profile lock. New
             generation on import/replay,refuse ceiling not wrap. Cancellation invalidates
             publication before ack;terminal progress remains until nextjob. No TX scope. */
    }
    item def DecodeJob :> WstxModeProcessing::ReceiveJob {
        attribute :>> kind = WstxReceiveControl::ReceiveKind::live;
        attribute settings : Settings;
        attribute available_count : Integer;
        attribute search_limited : Boolean;
        assert constraint boundedProgress {
            processed_frames >= 0 and processed_frames <= (900719925 * 10000000 + 4740991) and
            available_count >= 0 and available_count <= 2048
        }
        doc /* Existing station receive-job authority, kind=live with immutable mode.
             One import OR recorded spectrum OR continuous receive; no queue.
             Source-relative FT8/FT4 windows, reliable live ring and epoch rules12.8.
             Numerical recorded fixtures have no production receive operation. */
    }

    enum def Mode { enum ft4; enum ft8; }
    attribute def Settings { attribute mode : Mode; }
}
