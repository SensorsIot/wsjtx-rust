package WstxRecordingTransfer {
    private import ScalarValues::*;
    private import WstxReceiveControl::ErrorCode;
    private import WstxReceiveControl::JobView;
    port def RecordingTransfer { out item recording : Recording; }
    interface def RecordingTransferLink {
        doc /* An uploaded recording passed on after validation. */
        end sender : RecordingTransfer;
        end receiver : ~RecordingTransfer;
    }
    item def Recording;

    attribute def RecordingLimits {
        doc /* The bounds of an import and of the stored recording. */
        attribute rateHz : Integer = 12000 {
            doc /* The one sample rate an imported recording has. */
        }
        attribute fileBytes : Integer = 3145728 {
            doc /* The largest recording file. */
        }
        attribute importMaxFrames : Integer = 1440000 {
            doc /* The most source frames of a recording, 120 s at rateHz. */
        }
        attribute importMaxRiffChunks : Integer = 64 {
            doc /* The most RIFF chunks of a recording, fmt and data included. */
        }
        attribute rawChunkBytes : Integer = 2048 {
            doc /* The largest body of one upload PUT. */
        }
        attribute reservationMs : Integer = 30000 {
            doc /* A reservation without its first chunk expires after this time. */
        }
        attribute uploadIdleMs : Integer = 15000 {
            doc /* An upload without a chunk for this time expires. */
        }
        attribute uploadTotalMs : Integer = 1800000 {
            doc /* An upload not complete after this time expires. */
        }
        attribute importCancelAckMs : Integer = 250 {
            doc /* The station accepts a cancellation and builds its response within this
                 time, network transit excluded. */
        }
        attribute normalCleanupMs : Integer = 1000 {
            doc /* Cleanup of a cancelled or expired import ends within this time in isolated
                 Windows tests. */
        }
        attribute faultCleanupOutcomeMs : Integer = 5000 {
            doc /* A cleanup not ended after this time is published as failed. */
        }
        attribute snapshotBytes : Integer = 8192 {
            doc /* The largest GET /recording body. */
        }
    }

    enum def ImportState {
        enum reserved; enum receiving; enum validating; enum committing; enum cancelling;
        enum completed; enum cancelled; enum failed;
    }
    attribute def RecordingView {
        doc /* The recording of GET /recording with exactly these keys; utc_anchor is always
             null for a recording. */
        attribute id : String;
        attribute rate_hz : Integer;
        attribute frames : Integer;
        attribute file_bytes : Integer;
        attribute utc_anchor : String[0..1];
    }
    attribute def ImportView {
        doc /* The import resource with exactly these keys. total_bytes is null before the
             first chunk and fixed after it; recording_id is null until the commit. The latest
             terminal resource is kept until the next reservation or restart. */
        attribute id : String;
        attribute 'state' : ImportState;
        attribute received_bytes : Integer;
        attribute total_bytes : Integer[0..1];
        attribute error : ErrorCode[0..1];
        attribute recording_id : String[0..1];
    }
    attribute def RecordingSnapshot {
        doc /* The 200 body of GET /recording, at most RecordingLimits::snapshotBytes; the GET
             changes nothing. Its key import carries importOperation without recording_id and
             is null once the import is terminal. */
        doc /* A missing or corrupt committed original, metadata or manifest gives recording
             null and source_error recording_unavailable; the IDs, the generation and the
             operations stay, so that a fresh browser can replace the recording. No job is
             fabricated, and an affected job fails. A healthy or absent source has
             source_error null; a replacement clears it. */
        doc /* A degraded store gives storage_error storage_unavailable: GET still answers 200,
             and a new import or replay is refused with 503. */
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
        attribute recording : RecordingView[0..1];
        attribute source_error : ErrorCode[0..1];
        attribute storage_error : ErrorCode[0..1];
        attribute importOperation : ImportView[0..1];
        attribute job : JobView[0..1];
    }
    attribute def StartImportBody {
        attribute v : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute generation : Integer;
    }
}
