package WstxRecordingTransfer {
    private import ScalarValues::*;
    private import ModelNotes::NotStated;

    doc /* How a recording comes into the profile (the import, part by part) and how the
         stored recording goes to the receive function as samples. */

    // ---- The limits -----------------------------------------------------------------------

    attribute def RecordingLimits {
        doc /* The bounds of an import and of the stored recording. */
        attribute rateHz : Integer = 12000 {
            doc /* The one sample rate a recording has. */
        }
        attribute fileBytes : Integer = 3145728 {
            doc /* The largest recording file. */
        }
        attribute importMaxFrames : Integer = 1440000 {
            doc /* The most samples of a recording: 120 s at rateHz. */
        }
        attribute importMaxRiffChunks : Integer = 64 {
            doc /* The most chunks of a recording file, fmt and data among them. */
        }
        attribute rawChunkBytes : Integer = 2048 {
            doc /* The largest part of a file one ImportChunk carries. */
        }
        attribute reservationMs : Integer = 30000 {
            doc /* A reserved import without its first part ends after this time. */
        }
        attribute uploadIdleMs : Integer = 15000 {
            doc /* An import that receives ends this long after its latest part began. */
        }
        attribute uploadTotalMs : Integer = 1800000 {
            doc /* An import that is not complete ends this long after its
                 reservation. */
        }
    }

    // ---- The import, from the station service to the profile ------------------------------

    enum def ImportState {
        doc /* reserved: the import has a place and no part of its file.
             receiving: parts of the file come in.
             validating: the whole file is there and is being read.
             committing: the file is being put in the place of the stored recording.
             cancelling: the import has ended and its files are being removed.
             completed: the file is the stored recording.
             cancelled: the import was cancelled and has left nothing behind.
             failed: the import ended with an error. */
        enum reserved;
        enum receiving;
        enum validating;
        enum committing;
        enum cancelling;
        enum completed;
        enum cancelled;
        enum failed;
    }
    enum def ImportError {
        doc /* Why the profile refuses a command of an import, and why an import has
             ended without a stored recording.
             state_conflict: the part is not the next one of the file.
             busy: a job of receive, a band or mode selection or another import has not
             ended.
             storage_unavailable: the recordings cannot be read or written.
             not_found: no import of this id.
             invalid_state: the import is in a state in which the command cannot be
             carried out.
             request_too_large: the file is announced with more than
             RecordingLimits::fileBytes.
             upload_timeout: the import ran out of time.
             cancelled: the import was cancelled.
             invalid_recording: the file is not built as a WAV file.
             unsupported_audio: the file is a WAV file of another form than the one a
             recording has.
             recording_limit: the file is over a limit of RecordingLimits.
             recording_unavailable: the stored recording cannot be read. */
        enum state_conflict;
        enum busy;
        enum storage_unavailable;
        enum not_found;
        enum invalid_state;
        enum request_too_large;
        enum upload_timeout;
        enum cancelled;
        enum invalid_recording;
        enum unsupported_audio;
        enum recording_limit;
        enum recording_unavailable;
    }
    item def ReserveImport {
        doc /* Begin an import. */
    }
    item def ImportReserved {
        doc /* The answer to an admitted ReserveImport. */
        attribute id : String { doc /* The id of the import: a UUID. */ }
    }
    item def ImportChunk {
        doc /* The next part of the file of an import. */
        attribute id : String;
        attribute start : Integer {
            doc /* The place of the part's first byte in the file, from 0. */
        }
        attribute total : Integer {
            doc /* The length of the whole file, at least 1. */
        }
        attribute bytes : Integer[1..2048] {
            doc /* The bytes of the part, at most RecordingLimits::rawChunkBytes, none of
                 them beyond total. */
        }
    }
    item def CancelImport {
        doc /* End an import without a stored recording. */
        attribute id : String;
    }
    item def ReadImport {
        doc /* Ask for the state of an import. */
        attribute id : String;
    }
    item def ImportView {
        doc /* One import as it is: the answer to ImportChunk, CancelImport and
             ReadImport. The profile keeps the import that ended last until the next one
             is reserved or the station stops. */
        attribute id : String;
        attribute 'state' : ImportState;
        attribute received_bytes : Integer {
            doc /* How much of the file the profile has taken. */
        }
        attribute total_bytes : Integer[0..1] {
            doc /* The length of the file; absent before the first part. */
        }
        attribute error : ImportError[0..1] {
            doc /* Why the import ended; absent while it runs and when completed. */
        }
        attribute recording_id : String[0..1] {
            doc /* The id of the recording the import stored, which is the id of the
                 import; absent until the file is in the place of the stored
                 recording. */
        }
    }
    item def ImportRefused {
        doc /* The answer to a command of an import the profile does not carry out. */
        attribute error : ImportError;
    }
    item def Recording {
        doc /* The recording a profile holds. */
        attribute id : String { doc /* A UUID. */ }
        attribute frames : Integer {
            doc /* Its samples, 1 to RecordingLimits::importMaxFrames, at
                 RecordingLimits::rateHz. */
        }
        attribute file_bytes : Integer {
            doc /* The length of its file, at most RecordingLimits::fileBytes. */
        }
    }
    item def RecordingStatus {
        doc /* What the profile holds and what its import does. The profile gives it at
             station start and whenever one of its features changes. */
        item recording : Recording[0..1] {
            doc /* Absent when none is stored and when the stored one cannot be read. */
        }
        attribute source_error : ImportError[0..1] {
            doc /* recording_unavailable while a stored recording cannot be read;
                 absent otherwise. */
        }
        attribute storage_error : ImportError[0..1] {
            doc /* storage_unavailable while the recordings cannot be read or written;
                 absent otherwise. */
        }
        item running : ImportView[0..1] {
            doc /* The import that has not ended, without its recording_id. */
        }
    }
    item def ReceiveBusy {
        doc /* Whether receive holds the station's one place for a job or an import.
             The station service gives it at station start and whenever one of the two
             values changes. */
        attribute notReleased : Boolean {
            doc /* A live job that has ended has not yet given up everything it held,
                 or a band or mode selection runs. */
        }
        attribute jobRunning : Boolean { doc /* A job of receive has not ended. */ }
    }

    port def RecordingTransfer {
        doc /* Written from the side that brings a recording; the profile uses the
             conjugate.
             ReserveImport is answered by ImportReserved, the other three commands by
             ImportView, and each of the four by ImportRefused when it is not carried
             out. An answer goes to the one command it belongs to. */
        out item reserve : ReserveImport;
        out item chunk : ImportChunk;
        out item cancel : CancelImport;
        out item read : ReadImport;
        out item receiveBusy : ReceiveBusy;
        in item reserved : ImportReserved;
        in item importView : ImportView;
        in item refused : ImportRefused;
        in item status : RecordingStatus;
    }
    interface def RecordingTransferLink {
        doc /* A recording on its way into the profile. */
        end sender : RecordingTransfer;
        end receiver : ~RecordingTransfer;
    }

    // ---- The stored recording as samples, from the profile to receive ----------------------

    item def OpenRecording {
        doc /* Receive asks for the samples of the stored recording. */
        attribute id : String { doc /* The id of the recording. */ }
    }
    item def RecordedBlock {
        doc /* A run of samples of the stored recording: mono, 12 kHz, each the stored
             16-bit value divided by 32768. The blocks follow each other from frame 0
             without a gap. A recording has no tie to station time. */
        attribute firstFrame : Integer;
        attribute samples : Real[1..4096];
        attribute endOfStream : Boolean { doc /* True for the last block. */ }
    }
    item def RecordingUnreadable {
        doc /* The stored recording cannot be given: its file does not open, is not a
             valid recording any more, or has another length than the one stored. */
    }
    port def RecordedSamples {
        doc /* Written from the side that holds the recording. OpenRecording is answered
             by the blocks of the recording or by RecordingUnreadable. */
        in item open : OpenRecording;
        out item block : RecordedBlock;
        out item unreadable : RecordingUnreadable;
    }
    interface def RecordedSamplesLink {
        doc /* The stored recording as samples, to the receive function. */
        end profile : RecordedSamples;
        end receive : ~RecordedSamples;
    }
}
