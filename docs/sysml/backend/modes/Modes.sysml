package WstxModesPart {
    private import ScalarValues::*;
    private import WstxModeProcessing::ReceiveProcessing;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxModeProcessing::PackProcessing;
    private import WstxModelNotes::CodeDiffers;
    private import WstxModelBindings::ImplementedIn;

    part def ModeFunctions {
        doc /* The FT8 and FT4 protocol functions of the station. It decodes the frames in
             a window of samples, turns each payload into a message with its fields, and
             turns a message into its waveform. */
        @ImplementedIn {
            module = "server/src/decoder/mod.rs; server/src/decoder/payload.rs; "
                + "server/src/decoder/search.rs; server/src/decoder/subtraction.rs; "
                + "server/src/lib.rs; server/src/modes/decoder/apriori.rs; "
                + "server/src/modes/decoder/baseband.rs; server/src/modes/decoder/bitmetrics.rs; "
                + "server/src/modes/decoder/channel.rs; server/src/modes/decoder/coarse_ft4.rs; "
                + "server/src/modes/decoder/fit.rs; server/src/modes/decoder/hashes.rs; "
                + "server/src/modes/decoder/history.rs; server/src/modes/decoder/parallel.rs; "
                + "server/src/modes/decoder/physical_ft4.rs; "
                + "server/src/modes/decoder/physical_sync.rs; server/src/modes/decoder/snr.rs; "
                + "server/src/modes/decoder/synchronization.rs; "
                + "server/src/modes/decoder/waveform.rs; server/src/modes/playback/windows.rs; "
                + "server/src/modes/transmit/mod.rs; server/src/modes/transmit/waveform.rs; "
                + "server/src/transmit/pack.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/decoder/mod.rs, server/src/decoder/payload.rs, "
                + "server/src/decoder/search.rs, server/src/decoder/subtraction.rs, "
                + "server/src/lib.rs, server/src/transmit/pack.rs, outside server/src/modes/ and "
                + "client/src/modes/.";
        }
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
        port pack : ~PackProcessing {
            doc /* qso's texts, answered by PackMessage. */
        }
    }
}
