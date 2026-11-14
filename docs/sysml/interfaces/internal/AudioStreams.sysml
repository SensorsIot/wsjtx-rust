package WstxAudioStreams {
    private import ScalarValues::*;
    private import WstxAudioControl::AudioOutcome;
    port def AudioExchange {
        out item playback : SampleBlock;
        in item capture : SampleBlock;
        in item outcome : AudioOutcome;
    }
    interface def AudioExchangeLink {
        doc /* Capture and playback samples of the selected radio type. */
        end producer : AudioExchange;
        end consumer : ~AudioExchange;
    }
    port def CaptureSamples {
        out item capture : SampleBlock;
        out item outcome : AudioOutcome;
    }
    interface def CaptureSamplesLink {
        doc /* The capture samples of a native radio session, joined to the audio function's
             exchange. */
        end audio : AudioExchange;
        end session : CaptureSamples;
    }
    port def ReceiveSamples {
        out item samples : SampleBlock;
        out item outcome : AudioOutcome;
    }
    interface def ReceiveSamplesLink {
        doc /* Live samples, or a recording for replay, to the receive function. */
        end source : ReceiveSamples;
        end receive : ~ReceiveSamples;
    }
    item def SampleBlock {
        doc /* Immutable recorded and live samples feed the same receive boundary.
             WstxAudio::SampleBlock owns concrete recorded element units,
             clocks, ownership/lifetime and bounds; WstxRadioIO owns live adaptation.
             Source-specific metadata and discontinuities must be explicit; a generic
             architectural item does not settle every future live format. */
    }
    enum def NativeFormat { enum float32; enum pcm16; enum pcm24; enum pcm32; }
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
}
