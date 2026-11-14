package WstxDisplayData {
    private import ScalarValues::*;
    port def DisplayDataPort {
        out item spectrum : SpectrumFrame;
        out item detailedSpectrum : DetailedSpectrumFrame;
    }
    interface def DisplayData {
        doc /* Spectrum and waterfall rows from receive; discardable. */
        end receive : DisplayDataPort;
        end consumer : ~DisplayDataPort;
    }
    item def SpectrumFrame :> WstxModeProcessing::ProcessingResult {
        attribute v : Integer = 1;
        attribute boot_id : String;
        attribute source_id : String;
        attribute job_id : String;
        attribute generation : Integer;
        attribute sequence : Integer;
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        attribute levels : Integer[128];
        assert constraint interval { sequence >= 0 and first_frame == 12000 * sequence and end_frame > first_frame and end_frame <= first_frame + 12000 }
        doc /* Exact envelope v1,type spectrum.frame,data with fields above except v;
             levels each0..120,q-120dBFS. end=min(first+12000,source_frames). sequence0
             per replay,advances despite droppedrows. Immutable producer-owned frame,
             <=1replaceable pending/peer,<=1send/s;browser120rows*128values,1pendingpaint.
             groupb[b*23.4375,(b+1)*23.4375)Hz. Ignore obsolete tuple/socket callbacks,
             show gaps,clear newsource/job. Required decode results never share drop rule. */
    }

    item def DetailedSpectrumFrame :> WstxModeProcessing::ProcessingResult {
        attribute v : Integer = 1;
        attribute boot_id : String;
        attribute source_id : String;
        attribute job_id : String;
        attribute generation : Integer;
        attribute sequence : Integer;
        attribute first_frame : Integer;
        attribute end_frame : Integer;
        attribute levels_b64 : String;
        assert constraint interval { sequence >= 0 and first_frame == 2400 * sequence and end_frame > first_frame and end_frame <= first_frame + 2400 and end_frame <= (900719925 * 10000000 + 4740991) }
        doc /* Exact spectrum.detail.frame envelope, <=2048 UTF8bytes; same current UUID/
             safe-integer tuple as Thin. Canonical padded standard RFC4648 base64 exactly
             1368chars decodes1024 bytes each0..120. Unknown/missing fields,
             noncanonical encoding, bad bounds/identities/socket are rejected atomically.
             Retain one latest immutable frame per profile in existing station state;
             per peer one replaceable selected frame, not two queues or another job. */
    }
}
