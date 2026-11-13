package WstxStationAuthority {
    private import ScalarValues::*;
    private import WstxRecordingTransfer::ImportView;
    action def CancelImport {
        in importId : String;
        out resource : ImportView;
        doc /* Cancellation invalidates publication/commit authorization before its HTTP acknowledgement;
             accepting that operation and constructing its response take at most250ms locally,
             excluding network transit. Normal cleanup finishes within1s in isolated Windows tests.
             After an I/O error or5s cleanup deadline, publish failed/storage_unavailable and set
             storage_error; keep the pending files/handles quarantined and retain the one occupied
             operation/worker slot. Refuse further import/replay with503 storage_unavailable until
             cleanup actually succeeds or restart reconciles the directory. Do not claim deletion,
             start replacement workers or revert an already committed source. A blocked OS call may
             finish later, but its invalidated token cannot commit; final release clears storage_error
             only after real cleanup. Status/profile/settings and cancellation observation stay usable.
             Restart attempts cleanup once before enabling imports; failure keeps the degraded state.
             These are bounded application outcomes, not a claim to interrupt a blocked Windows I/O
             system call. A commit already begun is reconciled via snapshot, not cancelled. */
    }
    action cancelImport : CancelImport;
    dependency importAuthority from cancelImport to WstxArchitecture::physicalStation::backend::stations::station;
}
