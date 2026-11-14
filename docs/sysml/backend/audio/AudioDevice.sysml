package WstxAudio {
    private import ScalarValues::*;
    private import WstxAudioStreams::SourceDescriptor;
    enum def AudioState { enum closed; enum opening; enum running; enum closing; enum unavailable; }
    attribute def DeviceIntent {
        attribute audioEndpointId : String[0..1];
        attribute audioChannel : Integer = 0;
        attribute controlEndpoint : String[0..1];
        attribute pttDisabled : Boolean = true;
        doc /* Existing schema1 profile/audio/control shape and revision own persistence.
             Exact opaque audio ID, no default fallback. COMn compatibility or strict
             icom7300://COMn?baud=auto&radio=94&controller=E0 with contract 4.5 grammar.
             Catalogue/live observations are not persisted intent or permission. */
    }
    item def SampleBlock :> WstxAudioStreams::SampleBlock {
        attribute source : SourceDescriptor;
        attribute first_frame : Integer;
        attribute samples : Real[1..4096];
        attribute discontinuity : Boolean;
        attribute end_of_stream : Boolean;
        assert constraint nonnegativePosition { first_frame >= 0 }
        doc /* Finite f32 mono real,signedPCM16/32768 exactly. Arc<[f32]> or equivalent
             immutable shared owner;borrowers cannot mutate,producer reuse waits for
             last reference release. #6 spectrum path retains<=2blocks incl producer/
             consumers,no whole-file float array/backlog. #7 separately bounds modem
             history,not restricted to2blocks. Recordings start0,contiguous positions,
             discontinuityfalse,EOS last nonempty block. Semantic incompatible changes
             need coordinated new version. Unit conversion !=AGC/preprocessing/resampling. */
    }
    dependency sharedInput from SampleBlock to WstxArchitecture::StationProcess::audio;
}
