package WstxAudio {
    private import ScalarValues::*;
    enum def AudioState { enum closed; enum opening; enum running; enum closing; enum unavailable; }
    enum def NativeFormat { enum float32; enum pcm16; enum pcm24; enum pcm32; }
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
    item def NativePacket {
        attribute endpointId : String;
        attribute deviceFrame : Integer;
        attribute packetQpc100ns : Integer;
        attribute frames : Integer;
        attribute channels : Integer;
        attribute rateHz : Integer;
        attribute format : NativeFormat;
        attribute bytes : Integer[0..65536];
        attribute silent : Boolean;
        attribute discontinuity : Boolean;
        attribute timestampError : Boolean;
        assert constraint packetBound { frames > 0 and frames <= 8192 and channels >= 1 and channels <= 2 and (rateHz == 44100 or rateHz == 48000) }
        doc /* Raw interleaved little-endian device packet. Byte values0..255. Capture
             pump copies/releases only; float normalization/conversion belongs worker.
             SILENT is known measured zero; timestamp-error/gap is not silence.
             A discontinuity flag whose deviceFrame and packetQpc100ns both continue the
             previous packet (QPC within2ms) is a counted engine glitch on a continuous
             timeline: measured samples, no gap and no epoch; no interval is missing
             beyond the at most2 ms QPC deviation this bound admits. */
    }
    attribute def SourceDescriptor {
        attribute schema_version : Integer = 1;
        attribute profile_id : String;
        attribute boot_id : String;
        attribute source_id : String;
        attribute rate_hz : Integer;
        attribute channel : String = "mono_real";
        attribute total_frames : Integer[0..1];
        attribute utc_anchor : String[0..1];
        doc /* Immutable source lifetime. Recording12000Hz,known1..1440000frames,UTCnull;
             no filename timestamp. #8 settles live rates/clock/UTC/discontinuity before
             device code. Optional UTC separate from sample clock,not hardware support. */
        assert constraint schemaRate { schema_version == 1 and rate_hz > 0 }
    }
    item def SampleBlock :> WstxArchitecture::SampleBlock {
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
    dependency sharedInput from SampleBlock to WstxArchitecture::physicalStation::backend::stations::audio;
}
